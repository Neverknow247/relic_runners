class_name Weapon
extends RefCounted

var instance_id: String
var type: String
var element: String
var rarity: String = "common"
var forms: Array
# Every weapon has its own mana pool (not the player) — every spell costs
# mana to cast (see SpellData.FORMS' mana_cost, deducted in player.gd's
# cast_spell()). Flat 100 for every weapon type for now; a future pass can
# vary max_mana per type here without touching anything that reads it.
var mana: float
var max_mana: float
var durability: float
var max_durability: float

func _init(_type: String = "tome", _rarity: String = "common") -> void:
	type = _type
	rarity = _rarity
	var template: Dictionary = SpellData.EQUIPPABLE_WEAPONS.get(_type, SpellData.EQUIPPABLE_WEAPONS["tome"])
	element = template["element"]
	# Born form-less — forms are attached as Form Stone items at the weapon
	# workbench (the type's template["forms"] is now just the *capability*
	# list, i.e. which forms this type can ever hold; see capable_forms()).
	# Whoever creates the weapon decides what it starts with: the starter grant
	# attaches one STARTER_FORM, looted weapons get 1-3 rolled at enemy spawn.
	forms = []
	instance_id = "%d_%d" % [Time.get_ticks_usec(), randi()]
	# Rarity scales the weapon's basic pools (Common = x1.0). Damage scaling is
	# applied at cast time in SpellData.build_spell_data().
	var mult := ItemData.rarity_stat_mult(rarity)
	max_mana = 100.0 * mult
	mana = max_mana
	max_durability = 100.0 * mult
	durability = max_durability

func use_mana(amount: float) -> void:
	mana = clamp(mana - amount, 0.0, max_mana)

func restore_mana(amount: float) -> void:
	mana = clamp(mana + amount, 0.0, max_mana)

func use_durability(amount: float) -> void:
	durability = clamp(durability - amount, 0.0, max_durability)

# Which forms this weapon's TYPE is capable of holding (the workbench only
# ever offers these) — distinct from `forms`, which is the subset actually
# attached right now.
func capable_forms() -> Array:
	return SpellData.get_capable_forms(type)

func can_hold_form(form: String) -> bool:
	return capable_forms().has(form) and !forms.has(form)

func attach_form(form: String) -> bool:
	if !can_hold_form(form):
		return false
	forms.append(form)
	return true

func detach_form(form: String) -> bool:
	if !forms.has(form):
		return false
	forms.erase(form)
	return true

func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"type": type,
		"element": element,
		"rarity": rarity,
		"forms": forms,
		"mana": mana,
		"max_mana": max_mana,
		"durability": durability,
		"max_durability": max_durability,
	}

static func from_dict(data: Dictionary) -> Weapon:
	var weapon := Weapon.new(data.get("type", "tome"), data.get("rarity", "common"))
	weapon.instance_id = data.get("instance_id", weapon.instance_id)
	weapon.element = data.get("element", weapon.element)
	weapon.forms = data.get("forms", weapon.forms)
	weapon.mana = data.get("mana", weapon.mana)
	weapon.max_mana = data.get("max_mana", weapon.max_mana)
	weapon.durability = data.get("durability", weapon.durability)
	weapon.max_durability = data.get("max_durability", weapon.max_durability)
	return weapon
