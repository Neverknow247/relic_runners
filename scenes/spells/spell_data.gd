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

# The distance within which a form is actually effective (0 = long-range, no
# closing needed). Enemies use this to close in before casting short-range forms
# like beam/burst — see enemy.gd's _plan_next_cast().
static func get_close_range(form: String) -> float:
	return FORMS.get(form, {}).get("close_range", 0.0)

# How far a given cast can actually reach a target, so an enemy knows how close
# it must be to land it:
#   - forms with a declared close_range (beam/burst/cone) use that fixed reach,
#   - targeted forms (rain) can be placed out to spawn_offset,
#   - travelling forms use their real projectile reach = speed*lifetime (capped
#     at PROJECTILE_MAX_RANGE) + spawn_offset, which depends on the caster's
#     weapon/element, so a slow combo (e.g. a fire tome ball) reaches much less
#     far than a fast one.
static func get_effective_range(weapon: String, element: String, form: String, is_enemy: bool = false) -> float:
	var fd: Dictionary = FORMS.get(form, {})
	var cr: float = fd.get("close_range", 0.0)
	if cr > 0.0:
		return cr
	if fd.get("targeted", false):
		return fd.get("spawn_offset", ENGAGEMENT_RANGE)
	var form_speed: float = fd.get("speed", 1.0)
	if form_speed <= 0.0:
		return ENGAGEMENT_RANGE
	var wd: Dictionary = WEAPONS.get(weapon, WEAPONS["default"])
	var ed: Dictionary = ELEMENTS.get(element, ELEMENTS["default"])
	var base_speed: float = ENEMY_BASE_SPEED if is_enemy else BASE_SPEED
	var proj_speed: float = base_speed * wd["speed"] * ed["speed"] * form_speed
	var lifetime: float = BASE_LIFETIME * wd.get("lifetime", 1.0) * fd.get("lifetime", 1.0)
	return minf(proj_speed * lifetime, PROJECTILE_MAX_RANGE) + fd.get("spawn_offset", 32.0)

# crit_chance is a percent (5.0 = 5%) — rolled once by the casting peer at
# cast time (see player.gd's cast_spell()/enemy.gd's fire_spell()) and
# threaded through the spawn RPC as a plain bool so every peer applies the
# exact same result instead of each independently re-rolling and
# disagreeing on whether a given hit crit. "default" (the 0-durability/
# broken-weapon downgrade — see ELEMENTS' comment below) never crits, same
# neutral-in-every-way treatment as its other stats.
const CRIT_MULTIPLIER := 1.25

# Single source of truth for combat range: how far an enemy can see/acquire a
# target (its detection_area radius, applied in enemy.gd's _ready) AND how far a
# travelling projectile can go before it fizzles (see projectile.gd). Tying them
# means you can't snipe an enemy from beyond the range it could ever notice you,
# and your shots reach as far as you can see. Sized to the screen's half-width:
# camera zoom 3 over a 3840x2160 viewport shows 1280x720 of world, so 640 reaches
# the left/right edge of the screen (it slightly overshoots top/bottom, the
# trade-off of a circle rather than a screen-shaped rectangle).
const ENGAGEMENT_RANGE := 640.0
# How far a moving projectile may travel before it fizzles. A bit farther than
# ENGAGEMENT_RANGE (enemy vision) so shots reach comfortably past the screen edge
# rather than dying right at it — kept as a derived multiple so it stays "30%
# beyond vision" if ENGAGEMENT_RANGE is retuned.
const PROJECTILE_MAX_RANGE := ENGAGEMENT_RANGE * 1.3

# Base values a common, all-1.0 weapon+element+form produces in build_spell_data,
# before the per-type multipliers scale them. These are the single global knobs
# for overall spell damage/speed/size/lifetime — named so the formula carries no
# magic numbers.
const BASE_DAMAGE := 7.5
const BASE_SPEED := 600.0
const BASE_SIZE := 1.0
const BASE_LIFETIME := 2.0

