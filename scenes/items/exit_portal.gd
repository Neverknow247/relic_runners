extends Area2D
class_name ExitPortal

# Server-authoritative like enemy.gd (no set_multiplayer_authority() call,
# so this stays at the Godot default — peer 1/server). Any player can
# activate it from LOCKED; the server alone runs the actual timers and
# broadcasts each state change (plus that phase's duration) to every peer,
# so everyone's local copy can independently count down the display without
# needing continuous per-frame sync.

enum State { LOCKED, CHARGING, OPEN, DISABLED, SPAWN_POINT }

# 1-2 minutes to open, then a 30s window to actually use it.
@export var charge_time := 90.0
@export var open_duration := 30.0

# --- Extraction waves -----------------------------------------------------
# While the portal charges, enemy groups spawn in around it every
# WAVE_INTERVAL seconds — one immediately on activation, then each interval,
# then a final group right as it opens — so extracting means fighting off
# waves. Spawned deterministically on every peer (same approach as the room's
# baked enemies) from a shared seed, anchored to the portal so they converge on
# it and patrol it, then run normal AI. The server drives the timing.
const EnemyScene := preload("res://scenes/enemies/enemy.tscn")
const WAVE_INTERVAL := 20.0
const WAVE_MIN_SIZE := 1
const WAVE_MAX_SIZE := 4
# Groups spawn this far from the portal — past the screen's half-diagonal
# (~734) so they aren't on-screen for someone standing on the portal — then head
# in. Snapped onto the nav mesh (pulled to the room's edge if it's smaller).
const WAVE_SPAWN_RADIUS := 900.0
const WAVE_GROUP_SPREAD := 160.0
const WAVE_MIN_SEPARATION := 96.0
const WAVE_PLACEMENT_ATTEMPTS := 12

var state: State = State.LOCKED
var phase_time_remaining := 0.0
var can_use := false

@onready var color_rect: ColorRect = $visual_root/color_rect
@onready var status_label: Label = $visual_root/status_label

func _ready() -> void:
	_update_visual()

func _on_body_entered(body: Node) -> void:
	# During teardown (esc-menu Leave / death penalty) the peer is torn down
	# while bodies exit areas; is_multiplayer_authority() calls get_unique_id(),
	# which errors with no peer assigned.
	if multiplayer.multiplayer_peer == null:
		return
	if body.is_multiplayer_authority():
		can_use = true

func _on_body_exited(body: Node) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if body.is_multiplayer_authority():
		can_use = false

func _process(delta: float) -> void:
	if state == State.CHARGING or state == State.OPEN:
		phase_time_remaining = max(phase_time_remaining - delta, 0.0)
		_update_visual()
	if !can_use:
		return
	if !Input.is_action_just_pressed("interact"):
		return
	match state:
		State.LOCKED:
			request_activate()
		State.OPEN:
			var world = get_tree().get_first_node_in_group("world")
			if world:
				world.request_location_changes("hub", "main", "default")
		_:
			pass  # CHARGING, DISABLED, or SPAWN_POINT — interact does nothing

# Called locally (no RPC — see portal_group.gd) on whichever portal was
# deterministically picked as this expedition's arrival point. Permanently
# excludes it from ever functioning as an exit — _start_charging()'s own
# "must be LOCKED" guard means it can never progress past this.
func mark_as_spawn_point() -> void:
	state = State.SPAWN_POINT
	_update_visual()

func request_activate() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if is_multiplayer_authority():
		_start_charging()
	else:
		server_request_activate.rpc()

@rpc("any_peer", "call_remote", "reliable")
func server_request_activate() -> void:
	if !is_multiplayer_authority():
		return
	_start_charging()

