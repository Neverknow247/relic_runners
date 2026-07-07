extends CharacterBody2D
class_name Enemy

# Multiplayer authority is left at the Godot default (peer 1 / the server) —
# unlike players, no single peer owns an enemy, so nothing calls
# set_multiplayer_authority() here.

const WEAPON_TYPES := ["tome", "orb", "wand"]
const ELEMENT_TYPES := ["fire", "holy", "air"]

const WEAPON_LETTERS := {
	"tome": "T",
	"orb": "O",
	"wand": "W",
}

var all_spell_data = SpellData.new()
var all_spell_recipes = SpellRecipes.new()

@export var max_health := 100.0
var health := max_health
var is_dead := false:
	set(value):
		is_dead = value
		if value:
			velocity = Vector2.ZERO
			if visual_root:
				visual_root.visible = false
			if hurtbox:
				hurtbox.is_invincible = true
			# TODO: loot spawning hooks in here later. No death animation to
			# wait on, so free immediately rather than leaving a corpse
			# sitting invisible in the tree forever.
			queue_free()

@export var move_speed := 240.0

# Casting behavior: stays put and casts while the target is within
# cast_range and in line of sight; otherwise closes the distance. Fire rate
# is no longer a flat timer — it's set per-shot from the same
# FORMS[form]["attack_cooldown"] the player uses, so the enemy can loose
# spells exactly as often as a player with the same weapon/form could.
@export var cast_range := 640.0
@export var tap_interval := 0.35
@export var normal_cast_chance := 0.4
var cast_timer := 0.0
var tap_timer := 0.0
var spell_input_sequence: Array[int] = []
var target_recipe_sequence: Array = []

# Facing/vision cone: LOS is only granted within fov_degrees of the
# direction the enemy is currently facing, and facing turns toward whatever
# it's tracking (the point it's aiming at while casting, or its travel
# direction while chasing) at a limited rate rather than snapping — so a
# target directly behind it is genuinely out of view until it turns.
@export var fov_degrees := 160.0
@export var turn_speed := 6.0
var facing_direction := Vector2.DOWN
var current_visible_point := Vector2.ZERO
@onready var facing_indicator: Node2D = $visual_root/facing_indicator
const FACING_INDICATOR_DISTANCE := 48.0

# This enemy's own weapon/element identity — used both when it casts spells
# (as the attacker) and when a player's spell hits it (as the defender),
# same as a player's equipped Weapon serves both roles. Replicated so every
# peer shows the same color/letter and applies the same matchups regardless
# of who detects a given hit.
var attacker_weapon: String = "tome":
	set(value):
		attacker_weapon = value
		_update_visual()
var attacker_element: String = "fire":
	set(value):
		attacker_element = value
		_update_visual()

@onready var hurtbox: Hurtbox = $hurtbox
@onready var detection_area: Area2D = $detection_area
@onready var visual_root: Node2D = $visual_root
@onready var color_rect: ColorRect = $visual_root/color_rect
@onready var weapon_label: Label = $visual_root/weapon_label
@onready var nav_agent: NavigationAgent2D = $nav_agent

var targets_in_range: Array[Hurtbox] = []
var current_target: Hurtbox = null

# Only updated while we can actually see the target — this is where we
# path to once LOS breaks, not their live position. If we arrive there
# without re-spotting them, we give up (current_target = null) instead of
# omnisciently continuing to track wherever they currently are.
var last_known_position: Vector2 = Vector2.ZERO

# Corner-easing: if we're barely moving over a short window while trying to
# chase (jammed against a corner), stop pushing straight at the next
# waypoint and instead slide along the wall we're stuck on. Checked over a
# window rather than per-frame, since normal per-frame movement is already
# smaller than a naive single-frame threshold would allow for.
var last_stuck_check_position: Vector2 = Vector2.ZERO
var stuck_check_timer := 0.0
var is_easing_around_corner := false
const STUCK_CHECK_INTERVAL := 0.2
const STUCK_DISTANCE := 32.0

# Enemies now collide with each other (see enemy.tscn's collision_mask), so
# hard collision alone would otherwise just shove them into each other's
# blocked-path handling and feel jerky. A soft steering push away from
# anyone crowding closer than min_enemy_separation, blended continuously
# into the movement velocity, keeps a little personal space without them
# ever having to hard-stop against one another.
@export var min_enemy_separation := 28.0
const BODY_RADIUS := 28.0
const SEPARATION_CHECK_RADIUS := 160.0
const SEPARATION_RESPONSE := 6.0

