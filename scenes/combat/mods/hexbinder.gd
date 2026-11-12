extends WeaponMod
# Totem — Hexbinder: the first enemy your basic hits becomes the Effigy for 6 s.
# 30% of damage you deal to OTHER enemies is also dealt to it, and spells that hit
# it splash your element to everything near it. Server-side state.

static var _effigy := {}   # caster_id -> [enemy, until_msec]

func on_hit_resolved(defender, hitbox, damage: float, _adv: bool) -> void:
	var cid: int = hitbox.caster_id
	var now := Time.get_ticks_msec()
	var cur: Array = _effigy.get(cid, [])
	var alive: bool = !cur.is_empty() and is_instance_valid(cur[0]) and !cur[0].is_dead and int(cur[1]) > now
	if !alive:
		if !hitbox.is_spell:
			_effigy[cid] = [defender, now + 6000]
			defender.fx_mark("effigy", 6.0)
		return
	var eff = cur[0]
	if defender == eff:
		if hitbox.is_spell:
			defender.fx_ring_visual(350.0, Color(0.7, 0.2, 0.6))
			for e in enemies_near(defender.get_tree(), defender.global_position, 350.0, defender):
				e.receive_element_hit(hitbox.attacker_element, damage / maxf(hitbox.attack_ref, 1.0), true, hitbox, damage)
		return
	eff.take_secondary_hit(damage * 0.3, hitbox.attacker_element, cid)
