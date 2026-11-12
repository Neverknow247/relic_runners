extends WeaponMod
# Tome — Annotator: basic hits write marks on an enemy (max 5, per caster); a spell
# that hits a marked enemy pops every mark as a small blast. Server-side state.

func on_hit_resolved(defender, hitbox, _damage: float, _adv: bool) -> void:
	var key := "marks_%d" % hitbox.caster_id
	var n: int = defender.get_meta(key, 0)
	if !hitbox.is_spell:
		defender.set_meta(key, mini(n + 1, 5))
		defender.fx_mark("marked", 6.0)
		return
	if n <= 0:
		return
	defender.set_meta(key, 0)
	for i in n:
		defender.take_secondary_hit(maxf(hitbox.attack_ref, 1.0) * 0.6, hitbox.attacker_element, hitbox.caster_id)
	defender.fx_ring_visual(140.0 + n * 30.0, Color(0.95, 0.9, 0.6))
