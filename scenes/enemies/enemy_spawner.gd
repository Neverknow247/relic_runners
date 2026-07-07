extends Node2D

# Attach to a Node2D whose children are Marker2D spawn points (e.g. the
# "enemies" container in a room scene). Every peer loads the exact same
# static scene and runs this independently with no networked node spawning —
# so each spawn point's roll (and the resulting group's size/layout) has to
# be seeded identically on every peer rather than from real per-peer
# randomness, or different peers would end up with mismatched enemies.
# Stats.expedition_seed is picked once by the server per expedition launch
# and broadcast to everyone (see world.gd/world_expeditions.gd), so the
# layout is still genuinely different each time the party heads out, while
# staying byte-identical across every peer for a given launch. Combined
# with each marker's own name so spawn points don't all roll identically.

const EnemyScene := preload("res://scenes/enemies/enemy.tscn")

@export var spawn_chance := 0.5
@export var min_group_size := 1
@export var max_group_size := 3
@export var group_spread := 192.0

# Matches Enemy.BODY_RADIUS * 2 + a bit more than Enemy.min_enemy_separation
# — a fixed constant here rather than reading those directly since the
# latter is a per-instance export, not something reachable before an Enemy
# even exists. Keeps siblings from being placed close enough to spawn
# already overlapping, which made compute_separation() and hard collision
# fight each other into visibly glitching instead of calmly drifting apart.
const MIN_SPAWN_DISTANCE := 96.0
const SPAWN_PLACEMENT_ATTEMPTS := 10

# Set by world_rooms.gd right after instantiating this room's scene, before
# it's added to the tree (so it's already set by the time _ready() runs).
# Identifies this room ("zone/room", e.g. "dungeon/room_1") for
# expedition-persistent enemy state — see save_state() and Stats.
# expedition_room_state. Empty means "don't bother" (e.g. hub, or any room
# not reached through the normal zone/room location-change flow).
var room_key := ""

func _ready() -> void:
	var spawn_points: Array[Marker2D] = []
	for child in get_children():
		if child is Marker2D:
			spawn_points.append(child)
	# The nav map takes a frame or so after scene load to finish its first
	# sync (see enemy.gd's own guard for the same race) — querying it any
	# earlier returns Vector2.ZERO for every point instead of a real
	# snapped one, which would place every enemy at the map origin instead
	# of near its marker. map_get_iteration_id() > 0 turned out to NOT be a
	# reliable "actually queryable now" signal (it can tick up before
	# regions have really finished registering) — map_get_regions() being
	# non-empty is a more direct check, and a couple extra frames of margin
	# past that first sign of life is cheap insurance against the exact
	# same "every query returns (0,0)" bug happening again.
	var map_rid := get_world_2d().navigation_map
	while NavigationServer2D.map_get_regions(map_rid).is_empty():
		if not await _wait_one_physics_frame():
			return
	for i in 2:
		if not await _wait_one_physics_frame():
			return
	var saved_state: Dictionary = Stats.expedition_room_state.get(room_key, {})
	for point in spawn_points:
		var rng := RandomNumberGenerator.new()
		rng.seed = Stats.expedition_seed ^ point.name.hash()
		if rng.randf() < spawn_chance:
			spawn_group(point, rng, map_rid, saved_state)

# Awaits a single physics frame and reports whether we're still safe to keep
# going afterward. _ready() can be suspended here for a while (waiting on
# the nav map), and if the room gets torn down — a location change — before
# that wait resolves, resuming would call get_tree() on a node no longer in
# the tree and crash. Checking before AND after every await means we bail
# out cleanly the moment that happens instead.
func _wait_one_physics_frame() -> bool:
	if !is_inside_tree():
		return false
	await get_tree().physics_frame
	return is_inside_tree()

func spawn_group(
	point: Marker2D, rng: RandomNumberGenerator, map_rid: RID, saved_state: Dictionary
) -> void:
	var group_size := rng.randi_range(min_group_size, max_group_size)
	# Shared by reference across every member of this group — see
	# Enemy.group / Enemy.promote_new_leader() / Enemy.alert_nearby_group().
	var members: Array[Enemy] = []
	var placed_positions: Array[Vector2] = []
	var leader: Enemy = null
	for i in group_size:
		var safe_pos := pick_spawn_position(point, rng, map_rid, placed_positions)
		placed_positions.append(safe_pos)
		var enemy := EnemyScene.instantiate() as Enemy
		enemy.name = "%s_enemy_%d" % [point.name, i]
		# Local position (not global_position) has to be set before
		# add_child() — the node isn't in the tree yet, so global_position
		# can't resolve a parent transform, but to_local() works fine since
		# this spawner itself is already in the tree.
		enemy.position = to_local(safe_pos)
		enemy.group = members
		if i == 0:
			leader = enemy
		else:
			enemy.leader = leader
		members.append(enemy)
		add_child(enemy)
		apply_saved_state(enemy, saved_state)
		# Register this enemy the moment it exists, not just when we
		# eventually leave — otherwise a kill that happens before the first
		# departure has no earlier record to be recognized as "missing"
		# against, and save_state() would have nothing to compare against
		# to notice it's gone.
		record_enemy_state(enemy)