func _start_charging() -> void:
	if state != State.LOCKED:
		return
	state = State.CHARGING
	_broadcast_state(State.CHARGING, charge_time)
	# Kick off the extraction waves alongside the charge countdown (parallel
	# coroutine, not awaited — the charge timer below is the real clock).
	_spawn_charge_waves()
	await get_tree().create_timer(charge_time).timeout
	if !is_inside_tree() or state != State.CHARGING:
		return
	# The final wave lands exactly as the portal opens.
	_broadcast_spawn_wave(int(charge_time / WAVE_INTERVAL))
	state = State.OPEN
	_broadcast_state(State.OPEN, open_duration)
	await get_tree().create_timer(open_duration).timeout
	if !is_inside_tree() or state != State.OPEN:
		return
	state = State.DISABLED
	_broadcast_state(State.DISABLED, 0.0)

# Server-only coroutine: fires the charge-phase waves — one immediately, then one
# every WAVE_INTERVAL. The final wave (right as it opens) is fired by
# _start_charging itself, so this stops one short of charge_time.
func _spawn_charge_waves() -> void:
	var wave := 0
	while is_inside_tree() and state == State.CHARGING and wave * WAVE_INTERVAL < charge_time:
		_broadcast_spawn_wave(wave)
		wave += 1
		if wave * WAVE_INTERVAL >= charge_time:
			return
		await get_tree().create_timer(WAVE_INTERVAL).timeout

# Tell every peer in this room (and the server itself) to spawn wave N — scoped
# the same way portal state is, so peers who've left the room aren't spammed.
func _broadcast_spawn_wave(wave: int) -> void:
	var world = get_tree().get_first_node_in_group("world")
	var room_key := _my_room_key()
	if world == null or room_key == "":
		spawn_portal_wave.rpc(wave)
		return
	var server_id := multiplayer.get_unique_id()
	var recipients := {server_id: true}
	for pid in world.peers_in_room(room_key):
		recipients[pid] = true
	for pid in recipients:
		if pid == server_id:
			spawn_portal_wave(wave)
		else:
			spawn_portal_wave.rpc_id(pid, wave)

@rpc("authority", "call_local", "reliable")
func spawn_portal_wave(wave: int) -> void:
	_do_spawn_wave(wave)

# Deterministically spawn one wave's enemy group into this room's "enemies" node,
# anchored to the portal. Runs on every peer with the same seed, so each ends up
# with byte-identical enemies (matching node names) that the server then
# replicates — exactly how enemy_spawner.gd handles the room's baked enemies.
func _do_spawn_wave(wave: int) -> void:
	var room_key := _my_room_key()
	var world = get_tree().get_first_node_in_group("world")
	if world == null or room_key == "":
		return
	var room = world.world_rooms.loaded_rooms.get(room_key, {}).get("scene")
	if room == null or not is_instance_valid(room):
		return
	var enemies_node = room.get_node_or_null("enemies")
	if enemies_node == null:
		return
	var map_rid: RID = enemies_node.get_world_2d().navigation_map
	var rng := RandomNumberGenerator.new()
	rng.seed = Stats.expedition_seed ^ name.hash() ^ (hash("portalwave") + wave * 2654435761)
	var group_center := _pick_wave_center(rng, map_rid)
	var group_size := rng.randi_range(WAVE_MIN_SIZE, WAVE_MAX_SIZE)
	var members: Array[Enemy] = []
	var placed: Array[Vector2] = []
	var leader: Enemy = null
	for i in group_size:
		var pos := _pick_wave_member_position(group_center, rng, map_rid, placed)
		placed.append(pos)
		var enemy := EnemyScene.instantiate() as Enemy
		enemy.name = "portalwave_%d_%d" % [wave, i]
		enemy.position = enemies_node.to_local(pos)
		enemy.group = members
		if i == 0:
			leader = enemy
		else:
			enemy.leader = leader
		members.append(enemy)
		enemies_node.add_child(enemy)
		# Anchor their home/patrol to the portal (overriding the off-screen spawn
		# spot _ready set) so they converge on it and hold it. Only the server runs
		# the AI, so only its copy needs this.
		if world.multiplayer.is_server():
			enemy.spawn_position = global_position
	# Server now begins replicating these fresh enemies to the room's occupants.
	if world.multiplayer.is_server():
		world.world_rooms.refresh_all_entity_visibility()

