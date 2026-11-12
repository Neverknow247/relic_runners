extends Node
# Dev-only: prints build_spell_data for every weapon x form, plus roster validation.
func _ready() -> void:
	print("PROBE roster: '", SpellData.validate_roster(), "'")
	var sd := SpellData.new()
	for form in ["default", "bolt", "ball", "rain", "beam", "burst", "cone"]:
		var rows := {}
		for w in SpellData.WEAPON_ORDER:
			var d := sd.build_spell_data(w, "fire", form)
			rows["%.2f/%.0f/%.2f/%.2f/%.2f/%d" % [d["damage_mult"], d["speed"], d["size"], d["lifetime"], d["attack_cooldown"], d["pellets"]]] = true
		print("PROBE ", form, " distinct=", rows.size(), " ", rows.keys())
	for w in SpellData.WEAPON_ORDER:
		print("PROBE range ", w, " bolt=", SpellData.get_effective_range(w, "fire", "bolt"))
	var wpn := Weapon.new("tome")
	print("PROBE attach ", wpn.attach_form("ball"), wpn.attach_form("rain"), wpn.attach_form("beam"), " forms=", wpn.forms)
	for w in SpellData.WEAPON_ORDER:
		var ww := Weapon.new(w)
		var st := SpellData.get_starter_form(w)
		var ok_start := ww.attach_form(st)
		var refused := []
		for f in ["bolt", "ball", "rain", "beam", "burst", "cone", "wave"]:
			if !ww.forms.has(f) and !ww.can_hold_form(f):
				refused.append(f)
		var restored := Weapon.from_dict(ww.to_dict())
		print("PROBE w=", w, " item=", ItemData.ITEMS.has(w), " name=", ItemData.ITEMS.get(w, {}).get("display_name", "?"),
			" desc=", ItemData.get_description(w) != "", " starter=", st, ":", ok_start,
			" refuses=", refused, " reload=", restored.type, restored.forms)
	print("PROBE loot weapons=", ItemData.LOOT_GROUPS["weapons"])
	var e := Enemy.new()
	for i in 20:
		var fs: Array = e._roll_forms("lantern")
		if fs.has("wave"):
			pass  # wave is a built form since phase 3
	print("PROBE lantern roll ", e._roll_forms("lantern"), " totem ", e._roll_forms("totem"))
	e.free()
	sd.free()
	get_tree().quit()
