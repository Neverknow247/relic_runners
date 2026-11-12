extends WeaponMod
# Tome — Glyphscribe: spells leave a glyph where they end; basic hits on an enemy
# standing on one of YOUR glyphs apply your element at spell strength; every 6th
# basic hit stamps a small glyph at the impact.

func on_projectile_expire(proj, pos: Vector2, cast: Dictionary) -> void:
	if is_spell_sd(proj.spell_data) and !derived(cast) and !proj.spell_data.get("_explosion", false):
		glyph(proj, pos, 260.0, 4.0)

func on_projectile_hit(proj, hurtbox, cast: Dictionary) -> void:
	if !is_basic(proj) or hurtbox.is_player or derived(cast):
		return
	var c = caster_node(proj)
	if c == null:
		return
	var n: int = int(c.get_meta("glyph_hits", 0)) + 1
	c.set_meta("glyph_hits", n)
	if n % 6 == 0:
		glyph(proj, hurtbox.global_position, 140.0, 1.5)

func on_hit_resolved(defender, hitbox, damage: float, _advantage: bool) -> void:
	if hitbox.is_spell:
		return
	for z in defender.get_tree().get_nodes_in_group("glyph_%d" % hitbox.caster_id):
		if is_instance_valid(z) and z.inside(defender.global_position):
			defender.receive_element_hit(hitbox.attacker_element, damage / maxf(hitbox.attack_ref, 1.0), true, hitbox, damage)
			return

static func glyph(proj, pos: Vector2, r: float, life: float) -> void:
	var c: Color = proj.spell_data.get("color", Color.WHITE)
	c.a = 0.85
	Callable(GroundZone, "spawn").call_deferred(proj.get_tree(), pos, GroundZone.src_of(proj.hitbox), {
		"radius": r, "lifetime": life, "visual": "glyph", "color": c,
		"zone_group": "glyph_%d" % proj.hitbox.caster_id})
