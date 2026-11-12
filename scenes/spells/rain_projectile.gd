extends Projectile
class_name RainProjectile

# A stationary ground zone placed at the caster's chosen spot (the mouse, for a
# player; the target's location, for an enemy). It spreads the full computed
# damage across its lifetime's ticks (auto_hit off, so this DoT is the only
# damage) — the whole amount only lands on a target that stays in it the entire
# time. Runs on every peer that spawned it, but take_hit -> _on_hurtbox_hurt only
# applies the health change on each target's own authority, so damage lands once.

const TICK_INTERVAL := 1.0
# Walls are on collision layer 1.
const WALL_MASK := 1
# Stratagem call-down: a target marker sits on the spot for CALL_DOWN_DELAY, then
# the strike lands (burst of FX + sound) and the zone starts ticking. The marker is
# the warning; the full damage lands over the remaining lifetime.
const CALL_DOWN_DELAY := 1.0
var _call_down_left := CALL_DOWN_DELAY
# First tick shortly after the strike lands (once overlaps have a physics frame in).
var _tick_timer := 0.1

func setup_spell(_direction: Vector2, _spell_data: Dictionary, caster_id: int = 0, crit: bool = false):
	super.setup_spell(_direction, _spell_data, caster_id, crit)
	_clamp_to_wall()
	queue_redraw()

func _draw() -> void:
	if _call_down_left > 0.0:
		# Marker: a ring closing in on the spot plus a crosshair.
		var k := 1.0 - _call_down_left / CALL_DOWN_DELAY
		var r := VISUAL_RADIUS * lerpf(1.0, 0.55, k)
		draw_arc(Vector2.ZERO, VISUAL_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 2.0, true)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(1, 1, 1, 0.6 + 0.4 * k), 4.0, true)
		draw_line(Vector2(-VISUAL_RADIUS * 0.3, 0), Vector2(VISUAL_RADIUS * 0.3, 0), Color(1, 1, 1, 0.8), 2.0)
		draw_line(Vector2(0, -VISUAL_RADIUS * 0.3), Vector2(0, VISUAL_RADIUS * 0.3), Color(1, 1, 1, 0.8), 2.0)
	else:
		super._draw()

func _land() -> void:
	queue_redraw()
	_fx("land")
	Fx.shatter(get_tree(), global_position, _tint, clampf(scale.x / 4.0, 1.0, 2.2))
	Fx.shake_at(get_tree(), global_position, 0.5)
	Sounds.play_sfx("explosion", global_position)

# Line-of-sight rule for the targeted placement: if a wall sits between the caster
# and the chosen spot, pull the zone back to just in front of that wall so it
# forms on the wall rather than on its far side. Raycasts from the actual caster
# (resolved from the shared group) to wherever this zone was placed.
func _clamp_to_wall() -> void:
	var caster := _resolve_caster()
	if caster == null:
		return
	var origin: Vector2 = caster.global_position
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(origin, global_position)
	query.collision_mask = WALL_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		# Sit just short of the wall rather than embedded in it.
		var toward: Vector2 = (global_position - origin).normalized()
		global_position = hit["position"] - toward * 64.0

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _call_down_left > 0.0:
		_call_down_left -= delta
		queue_redraw()
		if _call_down_left <= 0.0:
			_land()
		return
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = TICK_INTERVAL
		_apply_tick()

func _apply_tick() -> void:
	# Thunderstorm / Boulderfall replace the ground ticks with seeded strikes.
	if spell_data.get("bespoke", "") in ["thunderstorm", "boulderfall"]:
		return
	# Full damage / number-of-ticks, so the lifetime's worth of ticks sums to the
	# computed damage. Crit rolled per tick (dot forms don't bake crit at spawn).
	# Ticks only run after the call-down, so spread over the active time.
	var tick_base: float = hitbox.damage * TICK_INTERVAL / maxf(lifetime - CALL_DOWN_DELAY, TICK_INTERVAL)
	for area in hitbox.get_overlapping_areas():
		if not area is Hurtbox:
			continue
		if not hitbox.can_hit(area):
			continue
		# An enemy's lobbed zone only hurts players, not the packmates it's
		# standing among.
		if not hitbox.from_player and not area.is_player:
			continue
		# Crit is resolved per tick at the defender's _on_hurtbox_hurt (it reads the
		# attacker crit stats off the hitbox), so just pass the base tick damage.
		area.take_hit(hitbox, tick_base)
		_fx("hit", area)
