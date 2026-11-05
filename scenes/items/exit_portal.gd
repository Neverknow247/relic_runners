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
const WAVE_INTERVAL := 25.0
# Waves RAMP as the portal nears opening (see _wave_plan). The first waves are a
# couple of triangles; later ones grow, mix in pentagons (the tanky archetype),
# and finally start rolling silver (elite) tier — so the last group that lands as
# the portal opens is the nastiest. Everything scales off "progress" (0 on the
# first wave → 1 on the final one) so it stays sensible if the timing changes.
const WAVE_START_SIZE := 2
const WAVE_MAX_SIZE := 7
# Pentagons begin mixing in past the opening waves; ramps up to this share.
const WAVE_PENTAGON_MAX_CHANCE := 0.6
# Silver only appears in the final stretch; ramps up to this share.
const WAVE_SILVER_MAX_CHANCE := 0.3
# Groups spawn this far from the portal — past the screen's half-diagonal
# (~734) so they aren't on-screen for someone standing on the portal — then head
# in. Snapped onto the nav mesh (pulled to the room's edge if it's smaller).
const WAVE_SPAWN_RADIUS := 3600.0
const WAVE_GROUP_SPREAD := 640.0
const WAVE_MIN_SEPARATION := 384.0
const WAVE_PLACEMENT_ATTEMPTS := 12
# A nav-snapped point can still sit right against a wall (the nav polygon has no
# agent-radius inset), so a body dropped there clips into it. Reject any spawn
# whose body (this radius, a touch over BODY_RADIUS to cover silver's 1.25x
# scale) would overlap a wall. Walls are static and the only thing on physics
# layer 1, so this test is identical on every peer — placement stays deterministic.
const WAVE_WALL_CLEARANCE := 64.0
const WALL_MASK := 1

# --- Noise ----------------------------------------------------------------
# A charging portal is LOUD: every NOISE_INTERVAL it draws every idle enemy
# within NOISE_RADIUS toward itself (they investigate the portal — see
# enemy.hear_world_noise), so pre-existing room enemies converge on it, not just
# the spawned waves. Server-only (enemy AI runs on the authority alone), so this
# needs no RPC — it just nudges local AI state. Big radius so it reaches across
# the whole room.
const NOISE_INTERVAL := 4.0
const NOISE_RADIUS := 5600.0

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
				_record_extraction()
				world.request_location_changes("hub", "main", "default")
		_:
			pass  # CHARGING, DISABLED, or SPAWN_POINT — interact does nothing

# Called locally (no RPC — see portal_group.gd) on whichever portal was
# deterministically picked as this expedition's arrival point. Permanently
# excludes it from ever functioning as an exit — _start_charging()'s own
# "must be LOCKED" guard means it can never progress past this.
# A successful extraction from this expedition's map counts toward the map-board
# ladder (MapDef.unlock_after). Local save; written when we arrive in the hub.
func _record_extraction() -> void:
	var map_id: String = Stats.current_map_id
	if map_id == "":
		return
	var unlocks: Dictionary = Stats.save_data.get("unlocks", {})
	var extracted: Dictionary = unlocks.get("extracted", {})
	extracted[map_id] = int(extracted.get(map_id, 0)) + 1
	unlocks["extracted"] = extracted
	Stats.save_data["unlocks"] = unlocks

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
	# And start pulsing "noise" that pulls nearby idle enemies onto the portal.
	_noise_loop()
	await get_tree().create_timer(charge_time).timeout
	if !is_inside_tree() or state != State.CHARGING:
		return
	# The final wave lands exactly as the portal opens — the biggest, nastiest one.
	_broadcast_spawn_wave(_final_wave_index())
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
	var final_idx := _final_wave_index()
	var wave := 0
	while is_inside_tree() and state == State.CHARGING and wave < final_idx:
		_broadcast_spawn_wave(wave)
		wave += 1
		if wave >= final_idx:
			return
		await get_tree().create_timer(WAVE_INTERVAL).timeout

# The index of the last wave (the one that lands as the portal opens). The
# interval waves are 0 .. this-1; this is fired separately by _start_charging.
# Also the denominator for a wave's ramp progress, so keep it a pure function of
# the (peer-identical) charge timing.
func _final_wave_index() -> int:
	return int(ceil(charge_time / WAVE_INTERVAL))

# Server-only coroutine: while the portal is charging or open, pulse noise every
# NOISE_INTERVAL so idle enemies in the room keep converging on it. No RPC — enemy
# AI (and thus this nudge) only runs on the server.
func _noise_loop() -> void:
	while is_inside_tree() and (state == State.CHARGING or state == State.OPEN):
		_emit_noise()
		await get_tree().create_timer(NOISE_INTERVAL).timeout

