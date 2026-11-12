extends Projectile
class_name WaveProjectile

# Wave: a fixed-width wall of force that rolls forward along the ground
# (docs/combat_redesign_plan.md §3). Hits each target once, stops when its
# CENTRE meets a wall (the ends may clip corners), and CARRIES enemies it
# overlaps: the server's copy pushes each one along (enemy.apply_carry), and an
# enemy shoved into a wall takes a slam. An enemy-cast wave only lightly pushes
# the local player (victim's own peer), never locks them, and can be rolled
# through. Runs on every peer like every other form; damage still lands once
# because take_hit only applies on the target's authority.
#
# Must not reference SpellData or Enemy (preload cycle: spell_data.gd preloads this
# scene, enemy.gd references SpellData): duck-type via has_method, data via spell_data.

const WALL_MASK := 1
# The rectangle lives in the scene (96 deep x 640 wide); mirror it for drawing.
const HALF_DEPTH := 48.0
const HALF_WIDTH := 320.0
const WALL_PROBE := 48.0
# Fraction of the wave's damage an enemy takes when carried into a wall.
const WALL_SLAM_FRACTION := 0.5
# Release fling when the wave dies, so carried enemies don't just stop dead.
const RELEASE_FLING := 600.0
# Enemy-cast wave vs a player: softened push, capped per wave.
const PLAYER_PUSH_FRACTION := 0.5
const PLAYER_PUSH_MAX_SEC := 0.4

var _hit_ids := {}
# instance_id -> Enemy currently being carried (server copy only).
var _carried := {}
var _player_push_left := PLAYER_PUSH_MAX_SEC
var _age := 0.0
var _done := false
# Tidal Wave widens it (ElementForms); drawing + hit shape follow this.
var width_mult := 1.0

func set_width_mult(m: float) -> void:
	width_mult = m
	var cs := get_node_or_null("hitbox/wave_shape") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		var r: RectangleShape2D = cs.shape.duplicate()
		r.size.y = 640.0 * m
		cs.shape = r
	queue_redraw()

func setup_spell(_direction: Vector2, _spell_data: Dictionary, caster_id: int = 0, crit: bool = false):
	super.setup_spell(_direction, _spell_data, caster_id, crit)
	# The scene owns its size; tint is drawn explicitly (works for both sides).
	scale = Vector2.ONE
	modulate = Color.WHITE
	# An enemy's wave only ever affects players, never the pack it rolls through.
	if _enemy_shot:
		hitbox.enemy_zone = true
		remove_from_group("enemy_bullets")
	queue_redraw()

func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if _wall_ahead(delta):
		_expire()
		return
	super._physics_process(delta)
	if _done:
		return
	var server := multiplayer.multiplayer_peer == null or multiplayer.is_server()
	var still_carried := {}
	for area in hitbox.get_overlapping_areas():
		if not area is Hurtbox or not hitbox.can_hit(area):
			continue
		if _wall_between(area.global_position):
			continue
		var target = area.get_parent()
		if not _hit_ids.has(area.owner_id):
			_hit_ids[area.owner_id] = true
			area.take_hit(hitbox, hitbox.damage)
			_fx("hit", area)
		if area.is_player:
			_push_local_player(target, delta)
		elif server and target != null and target.has_method("apply_carry") and spell_data.get("carry", false):
			if target.is_dead:
				continue
			target.apply_carry(direction * speed, self)
			still_carried[target.get_instance_id()] = target
	# Anyone who slipped out the back (or died) is no longer ours to fling.
	_carried = still_carried
	queue_redraw()

# Victim-side only: the local player's own peer moves it (movement is client-
# authoritative), so other peers' copies of this wave do nothing to it.
func _push_local_player(player: Node, delta: float) -> void:
	if not _enemy_shot or _player_push_left <= 0.0:
		return
	if player == null or not player.has_method("apply_push") or not player.is_multiplayer_authority():
		return
	if player.has_method("is_invulnerable") and player.is_invulnerable():
		return
	_player_push_left -= delta
	player.apply_push(direction * speed * PLAYER_PUSH_FRACTION)

# Called by a carried enemy (server) when our push slams it into a wall.
func slam_damage() -> float:
	return hitbox.damage * float(spell_data.get("slam_frac", WALL_SLAM_FRACTION))

func _expire() -> void:
	if _done:
		return
	_done = true
	_fx("expire", global_position)
	var fling: float = RELEASE_FLING * float(spell_data.get("fling_mult", 1.0))
	for e in _carried.values():
		if is_instance_valid(e) and not e.is_dead:
			e.apply_carry_release(direction * fling)
	_carried.clear()
	Fx.puff(get_tree(), global_position, _tint, 2.0)
	queue_free()

func _wall_ahead(delta: float) -> bool:
	var space := get_world_2d().direct_space_state
	var to: Vector2 = global_position + direction * (speed * delta + WALL_PROBE)
	var query := PhysicsRayQueryParameters2D.create(global_position, to)
	query.collision_mask = WALL_MASK
	query.collide_with_areas = false
	return not space.intersect_ray(query).is_empty()

# A target behind cover (relative to the wave's centre) isn't hit or carried.
func _wall_between(target: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, target)
	query.collision_mask = WALL_MASK
	query.collide_with_areas = false
	return not space.intersect_ray(query).is_empty()

# A curling crest: dark rim, element body, bright foam lip on the leading edge,
# fading over the last third of its life. Local +x = travel direction.
func _draw() -> void:
	var life := maxf(lifetime, 0.01)
	var fade := clampf((life - _age) / (life * 0.35), 0.0, 1.0)
	var body := _tint
	body.a = 0.55 * fade
	var rim := Color(0.04, 0.02, 0.06, 0.75 * fade)
	var foam := _tint.lerp(Color.WHITE, 0.75)
	foam.a = 0.95 * fade
	var steps := 16
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / steps
		var y := lerpf(-HALF_WIDTH, HALF_WIDTH, t) * width_mult
		# Bowed front: the middle leads, the ends trail.
		var bow := (1.0 - pow(2.0 * t - 1.0, 2.0)) * 28.0
		outer.append(Vector2(HALF_DEPTH + bow, y))
		inner.append(Vector2(-HALF_DEPTH + bow * 0.4, y))
	var poly := outer.duplicate()
	for i in range(inner.size() - 1, -1, -1):
		poly.append(inner[i])
	draw_colored_polygon(poly, body)
	draw_polyline(poly + PackedVector2Array([poly[0]]), rim, 10.0)
	draw_polyline(outer, foam, 14.0)
	# Trailing wake streaks.
	for k in 5:
		var y := lerpf(-HALF_WIDTH * 0.8, HALF_WIDTH * 0.8, k / 4.0) * width_mult
		var c := foam
		c.a *= 0.4
		draw_line(Vector2(-HALF_DEPTH - 20.0, y), Vector2(-HALF_DEPTH - 110.0, y), c, 8.0)
