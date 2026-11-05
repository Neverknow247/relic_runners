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
	# One element crystal per element in SpellData.ELEMENT_ORDER — attaching one at
	# the weapon workbench sets a weapon's element. Colors match SpellData.ELEMENTS
	# so a crystal reads as the element it becomes (projectile/enemy color, etc).
	# Cap at 1 per stack (rare/valuable, one cell each).
	"crystal_fire": {
		"display_name": "Fire Crystal", "stackable": false, "max_stack": 1,
		"footprint": Vector2i(1, 1), "color": Color(1.0, 0.35, 0.1), "icon_label": "F",
	},
	"crystal_lightning": {
		"display_name": "Lightning Crystal", "stackable": false, "max_stack": 1,
		"footprint": Vector2i(1, 1), "color": Color(1.0, 0.9, 0.2), "icon_label": "L",
	},
	"crystal_ice": {
		"display_name": "Ice Crystal", "stackable": false, "max_stack": 1,
		"footprint": Vector2i(1, 1), "color": Color(0.6, 0.9, 1.0), "icon_label": "I",
	},
	"crystal_wind": {
		"display_name": "Wind Crystal", "stackable": false, "max_stack": 1,
		"footprint": Vector2i(1, 1), "color": Color(0.75, 0.95, 0.85), "icon_label": "Wd",
	},
	"crystal_nature": {
		"display_name": "Nature Crystal", "stackable": false, "max_stack": 1,
		"footprint": Vector2i(1, 1), "color": Color(0.4, 0.8, 0.3), "icon_label": "N",
	},
	"crystal_water": {
		"display_name": "Water Crystal", "stackable": false, "max_stack": 1,
		"footprint": Vector2i(1, 1), "color": Color(0.25, 0.5, 0.95), "icon_label": "Wt",
	},
	"crystal_earth": {
		"display_name": "Earth Crystal", "stackable": false, "max_stack": 1,
		"footprint": Vector2i(1, 1), "color": Color(0.6, 0.45, 0.25), "icon_label": "E",
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
		"display_name": "Crude Mana Fragment",
		"stackable": true,
		"max_stack": 5,
		"footprint": Vector2i(1, 1),
		"color": Color(0.55, 0.4, 0.95),
		"icon_label": "M",
		"usable": true,
		"mana_restore": 500.0,
	},
	"refined_mana_crystal": {
		"display_name": "Refined Mana Fragment",
		"stackable": true,
		"max_stack": 5,
		"footprint": Vector2i(1, 1),
		"color": Color(0.75, 0.6, 1.0),
		"icon_label": "M",
		"usable": true,
		"mana_restore": 500.0,
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
		"heal_amount": 200.0,
	},
	"greater_health_potion": {
		"display_name": "Greater Health Potion",
		"stackable": true,
		"max_stack": 5,
		"footprint": Vector2i(1, 1),
		"color": Color(0.75, 0.1, 0.2),
		"icon_label": "+",
		"usable": true,
		"heal_amount": 350.0,
		"rarity": "rare",
	},
	# Crafting materials + crafted odds and ends (see CRAFTING_RECIPES). Plain
	# stackable bag items whose only role (beyond the two usable consumables) is
	# being recipe ingredients.
	"berries": {
		"usable": true, "food_amount": 15.0,
		"display_name": "Berries", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(0.7, 0.2, 0.45), "icon_label": "b",
	},
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
	# One dust per element (colors match the element crystals / SpellData.ELEMENTS).
	"fire_dust": {
		"display_name": "Fire Dust", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(1.0, 0.35, 0.1), "icon_label": "fd",
	},
	"lightning_dust": {
		"display_name": "Lightning Dust", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(1.0, 0.9, 0.2), "icon_label": "ld",
	},
	"ice_dust": {
		"display_name": "Ice Dust", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(0.6, 0.9, 1.0), "icon_label": "id",
	},
	"wind_dust": {
		"display_name": "Wind Dust", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(0.75, 0.95, 0.85), "icon_label": "wd",
	},
	"nature_dust": {
		"display_name": "Nature Dust", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(0.4, 0.8, 0.3), "icon_label": "nd",
	},
	"water_dust": {
		"display_name": "Water Dust", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(0.25, 0.5, 0.95), "icon_label": "wt",
	},
	"earth_dust": {
		"display_name": "Earth Dust", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(0.6, 0.45, 0.25), "icon_label": "ed",
	},
	"cloth": {
		"display_name": "Cloth", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(0.8, 0.75, 0.6), "icon_label": "cl",
	},
	"phoenix_ash": {
		"display_name": "Phoenix Ash", "stackable": true, "max_stack": 5,
		"footprint": Vector2i(1, 1), "color": Color(0.95, 0.5, 0.15), "icon_label": "a",
		# NOT a bag consumable (deliberately no "usable"/heal) — you can't drink it.
		# It's spent automatically to REVIVE a downed ally: stand over their body
		# while carrying one and hold interact (see player._check_revive). Just
		# carrying one is what makes the revive prompt appear over a downed ally.
	},
	"blessed_band": {
		"display_name": "Blessed Band", "stackable": false, "max_stack": 1,
		"footprint": Vector2i(1, 1), "color": Color(0.95, 0.9, 0.6), "icon_label": "bb",
		"equip_slot": "ring",
	},
	# Fishing catches (see FISHING_SPOTS / fishing_spot.gd). Fish are sellable odds
	# and ends; mana_eel doubles as a mana consumable, and river_pearl is a pure
	# trinket. Rarity climbs with the catch (and the reel minigame's difficulty).
	"minnow": {
		"usable": true, "food_amount": 12.0,
		"display_name": "Minnow", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(0.6, 0.7, 0.75), "icon_label": "fi",
	},
	"river_bass": {
		"usable": true, "food_amount": 25.0,
		"display_name": "River Bass", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(0.45, 0.6, 0.55), "icon_label": "fi",
	},
	"old_boot": {
		"display_name": "Old Boot", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(0.4, 0.32, 0.25), "icon_label": "bo",
	},
	"silverscale": {
		"usable": true, "food_amount": 35.0,
		"display_name": "Silverscale", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(0.75, 0.8, 0.85), "icon_label": "fi",
		"rarity": "uncommon",
	},
	"river_pearl": {
		"display_name": "River Pearl", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(0.9, 0.92, 0.98), "icon_label": "pe",
		"rarity": "uncommon", "category": "trinket",
	},
	"golden_koi": {
		"display_name": "Golden Koi", "stackable": true, "max_stack": 20,
		"footprint": Vector2i(1, 1), "color": Color(0.95, 0.75, 0.25), "icon_label": "fi",
		"rarity": "rare",
	},
	"mana_eel": {
		"display_name": "Mana Eel", "stackable": true, "max_stack": 10,
		"footprint": Vector2i(1, 1), "color": Color(0.55, 0.45, 0.9), "icon_label": "ee",
		"usable": true, "mana_restore": 400.0, "rarity": "rare",
	},
	# Form Stones: one per spell form. Attaching a stone at the weapon
	# workbench adds that form's spell to a weapon (if the weapon type is
	# capable of it — see SpellData.get_capable_forms()); detaching returns the
	# stone. Same rare-ish 1-per-stack shape as element crystals. icon_label is
	# a distinct single letter per form; color is arbitrary placeholder art.
	"form_stone_ball": {
		"display_name": "Ball Gem",
		"stackable": false,
		"max_stack": 1,
		"footprint": Vector2i(1, 1),
		"color": Color(0.85, 0.5, 0.2),
		"icon_label": "b",
	},
	"form_stone_bolt": {
		"display_name": "Bolt Gem",
		"stackable": false,
		"max_stack": 1,
		"footprint": Vector2i(1, 1),
		"color": Color(0.9, 0.85, 0.3),
		"icon_label": "l",
	},
	"form_stone_rain": {
		"display_name": "Rain Gem",
		"stackable": false,
		"max_stack": 1,
		"footprint": Vector2i(1, 1),
		"color": Color(0.3, 0.6, 0.9),
		"icon_label": "r",
	},
	"form_stone_beam": {
		"display_name": "Beam Gem",
		"stackable": false,
		"max_stack": 1,
		"footprint": Vector2i(1, 1),
		"color": Color(0.6, 0.35, 0.85),
		"icon_label": "m",
	},
	"form_stone_burst": {
		"display_name": "Burst Gem",
		"stackable": false,
		"max_stack": 1,
		"footprint": Vector2i(1, 1),
		"color": Color(0.9, 0.4, 0.3),
		"icon_label": "u",
	},
	"form_stone_cone": {
		"display_name": "Cone Gem",
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
	# The Fishing Rod is a weapon-slot item (takes up a weapon slot) but casts
	# nothing — equip it and interact with a fishing spot to fish. It's a real
	# Weapon under the hood (so it occupies the slot / uses the same equip flow),
	# but SpellData.EQUIPPABLE_WEAPONS gives it no capable forms, attack_check()
	# refuses to cast with it, and its tooltip/name skip the weapon stat lines.
	"fishing_rod": {
		"display_name": "Fishing Rod",
		"stackable": false,
		"max_stack": 1,
		"footprint": Vector2i(1, 3),
		"color": Color(0.55, 0.4, 0.25),
		"icon_label": "FR",
		"equip_slot": "weapon",
	},
}