# If this enemy (by name) has a record from an earlier visit to this room
# this same expedition, restore it instead of leaving the fresh spawn as-is
# — dead stays dead, survivors reappear where they were left with however
# much health they had.
func apply_saved_state(enemy: Enemy, saved_state: Dictionary) -> void:
	if !saved_state.has(enemy.name):
		return
	var data: Dictionary = saved_state[enemy.name]
	# Identity (weapon/element — what it looks like and how matchups apply
	# to it) has to be restored regardless of alive/dead, since _ready()
	# already rolled a fresh random one before this ever runs — otherwise a
	# persisted enemy would keep its position/health but look like (and
	# fight as) a completely different enemy after a revisit.
	enemy.attacker_weapon = data.get("attacker_weapon", enemy.attacker_weapon)
	enemy.attacker_element = data.get("attacker_element", enemy.attacker_element)
	if data.get("is_dead", false):
		enemy.is_dead = true
		return
	enemy.position = to_local(data.get("position", enemy.global_position))
	enemy.health = data.get("health", enemy.health)

func record_enemy_state(enemy: Enemy) -> void:
	if room_key == "":
		return
	var state: Dictionary = Stats.expedition_room_state.get(room_key, {})
	state[enemy.name] = {
		"is_dead": enemy.is_dead,
		"position": enemy.global_position,
		"health": enemy.health,
		"attacker_weapon": enemy.attacker_weapon,
		"attacker_element": enemy.attacker_element,
	}
	Stats.expedition_room_state[room_key] = state

# Called by world_rooms.gd on this room's "enemies" node right before the
# room scene is freed, so leaving and coming back later this same
# expedition finds things as they were left instead of a fresh roll.
func save_state() -> void:
	if room_key == "":
		return
	var still_present := {}
	for child in get_children():
		if child is Enemy:
			still_present[child.name] = true
			record_enemy_state(child)
	# Anything recorded (from spawn time or an earlier visit) that isn't in
	# the tree anymore was killed since then — queue_free() (triggered by
	# is_dead's setter) is the only way an enemy node disappears, so
	# there's no live node left to read it from, but the fact that it's
	# gone still counts.
	var state: Dictionary = Stats.expedition_room_state.get(room_key, {})
	for recorded_name in state.keys():
		if !still_present.has(recorded_name):
			state[recorded_name]["is_dead"] = true
	Stats.expedition_room_state[room_key] = state

func pick_spawn_position(
	point: Marker2D, rng: RandomNumberGenerator, map_rid: RID, placed_positions: Array[Vector2]
) -> Vector2:
	for attempt in SPAWN_PLACEMENT_ATTEMPTS:
		var offset := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU)) * rng.randf_range(0.0, group_spread)
		var desired_pos := point.global_position + offset
		# Snap onto the nav mesh so a random offset can't drop an enemy
		# inside a wall. Don't trust a wildly distant snap though (e.g. if
		# even the marker's own neighborhood has no coverage) — better to
		# stack a couple enemies right on the marker than scatter one
		# somewhere unrelated on the map.
		var safe_pos := NavigationServer2D.map_get_closest_point(map_rid, desired_pos)
		if safe_pos.distance_to(desired_pos) > group_spread * 2.0:
			safe_pos = point.global_position
		var far_enough := true
		for other_pos in placed_positions:
			if safe_pos.distance_to(other_pos) < MIN_SPAWN_DISTANCE:
				far_enough = false
				break
		if far_enough:
			return safe_pos
	# Every random attempt landed too close to a sibling already placed —
	# fall back to a deterministic ring around the marker instead of
	# retrying forever (or worse, giving up and risking an exact-overlap
	# duplicate of a previous member's position).
	var ring_angle := TAU * placed_positions.size() / 6.0
	return point.global_position + Vector2.RIGHT.rotated(ring_angle) * MIN_SPAWN_DISTANCE
