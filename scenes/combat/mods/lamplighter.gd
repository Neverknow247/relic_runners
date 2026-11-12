extends WeaponMod
# Lantern — Lamplighter: spells leave a light zone (5 s, r 320); enemies in light
# are Dazzled; basics fired by ANY player standing in light pierce (player.gd
# checks the "light_zone" group); each basic impact leaves a 1.5 s ember.

func on_projectile_expire(proj, pos: Vector2, cast: Dictionary) -> void:
	if proj.spell_data.get("_explosion", false):
		return
	if is_spell_sd(proj.spell_data) and !derived(cast):
		light(proj, pos, 320.0, 5.0)
	elif is_basic(proj) and !derived(cast):
		light(proj, pos, 110.0, 1.5)

static func light(proj, pos: Vector2, r: float, life: float) -> void:
	Callable(GroundZone, "spawn").call_deferred(proj.get_tree(), pos, GroundZone.src_of(proj.hitbox), {
		"radius": r, "lifetime": life, "visual": "light", "color": Color(1.0, 0.9, 0.55, 0.9),
		"zone_group": "light_zone", "on_enemy_inside": func(e): e.fx_dazzle(0.4)})