static var _warned_unknown_types := {}

# --- Vendor (hub) -------------------------------------------------------------
# Gold per unit the vendor pays. Junk and fish finally have a use; crystals and
# stones sell low enough that crafting them is still the better play. Weapons and
# gear sell by rarity (VENDOR_SELL_BY_RARITY). Anything not listed can't be sold.
const VENDOR_SELL := {
	"scrap": 1, "cloth": 2, "herbs": 1, "berries": 1, "red_moss": 2, "water_flask": 1,
	"mana_dust": 3, "pure_mana_shard": 15,
	"fire_dust": 3, "lightning_dust": 3, "ice_dust": 3, "wind_dust": 3,
	"nature_dust": 3, "water_dust": 3, "earth_dust": 3,
	"crystal_fire": 12, "crystal_lightning": 12, "crystal_ice": 12, "crystal_wind": 12,
	"crystal_nature": 12, "crystal_water": 12, "crystal_earth": 12,
	"form_stone_ball": 18, "form_stone_bolt": 18, "form_stone_rain": 18,
	"form_stone_beam": 18, "form_stone_burst": 18, "form_stone_cone": 18,
	"minnow": 2, "river_bass": 4, "silverscale": 8, "old_boot": 1, "mana_eel": 10,
	"river_pearl": 25, "golden_koi": 40,
	"health_potion": 10, "greater_health_potion": 25, "mana_crystal": 15, "refined_mana_crystal": 30,
}
const VENDOR_SELL_BY_RARITY := {"common": 8, "uncommon": 22, "rare": 55, "epic": 120, "legendary": 250, "mythic": 500}
# What the vendor sells: [item type, quantity, gold price].
const VENDOR_STOCK := [
	["health_potion", 1, 30],
	["greater_health_potion", 1, 75],
	["mana_crystal", 1, 45],
	["berries", 5, 12],
	["minnow", 3, 10],
	["backpack_basic", 1, 90],
	["belt_basic", 1, 60],
	["cloak_basic", 1, 70],
]

