extends WeaponMod
# Wand — Overflow: for 3 s after a spell, your basic takes that spell's shape in
# miniature (mini-balls that pop, mini-cones, piercing mini-bolts) at basic damage.
# It stays a BASIC (as_basic): no mana, no cooldown, basic-strength element.

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func on_spell_cast(player, weapon, sd: Dictionary, cast: Dictionary) -> void:
	if derived(cast):
		return
	var form: String = sd.get("form", "default")
	if form in ["bolt", "ball", "cone"]:
		var s := st(player, weapon)
		s["form"] = form
		s["until"] = _now() + 3.0

func modify_basic(player, weapon, sd: Dictionary) -> void:
	var s := st(player, weapon)
	if _now() >= float(s.get("until", 0.0)):
		return
	var form: String = s.get("form", "")
	var fd: Dictionary = player.build_form_data(form)
	if fd.is_empty():
		return
	for k in ["scene", "speed", "lifetime", "pierce", "stop_on_wall", "auto_hit", "spawn_offset"]:
		if fd.has(k):
			sd[k] = fd[k]
	sd["form"] = form
	sd["as_basic"] = true
	sd["no_element_fx"] = true
	sd["mana_cost"] = 0.0
	sd["damage_mult"] = 1.0
	match form:
		"ball":
			sd["size"] = float(fd.get("size", 1.0)) * 0.4
			sd["explosion_mult"] = 0.35
		"cone":
			sd["size"] = float(fd.get("size", 1.0)) * 0.4
		"bolt":
			sd["size"] = float(fd.get("size", 1.0)) * 0.6
			sd["pierce_count"] = int(sd.get("pierce_count", 0)) + 2
