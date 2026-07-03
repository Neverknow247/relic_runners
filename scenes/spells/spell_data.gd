extends Node
class_name SpellData

const EQUIPPABLE_WEAPONS = {
	"tome": {
		"element": "fire",
		"forms": ["ball", "rain", "beam"],
	},
	"orb": {
		"element": "fire",
		"forms": ["bolt", "beam", "burst"],
	},
	"wand": {
		"element": "fire",
		"forms": ["bolt", "ball", "cone"],
	},
}

const WEAPONS = {
	"default": {
		"damage": 1.0,
		"speed": 1.0,
		"size": 1.0,
		"lifetime": 1.0
	},
	"tome": {
		"damage": 1.25,
		"speed": 0.85,
		"size": 1.15,
		"lifetime": 1.15
	},
	"orb": {
		"damage": 1.0,
		"speed": 1.0,
		"size": 1.2,
		"lifetime": 1.0
	},
	"wand": {
		"damage": 0.85,
		"speed": 1.25,
		"size": 0.9,
		"lifetime": 0.9
	},
}

const ELEMENTS = {
	"default": {
		"damage": 1.0,
		"speed": 1.0,
		"color": Color(1.0, 1.0, 1.0)
	},
	"fire": {
		"damage": 1.25,
		"speed": 0.85,
		"color": Color(1.0, 0.35, 0.1)
	},
	"holy": {
		"damage": 1.0,
		"speed": 1.0,
		"color": Color(1.0, 0.95, 0.55)
	},
	"air": {
		"damage": 0.85,
		"speed": 1.35,
		"color": Color(0.65, 0.95, 1.0)
	},
}

const FORMS = {
	"default": {
		"scene": preload("res://scenes/spells/projectile.tscn"),
		"damage": 1.0,
		"speed": 1.0,
		"size": 1.0,
		"lifetime": 1.0,
		"attack_cooldown": 0.35,
		"spawn_offset": 18.0
	},
	"ball": {
		"scene": preload("res://scenes/spells/ball_projectile.tscn"),
		"damage": 1.25,
		"speed": 0.65,
		"size": 1.4,
		"lifetime": 1.1,
		"attack_cooldown": 0.5,
		"spawn_offset": 22.0
	},
	"bolt": {
		"scene": preload("res://scenes/spells/bolt_projectile.tscn"),
		"damage": 0.9,
		"speed": 1.5,
		"size": 0.8,
		"lifetime": 0.85,
		"attack_cooldown": 0.22,
		"spawn_offset": 18.0
	},
	"rain": {
		"scene": preload("res://scenes/spells/rain_projectile.tscn"),
		"damage": 0.75,
		"speed": 1.2,
		"size": 0.9,
		"lifetime": 1.0,
		"attack_cooldown": 0.4,
		"spawn_offset": 20.0
	},
	"beam": {
		"scene": preload("res://scenes/spells/beam_projectile.tscn"),
		"damage": 0.8,
		"speed": 2.0,
		"size": 0.7,
		"lifetime": 0.55,
		"attack_cooldown": 0.15,
		"spawn_offset": 20.0
	},
	"burst": {
		"scene": preload("res://scenes/spells/burst_projectile.tscn"),
		"damage": 1.1,
		"speed": 0.0,
		"size": 1.8,
		"lifetime": 0.35,
		"attack_cooldown": 0.65,
		"spawn_offset": 0.0
	},
	"cone": {
		"scene": preload("res://scenes/spells/cone_projectile.tscn"),
		"damage": 0.95,
		"speed": 0.75,
		"size": 1.5,
		"lifetime": 0.45,
		"attack_cooldown": 0.35,
		"spawn_offset": 18.0
	},
}

func build_spell_data(weapon: String, element: String, form: String) -> Dictionary:
	var weapon_data = WEAPONS[weapon]
	var element_data = ELEMENTS[element]
	var form_data = FORMS[form]
	return {
		"scene": form_data["scene"],
		"weapon": weapon,
		"element": element,
		"form": form,
		"damage": 10.0 * weapon_data["damage"] * element_data["damage"] * form_data["damage"],
		"speed": 250.0 * weapon_data["speed"] * element_data["speed"] * form_data["speed"],
		"size": 1.0 * weapon_data.get("size", 1.0) * form_data.get("size", 1.0),
		"lifetime": 2.0 * weapon_data.get("lifetime", 1.0) * form_data.get("lifetime", 1.0),
		"attack_cooldown": form_data.get("attack_cooldown", 0.35),
		"spawn_offset": form_data.get("spawn_offset", 18.0),
		"color": element_data["color"],
	}

func build_weapon_spell_data(weapon_id: String, form_index: int) -> Dictionary:
	var weapon = EQUIPPABLE_WEAPONS.get(weapon_id, EQUIPPABLE_WEAPONS["tome"])
	var element: String = weapon["element"]
	var forms: Array = weapon["forms"]
	form_index = clamp(form_index, 0, forms.size() - 1)
	var form: String = forms[form_index]
	return build_spell_data(weapon_id, element, form)
