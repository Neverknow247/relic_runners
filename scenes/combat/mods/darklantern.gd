extends WeaponMod
# Lantern — Darklantern: spells leave shadow zones (5 s, r 320) in which players
# cannot be seen by enemies (enemy.gd checks the "shadow_zone" group). Your basic
# makes no gunfire noise.

func modify_basic(_player, _weapon, sd: Dictionary) -> void:
	sd["silent"] = true

func on_projectile_expire(proj, pos: Vector2, cast: Dictionary) -> void:
	if !is_spell_sd(proj.spell_data) or derived(cast) or proj.spell_data.get("_explosion", false):
		return
	Callable(GroundZone, "spawn").call_deferred(proj.get_tree(), pos, GroundZone.src_of(proj.hitbox), {
		"radius": 320.0, "lifetime": 5.0, "visual": "light", "color": Color(0.15, 0.1, 0.25, 1.0),
		"zone_group": "shadow_zone"})