# When we give up on a target (arrived at their last known position without
# re-spotting them), that same target is ineligible for re-acquisition for a
# brief moment — otherwise a single flickering frame of LOS right where we
# just stood (very plausible, since give-up happens right at/near the
# corner they were last seen at) would re-lock on with no real gap at all.
# Short enough that it's just an anti-flicker guard, not a real delay.
var recently_lost_target: Hurtbox = null
var lost_target_cooldown := 0.0
const LOST_TARGET_COOLDOWN := 0.5

# Even with zero LOS, a target close enough to hear is still "known" —
# footsteps/casting noise don't care about walls or the vision cone the way
# sight does, so this check is pure distance, no shape-cast or FOV test.
# But a perfectly still player makes no noise to hear in the first place, so
# hearing-based ACQUISITION (not ongoing awareness of an already-known
# target — see the separate can_hear check in _physics_process) additionally
# requires them to have actually moved since last physics frame.
@export var hearing_radius := 256.0
var last_target_positions: Dictionary = {}
var target_is_moving: Dictionary = {}
const MOVEMENT_THRESHOLD := 2.0

# Getting hit from outside our vision/hearing range (a shot from off-screen
# or from behind, out of the cone) has no current_target to chase — but it
# shouldn't be a total non-event either. We pick a random reachable point
# roughly where the shot direction points and go investigate. If nothing
# navigable turns up near that guess (e.g. it's inside/behind a wall), we
# still walk toward the edge of our own vision range in that direction
# instead of just standing there.
@export var investigate_distance := 560.0
@export var investigate_jitter := 160.0
const INVESTIGATE_ATTEMPTS := 8
const MIN_INVESTIGATE_DISTANCE := 96.0
var is_investigating := false
var investigate_target := Vector2.ZERO

# When there's nothing to chase, react to, or investigate, the enemy
# alternates between wandering to a random reachable point near its spawn
# and pausing to "look around" (search) before picking the next wander
# point. Each search has a small chance of relocating "home" (spawn_position)
# to right where the enemy is standing, so a wandering enemy can gradually
# drift to a new area over time instead of being tied to its original spot
# forever.
enum IdleState { WANDER, SEARCH }
@export var wander_radius := 960.0
@export var wander_radius_variance := 80.0
@export var search_duration := 16.0
@export var search_duration_variance := 2.0
@export var search_turn_speed := 1.0
@export var search_turn_speed_variance := 0.3
@export var new_spawn_chance := 0.05
const WANDER_SNAP_TOLERANCE := 160.0
var spawn_position := Vector2.ZERO
var idle_state: int = IdleState.WANDER
var wander_target := Vector2.ZERO
var wander_target_valid := false
var search_timer := 0.0
# Rolled once per enemy at spawn so it stays consistent for that enemy's
# whole lifetime, rather than being different every single search — the
# goal is desyncing different enemies from each other, not variety within
# one enemy's own repeated cycles.
var actual_search_turn_speed := 0.0

# Region RIDs existing on the nav map doesn't guarantee their polygon data
# has actually finished syncing into it yet — map_get_iteration_id() > 0
# wasn't a reliable signal for this (see _physics_process's guard), so
# this counts consecutive frames of "the map reports regions" and only
# trusts it once that's held for a few frames running, not just once.
var nav_ready_frames := 0
const NAV_READY_FRAME_MARGIN := 3

# If we're stuck fighting a corner (is_easing_around_corner staying true)
# for too long while wandering, the picked point is unreachable in practice
# — abandon it and roll a new one rather than grinding against the wall
# forever.
var wander_stuck_time := 0.0
const WANDER_STUCK_TIMEOUT := 1.0

# Hard backstop independent of the above: wander_stuck_time resets to 0 the
# instant any single 0.2s window shows enough movement, which incidental
# jitter (a nearby enemy's separation push, a glancing bounce off the wall)
# can trigger repeatedly without ever adding up to real progress — letting
# an enemy stay wedged against a wall indefinitely instead of the ~1 second
# that mechanism is supposed to guarantee. This timer can't be reset by
# anything short of actually finishing or abandoning the leg, so it's a
# real ceiling on how long any single wander leg can run.
var wander_leg_timer := 0.0
var wander_leg_max_duration := 0.0
const WANDER_LEG_TIMEOUT_MULTIPLIER := 4.0
const WANDER_LEG_MIN_TIMEOUT := 6.0

