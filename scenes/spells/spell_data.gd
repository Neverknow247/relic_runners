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

# Weapons no longer ship with all their forms — they're born form-less (see
# weapon.gd's _init) and forms get attached/detached as Form Stone items at
# the weapon workbench. Each type's "forms" list above is now the *capability
# list* (which forms it CAN hold), not what it starts with. STARTER_FORMS is
# the single form the Starter Kit's weapon comes pre-attached with (see
# player.gd's apply_starter_kit()) so a fresh loadout always has at least one
# sequence spell to cast, not just the free default.
const STARTER_FORMS := {
	"tome": "ball",
	"orb": "burst",
	"wand": "bolt",
}

static func get_capable_forms(weapon_type: String) -> Array:
	return EQUIPPABLE_WEAPONS.get(weapon_type, EQUIPPABLE_WEAPONS["tome"])["forms"]

static func get_starter_form(weapon_type: String) -> String:
	return STARTER_FORMS.get(weapon_type, "")

# crit_chance is a percent (5.0 = 5%) — rolled once by the casting peer at
# cast time (see player.gd's cast_spell()/enemy.gd's fire_spell()) and
# threaded through the spawn RPC as a plain bool so every peer applies the
# exact same result instead of each independently re-rolling and
# disagreeing on whether a given hit crit. "default" (the 0-durability/
# broken-weapon downgrade — see ELEMENTS' comment below) never crits, same
# neutral-in-every-way treatment as its other stats.
const CRIT_MULTIPLIER := 1.5

const WEAPONS = {
	"default": {
		"damage": 1.0,
		"speed": 1.0,
		"size": 1.0,
		"lifetime": 1.0,
		"crit_chance": 0.0,
	},
	"tome": {
		"damage": 1.5,
		"speed": 0.85,
		"size": 1.15,
		"lifetime": 1.15,
		"crit_chance": 5.0,
	},
	"orb": {
		"damage": 1.25,
		"speed": 1.0,
		"size": 1.2,
		"lifetime": 1.0,
		"crit_chance": 5.0,
	},
	"wand": {
		"damage": 1.15,
		"speed": 1.25,
		"size": 0.9,
		"lifetime": 0.9,
		"crit_chance": 5.0,
	},
}

const ELEMENTS = {
	# Never assigned to a real weapon/enemy (see EQUIPPABLE_WEAPONS/enemy.gd's
	# ELEMENT_TYPES — always fire/holy/air) except as a neutral fallback and,
	# deliberately, as what a 0-durability weapon's casts get downgraded to
	# (see player.gd's get_spell_data()/get_default_spell_data()) — reusing
	# "default"'s already-neutral 1.0 multipliers (and its absence from
	# WEAPON_BEATS/ELEMENT_BEATS, so matchup bonuses are 0 too) for "a broken
	# weapon gets no elemental/weapon bonuses", with gray standing in for
	# "nothing special" instead of white.
	"default": {
		"damage": 1.0,
		"speed": 1.0,
		"color": Color(0.5, 0.5, 0.5)
	},
	"fire": {
		"damage": 1.5,
		"speed": 0.85,
		"color": Color(1.0, 0.35, 0.1)
	},
	"holy": {
		"damage": 1.25,
		"speed": 1.0,
		"color": Color(1.0, 0.95, 0.55)
	},
	"air": {
		"damage": 1.15,
		"speed": 1.35,
		"color": Color(0.65, 0.95, 1.0)
	},
}