static func vendor_sell_price(item) -> int:
	if item == null:
		return 0
	if is_gear(item.type) or get_equip_slot(item.type) == "weapon":
		var r: String = item.rarity if item.rarity != "" else "common"
		return VENDOR_SELL_BY_RARITY.get(r, 8)
	return int(VENDOR_SELL.get(item.type, 0)) * maxi(1, item.quantity)

static func get_def(item_type: String) -> Dictionary:
	if !ITEMS.has(item_type):
		# Still falls back to scrap so nothing crashes, but say so once: a typo in
		# a loot table or recipe used to turn silently into scrap.
		if !_warned_unknown_types.has(item_type):
			_warned_unknown_types[item_type] = true
			push_warning("ItemData: unknown item type '%s' (treated as scrap)" % item_type)
		return ITEMS["scrap"]
	return ITEMS[item_type]

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
	"crystal_fire", "crystal_lightning", "crystal_ice", "crystal_wind", "crystal_nature", "crystal_water", "crystal_earth",
	"form_stone_ball", "form_stone_bolt", "form_stone_rain",
	"form_stone_beam", "form_stone_burst", "form_stone_cone",
]

static func is_material(item_type: String) -> bool:
	return is_form_stone(item_type) or item_type.begins_with("crystal_")

static func is_crystal(item_type: String) -> bool:
	return item_type.begins_with("crystal_")

# The Materials bank is split across two stash tabs: "crystals" (the element
# crystals) and "gems" (the form stones — their flavor text calls them rune/relic
# gems). "" (or anything else) = every material type, unsplit.
static func material_types_in(category: String) -> Array:
	match category:
		"crystals": return MATERIAL_TYPES.filter(func(t): return is_crystal(t))
		"gems": return MATERIAL_TYPES.filter(func(t): return is_form_stone(t))
		_: return MATERIAL_TYPES