# After losing an actively-chased player (not just giving up on an
# investigation), the enemy wanders 0-3 times before deliberately heading
# back to spawn_position once, then resumes free wandering from there.
# -1 means "not in that countdown" (normal free-roaming).
var post_chase_wanders_remaining := -1

# Group behavior: a follower has no wander/search logic of its own — it just
# treats its leader's current position as if it were its own spawn_position,
# so it drifts along with wherever the leader wanders instead of sitting at
# a fixed point. Combat (LOS/hearing/casting/investigating) is entirely
# independent per enemy either way; this only changes the wander anchor.
# null means "no leader" — either always solo, or the leader has died and
# this enemy already got promoted (or fell back) to being its own leader.
var leader: Enemy = null

# All members of this enemy's spawn group (including the leader), the SAME
# Array object shared by reference across every member — set once by
# enemy_spawner.gd. Never pruned in place (see promote_new_leader(), which
# filters into a local copy instead) so every member's view of "who's still
# around" stays consistent within a frame regardless of processing order.
var group: Array[Enemy] = []

func get_wander_anchor() -> Vector2:
	if leader != null and is_instance_valid(leader) and !leader.is_dead:
		return leader.global_position
	return spawn_position

# Runs on every surviving follower once their leader is confirmed gone.
# Rather than each one independently going solo, the group promotes its
# most-senior surviving member (deterministic: first non-dead entry in the
# shared, never-mutated group list) to be the new leader, and everyone else
# just follows them instead. Safe to call redundantly from multiple
# members in the same frame regardless of _physics_process order — see the
# comment on `group` above.
func promote_new_leader() -> void:
	var survivors: Array = group.filter(func(m): return is_instance_valid(m) and !m.is_dead)
	if survivors.is_empty():
		spawn_position = global_position
		leader = null
		return
	var new_leader: Enemy = null
	for m in survivors:
		if m.leader == null:
			new_leader = m
			break
	if new_leader == null:
		new_leader = survivors[0]
	if new_leader == self:
		spawn_position = global_position
		leader = null
	else:
		leader = new_leader

# Groupmates within earshot of whatever just happened (spotting the player,
# or getting hit by them) react too, instead of only the one enemy that
# actually noticed anything. known_target null means we only have a rough
# direction (e.g. a blind hit), so nearby idle groupmates go investigate
# that point rather than being handed a definite lock they didn't earn.
func alert_nearby_group(known_target: Hurtbox, known_point: Vector2) -> void:
	for member in group:
		if member == self or !is_instance_valid(member) or member.is_dead:
			continue
		if member.current_target != null:
			continue
		if global_position.distance_to(member.global_position) > hearing_radius:
			continue
		if known_target != null:
			member.current_target = known_target
			member.last_known_position = known_point
		else:
			member.start_investigating(member.global_position.direction_to(known_point))

func _ready() -> void:
	hurtbox.hurt.connect(_on_hurtbox_hurt)
	detection_area.area_entered.connect(_on_detection_area_entered)
	detection_area.area_exited.connect(_on_detection_area_exited)
	# name.hash() (not get_instance_id()) so this identifier is identical on
	# every peer's local copy of this same static, room-baked enemy —
	# get_instance_id() is process-local and would differ per peer, silently
	# breaking self-hit exclusion on whichever clients don't match.
	hurtbox.owner_id = name.hash()
	if is_multiplayer_authority():
		attacker_weapon = WEAPON_TYPES.pick_random()
		attacker_element = ELEMENT_TYPES.pick_random()
		spawn_position = global_position
		actual_search_turn_speed = max(0.1, search_turn_speed + randf_range(-search_turn_speed_variance, search_turn_speed_variance))
		# Start idle by looking around rather than immediately wandering off.
		idle_state = IdleState.SEARCH
		search_timer = search_duration + randf_range(-search_duration_variance, search_duration_variance)
	_update_visual()

func _update_visual() -> void:
	if !color_rect or !weapon_label:
		return
	var element_data: Dictionary = SpellData.ELEMENTS.get(attacker_element, SpellData.ELEMENTS["default"])
	color_rect.color = element_data["color"]
	weapon_label.text = WEAPON_LETTERS.get(attacker_weapon, "?")

