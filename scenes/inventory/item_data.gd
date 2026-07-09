class_name ItemData
extends Node

# No item-icon art exists yet — items render as a color + short label, same
# placeholder convention enemy.tscn uses for its color_rect + weapon_label.
const ITEMS := {
	"scrap": {
		"display_name": "Scrap",
		"stackable": true,
		"max_stack": 50,
		"footprint": Vector2i(1, 1),
		"color": Color(0.6, 0.6, 0.65),
		"icon_label": "S",
	},
	# Crystal colors match SpellData.ELEMENTS' existing fire/holy/air colors,
	# so a crystal reads as "the same fire/holy/air" a weapon's element does
	# elsewhere (enemy color_rect, projectile color, etc). Element crystals
	# cap at 1 per stack (rare/valuable, one cell each) — mana crystals and
	# health potions are more everyday consumables and stack to 3.
	"crystal_fire": {
		"display_name": "Fire Crystal",
		"stackable": false,
		"max_stack": 1,
		"footprint": Vector2i(1, 1),
		"color": Color(1.0, 0.35, 0.1),
		"icon_label": "F",
	},
	"crystal_holy": {
		"display_name": "Holy Crystal",
		"stackable": false,
		"max_stack": 1,
		"footprint": Vector2i(1, 1),
		"color": Color(1.0, 0.95, 0.55),
		"icon_label": "H",
	},
	"crystal_air": {
		"display_name": "Air Crystal",
		"stackable": false,
		"max_stack": 1,
		"footprint": Vector2i(1, 1),
		"color": Color(0.65, 0.95, 1.0),
		"icon_label": "A",
	},
	"gold": {
		"display_name": "Gold",
		"stackable": true,
		"max_stack": 999,
		"footprint": Vector2i(1, 1),
		"color": Color(0.95, 0.8, 0.15),
		"icon_label": "G",
		"category": "currency",
	},
	"mana_crystal": {
		"display_name": "Crude Mana Crystal",
		"stackable": true,
		"max_stack": 5,
		"footprint": Vector2i(1, 1),
		"color": Color(0.55, 0.4, 0.95),
		"icon_label": "M",
		"usable": true,
		"mana_restore": 50.0,
	},
	"refined_mana_crystal": {
		"display_name": "Refined Mana Crystal",
		"stackable": true,
		"max_stack": 5,
		"footprint": Vector2i(1, 1),
		"color": Color(0.75, 0.6, 1.0),
		"icon_label": "M",
		"usable": true,
		"mana_restore": 50.0,
		# Charges the held AND holstered weapon (see player.gd _apply_item_effect).
		"mana_both_weapons": true,
		"rarity": "rare",
	},
	"health_potion": {
		"display_name": "Lesser Health Potion",
		"stackable": true,
		"max_stack": 5,
		"footprint": Vector2i(1, 1),
		"color": Color(0.9, 0.2, 0.35),
		"icon_label": "+",
		"usable": true,
		"heal_amount": 20.0,
	},
	"greater_health_potion": {
		"display_name": "Greater Health Potion",
		"stackable": true,
		"max_stack": 5,
		"footprint": Vector2i(1, 1),
		"color": Color(0.75, 0.1, 0.2),
		"icon_label": "+",
		"usable": true,
		"heal_amount": 35.0,
		"rarity": "rare",
	},
	# Crafting materials + crafted odds and ends (see CRAFTING_RECIPES). Plain
	# stackable bag items whose only role (beyond the two usable consumables) is
	# being recipe ingredients.
	"herbs": {
		"display_name": "Herbs", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(0.35, 0.7, 0.3), "icon_label": "h",
	},
	"water_flask": {
		"display_name": "Water Flask", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(0.3, 0.55, 0.85), "icon_label": "w",
	},
	"red_moss": {
		"display_name": "Red Moss", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(0.7, 0.25, 0.3), "icon_label": "o",
	},
	"mana_dust": {
		"display_name": "Mana Dust", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(0.5, 0.4, 0.85), "icon_label": "d",
	},
	"pure_mana_shard": {
		"display_name": "Pure Mana Shard", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(0.7, 0.6, 1.0), "icon_label": "s",
	},
	"fire_dust": {
		"display_name": "Fire Dust", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(1.0, 0.45, 0.2), "icon_label": "f",
	},
	"holy_dust": {
		"display_name": "Holy Dust", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(1.0, 0.9, 0.6), "icon_label": "y",
	},
	"air_dust": {
		"display_name": "Air Dust", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(0.7, 0.95, 1.0), "icon_label": "i",
	},
	"cloth": {
		"display_name": "Cloth", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(0.8, 0.75, 0.6), "icon_label": "cl",
	},
	"phoenix_ash": {
		"display_name": "Phoenix Ash", "stackable": true, "max_stack": 5,
		"footprint": Vector2i(1, 1), "color": Color(0.95, 0.5, 0.15), "icon_label": "a",
		# Consumable; placeholder effect is a strong heal — tune once its real role
		# (revive?) is decided.
		"usable": true, "heal_amount": 50.0,
	},
	"blessed_band": {
		"display_name": "Blessed Band", "stackable": false, "max_stack": 1,
		"footprint": Vector2i(1, 1), "color": Color(0.95, 0.9, 0.6), "icon_label": "bb",
		"equip_slot": "ring",
	},
	# Form Stones: one per spell form. Attaching a stone at the weapon
	# workbench adds that form's spell to a weapon (if the weapon type is
	# capable of it — see SpellData.get_capable_forms()); detaching returns the
	# stone. Same rare-ish 1-per-stack shape as element crystals. icon_label is
	# a distinct single letter per form; color is arbitrary placeholder art.
	"form_stone_ball": {
		"display_name": "Ball Stone",
		"stackable": false,
		"max_stack": 1,
		"footprint": Vector2i(1, 1),
		"color": Color(0.85, 0.5, 0.2),
		"icon_label": "b",
	},
	"form_stone_bolt": {
		"display_name": "Bolt Stone",
		"stackable": false,
		"max_stack": 1,
		"footprint": Vector2i(1, 1),
		"color": Color(0.9, 0.85, 0.3),
		"icon_label": "l",
	},
	"form_stone_rain": {
		"display_name": "Rain Stone",
		"stackable": false,
		"max_stack": 1,
		"footprint": Vector2i(1, 1),
		"color": Color(0.3, 0.6, 0.9),
		"icon_label": "r",
	},
	"form_stone_beam": {
		"display_name": "Beam Stone",
		"stackable": false,
		"max_stack": 1,
		"footprint": Vector2i(1, 1),
		"color": Color(0.6, 0.35, 0.85),
		"icon_label": "m",
	},
	"form_stone_burst": {
		"display_name": "Burst Stone",
		"stackable": false,
		"max_stack": 1,
		"footprint": Vector2i(1, 1),
		"color": Color(0.9, 0.4, 0.3),
		"icon_label": "u",
	},
	"form_stone_cone": {
		"display_name": "Cone Stone",
		"stackable": false,
		"max_stack": 1,
		"footprint": Vector2i(1, 1),
		"color": Color(0.4, 0.8, 0.5),
		"icon_label": "c",
	},
	# Gear: equippable, never stacks, and takes up real space in the grid
	# when carried loose ("if it's held") rather than worn. equip_slot ties
	# an item type to which EquipmentSlot will accept it. Only backpack_basic
	# does anything functional right now (provides_capacity sizes the
	# player's whole grid) — belt/cloak just occupy their slot for now.
	"belt_basic": {
		"display_name": "Belt",
		"stackable": false,
		"max_stack": 1,
		"footprint": Vector2i(2, 1),
		"color": Color(0.5, 0.35, 0.2),
		"icon_label": "B",
		"equip_slot": "belt",
		# How many quick slots equipping this belt grants (see player.gd's
		# _resize_quick_slots_for_belt()) — a property of the belt itself so a
		# future rarer belt can just declare a bigger number here, same idea
		# as provides_capacity for backpacks.
		"provides_quick_slots": 1,
	},
	# The body-armor slot is generic ("body") so both robes and cloaks can live
	# there; this starter piece is flavored as a Robe. equip_slot is the slot,
	# display_name is the flavor.
	"cloak_basic": {
		"display_name": "Robe",
		"stackable": false,
		"max_stack": 1,
		"footprint": Vector2i(2, 3),
		"color": Color(0.3, 0.2, 0.45),
		"icon_label": "R",
		"equip_slot": "body",
	},
	"backpack_basic": {
		"display_name": "Backpack",
		"stackable": false,
		"max_stack": 1,
		"footprint": Vector2i(2, 2),
		"color": Color(0.45, 0.3, 0.15),
		"icon_label": "P",
		"equip_slot": "backpack",
		"provides_capacity": Vector2i(4, 5),
	},
	# Weapons as loot: equip_slot="weapon" (both Hand and Holster accept
	# these — see weapon_slot_button.gd). icon_label letters match the
	# existing WEAPON_LETTERS convention on enemy.gd's own weapon_label.
	# The actual mana/durability/element live on the Item's attached
	# `weapon` field (see item.gd's Item.create()), not here — this is just
	# the grid-facing shape (size, color, label).
	"tome": {
		"display_name": "Tome",
		"stackable": false,
		"max_stack": 1,
		"footprint": Vector2i(1, 2),
		"color": Color(0.2, 0.3, 0.6),
		"icon_label": "T",
		"equip_slot": "weapon",
	},
	"orb": {
		"display_name": "Orb",
		"stackable": false,
		"max_stack": 1,
		"footprint": Vector2i(1, 1),
		"color": Color(0.6, 0.85, 0.9),
		"icon_label": "O",
		"equip_slot": "weapon",
	},
	"wand": {
		"display_name": "Wand",
		"stackable": false,
		"max_stack": 1,
		"footprint": Vector2i(1, 2),
		"color": Color(0.6, 0.45, 0.25),
		"icon_label": "W",
		"equip_slot": "weapon",
	},
}