func _emit_noise() -> void:
	if !multiplayer.is_server():
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if !is_instance_valid(e):
			continue
		if e.global_position.distance_to(global_position) <= NOISE_RADIUS:
			e.hear_world_noise(global_position)

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

# Server: every wave index this portal has spawned this expedition, so a peer who
# enters the room later can be caught up (see catch_up_peer).
var _spawned_waves: Array = []

# Unique per portal: rooms have several portals, and two charging portals used to
# both name their members "portalwave_<wave>_<i>". Godot auto-renames clashing
# siblings differently on each peer, which broke enemy sync.
func _wave_member_name(wave: int, i: int) -> String:
	return "portalwave_%s_%d_%d" % [name, wave, i]

# Server: a peer just finished loading this room. Waves spawned before it arrived
# never reached it, so send the list plus which members are still alive; the peer
# re-creates them deterministically and frees the dead ones (otherwise it would
# have no node for enemies the server then starts syncing to it).
func catch_up_peer(peer_id: int) -> void:
	if !multiplayer.is_server() or _spawned_waves.is_empty():
		return
	if peer_id == multiplayer.get_unique_id():
		return
	var enemies_node = _room_enemies_node()
	if enemies_node == null:
		return
	var alive: Array = []
	var prefix := "portalwave_%s_" % name
	for e in enemies_node.get_children():
		if e is Enemy and !e.is_dead and String(e.name).begins_with(prefix):
			alive.append(String(e.name))
	client_catch_up_waves.rpc_id(peer_id, _spawned_waves, alive)

@rpc("authority", "call_remote", "reliable")
func client_catch_up_waves(waves: Array, alive: Array) -> void:
	var enemies_node = _room_enemies_node()
	if enemies_node == null:
		return
	for wave in waves:
		if enemies_node.has_node(_wave_member_name(int(wave), 0)):
			continue
		_do_spawn_wave(int(wave))
	var prefix := "portalwave_%s_" % name
	for e in enemies_node.get_children():
		if e is Enemy and String(e.name).begins_with(prefix) and !alive.has(String(e.name)):
			e.queue_free()

func _room_enemies_node():
	var world = get_tree().get_first_node_in_group("world")
	var room_key := _my_room_key()
	if world == null or room_key == "":
		return null
	var room = world.world_rooms.loaded_rooms.get(room_key, {}).get("scene")
	if room == null or not is_instance_valid(room):
		return null
	return room.get_node_or_null("enemies")

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
	if multiplayer.is_server() and !_spawned_waves.has(wave):
		_spawned_waves.append(wave)
	var map_rid: RID = enemies_node.get_world_2d().navigation_map
	var space: PhysicsDirectSpaceState2D = enemies_node.get_world_2d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = Stats.expedition_seed ^ name.hash() ^ (hash("portalwave") + wave * 2654435761)
	var group_center := _pick_wave_center(rng, map_rid, space)
	# How big/nasty this wave is, ramped by how close the portal is to opening.
	var plan := _wave_plan(wave, rng)
	var group_size: int = plan["size"]
	# 1-2 shared element types for the whole wave (seeded, every peer agrees) so
	# the pack reads as cohesive — each member rolls from just these (Enemy._ready).
	var group_element_palette := Enemy.pick_group_elements(rng)
	var members: Array[Enemy] = []
	var placed: Array[Vector2] = []
	var leader: Enemy = null
	for i in group_size:
		var pos := _pick_wave_member_position(group_center, rng, map_rid, space, placed)
		placed.append(pos)
		var enemy := EnemyScene.instantiate() as Enemy
		enemy.name = _wave_member_name(wave, i)
		enemy.position = enemies_node.to_local(pos)
		enemy.group = members
		enemy.group_elements = group_element_palette
		# Per-enemy archetype + tier, off the same deterministic rng (in a fixed
		# order so every peer rolls identical members). Set BEFORE add_child so the
		# enemy's _ready() applies the archetype/tier preset (stats + look).
		enemy.archetype = "pentagon" if rng.randf() < plan["pentagon_chance"] else "triangle"
		enemy.tier = "silver" if rng.randf() < plan["silver_chance"] else "bronze"
		if i == 0:
			leader = enemy
		else:
			enemy.leader = leader
		members.append(enemy)
		enemies_node.add_child(enemy)
		# Anchor their home/patrol to the portal (overriding the off-screen spawn
		# spot _ready set) so they converge on it and hold it, and send them at it
		# right away (rather than waiting for the next noise pulse). Only the server
		# runs the AI, so only its copy needs this.
		if world.multiplayer.is_server():
			enemy.spawn_position = global_position
			enemy.call_deferred("hear_world_noise", global_position)
	# Server now begins replicating these fresh enemies to the room's occupants.
	if world.multiplayer.is_server():
		world.world_rooms.refresh_all_entity_visibility()