func _physics_process(delta: float) -> void:
	if !is_multiplayer_authority():
		return
	if is_dead:
		return
	if NavigationServer2D.map_get_regions(nav_agent.get_navigation_map()).is_empty():
		# The nav map hasn't finished its first sync yet (region registration
		# happens a frame or so after scene load) — every NavigationServer2D
		# query against an empty map returns Vector2.ZERO instead of a real
		# snapped point, which is exactly (0, 0), i.e. this room's own
		# player spawn point. Querying it this early was making every
		# freshly-spawned enemy's very first wander target resolve to the
		# player's spawn, making it look like they'd all beelined straight
		# there the instant the room loaded. Just wait for it to sync
		# instead of trusting a bogus result.
		nav_ready_frames = 0
		velocity = Vector2.ZERO
		move_and_slide()
		return
	nav_ready_frames += 1
	if nav_ready_frames <= NAV_READY_FRAME_MARGIN:
		# Regions existing doesn't guarantee their polygon data has fully
		# synced into the map yet either — a few frames of margin past
		# that first sign of life is cheap insurance against the exact
		# same bug recurring.
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if leader != null and (!is_instance_valid(leader) or leader.is_dead):
		promote_new_leader()
	cast_timer = max(cast_timer - delta, 0.0)
	lost_target_cooldown = max(lost_target_cooldown - delta, 0.0)
	update_current_target()
	if current_target != null:
		is_investigating = false
	if current_target == null:
		if is_investigating:
			if follow_nav_path(delta, investigate_target):
				is_investigating = false
		else:
			update_idle(delta)
		reset_casting()
		move_and_slide()
		if facing_indicator:
			facing_indicator.position = facing_direction * FACING_INDICATOR_DISTANCE
		return
	var visible_point = get_visible_point(current_target)
	var can_see := visible_point != null
	var distance := global_position.distance_to(current_target.global_position)
	var can_hear := distance <= hearing_radius
	# Hearing reveals location the same as sight would (no wall/FOV check),
	# but only sight lets us aim — you can't snipe someone you only hear
	# through a wall, so current_visible_point stays sight-only.
	var aware := can_see or can_hear
	if aware:
		last_known_position = current_target.global_position
	if can_see:
		current_visible_point = visible_point

	if can_see and distance <= cast_range:
		velocity = compute_separation()
		update_facing(delta, current_visible_point - global_position)
		update_casting(delta)
		stuck_check_timer = 0.0
		is_easing_around_corner = false
	else:
		# Chase the live position while we're still aware of them (in sight
		# or in earshot) — otherwise head for their last-known spot and give
		# up once we get there without re-spotting/re-hearing them.
		var chase_target := current_target.global_position if aware else last_known_position
		if follow_nav_path(delta, chase_target) and !aware:
			recently_lost_target = current_target
			lost_target_cooldown = LOST_TARGET_COOLDOWN
			current_target = null
			# Just lost an actively-chased player — start the wander/return
			# cycle fresh rather than resuming whatever idle state we were
			# in before we ever spotted them.
			post_chase_wanders_remaining = randi_range(0, 3)
			idle_state = IdleState.WANDER
			wander_target_valid = false
		reset_casting()
	move_and_slide()
	if facing_indicator:
		facing_indicator.position = facing_direction * FACING_INDICATOR_DISTANCE

# Steps one physics frame toward target_position along the nav mesh,
# gliding around corners we're jammed against. Returns true once arrived
# (navigation finished) so callers can decide what "arrived" means for them
# (give up on a target, stop investigating, etc).
func follow_nav_path(delta: float, target_position: Vector2) -> bool:
	nav_agent.target_position = target_position
	stuck_check_timer -= delta
	if stuck_check_timer <= 0.0:
		var moved := global_position.distance_to(last_stuck_check_position)
		is_easing_around_corner = moved < STUCK_DISTANCE
		last_stuck_check_position = global_position
		stuck_check_timer = STUCK_CHECK_INTERVAL
	if nav_agent.is_navigation_finished():
		velocity = compute_separation()
		return true
	var next_point: Vector2 = nav_agent.get_next_path_position()
	var desired_velocity := global_position.direction_to(next_point) * move_speed
	if is_easing_around_corner and get_slide_collision_count() > 0:
		# Average every simultaneous WALL collision's normal rather than
		# just the first one — at a concave (inside) corner, two walls can
		# both be colliding the same frame, and a tangent based on only one
		# of them often points straight into the other, keeping us stuck
		# even with easing "on". The averaged normal points roughly out of
		# the corner vertex, so its tangent actually clears both walls.
		# Other enemies are excluded here — they're moving too, so gliding
		# along a tangent computed from one instant of their normal is
		# jittery and doesn't represent stable geometry; separation
		# (below) handles enemy-enemy spacing instead.
		var normal_sum := Vector2.ZERO
		var wall_hits := 0
		for i in get_slide_collision_count():
			var collision := get_slide_collision(i)
			if collision.get_collider() is Enemy:
				continue
			normal_sum += collision.get_normal()
			wall_hits += 1
		if wall_hits > 0:
			var normal: Vector2 = normal_sum.normalized()
			var tangent := Vector2(-normal.y, normal.x)
			if tangent.dot(desired_velocity) < 0.0:
				tangent = -tangent
			desired_velocity = tangent * move_speed
	velocity = desired_velocity + compute_separation()
	update_facing(delta, velocity)
	return false