static func get_def(item_type: String) -> Dictionary:
	return ITEMS.get(item_type, ITEMS["scrap"])

static func get_footprint(item_type: String) -> Vector2i:
	return get_def(item_type)["footprint"]

static func is_stackable(item_type: String) -> bool:
	return get_def(item_type)["stackable"]

static func get_max_stack(item_type: String) -> int:
	return get_def(item_type)["max_stack"]

# "" means not equippable (scrap, crystals, potions).
static func get_equip_slot(item_type: String) -> String:
	return get_def(item_type).get("equip_slot", "")

static func get_provides_capacity(item_type: String) -> Vector2i:
	return get_def(item_type).get("provides_capacity", Vector2i.ZERO)

static func get_provides_quick_slots(item_type: String) -> int:
	return get_def(item_type).get("provides_quick_slots", 0)

static func is_usable(item_type: String) -> bool:
	return get_def(item_type).get("usable", false)

const FORM_STONE_PREFIX := "form_stone_"

static func is_form_stone(item_type: String) -> bool:
	return item_type.begins_with(FORM_STONE_PREFIX)

# "form_stone_ball" -> "ball" (and "" for anything that isn't a form stone).
static func form_from_stone(item_type: String) -> String:
	if !is_form_stone(item_type):
		return ""
	return item_type.substr(FORM_STONE_PREFIX.length())

