extends WeaponMod
# Lantern — Flarekeeper: spells plant a flare where they end that enemies target for
# 2.5 s; every 8th basic hit sticks a mini-flare to the enemy it hits (its
# packmates shoot at it for 2 s). Taunts are applied by the server.

static var _counts := {}

func on_projectile_expire(proj, pos: Vector2, cast: Dictionary) -> void:
	if !is_spell_sd(proj.spell_data) or derived(cast) or proj.spell_data.get("_explosion", false):
		return
	Callable(GroundZone, "spawn").call_deferred(proj.get_tree(), pos, GroundZone.src_of(proj.hitbox), {
		"radius": 70.0, "lifetime": 2.5, "visual": "light", "color": Color(1.0, 0.35, 0.2, 1.0)})
	if server(proj):
		for e in enemies_near(proj.get_tree(), pos, 1400.0):
			e.fx_taunt(pos, 2.5)

func on_hit_resolved(defender, hitbox, _damage: float, _adv: bool) -> void:
	if hitbox.is_spell:
		return
	var n: int = int(_counts.get(hitbox.caster_id, 0)) + 1
	_counts[hitbox.caster_id] = n
	if n % 8 != 0:
		return
	defender.fx_ring_visual(90.0, Color(1.0, 0.35, 0.2))
	for e in enemies_near(defender.get_tree(), defender.global_position, 900.0, defender):
		e.fx_taunt_node(defender, 2.0)
