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
# First tick shortly after spawn (once the area's overlaps have registered a
# physics frame in), so someone already standing in it gets hit promptly.
var _tick_timer := 0.1

func setup_spell(_direction: Vector2, _spell_data: Dictionary, caster_id: int = 0, crit: bool = false):
	super.setup_spell(_direction, _spell_data, caster_id, crit)
	_clamp_to_wall()

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
		global_position = hit["position"] - toward * 16.0

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = TICK_INTERVAL
		_apply_tick()

func _apply_tick() -> void:
	# Full damage / number-of-ticks, so the lifetime's worth of ticks sums to the
	# computed damage. Crit rolled per tick (dot forms don't bake crit at spawn).
	var tick_base: float = hitbox.damage * TICK_INTERVAL / lifetime
	for area in hitbox.get_overlapping_areas():
		if not area is Hurtbox:
			continue
		if hitbox.caster_id != 0 and area.owner_id == hitbox.caster_id:
			continue
		var dmg := tick_base
		hitbox.is_crit = randf() * 100.0 < spell_data.get("crit_chance", 0.0)
		if hitbox.is_crit:
			dmg *= spell_data.get("crit_multiplier", 1.0)
		area.take_hit(hitbox, dmg)
