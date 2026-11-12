extends WeaponMod
# Wand — Trickshot: basics and spells ricochet once off walls; a ricocheted hit
# applies your element at double strength (attack_ref halved = double units).
# Cones can't bounce, so a cone whose reach meets a wall reflects a second,
# half-size wedge off it (a local copy on every peer, like other forks).

const CONE_REACH := 600.0   # cone_projectile.tscn wedge length at size 1.0

func on_projectile_wall(proj, _cast: Dictionary) -> void:
	if proj.get_meta("bounced", false):
		return
	if ricochet(proj):
		proj.set_meta("bounced", true)
		proj.hitbox.attack_ref *= 0.5
		Fx.puff(proj.get_tree(), proj.global_position, proj.spell_data.get("color", Color.WHITE), 0.5)

func on_projectile_spawn(proj, _cast: Dictionary) -> void:
	if proj.spell_data.get("form", "") != "cone" or proj.spell_data.get("_reflected", false):
		return
	var reach: float = CONE_REACH * proj.scale.x
	var space = proj.get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(proj.global_position, proj.global_position + proj.direction * reach)
	q.collision_mask = 1
	q.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return
	var n: Vector2 = hit["normal"]
	var out: Vector2 = proj.direction.bounce(n).normalized()
	var apex: Vector2 = hit["position"] + n * 24.0
	Fx.puff(proj.get_tree(), apex, proj.spell_data.get("color", Color.WHITE), 0.8)
	spawn_local_copy(proj, apex, out, {"sz": 0.5, "dm": 0.5, "_reflected": true,
		"attack_ref": float(proj.spell_data.get("attack_ref", proj.hitbox.attack_ref)) * 0.5})