const FORMS = {
	# "default" is the free, sequence-less fallback attack — no mana cost at
	# all (not just cheap), and its damage is intentionally left alone (not
	# doubled) so a real sequence cast reads as meaningfully more powerful,
	# matching the "sequences should feel powerful since they're limited by
	# mana" goal.
	"default": {
		"scene": preload("res://scenes/spells/projectile.tscn"),
		"damage": 1.0,
		"speed": 1.0,
		"size": 1.0,
		"lifetime": 1.0,
		"attack_cooldown": 0.35,
		"spawn_offset": 32.0,
		"mana_cost": 0.0,
	},
	# ball travels, then detonates an AoE on the enemy it strikes (see
	# ball_projectile.gd). auto_hit is off so the ball deals no direct damage —
	# all of it comes from the explosion it spawns, so the struck enemy takes
	# exactly one explosion hit, not hit + explosion.
	"ball": {
		"scene": preload("res://scenes/spells/ball_projectile.tscn"),
		"damage": 3.3,
		"speed": 0.65,
		"size": 2.0,
		"lifetime": 1.1,
		"attack_cooldown": 0.5,
		"spawn_offset": 32.0,
		"mana_cost": 16.0,
		"auto_hit": false,
	},
	"bolt": {
		"scene": preload("res://scenes/spells/bolt_projectile.tscn"),
		"damage": 2.6,
		"speed": 1.5,
		"size": 0.8,
		"lifetime": 0.85,
		"attack_cooldown": 0.22,
		"spawn_offset": 32.0,
		"mana_cost": 12.0,
	},
	# rain is a stationary ground zone that ticks full damage each second to
	# anyone standing in it (see rain_projectile.gd); auto_hit off so the only
	# damage is the DoT, pierce/no-wall-stop so the zone persists its lifetime.
	"rain": {
		"scene": preload("res://scenes/spells/rain_projectile.tscn"),
		"damage": 2.3,
		"speed": 0.0,
		"size": 3.0,
		"lifetime": 4.0,
		"attack_cooldown": 0.4,
		"spawn_offset": 32.0,
		"mana_cost": 11.0,
		"pierce": true,
		"stop_on_wall": false,
		"auto_hit": false,
	},
	# beam is a fixed forward line anchored at the caster (speed 0, spawn at the
	# caster), piercing everything along it — the long thin hitbox lives in
	# beam_projectile.tscn.
	"beam": {
		"scene": preload("res://scenes/spells/beam_projectile.tscn"),
		"damage": 2.4,
		"speed": 0.0,
		"size": 0.7,
		"lifetime": 0.55,
		"attack_cooldown": 0.15,
		"spawn_offset": 0.0,
		"mana_cost": 9.0,
		"pierce": true,
		"stop_on_wall": false,
	},
	# burst is a stationary AoE centered on the caster that hits everyone in it
	# (multi-hit, not consumed by the first target).
	"burst": {
		"scene": preload("res://scenes/spells/burst_projectile.tscn"),
		"damage": 3.0,
		"speed": 0.0,
		"size": 4.8,
		"lifetime": 0.35,
		"attack_cooldown": 0.65,
		"spawn_offset": 0.0,
		"mana_cost": 14.0,
		"pierce": true,
		"stop_on_wall": false,
	},
	# cone is a fixed 45-degree wedge in front of the caster (speed 0, spawn at
	# the caster), piercing everyone inside it — the wedge hitbox lives in
	# cone_projectile.tscn.
	"cone": {
		"scene": preload("res://scenes/spells/cone_projectile.tscn"),
		"damage": 2.7,
		"speed": 0.0,
		"size": 1.5,
		"lifetime": 0.45,
		"attack_cooldown": 0.35,
		"spawn_offset": 0.0,
		"mana_cost": 13.0,
		"pierce": true,
		"stop_on_wall": false,
	},
}

# "Paradox tournament" type matchups. Full future roster (7 weapons, 7
# elements), keyed by real name — letters below match the reference table:
#   A: tome/fire        B: totem/earth        C: instrument/lightning
#   D: lantern/water    E: orb/holy           F: staff/necrotic
#   G: wand/air
# Only tome/orb/wand and fire/holy/air have real stats (WEAPONS/ELEMENTS)
# right now, but the full beats-table is defined up front so adding the
# other 4 of each later is just adding their WEAPONS/ELEMENTS/FORMS entries
# — no matchup logic changes needed.
const WEAPON_BEATS := {
	"tome": ["totem", "instrument", "orb"],
	"totem": ["instrument", "lantern", "staff"],
	"instrument": ["lantern", "orb", "wand"],
	"lantern": ["orb", "staff", "tome"],
	"orb": ["staff", "wand", "totem"],
	"staff": ["wand", "tome", "instrument"],
	"wand": ["tome", "totem", "lantern"],
}

