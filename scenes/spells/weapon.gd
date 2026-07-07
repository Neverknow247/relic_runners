class_name Weapon
extends RefCounted

var instance_id: String
var type: String
var element: String
var forms: Array

func _init(_type: String = "tome") -> void:
	type = _type
	var template: Dictionary = SpellData.EQUIPPABLE_WEAPONS.get(_type, SpellData.EQUIPPABLE_WEAPONS["tome"])
	element = template["element"]
	forms = template["forms"].duplicate()
	instance_id = "%d_%d" % [Time.get_ticks_usec(), randi()]

func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"type": type,
		"element": element,
		"forms": forms,
	}

static func from_dict(data: Dictionary) -> Weapon:
	var weapon := Weapon.new(data.get("type", "tome"))
	weapon.instance_id = data.get("instance_id", weapon.instance_id)
	weapon.element = data.get("element", weapon.element)
	weapon.forms = data.get("forms", weapon.forms)
	return weapon
