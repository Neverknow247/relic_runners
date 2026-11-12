extends WeaponMod
# Staff — Leywalker: spells draw a ley line along their path for 5 s (every peer).
# Basic shots that cross one of YOUR lines fork along it in both directions.

func on_projectile_spawn(proj, cast: Dictionary) -> void:
	if is_spell_sd(proj.spell_data) and !derived(cast):
		proj.set_meta("ley_start", proj._spawn_position)

func on_projectile_expire(proj, pos: Vector2, cast: Dictionary) -> void:
	if !proj.has_meta("ley_start") or derived(cast) or proj.spell_data.get("_explosion", false):
		return
	var a: Vector2 = proj.get_meta("ley_start")
	if a.distance_to(pos) < 200.0:
		return
	var c: Color = proj.spell_data.get("color", Color.WHITE)
	c.a = 0.6
	Callable(GroundZone, "spawn").call_deferred(proj.get_tree(), (a + pos) * 0.5, GroundZone.src_of(proj.hitbox), {
		"shape": "rect", "length": a.distance_to(pos), "width": 60.0, "rotation": (pos - a).angle(),
		"lifetime": 5.0, "color": c, "zone_group": "ley_%d" % proj.hitbox.caster_id})

func on_projectile_tick(proj, _delta: float, cast: Dictionary) -> void:
	if !is_basic(proj) or proj.spell_data.get("_forked", false) or proj.get_meta("ley_done", false):
		return
	for z in proj.get_tree().get_nodes_in_group("ley_%d" % proj.hitbox.caster_id):
		if is_instance_valid(z) and z.inside(proj.global_position):
			proj.set_meta("ley_done", true)
			var along := Vector2.from_angle(z.rotation)
			for d in [along, -along]:
				spawn_local_copy(proj, proj.global_position, d, {"dm": 0.6, "_forked": true})
			return