# The composition of wave N — size, and the per-enemy chances of being a
# pentagon / silver — ramped by how close the portal is to opening. "progress"
# runs 0.0 (first wave) → 1.0 (final wave that lands as it opens), and everything
# scales off it so the ramp stays sensible if the charge timing changes. Nearly a
# pure function of `wave` (the rng only adds a little size jitter), so every peer
# derives the same plan for the same wave.
func _wave_plan(wave: int, rng: RandomNumberGenerator) -> Dictionary:
	var final_idx := _final_wave_index()
	var progress := float(wave) / float(maxi(1, final_idx))
	# Grows from WAVE_START_SIZE toward WAVE_MAX_SIZE, plus a small 0-1 jitter.
	var size := clampi(WAVE_START_SIZE + int(round(progress * 4.0)), WAVE_START_SIZE, WAVE_MAX_SIZE)
	size = clampi(size + rng.randi_range(0, 1), WAVE_START_SIZE, WAVE_MAX_SIZE)
	# Pentagons only start mixing in past the opening quarter, then ramp to cap.
	var pentagon_chance := clampf((progress - 0.25) / 0.75, 0.0, 1.0) * WAVE_PENTAGON_MAX_CHANCE
	# Silver (elite) tier is held back until the final stretch (last ~30%).
	var silver_chance := clampf((progress - 0.7) / 0.3, 0.0, 1.0) * WAVE_SILVER_MAX_CHANCE
	return {
		"size": size,
		"pentagon_chance": pentagon_chance,
		"silver_chance": silver_chance,
	}

# A nav-mesh point roughly WAVE_SPAWN_RADIUS from the portal in a random (seeded)
# direction, so the group forms up off-screen. If the room's too small to get a
# point that far out, it uses the FARTHEST walkable point it found — never the
# portal itself, so the group never spawns right on a player standing on it.
func _pick_wave_center(rng: RandomNumberGenerator, map_rid: RID, space: PhysicsDirectSpaceState2D) -> Vector2:
	var best := global_position
	var best_dist := 0.0
	for attempt in WAVE_PLACEMENT_ATTEMPTS:
		var dir := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
		var snapped := NavigationServer2D.map_get_closest_point(map_rid, global_position + dir * WAVE_SPAWN_RADIUS)
		if not _wall_clear(space, snapped):
			continue
		var d := snapped.distance_to(global_position)
		if d > WAVE_SPAWN_RADIUS * 0.5:
			return snapped
		if d > best_dist:
			best_dist = d
			best = snapped
	return best

# True if an enemy body at `pos` clears the walls — nothing on physics layer 1
# (walls, which are static and the only occupants of that layer) overlaps a
# WAVE_WALL_CLEARANCE circle there. Deterministic across peers. A null space
# (shouldn't happen mid-game) counts as clear so spawning is never blocked.
func _wall_clear(space: PhysicsDirectSpaceState2D, pos: Vector2) -> bool:
	if space == null:
		return true
	var shape := CircleShape2D.new()
	shape.radius = WAVE_WALL_CLEARANCE
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, pos)
	q.collision_mask = WALL_MASK
	return space.intersect_shape(q, 1).is_empty()

# One group member's spot: clustered around the center, nav-snapped, kept apart
# from siblings. Mirrors enemy_spawner.gd's placement.
func _pick_wave_member_position(
	center: Vector2, rng: RandomNumberGenerator, map_rid: RID, space: PhysicsDirectSpaceState2D, placed: Array[Vector2]
) -> Vector2:
	for attempt in WAVE_PLACEMENT_ATTEMPTS:
		var offset := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU)) * rng.randf_range(0.0, WAVE_GROUP_SPREAD)
		var snapped := NavigationServer2D.map_get_closest_point(map_rid, center + offset)
		if snapped.distance_to(center + offset) > WAVE_GROUP_SPREAD * 2.0:
			snapped = center
		if not _wall_clear(space, snapped):
			continue
		var far_enough := true
		for other in placed:
			if snapped.distance_to(other) < WAVE_MIN_SEPARATION:
				far_enough = false
				break
		if far_enough:
			return snapped
	# Every attempt hit a wall or crowded a sibling. Prefer the group center, then
	# the portal spot — both known-walkable — over an unsnapped ring point that
	# could drop the enemy straight into a wall.
	if _wall_clear(space, center):
		return center
	return global_position

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