# Soft push away from any other enemy crowding closer than
# min_enemy_separation, scaled by how much that gap is being violated.
# Continuous and additive rather than a hard stop, so a group moving
# together drifts apart smoothly instead of jamming against each other.
func compute_separation() -> Vector2:
	var space_state := get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = SEPARATION_CHECK_RADIUS
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = 32
	query.exclude = [get_rid()]
	var results := space_state.intersect_shape(query, 8)
	var desired_min := BODY_RADIUS * 2.0 + min_enemy_separation
	var push := Vector2.ZERO
	for result in results:
		var other = result.get("collider")
		if other == self or not other is Enemy:
			continue
		var offset: Vector2 = global_position - other.global_position
		var dist := offset.length()
		if dist >= desired_min:
			continue
		# When exactly overlapping, offset.normalized() is undefined — pick
		# a direction from the two instance IDs rather than randf(), so
		# it's the same every frame instead of re-rolling and making them
		# jitter in a new random direction each tick while never actually
		# separating.
		var dir := offset.normalized() if dist > 0.001 \
			else Vector2.RIGHT.rotated(float(get_instance_id() - other.get_instance_id()))
		push += dir * (desired_min - dist)
	return push * SEPARATION_RESPONSE

func start_investigating(direction: Vector2) -> void:
	# 95% of the time head roughly toward the shot (the original behavior);
	# 5% of the time flee roughly away from it instead — keeps a
	# blindsided enemy from being 100% predictable.
	var chosen_direction := direction if randf() < 0.95 else -direction
	var map_rid := nav_agent.get_navigation_map()
	var guess := global_position + chosen_direction * investigate_distance
	for i in INVESTIGATE_ATTEMPTS:
		var candidate := guess + Vector2(
			randf_range(-investigate_jitter, investigate_jitter),
			randf_range(-investigate_jitter, investigate_jitter)
		)
		var snapped := NavigationServer2D.map_get_closest_point(map_rid, candidate)
		# map_get_closest_point always returns *some* point on the mesh, even
		# if the candidate was far off it (e.g. inside a wall) — only trust
		# it as "near where the shot came from" if it didn't have to move
		# the candidate more than our own jitter radius to get there. Also
		# reject anything too close to where we're already standing — that
		# would count as "arrived" on the very first frame, making the
		# enemy appear to not react to the hit at all.
		if snapped.distance_to(candidate) <= investigate_jitter \
				and snapped.distance_to(global_position) >= MIN_INVESTIGATE_DISTANCE:
			investigate_target = snapped
			is_investigating = true
			return
	# No usable point near the guess — at least head toward the edge of our
	# own vision range in that direction instead of not reacting at all.
	var edge_point := global_position + chosen_direction * cast_range
	investigate_target = safe_snap_to_nav(edge_point, investigate_jitter * 1.5)
	is_investigating = true