# Enemies cast with a slower projectile and a shorter cooldown than players — a
# steadier stream of easier-to-dodge shots rather than player-speed bursts.
# Applied in build_spell_data when is_enemy is true (enemy.gd passes it).
const ENEMY_BASE_SPEED := 250.0    # in place of BASE_SPEED for enemy casts
const ENEMY_COOLDOWN_MULT := 0.5   # half the cooldown = they attack twice as fast

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
		"speed": 2.1,
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
		"size": 8.0,
		"lifetime": 5.0,
		"attack_cooldown": 0.4,
		# targeted = placed at the mouse (player) / target's spot (enemy), with
		# spawn_offset acting as the MAX cast range. Set past the screen's half-
		# diagonal (~734) so the mouse is always in range and rain lands right on
		# the cursor rather than clamping to a fixed distance. dot = its damage is
		# spread over its ticks (see rain_projectile.gd), so the full computed
		# damage only lands if you stand in it the whole lifetime.
		"spawn_offset": 750.0,
		"mana_cost": 11.0,
		"pierce": true,
		"stop_on_wall": false,
		"auto_hit": false,
		"targeted": true,
		"dot": true,
	},
	# beam is a channeled line that FOLLOWS the caster's position and aim while
	# it lasts (see beam_projectile.gd) and deals damage-over-time (auto_hit off,
	# ticked like rain) so sweeping it across enemies keeps hitting them.
	"beam": {
		"scene": preload("res://scenes/spells/beam_projectile.tscn"),
		"damage": 2.4,
		"speed": 0.0,
		"size": 0.7,
		"lifetime": 1.2,
		"attack_cooldown": 0.15,
		"spawn_offset": 0.0,
		"mana_cost": 9.0,
		"pierce": true,
		"stop_on_wall": false,
		"auto_hit": false,
		"dot": true,
		# close_range: the beam only reaches MAX_LENGTH, so an enemy closes to
		# roughly within it before casting (see enemy.gd).
		"close_range": 300.0,
	},
	# burst is a stationary AoE centered on the caster that hits everyone in it
	# (multi-hit, not consumed by the first target).
	"burst": {
		"scene": preload("res://scenes/spells/burst_projectile.tscn"),
		"damage": 4.0,
		"speed": 0.0,
		"size": 10.0,
		"lifetime": 0.2,
		"attack_cooldown": 0.65,
		"spawn_offset": 0.0,
		"mana_cost": 14.0,
		"pierce": true,
		"stop_on_wall": false,
		# close_range: an AoE centered on the caster, so an enemy has to be near
		# the target for it to land. Enemies close to this distance before casting.
		"close_range": 90.0,
	},
	# cone is a fixed 45-degree wedge in front of the caster (speed 0, spawn at
	# the caster), piercing everyone inside it — the wedge hitbox lives in
	# cone_projectile.tscn. auto_hit is off so cone_projectile.gd can gate each
	# hit on line-of-sight (it won't cut through walls, same as the beam).
	"cone": {
		"scene": preload("res://scenes/spells/cone_projectile.tscn"),
		"damage": 2.7,
		"speed": 0.0,
		"size": 1.5,
		"lifetime": 0.125,
		"attack_cooldown": 0.35,
		"spawn_offset": 0.0,
		"mana_cost": 13.0,
		"pierce": true,
		"stop_on_wall": false,
		"auto_hit": false,
		# close_range: a short wedge in front of the caster (~150 * size reach), so
		# an enemy has to be near the target to catch them in it.
		"close_range": 180.0,
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

const ADVANTAGE_BONUS := 0.25
const DISADVANTAGE_PENALTY := 0.125

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

func build_spell_data(weapon: String, element: String, form: String, rarity: String = "common", is_enemy: bool = false) -> Dictionary:
	var weapon_data = WEAPONS[weapon]
	var element_data = ELEMENTS[element]
	var form_data = FORMS[form]
	var rarity_mult := ItemData.rarity_stat_mult(rarity)
	# Enemy casts swap in the slower base speed and the shortened cooldown.
	var base_speed := ENEMY_BASE_SPEED if is_enemy else BASE_SPEED
	var cooldown_mult := ENEMY_COOLDOWN_MULT if is_enemy else 1.0
	return {
		"scene": form_data["scene"],
		"weapon": weapon,
		"element": element,
		"form": form,
		"rarity": rarity,
		"damage": BASE_DAMAGE * weapon_data["damage"] * element_data["damage"] * form_data["damage"] * rarity_mult,
		"speed": base_speed * weapon_data["speed"] * element_data["speed"] * form_data["speed"],
		"size": BASE_SIZE * weapon_data.get("size", 1.0) * form_data.get("size", 1.0),
		"lifetime": BASE_LIFETIME * weapon_data.get("lifetime", 1.0) * form_data.get("lifetime", 1.0),
		"attack_cooldown": form_data.get("attack_cooldown", 0.35) * cooldown_mult,
		"spawn_offset": form_data.get("spawn_offset", 72.0),
		"mana_cost": form_data.get("mana_cost", 0.0),
		"color": element_data["color"],
		# Per-form behavior flags (see projectile.gd / hitbox.gd). Default to a
		# normal single-hit projectile that stops on hurtboxes and walls.
		"pierce": form_data.get("pierce", false),
		"stop_on_wall": form_data.get("stop_on_wall", true),
		"auto_hit": form_data.get("auto_hit", true),
		# targeted = placed at a chosen point (mouse / target), not a fixed offset
		# ahead. dot = damage is spread across ticks over the lifetime, and crit is
		# rolled per tick rather than baked in once at cast.
		"targeted": form_data.get("targeted", false),
		"dot": form_data.get("dot", false),
		# Crit chance/multiplier passed through so the dot forms can roll crit
		# per-tick in their own scripts without referencing SpellData (which would
		# form a preload cycle, since SpellData preloads the projectile scenes).
		"crit_chance": get_crit_chance(weapon),
		"crit_multiplier": CRIT_MULTIPLIER,
		# How far a moving projectile may travel before it fizzles (PROJECTILE_MAX_
		# RANGE — a bit past the screen edge). Passed through the data dict rather
		# than read from SpellData in projectile.gd, because spell_data.gd preloads
		# the projectile scenes and a back-reference would form a compile cycle.
		"max_distance": form_data.get("max_distance", PROJECTILE_MAX_RANGE),
	}

func build_weapon_spell_data(weapon_id: String, form_index: int) -> Dictionary:
	var weapon = EQUIPPABLE_WEAPONS.get(weapon_id, EQUIPPABLE_WEAPONS["tome"])
	var element: String = weapon["element"]
	var forms: Array = weapon["forms"]
	form_index = clamp(form_index, 0, forms.size() - 1)
	var form: String = forms[form_index]
	return build_spell_data(weapon_id, element, form)
