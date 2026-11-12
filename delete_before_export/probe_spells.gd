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
	sd.free()
	get_tree().quit()