func update_idle(delta: float) -> void:
	match idle_state:
		IdleState.WANDER:
			if !wander_target_valid:
				pick_next_wander_target()
			if wander_target_valid:
				wander_leg_timer += delta
				var arrived := follow_nav_path(delta, wander_target)
				if is_easing_around_corner:
					wander_stuck_time += delta
					if wander_stuck_time >= WANDER_STUCK_TIMEOUT:
						# Stuck fighting this corner too long — this point
						# isn't practically reachable, so give up on it and
						# roll a fresh one next frame instead of grinding here.
						wander_target_valid = false
						wander_stuck_time = 0.0
				else:
					wander_stuck_time = 0.0
				if wander_target_valid and wander_leg_timer >= wander_leg_max_duration:
					# Absolute backstop: the check above can keep getting
					# reset by incidental jitter that never amounts to real
					# progress, so this timer — which nothing but finishing
					# or abandoning the leg can reset — guarantees a real
					# ceiling on how long any single wander leg can run.
					wander_target_valid = false
					wander_stuck_time = 0.0
				if arrived:
					idle_state = IdleState.SEARCH
					search_timer = search_duration + randf_range(-search_duration_variance, search_duration_variance)
					wander_stuck_time = 0.0
		IdleState.SEARCH:
			velocity = compute_separation()
			# No fixed "desired" direction here (that's what update_facing
			# eases toward) — searching is a continuous sweep, so just spin
			# facing_direction directly at a steady rate.
			facing_direction = facing_direction.rotated(actual_search_turn_speed * delta)
			search_timer -= delta
			if search_timer <= 0.0:
				if randf() < new_spawn_chance:
					spawn_position = global_position
				wander_target_valid = false
				# Fresh baseline so the corner-stuck check doesn't compare
				# against a stale pre-search position and immediately think
				# we're jammed the instant we start moving again.
				last_stuck_check_position = global_position
				stuck_check_timer = STUCK_CHECK_INTERVAL
				idle_state = IdleState.WANDER

func pick_next_wander_target() -> void:
	# Varying the radius per-leg (on top of pick_random_point_near's own
	# random angle/distance within it) gives each leg a slightly different
	# reach — and therefore a slightly different travel time — so a whole
	# group of enemies doesn't visibly settle into the same wander rhythm.
	var radius = max(1.0, wander_radius + randf_range(-wander_radius_variance, wander_radius_variance))
	var anchor := get_wander_anchor()
	if post_chase_wanders_remaining > 0:
		post_chase_wanders_remaining -= 1
		wander_target = pick_random_point_near(anchor, radius)
	elif post_chase_wanders_remaining == 0:
		# Countdown's up — head deliberately back toward our anchor (the
		# leader, if we still have one, otherwise our own spawn) once, then
		# go back to free-roaming wander/search from there.
		post_chase_wanders_remaining = -1
		wander_target = safe_snap_to_nav(anchor, radius * 1.5)
	else:
		wander_target = pick_random_point_near(anchor, radius)
	wander_target_valid = true
	wander_leg_timer = 0.0
	wander_leg_max_duration = max(
		WANDER_LEG_MIN_TIMEOUT,
		global_position.distance_to(wander_target) / move_speed * WANDER_LEG_TIMEOUT_MULTIPLIER
	)

func pick_random_point_near(center: Vector2, radius: float) -> Vector2:
	var map_rid := nav_agent.get_navigation_map()
	for i in INVESTIGATE_ATTEMPTS:
		var candidate := center + Vector2.RIGHT.rotated(randf_range(0.0, TAU)) * randf_range(0.0, radius)
		var snapped := NavigationServer2D.map_get_closest_point(map_rid, candidate)
		if snapped.distance_to(candidate) <= WANDER_SNAP_TOLERANCE:
			return snapped
	return safe_snap_to_nav(center, radius * 1.5)

# map_get_closest_point always returns *some* point on the mesh — if center
# itself isn't actually near any navigable tile (e.g. an enemy_spawn marker
# sitting outside the baked navigation area), that "closest point anywhere
# on the whole map" can be clear across the level. Rather than let that drag
# an enemy off toward some unrelated part of the map, only trust it within
# max_distance of what we asked for; otherwise just stay where we are.
func safe_snap_to_nav(point: Vector2, max_distance: float) -> Vector2:
	var snapped := NavigationServer2D.map_get_closest_point(nav_agent.get_navigation_map(), point)
	if snapped.distance_to(point) <= max_distance:
		return snapped
	return point

func update_facing(delta: float, desired: Vector2) -> void:
	if desired.length_squared() < 0.0001:
		return
	var target_angle := desired.angle()
	var new_angle := rotate_toward(facing_direction.angle(), target_angle, turn_speed * delta)
	facing_direction = Vector2.RIGHT.rotated(new_angle)

const LOS_PEEK_RADIUS := 24.0
const LOS_PEEK_OFFSETS: Array[Vector2] = [
	Vector2.ZERO,
	Vector2(LOS_PEEK_RADIUS, 0), Vector2(-LOS_PEEK_RADIUS, 0),
	Vector2(0, LOS_PEEK_RADIUS), Vector2(0, -LOS_PEEK_RADIUS),
]