# "ball" -> "form_stone_ball".
static func stone_for_form(form: String) -> String:
	return FORM_STONE_PREFIX + form

# Crafting materials (element crystals + form stones) — banked into the stash's
# Materials tab in dedicated, infinitely-stacking per-type slots (see
# materials_grid.gd / player.gd's materials container). This is the fixed slot
# order shown in the tab.
const MATERIAL_TYPES := [
	"crystal_fire", "crystal_holy", "crystal_air",
	"form_stone_ball", "form_stone_bolt", "form_stone_rain",
	"form_stone_beam", "form_stone_burst", "form_stone_cone",
]

static func is_material(item_type: String) -> bool:
	return is_form_stone(item_type) or item_type.begins_with("crystal_")

# One-line flavor/util descriptions, keyed by type (kept out of ITEMS so the
# grid-shape data stays terse). Shown in the hover tooltip under the name.
const DESCRIPTIONS := {
	"scrap": "Bits of broken gear.",
	"gold": "It's Gold.",
	"crystal_fire": "Formed in the cooling blood of Hakii, it's still warm.",
	"crystal_holy": "A crystal tear.",
	"crystal_air": "A bit of Aeris's last Breath",
	"mana_crystal": "Crudely condensed mana.",
	"refined_mana_crystal": "Purified mana — charges both your weapons.",
	"health_potion": "A minor healing draught.",
	"greater_health_potion": "A potent healing draught.",
	"herbs": "Common wild herbs.",
	"water_flask": "A flask of clean water.",
	"red_moss": "Crimson moss with restorative properties.",
	"mana_dust": "Faintly glowing arcane dust.",
	"pure_mana_shard": "A shard humming with pure mana.",
	"fire_dust": "Warm to the touch.",
	"holy_dust": "Softly radiant motes.",
	"air_dust": "Weightless, drifting dust.",
	"cloth": "A scrap of woven cloth.",
	"phoenix_ash": "Embers that rekindle life.",
	"blessed_band": "A ring blessed with holy light.",
	"form_stone_ball": "An ancient rune stone that shapes magic into an explosive sphere.",
	"form_stone_bolt": "Its carved sigils focus magic into a swift projectile.",
	"form_stone_rain": "A relic stone that calls magic down upon a targeted area.",
	"form_stone_beam": "A worn stone that channels magic into a continuous stream.",
	"form_stone_burst": "Ancient runes force magic outward in every direction.",
	"form_stone_cone": "Its widening glyphs spread magic into a broad arc.",
	"tome": "A heavy spellbook.",
	"orb": "A floating focus.",
	"wand": "A quick casting rod.",
	"belt_basic": "Adds a quick slot. +1 trait",
	"cloak_basic": "A basic wizard robe. +1 trait",
	"backpack_basic": "4x5 personal storage. +1 trait.",
}

