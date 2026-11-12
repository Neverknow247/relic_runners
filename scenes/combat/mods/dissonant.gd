extends WeaponMod
# Instrument — Dissonant: basics mark enemies with Dissonance (6 s); a spell that
# hits a marked enemy makes it shriek, damaging other enemies around it. Server.

func on_hit_resolved(defender, hitbox, damage: float, _adv: bool) -> void:
	var key := "dissonance_%d" % hitbox.caster_id
	var now := Time.get_ticks_msec()
	if !hitbox.is_spell:
		defender.set_meta(key, now + 6000)
		defender.fx_mark("marked", 6.0)
		return
	if int(defender.get_meta(key, 0)) < now:
		return
	defender.set_meta(key, 0)
	defender.fx_ring_visual(340.0, Color(0.7, 0.4, 0.9))
	for e in enemies_near(defender.get_tree(), defender.global_position, 340.0, defender):
		e.take_secondary_hit(damage * 0.5, hitbox.attacker_element, hitbox.caster_id)