func has_line_of_sight(target: Hurtbox) -> bool:
	return get_visible_point(target) != null

# Returns the world-space point we can actually see on target (so callers
# can aim at what's really exposed instead of a possibly-blocked dead
# center), or null if no part of them is both within our fov_degrees vision
# cone and unobstructed.
func get_visible_point(target: Hurtbox) -> Variant:
	# A zero-width ray (or even a few parallel rays) can still slip through
	# the single-point diagonal gap where two wall tiles meet corner-to-
	# corner. Sweeping an actual circle shape along the path has real width
	# the whole way, so it can't pass through a gap smaller than its
	# diameter — geometrically closes off the pinhole case entirely.
	var space_state := get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = 16.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var half_fov := deg_to_rad(fov_degrees * 0.5)
	# Check center-to-center first, then a few points around the target's
	# body (peek offsets) rather than just its dead center — someone peeking
	# out from behind a corner has their center still hidden but an edge of
	# them already exposed, and that should count as spotted just like it
	# would for a person actually looking.
	for offset in LOS_PEEK_OFFSETS:
		var point := target.global_position + offset
		var to_point := point - global_position
		if to_point.length_squared() > 0.0001 and absf(facing_direction.angle_to(to_point)) > half_fov:
			continue
		query.transform = Transform2D(0.0, global_position)
		query.motion = to_point
		var result := space_state.cast_motion(query)
		if result.is_empty() or result[0] >= 1.0:
			return point
	return null

func update_current_target() -> void:
	targets_in_range = targets_in_range.filter(func(h): return is_instance_valid(h))
	# Track "moved since last physics frame" for every target in range,
	# every frame, regardless of whether we end up needing it below — doing
	# this unconditionally (rather than only inside the filter lambda) keeps
	# it measuring "since last frame" instead of "since we last happened to
	# check", which would misreport a player who just walked up and stopped
	# as still moving.
	for h in targets_in_range:
		var last: Vector2 = last_target_positions.get(h, h.global_position)
		target_is_moving[h] = h.global_position.distance_to(last) >= MOVEMENT_THRESHOLD
		last_target_positions[h] = h.global_position
	# Leaving detection_area's radius must NOT clear current_target — that's
	# exactly the "walked around a corner" case we want to keep chasing the
	# last known position through. Only drop it here if the hurtbox itself
	# is gone; actually losing an active chase is the give-up logic's job
	# (arriving at last_known_position without re-spotting them).
	if current_target and !is_instance_valid(current_target):
		current_target = null
	# Acquiring a NEW target requires either line of sight or being within
	# earshot AND actually moving (a perfectly still player makes no noise
	# to hear) — sight alone would mean no detecting through walls just by
	# proximity, but close enough to hear a moving target bypasses that
	# entirely. Once engaged, losing both mid-chase doesn't drop the target
	# immediately either (see the give-up logic in _physics_process), so the
	# enemy can still pursue your last known position instead of forgetting
	# you the instant you turn a corner.
	if current_target == null and !targets_in_range.is_empty():
		for h in targets_in_range:
			var dist := global_position.distance_to(h.global_position)
			if dist <= hearing_radius:
				print(
					"[Enemy hearing check] name=", name, " dist=", dist,
					" hearing_radius=", hearing_radius,
					" moving=", target_is_moving.get(h, false),
					" last=", last_target_positions.get(h, "none"),
					" current=", h.global_position,
					" on_cooldown=", h == recently_lost_target and lost_target_cooldown > 0.0
				)
		var detectable: Array = targets_in_range.filter(func(h):
			if h == recently_lost_target and lost_target_cooldown > 0.0:
				return false
			if global_position.distance_to(h.global_position) <= hearing_radius:
				return target_is_moving.get(h, false)
			return has_line_of_sight(h)
		)
		if !detectable.is_empty():
			current_target = _closest_target(detectable)
			alert_nearby_group(current_target, current_target.global_position)