static func get_description(item_type: String) -> String:
	return DESCRIPTIONS.get(item_type, "")

# --- Crafting -------------------------------------------------------------
# The recipe list the (not-yet-built) crafting bench will use. Each recipe is a
# list of [ingredient, count] inputs producing [item, count]. An ingredient
# starting with "@" is a wildcard matching any type in CRAFTING_WILDCARDS (so
# "@element_crystal" accepts any fire/holy/air crystal).
const CRAFTING_WILDCARDS := {
	"@element_crystal": ["crystal_fire", "crystal_holy", "crystal_air"],
}
const CRAFTING_RECIPES := [
	{"inputs": [["cloth", 1], ["crystal_holy", 1]], "output": ["blessed_band", 1]},
	{"inputs": [["crystal_fire", 1], ["herbs", 3]], "output": ["phoenix_ash", 1]},
	{"inputs": [["herbs", 2], ["water_flask", 1]], "output": ["health_potion", 1]},
	{"inputs": [["health_potion", 1], ["red_moss", 2]], "output": ["greater_health_potion", 1]},
	{"inputs": [["mana_dust", 3], ["@element_crystal", 1]], "output": ["mana_crystal", 1]},
	{"inputs": [["mana_crystal", 1], ["pure_mana_shard", 1]], "output": ["refined_mana_crystal", 1]},
]

# True if item_type can satisfy a recipe ingredient (direct match or wildcard).
static func ingredient_matches(item_type: String, ingredient: String) -> bool:
	if ingredient.begins_with("@"):
		return CRAFTING_WILDCARDS.get(ingredient, []).has(item_type)
	return item_type == ingredient

# Rarity applies to weapons and gear. Only "common" exists in content today;
# the rest are scaffolding. gear_traits = how many traits a gear piece rolls
# (capped by the slot's available traits); stat_mult scales a weapon's basic
# stats (damage + max mana/durability). Colors are the display accent.
const RARITY_ORDER := ["common", "uncommon", "rare", "epic", "legendary"]
const RARITIES := {
	"common": {"display": "Common", "color": Color(0.72, 0.72, 0.75), "gear_traits": 1, "stat_mult": 1.0},
	"uncommon": {"display": "Uncommon", "color": Color(0.35, 0.8, 0.35), "gear_traits": 2, "stat_mult": 1.15},
	"rare": {"display": "Rare", "color": Color(0.3, 0.55, 0.95), "gear_traits": 3, "stat_mult": 1.3},
	"epic": {"display": "Epic", "color": Color(0.9, 0.45, 0.85), "gear_traits": 4, "stat_mult": 1.5},
	"legendary": {"display": "Legendary", "color": Color(0.95, 0.6, 0.15), "gear_traits": 4, "stat_mult": 1.8},
}

static func rarity_def(rarity: String) -> Dictionary:
	return RARITIES.get(rarity, RARITIES["common"])

static func rarity_display(rarity: String) -> String:
	return rarity_def(rarity)["display"]

static func rarity_color(rarity: String) -> Color:
	return rarity_def(rarity)["color"]

static func rarity_gear_traits(rarity: String) -> int:
	return rarity_def(rarity)["gear_traits"]

static func rarity_stat_mult(rarity: String) -> float:
	return rarity_def(rarity)["stat_mult"]

# --- Item category --------------------------------------------------------
# weapon / gear (any equippable non-weapon) / consumable / crafting_material /
# currency, plus key / quest / relic / trinket for future use. Mostly derived;
# add an explicit "category" to a def to override. Trinkets are no-function
# sellables (worth money only).
static func get_category(item_type: String) -> String:
	var def := get_def(item_type)
	if def.has("category"):
		return def["category"]
	var slot: String = def.get("equip_slot", "")
	if slot == "weapon":
		return "weapon"
	if slot != "":
		return "gear"
	if def.get("usable", false):
		return "consumable"
	return "crafting_material"