# One-line flavor/util descriptions, keyed by type (kept out of ITEMS so the
# grid-shape data stays terse). Shown in the hover tooltip under the name.
const DESCRIPTIONS := {
	"scrap": "Bits of broken gear.",
	"gold": "It's Gold.",
	"crystal_fire": "Formed in the cooling blood of Hakii, it's still warm.",
	"crystal_lightning": "It crackles faintly against your palm.",
	"crystal_ice": "Cold enough to bite through a glove.",
	"crystal_wind": "A bit of Aeris's last breath, still restless.",
	"crystal_nature": "Green light stirs somewhere deep inside it.",
	"crystal_water": "A crystal tear that never quite dries.",
	"crystal_earth": "Dense, unyielding, older than the ruins.",
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
	"lightning_dust": "It prickles with static.",
	"ice_dust": "Cold, glittering motes.",
	"wind_dust": "Weightless, drifting dust.",
	"nature_dust": "Smells of loam and leaves.",
	"water_dust": "Damp, faintly cool grains.",
	"earth_dust": "Coarse mineral grit.",
	"cloth": "A scrap of woven cloth.",
	"phoenix_ash": "Embers that rekindle life. Stand over a downed ally to revive them — one is spent per revive. Can't be used from your bag.",
	"blessed_band": "A holy ring. Grants a barrier that shatters when spent.",
	"fishing_rod": "Equip it and cast at a fishing spot. Casts no magic.",
	"minnow": "A tiny river fish.",
	"river_bass": "A decent catch.",
	"old_boot": "Someone's soggy loss.",
	"silverscale": "A prized silver fish.",
	"river_pearl": "A lustrous pearl from the riverbed.",
	"golden_koi": "A rare, radiant koi.",
	"mana_eel": "An eel humming with mana — restores mana when eaten.",
	"form_stone_ball": "An ancient rune gem that shapes magic into an explosive sphere.",
	"form_stone_bolt": "Its carved sigils focus magic into a swift projectile.",
	"form_stone_rain": "A relic gem that calls magic down upon a targeted area.",
	"form_stone_beam": "A worn gem that channels magic into a continuous stream.",
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
# "@element_crystal" accepts any element crystal).
const CRAFTING_WILDCARDS := {
	"@element_crystal": ["crystal_fire", "crystal_lightning", "crystal_ice", "crystal_wind", "crystal_nature", "crystal_water", "crystal_earth"],
}
const CRAFTING_RECIPES := [
	{"inputs": [["cloth", 1], ["crystal_nature", 1]], "output": ["blessed_band", 1]},
	{"inputs": [["crystal_fire", 1], ["herbs", 3]], "output": ["phoenix_ash", 1]},
	{"inputs": [["herbs", 2], ["water_flask", 1]], "output": ["health_potion", 1]},
	{"inputs": [["health_potion", 1], ["red_moss", 2]], "output": ["greater_health_potion", 1]},
	{"inputs": [["mana_dust", 3], ["@element_crystal", 1]], "output": ["mana_crystal", 1]},
	{"inputs": [["mana_crystal", 1], ["pure_mana_shard", 1]], "output": ["refined_mana_crystal", 1]},
	{"inputs": [["cloth", 2], ["scrap", 2]], "output": ["fishing_rod", 1]},
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
const RARITY_ORDER := ["common", "uncommon", "rare", "epic", "legendary", "mythic"]
# 6 rarity tiers: grey / green / blue / purple / orange / red. Only common,
# uncommon and rare actually DROP right now (see RARITY_DROP_WEIGHTS); the rest
# exist for colors + future use.
const RARITIES := {
	"common": {"display": "Common", "color": Color(0.72, 0.72, 0.75), "gear_traits": 1, "stat_mult": 1.0},
	"uncommon": {"display": "Uncommon", "color": Color(0.35, 0.8, 0.35), "gear_traits": 2, "stat_mult": 1.15},
	"rare": {"display": "Rare", "color": Color(0.3, 0.55, 0.95), "gear_traits": 3, "stat_mult": 1.3},
	"epic": {"display": "Epic", "color": Color(0.65, 0.3, 0.9), "gear_traits": 4, "stat_mult": 1.5},
	"legendary": {"display": "Legendary", "color": Color(0.95, 0.6, 0.15), "gear_traits": 4, "stat_mult": 1.8},
	"mythic": {"display": "Mythic", "color": Color(0.9, 0.2, 0.2), "gear_traits": 5, "stat_mult": 2.2},
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

# --- Itemization stat generation (rarity -> rolled numeric stats) ----------
# Weapons ALWAYS roll Attack first (flat, base 100). Uncommon+ also roll crit stats
# (uncommon = one random crit stat; rare = both).
const WEAPON_ATTACK_BY_RARITY := {
	"common": [90, 100], "uncommon": [105, 110], "rare": [110, 120],
}
# +% range for EACH crit stat a weapon carries.
const WEAPON_CRIT_BY_RARITY := {
	"uncommon": [5, 10], "rare": [10, 20],
}
# Gear rolls this many RANDOM numeric stats from GEAR_STAT_POOL (common = none).
const GEAR_STAT_COUNT_BY_RARITY := {"common": 0, "uncommon": 1, "rare": 2}
const GEAR_STAT_POOL := ["attack", "crit_rate", "crit_damage", "defense", "health", "mana"]
# Per-stat [min,max] roll by rarity. Defense is a FIRST-PASS guess (DR = def/(def+100),
# so a rare +20-40 piece ≈ 17-29% less damage each — tune once it's felt in play).
# Mana mirrors Health (both are flat pools with a 1000 base), added to the wielded
# weapon's mana cap (weapon.bonus_max_mana <- player._refresh_gear_effects).
const GEAR_STAT_RANGES := {
	"attack": {"uncommon": [5, 10], "rare": [10, 20]},
	"health": {"uncommon": [50, 100], "rare": [100, 200]},
	"mana": {"uncommon": [50, 100], "rare": [100, 200]},
	"crit_rate": {"uncommon": [2, 5], "rare": [4, 7]},
	"crit_damage": {"uncommon": [2, 5], "rare": [4, 7]},
	"defense": {"uncommon": [10, 20], "rare": [20, 40]},
}

# Roll the numeric stat dict for a gear item of this rarity (common -> {}). Rarities
# above rare fall back to rare's counts/ranges until they're specced.
static func roll_gear_stats(rarity: String) -> Dictionary:
	var count: int = GEAR_STAT_COUNT_BY_RARITY.get(rarity, GEAR_STAT_COUNT_BY_RARITY.get("rare", 2))
	if count <= 0:
		return {}
	var pool := GEAR_STAT_POOL.duplicate()
	pool.shuffle()
	var result := {}
	for i in mini(count, pool.size()):
		var stat: String = pool[i]
		var ranges: Dictionary = GEAR_STAT_RANGES.get(stat, {})
		var band: Array = ranges.get(rarity, ranges.get("rare", [0, 0]))
		result[stat] = randi_range(int(band[0]), int(band[1]))
	return result

# Display metadata for the numeric stats (tooltips). crit_rate/crit_damage show as %.
const STAT_DISPLAY := {
	"attack": "Attack", "defense": "Defense", "health": "Health", "mana": "Mana",
	"crit_rate": "Crit Rate", "crit_damage": "Crit Damage",
}
static func stat_is_percent(stat: String) -> bool:
	return stat == "crit_rate" or stat == "crit_damage"

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
	"common": 60, "uncommon": 30, "rare": 10,
}

# --- Loot tables (per-entry-chance system — see world_loot.roll_loot_table) --------
# Named item bundles a loot entry can reference. Rarity-agnostic: how OFTEN each item
# in a group appears is weighted by its rarity_of_type via RARITY_DROP_WEIGHTS.
# Thematic bundles. gold / scrap / cloth are single items — reference them directly by
# type in a table, not via a group (gold = money, scrap = repair resource, kept apart).
const LOOT_GROUPS := {
	"field": ["herbs", "water_flask", "red_moss"],
	"dusts": ["fire_dust", "lightning_dust", "ice_dust", "wind_dust", "nature_dust", "water_dust", "earth_dust"],
	"crystals": ["crystal_fire", "crystal_lightning", "crystal_ice", "crystal_wind", "crystal_nature", "crystal_water", "crystal_earth"],
	"form_stones": ["form_stone_ball", "form_stone_bolt", "form_stone_rain", "form_stone_beam", "form_stone_burst", "form_stone_cone"],
	"mana_mats": ["mana_dust", "pure_mana_shard"],
	"potions": ["health_potion", "greater_health_potion"],
	"mana_potions": ["mana_crystal", "refined_mana_crystal"],
	"weapons": ["tome", "orb", "wand"],
	"gear": ["belt_basic", "cloak_basic", "backpack_basic"],
}
# Gear an "@gear" token can resolve to (rolled at the enemy's tier rarity).
const GEAR_DROP_TYPES := ["belt_basic", "cloak_basic", "backpack_basic"]

# Loot tables: SOURCE TYPE -> TIER (bronze/silver/gold) -> a list of ENTRIES. Every
# lootable (enemy archetype OR container base type) resolves to LOOT_TABLES[type][tier].
# TIER is separate from item rarity: bronze = baseline, silver = the "elite"/rarer
# version, gold = locked-area only (never spawns yet). Each entry is one independent roll:
#   {"src": <group | item type | @token>, "chance": 0-100, "qty": [min,max]?, "rarity": <override>?}
# chance defaults 100; qty defaults to the item's DROP_QUANTITIES (1 for @tokens); an
# optional "rarity" forces the created weapon/gear rarity (containers have no enemy tier
# to inherit). @tokens resolve to the source's identity: @weapon/@crystal/@gear (enemies)
# and @dust/@crystal (element for mining nodes). Enemies drop combat loot only (no field/
# cloth/dust). All placeholders — tune freely.
const LOOT_TABLES := {
	# Elemental enemies (2026-08-30): NO @weapon/@gear/form_stones — they drop
	# materials, potions, gold, and their element crystal (@crystal) only.
	"pentagon": {
		"bronze": [
			{"src": "scrap", "chance": 50},
			{"src": "mana_potions", "chance": 20},
			{"src": "@crystal", "chance": 15},
		],
		"silver": [
			{"src": "scrap", "chance": 80},
			{"src": "mana_potions", "chance": 25},
			{"src": "potions", "chance": 15},
			{"src": "@crystal", "chance": 30},
		],
		"gold": [
			{"src": "gold", "chance": 100, "qty": [8, 20]},
			{"src": "potions", "chance": 50},
			{"src": "@crystal", "chance": 60},
		],
	},
	"triangle": {
		"bronze": [
			{"src": "scrap", "chance": 30},
			{"src": "mana_potions", "chance": 10},
			{"src": "@crystal", "chance": 8},
		],
		"silver": [
			{"src": "scrap", "chance": 50},
			{"src": "mana_potions", "chance": 20},
			{"src": "potions", "chance": 10},
			{"src": "@crystal", "chance": 15},
		],
		"gold": [
			{"src": "gold", "chance": 100, "qty": [5, 12]},
			{"src": "potions", "chance": 30},
			{"src": "@crystal", "chance": 35},
		],
	},
	"circle": {
		"bronze": [
			{"src": "scrap", "chance": 45},
			{"src": "mana_potions", "chance": 18},
			{"src": "@crystal", "chance": 12},
		],
		"silver": [
			{"src": "scrap", "chance": 70},
			{"src": "mana_potions", "chance": 22},
			{"src": "potions", "chance": 12},
			{"src": "@crystal", "chance": 25},
		],
		"gold": [
			{"src": "gold", "chance": 100, "qty": [6, 16]},
			{"src": "potions", "chance": 40},
			{"src": "@crystal", "chance": 50},
		],
	},
	"hexagon": {
		"bronze": [
			{"src": "scrap", "chance": 50},
			{"src": "mana_potions", "chance": 18},
			{"src": "@crystal", "chance": 15},
		],
		"silver": [
			{"src": "scrap", "chance": 75},
			{"src": "mana_potions", "chance": 22},
			{"src": "potions", "chance": 14},
			{"src": "@crystal", "chance": 28},
		],
		"gold": [
			{"src": "gold", "chance": 100, "qty": [8, 18]},
			{"src": "potions", "chance": 40},
			{"src": "@crystal", "chance": 55},
		],
	},
	"square": {
		"bronze": [
			{"src": "scrap", "chance": 55},
			{"src": "mana_potions", "chance": 20},
			{"src": "@crystal", "chance": 18},
		],
		"silver": [
			{"src": "scrap", "chance": 85},
			{"src": "potions", "chance": 18},
			{"src": "@crystal", "chance": 35},
		],
		"gold": [
			{"src": "gold", "chance": 100, "qty": [10, 24]},
			{"src": "potions", "chance": 55},
			{"src": "@crystal", "chance": 70},
		],
	},
	"berry_bush": {
		"bronze": [
			{"src": "berries", "chance": 100, "qty": [2, 4]},
			{"src": "herbs", "chance": 40, "qty": [1, 2]},
		],
		"silver": [
			{"src": "berries", "chance": 100, "qty": [3, 6]},
			{"src": "herbs", "chance": 60, "qty": [1, 3]},
			{"src": "red_moss", "chance": 25},
		],
		"gold": [
			{"src": "berries", "chance": 100, "qty": [5, 8]},
			{"src": "herbs", "chance": 80, "qty": [2, 4]},
			{"src": "red_moss", "chance": 50},
		],
	},
	"crate": {
		"bronze": [
			{"src": "scrap", "chance": 80, "qty": [1, 3]},
			{"src": "gold", "chance": 60, "qty": [1, 6]},
			{"src": "cloth", "chance": 30, "qty": [1, 2]},
			{"src": "potions", "chance": 20},
		],
		"silver": [
			{"src": "scrap", "chance": 70, "qty": [1, 4]},
			{"src": "gold", "chance": 80, "qty": [3, 10]},
			{"src": "potions", "chance": 40},
			{"src": "mana_mats", "chance": 30},
			{"src": "crystals", "chance": 15},
		],
		"gold": [
			{"src": "gold", "chance": 100, "qty": [8, 20]},
			{"src": "potions", "chance": 60},
			{"src": "crystals", "chance": 40},
			{"src": "form_stones", "chance": 20},
			{"src": "weapons", "chance": 15, "rarity": "rare"},
		],
	},
	"chest": {
		"bronze": [
			{"src": "gold", "chance": 90, "qty": [2, 8]},
			{"src": "potions", "chance": 40},
			{"src": "mana_potions", "chance": 20},
			{"src": "crystals", "chance": 15},
		],
		"silver": [
			{"src": "gold", "chance": 100, "qty": [5, 15]},
			{"src": "potions", "chance": 50},
			{"src": "crystals", "chance": 30},
			{"src": "form_stones", "chance": 15},
			{"src": "gear", "chance": 10, "rarity": "uncommon"},
		],
		"gold": [
			{"src": "gold", "chance": 100, "qty": [15, 40]},
			{"src": "potions", "chance": 60},
			{"src": "crystals", "chance": 60},
			{"src": "form_stones", "chance": 40},
			{"src": "gear", "chance": 30, "rarity": "rare"},
			{"src": "weapons", "chance": 20, "rarity": "rare"},
		],
	},
	"weapon_case": {
		"bronze": [
			{"src": "scrap", "chance": 40, "qty": [1, 2]},
			{"src": "form_stones", "chance": 30},
			{"src": "weapons", "chance": 60, "rarity": "common"},
		],
		"silver": [
			{"src": "form_stones", "chance": 50},
			{"src": "weapons", "chance": 70, "rarity": "uncommon"},
			{"src": "gear", "chance": 30, "rarity": "uncommon"},
		],
		"gold": [
			{"src": "form_stones", "chance": 70},
			{"src": "weapons", "chance": 100, "rarity": "rare"},
			{"src": "gear", "chance": 50, "rarity": "rare"},
		],
	},
	"mining_node": {
		"bronze": [
			{"src": "@dust", "chance": 100, "qty": [1, 3]},
			{"src": "@crystal", "chance": 10},
		],
		"silver": [
			{"src": "@dust", "chance": 100, "qty": [2, 5]},
			{"src": "@crystal", "chance": 25},
		],
		"gold": [
			{"src": "@dust", "chance": 100, "qty": [4, 8]},
			{"src": "@crystal", "chance": 60},
			{"src": "pure_mana_shard", "chance": 30, "qty": [1, 2]},
		],
	},
	"medic_box": {
		"bronze": [
			{"src": "field", "chance": 70, "qty": [1, 3]},
			{"src": "cloth", "chance": 50, "qty": [1, 2]},
			{"src": "potions", "chance": 80},
		],
		"silver": [
			{"src": "field", "chance": 80, "qty": [2, 4]},
			{"src": "cloth", "chance": 60, "qty": [1, 3]},
			{"src": "potions", "chance": 100},
			{"src": "mana_potions", "chance": 30},
		],
		"gold": [
			{"src": "field", "chance": 90, "qty": [2, 5]},
			{"src": "cloth", "chance": 70, "qty": [2, 4]},
			{"src": "potions", "chance": 100, "qty": [2, 3]},
			{"src": "mana_potions", "chance": 60},
		],
	},
}

# The table for a source type + tier (falls back to the type's bronze, then []).
static func get_loot_table(source_type: String, tier: String) -> Array:
	var tiers: Dictionary = LOOT_TABLES.get(source_type, {})
	return tiers.get(tier, tiers.get("bronze", []))
# Per-enemy-type loot pools — item types grouped by rarity. Each roll picks a
# rarity (weighted), then a random item of that tier here. "@weapon" resolves to
# the enemy's own weapon (carrying its element/forms). New enemy types get their
# own entry keyed by their loot_pool id (see enemy.gd).
const ENEMY_LOOT_POOLS := {
	"basic": {
		"common": ["scrap", "gold", "herbs", "water_flask", "red_moss", "cloth", "mana_dust",
			"fire_dust", "lightning_dust", "ice_dust", "wind_dust", "nature_dust", "water_dust", "earth_dust",
			"health_potion", "mana_crystal"],
		"uncommon": ["pure_mana_shard", "crystal_fire", "crystal_lightning", "crystal_ice", "crystal_wind", "crystal_nature", "crystal_water", "crystal_earth",
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
	"fire_dust": [1, 3], "lightning_dust": [1, 3], "ice_dust": [1, 3], "wind_dust": [1, 3],
	"nature_dust": [1, 3], "water_dust": [1, 3], "earth_dust": [1, 3],
	"health_potion": [1, 2], "mana_crystal": [1, 2], "greater_health_potion": [1, 2],
	"minnow": [1, 2], "river_bass": [1, 2], "silverscale": [1, 1], "golden_koi": [1, 1],
	"mana_eel": [1, 1], "old_boot": [1, 1], "river_pearl": [1, 1],
}
static func get_drop_qty(item_type: String) -> Array:
	return DROP_QUANTITIES.get(item_type, [1, 1])

# Hand-placed lootable containers. Each loot_container node's `container_type`
# keys in here for its label, color, roll count, and rarity-grouped loot pool —
# same tier structure as ENEMY_LOOT_POOLS (a roll picks a rarity, then a random
# item of that tier; empty/missing tiers are skipped). These "loot" pools are
# placeholders meant to be edited freely; "@weapon" is NOT valid here (no source
# enemy) — list real weapon types (tome/orb/wand) for weapon drops instead.
const CONTAINERS := {
	# New-format container base types (loot lives in LOOT_TABLES[type][tier]). Tier
	# tints the crate (bronze/silver/gold); an "elemental" node's color is its element.
	"crate": {"display_name": "Crate", "color": Color(0.55, 0.4, 0.22)},
	"chest": {"display_name": "Chest", "color": Color(0.5, 0.42, 0.3)},
	"weapon_case": {"display_name": "Weapon Case", "color": Color(0.4, 0.4, 0.48)},
	"medic_box": {"display_name": "Medic Box", "color": Color(0.85, 0.35, 0.35)},
	"mining_node": {"display_name": "Mining Node", "color": Color(0.42, 0.4, 0.46), "elemental": true},
	"wooden_crate": {"display_name": "Wooden Crate", "color": Color(0.55, 0.4, 0.2), "rolls_min": 1, "rolls_max": 2, "loot": {
		"common": ["scrap", "gold", "cloth", "health_potion"], "uncommon": ["mana_crystal", "mana_dust"]}},
	"iron_chest": {"display_name": "Iron Chest", "color": Color(0.5, 0.5, 0.55), "rolls_min": 1, "rolls_max": 2, "loot": {
		"common": ["gold", "health_potion", "mana_crystal"], "uncommon": ["crystal_fire", "crystal_lightning", "crystal_ice", "crystal_wind", "crystal_nature", "crystal_water", "crystal_earth"],
		"rare": ["greater_health_potion", "refined_mana_crystal"]}},
	"barrel": {"display_name": "Barrel", "color": Color(0.45, 0.3, 0.15), "rolls_min": 1, "rolls_max": 2, "loot": {
		"common": ["gold", "water_flask", "herbs", "health_potion"], "uncommon": ["mana_crystal"]}},
	"herb_patch": {"display_name": "Herb Patch", "color": Color(0.3, 0.6, 0.3), "rolls_min": 1, "rolls_max": 2, "loot": {
		"common": ["herbs", "red_moss"], "uncommon": ["herbs"]}},
	"boss_cache": {"display_name": "Boss Cache", "color": Color(0.7, 0.5, 0.15), "rolls_min": 2, "rolls_max": 4, "loot": {
		"common": ["gold", "health_potion"], "uncommon": ["crystal_fire", "crystal_lightning", "crystal_ice", "crystal_wind", "crystal_nature", "crystal_water", "crystal_earth", "belt_basic", "cloak_basic", "backpack_basic"],
		"rare": ["greater_health_potion", "refined_mana_crystal", "form_stone_ball", "form_stone_bolt", "form_stone_beam", "blessed_band"]}},
	"cabinet": {"display_name": "Cabinet", "color": Color(0.5, 0.38, 0.25), "rolls_min": 1, "rolls_max": 2, "loot": {
		"common": ["cloth", "scrap", "gold", "health_potion"], "uncommon": ["mana_crystal"]}},
	"weapon_rack": {"display_name": "Weapon Rack", "color": Color(0.4, 0.4, 0.45), "rolls_min": 1, "rolls_max": 2, "loot": {
		"common": ["scrap"], "uncommon": ["form_stone_ball", "form_stone_bolt"],
		"rare": ["tome", "orb", "wand", "form_stone_beam", "form_stone_burst", "form_stone_cone"]}},
	"mushroom_cluster": {"display_name": "Mushroom Cluster", "color": Color(0.6, 0.35, 0.4), "rolls_min": 1, "rolls_max": 2, "loot": {
		"common": ["herbs", "red_moss"], "uncommon": ["red_moss"]}},
	"berry_bush": {"display_name": "Berry Bush", "color": Color(0.35, 0.55, 0.3), "rolls_min": 1, "rolls_max": 2, "loot": {
		"common": ["herbs", "water_flask"], "uncommon": ["herbs"]}},
	"ancient_chest": {"display_name": "Ancient Chest", "color": Color(0.4, 0.55, 0.5), "rolls_min": 2, "rolls_max": 3, "loot": {
		"common": ["gold"], "uncommon": ["crystal_fire", "crystal_lightning", "crystal_ice", "crystal_wind", "crystal_nature", "crystal_water", "crystal_earth"],
		"rare": ["greater_health_potion", "refined_mana_crystal", "blessed_band", "form_stone_rain", "form_stone_beam"]}},
	"grave": {"display_name": "Grave", "color": Color(0.4, 0.4, 0.42), "rolls_min": 1, "rolls_max": 2, "loot": {
		"common": ["scrap", "gold", "cloth"], "uncommon": ["crystal_nature"], "rare": ["blessed_band"]}},
	"supply_wagon": {"display_name": "Supply Wagon", "color": Color(0.6, 0.5, 0.35), "rolls_min": 2, "rolls_max": 3, "loot": {
		"common": ["gold", "health_potion", "mana_crystal", "herbs", "water_flask", "cloth"], "uncommon": ["mana_dust", "crystal_fire"]}},
	"ore_vein": {"display_name": "Ore Vein", "color": Color(0.35, 0.35, 0.4), "rolls_min": 1, "rolls_max": 2, "loot": {
		"common": ["scrap"], "uncommon": ["crystal_fire", "crystal_lightning", "crystal_ice", "crystal_wind", "crystal_nature", "crystal_water", "crystal_earth"], "rare": ["pure_mana_shard"]}},
	"crystal_growth": {"display_name": "Crystal Growth", "color": Color(0.4, 0.7, 0.85), "rolls_min": 1, "rolls_max": 2, "loot": {
		"common": ["mana_dust"], "uncommon": ["crystal_fire", "crystal_lightning", "crystal_ice", "crystal_wind", "crystal_nature", "crystal_water", "crystal_earth", "pure_mana_shard"], "rare": ["refined_mana_crystal"]}},
	"runner_pack": {"display_name": "Runner Pack", "color": Color(0.5, 0.35, 0.25), "rolls_min": 1, "rolls_max": 3, "loot": {
		"common": ["gold", "health_potion", "mana_crystal", "scrap"], "uncommon": ["crystal_fire", "crystal_lightning", "crystal_ice", "crystal_wind", "crystal_nature", "crystal_water", "crystal_earth", "mana_dust"],
		"rare": ["greater_health_potion", "form_stone_ball", "blessed_band"]}},
}

# Hand-placed fishing spots (see fishing_spot.gd). A cast rolls ONE catch from
# this spot's rarity-grouped pool (weighted by RARITY_DROP_WEIGHTS, falling to a
# lower tier if the rolled one is empty). The catch's rarity scales the reel
# minigame's difficulty — rarer fish are harder to land. Same "loot" tier shape
# as CONTAINERS; edit freely. "@weapon" is NOT valid here.
const FISHING_SPOTS := {
	"pond": {"display_name": "Fishing Spot", "color": Color(0.35, 0.55, 0.7), "loot": {
		"common": ["minnow", "river_bass", "old_boot"],
		"uncommon": ["silverscale", "river_pearl"],
		"rare": ["golden_koi"]}},
	"river": {"display_name": "River", "color": Color(0.3, 0.5, 0.75), "loot": {
		"common": ["minnow", "river_bass", "old_boot"],
		"uncommon": ["silverscale", "river_pearl"],
		"rare": ["golden_koi", "mana_eel"]}},
	"deep_water": {"display_name": "Deep Water", "color": Color(0.2, 0.35, 0.6), "loot": {
		"common": ["river_bass", "old_boot"],
		"uncommon": ["silverscale", "river_pearl"],
		"rare": ["golden_koi", "mana_eel"]}},
}

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
	return rarity_of_type(item.type)

# The canonical rarity of an item TYPE (loot weighting + color). An explicit def
# "rarity" wins; else crystals + form stones are uncommon; else common. A few valuable
# odds-and-ends are bumped here so their defs don't need editing.
const TYPE_RARITY := {
	"pure_mana_shard": "uncommon",
	"phoenix_ash": "rare",
	"blessed_band": "rare",
}
static func rarity_of_type(item_type: String) -> String:
	var def := get_def(item_type)
	if def.has("rarity"):
		return def["rarity"]
	if TYPE_RARITY.has(item_type):
		return TYPE_RARITY[item_type]
	if item_type.begins_with("crystal_") or is_form_stone(item_type):
		return "uncommon"
	return "common"

# Full display name: weapons read "<Rarity> <Element> <Type>" (e.g. "Common
# Fire Wand"), gear reads "<Rarity> <Type>" (e.g. "Common Cloak"); everything
# else is just its plain name.
static func display_name(item) -> String:
	var base: String = get_def(item.type).get("display_name", item.type)
	if item.weapon != null:
		# The fishing rod is a Weapon under the hood but has no element/rarity
		# flavor — show its plain name.
		if item.type == "fishing_rod":
			return base
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
	if item.weapon != null and item.type != "fishing_rod":
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
	if item.weapon != null and item.type != "fishing_rod":
		var w = item.weapon
		var ecol := _hex(SpellData.ELEMENTS.get(w.element, SpellData.ELEMENTS["default"])["color"])
		if not w.forms.is_empty():
			var forms_str := " | ".join(w.forms.map(func(f): return String(f).capitalize()))
			out += "\n[font_size=38][color=#%s]%s[/color][/font_size]" % [ecol, forms_str]
		# Combat stats (itemization pass): Attack is the base; crit stats show only if
		# the weapon rolled them (uncommon = one, rare = both).
		out += "\n[font_size=36][color=#ffd27a]Attack %d[/color][/font_size]" % roundi(w.attack)
		if w.crit_rate > 0.0:
			out += "\n[font_size=30][color=#d9d98a]+%d%% Crit Rate[/color][/font_size]" % roundi(w.crit_rate)
		if w.crit_damage > 0.0:
			out += "\n[font_size=30][color=#d9d98a]+%d%% Crit Damage[/color][/font_size]" % roundi(w.crit_damage)
		out += "\n[font_size=34][color=#a98cf0]Mana %d/%d[/color][/font_size]" % [roundi(w.mana), roundi(w.max_mana)]
		out += "\n[font_size=24][color=#8a8a90]Durability %d/%d[/color][/font_size]" % [roundi(w.durability), roundi(w.max_durability)]
	if is_gear(item.type):
		var broken: bool = item.max_durability > 0.0 and item.durability <= 0.0
		var acol := "8a8a90" if broken else "7ad07a"
		for attr_id in item.attributes:
			out += "\n[font_size=30][color=#%s]• %s[/color][/font_size]" % [acol, gear_attribute_desc(attr_id)]
		# Numeric stats rolled by rarity (greyed out when the piece is broken, matching
		# how _gear_stat_sum() stops applying them at 0 durability).
		var scol := "8a8a90" if broken else "d9d98a"
		for stat in ["attack", "defense", "health", "mana", "crit_rate", "crit_damage"]:
			if item.stats.has(stat):
				var suffix := "%" if stat_is_percent(stat) else ""
				out += "\n[font_size=30][color=#%s]+%d%s %s[/color][/font_size]" % [scol, roundi(item.stats[stat]), suffix, STAT_DISPLAY.get(stat, stat)]
		if item.max_durability > 0.0:
			out += "\n[font_size=24][color=#8a8a90]Durability %d/%d[/color][/font_size]" % [roundi(item.durability), roundi(item.max_durability)]
	if def.get("usable", false):
		if def.has("heal_amount"):
			out += "\n[font_size=30]Restores %d health.[/font_size]" % roundi(def["heal_amount"])
		if def.has("mana_restore"):
			out += "\n[font_size=30]Restores %d mana.[/font_size]" % roundi(def["mana_restore"])
	return out