func _closest_target(hurtboxes: Array) -> Hurtbox:
	var closest: Hurtbox = null
	var closest_dist := INF
	for h in hurtboxes:
		var dist := global_position.distance_to(h.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = h
	return closest

func reset_casting() -> void:
	spell_input_sequence.clear()
	target_recipe_sequence.clear()
	tap_timer = 0.0

func update_casting(delta: float) -> void:
	if !target_recipe_sequence.is_empty():
		tap_timer -= delta
		if tap_timer <= 0.0:
			enter_next_tap()
		return
	if cast_timer <= 0.0:
		start_new_cast()

func start_new_cast() -> void:
	var forms: Array = SpellData.EQUIPPABLE_WEAPONS[attacker_weapon]["forms"]
	var recipes: Array = all_spell_recipes.get_available_recipes(attacker_element, forms)
	if recipes.is_empty() or randf() < normal_cast_chance:
		cast_default()
		return
	var recipe: Dictionary = recipes.pick_random()
	target_recipe_sequence = recipe["sequence"].duplicate()
	tap_timer = tap_interval

func enter_next_tap() -> void:
	var next_index := spell_input_sequence.size()
	if next_index >= target_recipe_sequence.size():
		reset_casting()
		return
	spell_input_sequence.append(target_recipe_sequence[next_index])
	tap_timer = tap_interval
	if spell_input_sequence.size() >= target_recipe_sequence.size():
		cast_sequence()

func cast_sequence() -> void:
	var recipe := all_spell_recipes.get_spell_recipe_from_sequence(spell_input_sequence)
	if recipe.is_empty():
		cast_default()
	else:
		fire_spell(attacker_weapon, recipe["element"], recipe["form"])
	reset_casting()

func cast_default() -> void:
	fire_spell(attacker_weapon, attacker_element, "default")

func fire_spell(weapon: String, element: String, form: String) -> void:
	if current_target == null:
		return
	# Aim at the actual point of them we can see (may be an edge peeking
	# past a corner) rather than their dead center, which could still be
	# behind cover even while some part of them is exposed.
	var direction := global_position.direction_to(current_visible_point)
	var spell_data := all_spell_data.build_spell_data(weapon, element, form)
	spawn_projectile.rpc(weapon, element, form, direction)
	# Same per-form cooldown table the player's attack_check() uses, so the
	# enemy fires exactly as often as a player equipped with this weapon/
	# form could — not a flat, unrelated timer.
	cast_timer = spell_data["attack_cooldown"]

@rpc("authority", "call_local", "reliable")
func spawn_projectile(weapon: String, element: String, form: String, direction: Vector2) -> void:
	var spell_data := all_spell_data.build_spell_data(weapon, element, form)
	var projectile = spell_data["scene"].instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = global_position + direction * spell_data["spawn_offset"]
	projectile.setup_spell(direction, spell_data, name.hash())

func _on_detection_area_entered(area: Area2D) -> void:
	if area is Hurtbox:
		targets_in_range.append(area)
		print("[Enemy detect area] name=", name, " entered=", area.name, " owner_id=", area.owner_id)

func _on_detection_area_exited(area: Area2D) -> void:
	if area is Hurtbox:
		targets_in_range.erase(area)

func _on_hurtbox_hurt(hitbox, damage) -> void:
	if !is_multiplayer_authority():
		return
	var final_damage: float = damage
	if hitbox != null and "attacker_weapon" in hitbox and "attacker_element" in hitbox:
		var multiplier := SpellData.get_damage_multiplier(
			hitbox.attacker_weapon,
			hitbox.attacker_element,
			attacker_weapon,
			attacker_element
		)
		final_damage = damage * multiplier
	# Getting hit is an instant, unmissable cue of where the attack came
	# from — snap facing straight there instead of easing over with
	# turn_speed like normal tracking does.
	if hitbox != null and is_instance_valid(hitbox):
		var to_attacker = hitbox.global_position - global_position
		if to_attacker.length_squared() > 0.0001:
			facing_direction = to_attacker.normalized()
			# Only start investigating if we're not already tracking someone —
			# a hit that lands while we're engaged doesn't need this, we
			# already know roughly where the threat is.
			if current_target == null:
				start_investigating(facing_direction)
			# Getting attacked alerts nearby groupmates too — use our actual
			# current_target's live position if we have one (more accurate
			# than the hit itself), otherwise just the point we were hit
			# from, same as what we just used to start our own investigation.
			var alert_point = current_target.global_position if current_target != null else hitbox.global_position
			alert_nearby_group(current_target, alert_point)
	take_damage(final_damage)

func take_damage(amount: float) -> void:
	if is_dead:
		return
	health = clamp(health - amount, 0.0, max_health)
	if health <= 0.0:
		die()

func die() -> void:
	is_dead = true
