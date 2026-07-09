extends Projectile
class_name ConeProjectile

# A brief wedge AoE in front of the caster. Hits each enemy inside the wedge
# once, but only if a wall isn't blocking the straight line from the caster to
# that enemy — so the cone can't cut through walls (same principle as the beam).
# auto_hit is off in FORMS, so this drives the damage with that line-of-sight
# gate. Runs on every peer; take_hit -> _on_hurtbox_hurt applies the health
# change only on each target's own authority, so the damage lands once.

# Walls are on collision layer 1 — only walls block the cone (enemy bodies,
# on their own layer, don't shield each other).
const WALL_MASK := 1

# owner_ids already hit, so each enemy takes exactly one cone hit over its life.
var _hit_ids := {}

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	for area in hitbox.get_overlapping_areas():
		if not area is Hurtbox:
			continue
		if hitbox.caster_id != 0 and area.owner_id == hitbox.caster_id:
			continue
		if _hit_ids.has(area.owner_id):
			continue
		if _wall_between(area.global_position):
			continue
		_hit_ids[area.owner_id] = true
		area.take_hit(hitbox, hitbox.damage)

# True if a wall sits on the line from the cone's origin (the caster) to the
# target, so the target is behind cover and shouldn't be hit.
func _wall_between(target: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, target)
	query.collision_mask = WALL_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return not space.intersect_ray(query).is_empty()
