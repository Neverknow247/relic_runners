extends WeaponMod
# Wand — Trickshot: basics and spells ricochet once off walls; a ricocheted hit
# applies your element at double strength (attack_ref halved = double units).

func on_projectile_wall(proj, _cast: Dictionary) -> void:
	if proj.get_meta("bounced", false):
		return
	if ricochet(proj):
		proj.set_meta("bounced", true)
		proj.hitbox.attack_ref *= 0.5
		Fx.puff(proj.get_tree(), proj.global_position, proj.spell_data.get("color", Color.WHITE), 0.5)