# --- Loot -----------------------------------------------------------------
# A single loot roll lands on one rarity tier at these odds (sum 100). Then a
# random item of that tier is pulled from the killed enemy's pool.
const RARITY_DROP_WEIGHTS := {
	"common": 60, "uncommon": 25, "rare": 10, "epic": 4, "legendary": 1,
}
# Per-enemy-type loot pools — item types grouped by rarity. Each roll picks a
# rarity (weighted), then a random item of that tier here. "@weapon" resolves to
# the enemy's own weapon (carrying its element/forms). New enemy types get their
# own entry keyed by their loot_pool id (see enemy.gd).
const ENEMY_LOOT_POOLS := {
	"basic": {
		"common": ["scrap", "gold", "herbs", "water_flask", "red_moss", "cloth",
			"mana_dust", "fire_dust", "holy_dust", "air_dust", "health_potion", "mana_crystal"],
		"uncommon": ["pure_mana_shard", "crystal_fire", "crystal_holy", "crystal_air",
			"belt_basic", "cloak_basic", "backpack_basic"],
		"rare": ["greater_health_potion", "refined_mana_crystal", "blessed_band", "@weapon",
			"form_stone_ball", "form_stone_bolt", "form_stone_rain",
			"form_stone_beam", "form_stone_burst", "form_stone_cone"],
		"epic": [],
		"legendary": [],
	},
}
# How many of an item type drop when it's rolled, [min, max] (default [1,1]). Per
# ITEM, so a rare wand always drops 1 while a rare potion can drop a couple.
const DROP_QUANTITIES := {
	"gold": [1, 8], "scrap": [1, 3],
	"herbs": [1, 3], "water_flask": [1, 3], "red_moss": [1, 3], "cloth": [1, 3],
	"mana_dust": [1, 3], "pure_mana_shard": [1, 2],
	"fire_dust": [1, 3], "holy_dust": [1, 3], "air_dust": [1, 3],
	"health_potion": [1, 2], "mana_crystal": [1, 2], "greater_health_potion": [1, 2],
}
static func get_drop_qty(item_type: String) -> Array:
	return DROP_QUANTITIES.get(item_type, [1, 1])

# Gear traits, one rolled per looted/crafted piece (see Item.create()). Each is
# {id, desc}; the player applies the effect while the piece is equipped AND
# unbroken (durability > 0). See player.gd's has_gear_attribute().
const GEAR_ATTRIBUTES := {
	# The body slot's traits (ids keep the historical "cloak_" prefix — they're
	# internal only, never shown).
	"body": [
		{"id": "cloak_armor", "desc": "Take 5% less damage."},
		{"id": "cloak_silent", "desc": "Enemies can no longer hear you."},
		{"id": "cloak_unseen_still", "desc": "Enemies can't see you while you stand still."},
		{"id": "cloak_efficient", "desc": "Sequence spells cost 10% less mana."},
	],
	"belt": [
		{"id": "belt_potency", "desc": "+10% potency on quick-slot items."},
		{"id": "belt_autoreplace", "desc": "Used quick-slot items auto-refill from your bag."},
		{"id": "belt_vitality", "desc": "+10% max health."},
	],
	"backpack": [
		{"id": "pack_takeall", "desc": "Unlocks the Take All button."},
	],
}

static func is_gear(item_type: String) -> bool:
	return get_equip_slot(item_type) in ["belt", "body", "backpack"]

# Up to `count` distinct traits for a slot (capped by how many that slot has).
static func roll_gear_attributes(slot: String, count: int) -> Array:
	var pool: Array = GEAR_ATTRIBUTES.get(slot, []).duplicate()
	pool.shuffle()
	var n: int = min(count, pool.size())
	var result: Array = []
	for i in n:
		result.append(pool[i]["id"])
	return result

static func gear_attribute_desc(attr_id: String) -> String:
	for slot in GEAR_ATTRIBUTES:
		for entry in GEAR_ATTRIBUTES[slot]:
			if entry["id"] == attr_id:
				return entry["desc"]
	return ""