const ELEMENT_BEATS := {
	"fire": ["earth", "lightning", "holy"],
	"earth": ["lightning", "water", "necrotic"],
	"lightning": ["water", "holy", "air"],
	"water": ["holy", "necrotic", "fire"],
	"holy": ["necrotic", "air", "earth"],
	"necrotic": ["air", "fire", "lightning"],
	"air": ["fire", "earth", "water"],
}

static func get_crit_chance(weapon: String) -> float:
	return WEAPONS.get(weapon, WEAPONS["default"]).get("crit_chance", 0.0)

# Called ONCE by whoever is actually casting (never by a receiving peer
# rebuilding spell_data from the RPC'd weapon/element/form strings) — the
# result is transmitted as a plain bool alongside those strings so every
# peer agrees on the same outcome rather than each rolling independently.
static func roll_crit(weapon: String) -> bool:
	return randf() * 100.0 < get_crit_chance(weapon)

const ADVANTAGE_BONUS := 0.5
const DISADVANTAGE_PENALTY := 0.25

static func get_type_modifier(beats_table: Dictionary, attacker: String, defender: String) -> float:
	if attacker == defender:
		return 0.0
	var attacker_beats: Array = beats_table.get(attacker, [])
	if attacker_beats.has(defender):
		return ADVANTAGE_BONUS
	var defender_beats: Array = beats_table.get(defender, [])
	if defender_beats.has(attacker):
		return -DISADVANTAGE_PENALTY
	return 0.0

static func get_damage_multiplier(
	attacker_weapon: String,
	attacker_element: String,
	defender_weapon: String,
	defender_element: String
) -> float:
	var multiplier := 1.0
	multiplier += get_type_modifier(WEAPON_BEATS, attacker_weapon, defender_weapon)
	multiplier += get_type_modifier(ELEMENT_BEATS, attacker_element, defender_element)
	return multiplier

func build_spell_data(weapon: String, element: String, form: String, rarity: String = "common") -> Dictionary:
	var weapon_data = WEAPONS[weapon]
	var element_data = ELEMENTS[element]
	var form_data = FORMS[form]
	var rarity_mult := ItemData.rarity_stat_mult(rarity)
	return {
		"scene": form_data["scene"],
		"weapon": weapon,
		"element": element,
		"form": form,
		"rarity": rarity,
		"damage": 10.0 * weapon_data["damage"] * element_data["damage"] * form_data["damage"] * rarity_mult,
		"speed": 1000.0 * weapon_data["speed"] * element_data["speed"] * form_data["speed"],
		"size": 1.0 * weapon_data.get("size", 1.0) * form_data.get("size", 1.0),
		"lifetime": 2.0 * weapon_data.get("lifetime", 1.0) * form_data.get("lifetime", 1.0),
		"attack_cooldown": form_data.get("attack_cooldown", 0.35),
		"spawn_offset": form_data.get("spawn_offset", 72.0),
		"mana_cost": form_data.get("mana_cost", 0.0),
		"color": element_data["color"],
		# Per-form behavior flags (see projectile.gd / hitbox.gd). Default to a
		# normal single-hit projectile that stops on hurtboxes and walls.
		"pierce": form_data.get("pierce", false),
		"stop_on_wall": form_data.get("stop_on_wall", true),
		"auto_hit": form_data.get("auto_hit", true),
	}

func build_weapon_spell_data(weapon_id: String, form_index: int) -> Dictionary:
	var weapon = EQUIPPABLE_WEAPONS.get(weapon_id, EQUIPPABLE_WEAPONS["tome"])
	var element: String = weapon["element"]
	var forms: Array = weapon["forms"]
	form_index = clamp(form_index, 0, forms.size() - 1)
	var form: String = forms[form_index]
	return build_spell_data(weapon_id, element, form)