# A nav-mesh point roughly WAVE_SPAWN_RADIUS from the portal in a random (seeded)
# direction, so the group forms up off-screen. Falls back to the portal itself if
# the room has no distant walkable point.
func _pick_wave_center(rng: RandomNumberGenerator, map_rid: RID) -> Vector2:
	for attempt in WAVE_PLACEMENT_ATTEMPTS:
		var dir := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
		var snapped := NavigationServer2D.map_get_closest_point(map_rid, global_position + dir * WAVE_SPAWN_RADIUS)
		if snapped.distance_to(global_position) > WAVE_SPAWN_RADIUS * 0.5:
			return snapped
	return global_position

# One group member's spot: clustered around the center, nav-snapped, kept apart
# from siblings. Mirrors enemy_spawner.gd's placement.
func _pick_wave_member_position(
	center: Vector2, rng: RandomNumberGenerator, map_rid: RID, placed: Array[Vector2]
) -> Vector2:
	for attempt in WAVE_PLACEMENT_ATTEMPTS:
		var offset := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU)) * rng.randf_range(0.0, WAVE_GROUP_SPREAD)
		var snapped := NavigationServer2D.map_get_closest_point(map_rid, center + offset)
		if snapped.distance_to(center + offset) > WAVE_GROUP_SPREAD * 2.0:
			snapped = center
		var far_enough := true
		for other in placed:
			if snapped.distance_to(other) < WAVE_MIN_SEPARATION:
				far_enough = false
				break
		if far_enough:
			return snapped
	return center + Vector2.RIGHT.rotated(TAU * placed.size() / 6.0) * WAVE_MIN_SEPARATION

func _my_room_key() -> String:
	var parent = get_parent()
	return parent.room_key if (parent != null and "room_key" in parent) else ""

# Only send portal state to peers who actually HAVE this portal — the room's
# current occupants, plus the server itself (which always holds the room). A
# blanket .rpc() also hit peers who'd left and freed the room, spamming
# "node not found" (and congesting the reliable channel).
func _broadcast_state(new_state: State, time_remaining: float) -> void:
	var world = get_tree().get_first_node_in_group("world")
	var parent = get_parent()
	var room_key: String = parent.room_key if (parent != null and "room_key" in parent) else ""
	if world == null or room_key == "":
		broadcast_portal_state.rpc(new_state, time_remaining)
		return
	var server_id := multiplayer.get_unique_id()
	var recipients := {server_id: true}
	for pid in world.peers_in_room(room_key):
		recipients[pid] = true
	for pid in recipients:
		if pid == server_id:
			broadcast_portal_state(new_state, time_remaining)
		else:
			broadcast_portal_state.rpc_id(pid, new_state, time_remaining)

@rpc("authority", "call_local", "reliable")
func broadcast_portal_state(new_state: State, time_remaining: float) -> void:
	state = new_state
	phase_time_remaining = time_remaining
	_update_visual()

func _update_visual() -> void:
	match state:
		State.LOCKED:
			color_rect.color = Color(0.4, 0.4, 0.4)
			status_label.text = "Exit Portal\n(inactive)"
		State.CHARGING:
			color_rect.color = Color(0.9, 0.7, 0.1)
			status_label.text = "Exit Portal\nOpening in %d s" % ceili(phase_time_remaining)
		State.OPEN:
			color_rect.color = Color(0.2, 0.85, 0.4)
			status_label.text = "Exit Portal\nOPEN — %d s" % ceili(phase_time_remaining)
		State.DISABLED:
			color_rect.color = Color(0.25, 0.2, 0.2)
			status_label.text = "Exit Portal\n(closed)"
		State.SPAWN_POINT:
			color_rect.color = Color(0.3, 0.5, 0.8)
			status_label.text = "Arrival Point"
