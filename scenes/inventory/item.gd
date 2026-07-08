class_name Item
extends RefCounted

var instance_id: String
var type: String
var quantity: int
# Only meaningful when ItemData.get_equip_slot(type) == "weapon" — the full
# Weapon this item represents (mana/durability/element/its own instance_id),
# so equipping it hands over the exact same instance instead of a fresh one,
# and dropping/storing/re-equipping a weapon never resets its stats. Use
# Item.create() rather than Item.new() directly for weapon types so this
# always gets attached.
var weapon: Weapon = null
# Only meaningful for gear (belt/cloak/backpack). rarity sets how many traits
# this piece rolls; attributes are those trait ids (see ItemData.GEAR_ATTRIBUTES);
# durability drains as the wearer takes hits and, at 0, the traits stop applying.
# Weapons keep their own rarity/durability on the attached Weapon instead.
var rarity := "common"
var attributes: Array = []
var durability := 0.0
var max_durability := 0.0

const GEAR_MAX_DURABILITY := 100.0

func _init(_type := "scrap", _quantity := 1) -> void:
	type = _type
	quantity = _quantity
	instance_id = "%d_%d" % [Time.get_ticks_usec(), randi()]

# Factory that also attaches a fresh Weapon for weapon-type items (and keeps
# instance_id in sync with it) — the constructor itself stays plain/generic
# since only 3 of the many item types need this.
static func create(_type := "scrap", _quantity := 1) -> Item:
	var item := Item.new(_type, _quantity)
	if ItemData.get_equip_slot(_type) == "weapon":
		item.weapon = Weapon.new(_type)
		item.instance_id = item.weapon.instance_id
	elif ItemData.is_gear(_type):
		# Fresh gear: rarity-many rolled traits, full durability. (Looted gear
		# overrides durability to a worn value afterward — see world_loot.gd.)
		item.attributes = ItemData.roll_gear_attributes(
			ItemData.get_equip_slot(_type), ItemData.rarity_gear_traits(item.rarity)
		)
		item.max_durability = GEAR_MAX_DURABILITY
		item.durability = GEAR_MAX_DURABILITY
	return item

func to_dict() -> Dictionary:
	var data := {"instance_id": instance_id, "type": type, "quantity": quantity}
	if weapon != null:
		data["weapon"] = weapon.to_dict()
	if not attributes.is_empty() or max_durability > 0.0:
		data["rarity"] = rarity
		data["attributes"] = attributes
		data["durability"] = durability
		data["max_durability"] = max_durability
	return data

static func from_dict(data: Dictionary) -> Item:
	var item := Item.new(data.get("type", "scrap"), data.get("quantity", 1))
	item.instance_id = data.get("instance_id", item.instance_id)
	if data.has("weapon"):
		item.weapon = Weapon.from_dict(data["weapon"])
	item.rarity = data.get("rarity", "common")
	# Back-compat: an older save stored a single "attribute" string.
	if data.has("attributes"):
		item.attributes = data.get("attributes", [])
	elif data.get("attribute", "") != "":
		item.attributes = [data["attribute"]]
	item.durability = data.get("durability", 0.0)
	item.max_durability = data.get("max_durability", 0.0)
	return item