# This item's rarity. Weapons/gear carry a rolled rarity on the instance; every
# other item takes the static rarity from its def (defaulting to common), so all
# loot has a rarity for drop-rate weighting.
static func item_rarity(item) -> String:
	if item.weapon != null:
		return item.weapon.rarity
	if is_gear(item.type):
		return item.rarity
	return get_def(item.type).get("rarity", "common")

# Full display name: weapons read "<Rarity> <Element> <Type>" (e.g. "Common
# Fire Wand"), gear reads "<Rarity> <Type>" (e.g. "Common Cloak"); everything
# else is just its plain name.
static func display_name(item) -> String:
	var base: String = get_def(item.type).get("display_name", item.type)
	if item.weapon != null:
		return "%s %s %s" % [rarity_display(item.weapon.rarity), item.weapon.element.capitalize(), base]
	if is_gear(item.type):
		return "%s %s" % [rarity_display(item.rarity), base]
	return base

# Tooltip border accent: the item's rarity color, or a neutral grey for items
# without a rarity.
static func tooltip_accent_color(item) -> Color:
	var r := item_rarity(item)
	return rarity_color(r) if r != "" else Color(0.4, 0.4, 0.45)

# Shared tooltip label — a RichTextLabel so tooltip_text() BBCode (colors,
# italics, per-line sizes) renders. Sizes to its content.
static func build_tooltip_label() -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rt

# Shared "solid + bordered" tooltip panel style (the fancier, less-transparent
# look). Border color is set per-item by the UI (to the rarity accent).
static func build_tooltip_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.09, 0.11, 0.98)
	style.set_border_width_all(3)
	style.border_color = Color(0.4, 0.4, 0.45)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(16)
	return style

# The hover tooltip text for any item: name + description + whatever live stats
# apply (weapon durability/mana/forms, gear durability + trait, consumable
# effect). item is an Item (untyped to avoid a class cross-reference).
# Color of the item's name in the tooltip: weapons pop in their element color,
# gear in its rarity color, everything else plain white.
static func _name_color(item) -> Color:
	if item.weapon != null:
		return SpellData.ELEMENTS.get(item.weapon.element, SpellData.ELEMENTS["default"])["color"]
	if is_gear(item.type):
		return rarity_color(item.rarity)
	return Color(1, 1, 1)

static func _hex(c: Color) -> String:
	return c.to_html(false)

# BBCode tooltip (rendered by a RichTextLabel). Order for weapons: name,
# description (small italic), forms (element-colored, |-separated), mana,
# durability (small). For gear: name, description, traits (bulleted + colored,
# no header), durability. Descriptions are small italic for every item.
static func tooltip_text(item) -> String:
	var def := get_def(item.type)
	var out := "[font_size=44][b][color=#%s]%s[/color][/b][/font_size]" % [_hex(_name_color(item)), display_name(item)]
	var desc := get_description(item.type)
	if desc != "":
		out += "\n[font_size=26][i][color=#9a9aa2]%s[/color][/i][/font_size]" % desc
	if item.weapon != null:
		var w = item.weapon
		var ecol := _hex(SpellData.ELEMENTS.get(w.element, SpellData.ELEMENTS["default"])["color"])
		if not w.forms.is_empty():
			var forms_str := " | ".join(w.forms.map(func(f): return String(f).capitalize()))
			out += "\n[font_size=38][color=#%s]%s[/color][/font_size]" % [ecol, forms_str]
		out += "\n[font_size=34][color=#a98cf0]Mana %d/%d[/color][/font_size]" % [roundi(w.mana), roundi(w.max_mana)]
		out += "\n[font_size=24][color=#8a8a90]Durability %d/%d[/color][/font_size]" % [roundi(w.durability), roundi(w.max_durability)]
	if is_gear(item.type):
		if not item.attributes.is_empty():
			var broken: bool = item.max_durability > 0.0 and item.durability <= 0.0
			var acol := "8a8a90" if broken else "7ad07a"
			for attr_id in item.attributes:
				out += "\n[font_size=30][color=#%s]• %s[/color][/font_size]" % [acol, gear_attribute_desc(attr_id)]
		if item.max_durability > 0.0:
			out += "\n[font_size=24][color=#8a8a90]Durability %d/%d[/color][/font_size]" % [roundi(item.durability), roundi(item.max_durability)]
	if def.get("usable", false):
		if def.has("heal_amount"):
			out += "\n[font_size=30]Restores %d health.[/font_size]" % roundi(def["heal_amount"])
		if def.has("mana_restore"):
			out += "\n[font_size=30]Restores %d mana.[/font_size]" % roundi(def["mana_restore"])
	return out
