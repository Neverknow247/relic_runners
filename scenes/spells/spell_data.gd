extends Node
class_name SpellData

# The 7-weapon roster (docs/master_plan.md §3, docs/combat_redesign_plan.md §2).
# WEAPON_ORDER is the single source for "every weapon type". Weapons have NO stat
# differences: a weapon differs only by which forms it can hold, its rolled subclass
# and its rolled traits. `forms` is the CAPABILITY list (Fano plane: each form on
# exactly 3 weapons, every weapon pair shares exactly one); at most
# MAX_ATTACHED_FORMS are attached at once (grows to 6 capable when 7 more forms land).
const WEAPON_ORDER := ["tome", "wand", "staff", "orb", "lantern", "instrument", "totem"]
const MAX_ATTACHED_FORMS := 3
const EQUIPPABLE_WEAPONS = {
	"tome": {"element": "fire", "forms": ["ball", "rain", "beam"]},
	"wand": {"element": "fire", "forms": ["bolt", "ball", "cone"]},
	"staff": {"element": "fire", "forms": ["bolt", "beam", "wave"]},
	"orb": {"element": "fire", "forms": ["bolt", "rain", "burst"]},
	"lantern": {"element": "fire", "forms": ["wave", "rain", "cone"]},
	"instrument": {"element": "fire", "forms": ["cone", "beam", "burst"]},
	"totem": {"element": "fire", "forms": ["ball", "wave", "burst"]},
	# Not a spellcasting weapon — occupies a weapon slot but holds no forms and
	# never casts (see fishing_rod in item_data.gd / attack_check() in player.gd).
	"fishing_rod": {"element": "default", "forms": []},
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
	"wand": "bolt",
	"staff": "bolt",
	"orb": "burst",
	"lantern": "cone",
	"instrument": "cone",
	"totem": "ball",
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
	# A form with its own fixed reach (wave) reaches exactly that, for everyone.
	if fd.has("max_distance"):
		return fd["max_distance"] + fd.get("spawn_offset", 128.0)
	var form_speed: float = fd.get("speed", 1.0)
	if form_speed <= 0.0:
		return ENGAGEMENT_RANGE
	if is_enemy:
		# Enemy projectiles are FLAT — no weapon/element/form speed scaling (matches
		# build_spell_data), so every enemy moving shot reaches the same distance.
		return minf(ENEMY_BASE_SPEED * ENEMY_BASE_LIFETIME, ENEMY_PROJECTILE_MAX_RANGE) + fd.get("spawn_offset", 128.0)
	var ed: Dictionary = ELEMENTS.get(element, ELEMENTS["default"])
	var proj_speed: float = BASE_SPEED * ed["speed"] * form_speed
	var lifetime: float = BASE_LIFETIME * fd.get("lifetime", 1.0)
	return minf(proj_speed * lifetime, PROJECTILE_MAX_RANGE) + fd.get("spawn_offset", 128.0)

# Crit is STAT-DRIVEN now (Crit Rate / Crit Damage stats) and resolved at the
# DEFENDER's hit handler (_on_hurtbox_hurt), not at cast — so the element-advantage
# +50 crit bonus can use the defender's element. The attacker's crit stats ride on
# the Hitbox.

# Defense: Diablo-style diminishing-returns damage reduction, DR = Def/(Def+C)
# hard-capped at DR_CAP. C is the tuning knob.
const DR_CONSTANT := 100.0
const DR_CAP := 0.9

# Single source of truth for combat range: how far an enemy can see/acquire a
# target (its detection_area radius, applied in enemy.gd's _ready) AND how far a
# travelling projectile can go before it fizzles (see projectile.gd). Tying them
# means you can't snipe an enemy from beyond the range it could ever notice you,
# and your shots reach as far as you can see. Sized to the screen's half-width:
# camera zoom 3 over a 3840x2160 viewport shows 1280x720 of world, so 640 reaches
# the left/right edge of the screen (it slightly overshoots top/bottom, the
# trade-off of a circle rather than a screen-shaped rectangle).
const ENGAGEMENT_RANGE := 2560.0
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
const BASE_SPEED := 4000.0
const BASE_SIZE := 1.0
const BASE_LIFETIME := 2.0

# Enemy projectiles are UNIFORM — a single flat speed/size for every enemy, with NO
# weapon/element/form scaling (see build_spell_data / get_effective_range), so there's
# one stat to balance. Enter-the-Gungeon style: dodgeable shots at a measured cadence.
const ENEMY_BASE_SPEED := 1100.0     # flat speed for ALL enemy shots (bumped +10% from 250)
const ENEMY_BASE_SIZE := 1.0        # flat size for ALL enemy shots (BASE_SIZE is also 1.0)
const ENEMY_COOLDOWN_MULT := 1.89   # multiplies the form cooldown; >1 = slower than a player, lower = shoots more often (raised from 1.8 → fires ~5% less often)
# A MOVING projectile dies at whichever comes first: its lifetime OR its max_distance.
# Enemy bullets were clipped by the shared cap well before their lifetime, so a lifetime
# bump alone did nothing — the reach cap AND the lifetime have to rise together. Reach
# cap is now 2.475x the player's and lifetime 9.9s, i.e. bumped +10% over the previous
# pass (2.25 / 9.0), so enemy bullets travel/persist 10% longer. The reach cap is the
# real limiter for every archetype's speed, so both had to rise. Only moving forms use
# the lifetime — stationary forms (speed 0) keep BASE_LIFETIME.
const ENEMY_BASE_LIFETIME := 9.9
const ENEMY_PROJECTILE_MAX_RANGE := PROJECTILE_MAX_RANGE * 2.475

# (The per-weapon WEAPONS stat table is gone: weapons have no stat differences and
# every weapon fires the same basic attack, FORMS["default"]. Basic-attack shape
# variety comes from rolled traits — docs/combat_redesign_plan.md §7.)

# Elements are now flat-EQUAL (uniform 1.0 damage/speed) — an element's only combat
# effect is its color + the ELEMENT_BEATS matchup below. Forms and weapons carry all
# the raw damage/speed differences. "default" is the neutral fallback a 0-durability
# weapon's casts downgrade to (gray, and absent from ELEMENT_BEATS so it gets no
# matchup bonus — see player.gd's get_spell_data()/get_default_spell_data()).
const ELEMENTS = {
	"default": {"damage": 1.0, "speed": 1.0, "color": Color(0.5, 0.5, 0.5)},
	"fire": {"damage": 1.0, "speed": 1.0, "color": Color(1.0, 0.35, 0.1)},
	"lightning": {"damage": 1.0, "speed": 1.0, "color": Color(1.0, 0.9, 0.2)},
	"ice": {"damage": 1.0, "speed": 1.0, "color": Color(0.6, 0.9, 1.0)},
	"wind": {"damage": 1.0, "speed": 1.0, "color": Color(0.75, 0.95, 0.85)},
	"nature": {"damage": 1.0, "speed": 1.0, "color": Color(0.4, 0.8, 0.3)},
	"water": {"damage": 1.0, "speed": 1.0, "color": Color(0.25, 0.5, 0.95)},
	"earth": {"damage": 1.0, "speed": 1.0, "color": Color(0.6, 0.45, 0.25)},
}

# Roster order for the elemental "paradox tournament" — index drives ELEMENT_BEATS
# (each element beats +1/+2/+4 around the circle) and is the SINGLE SOURCE the enemy
# roster / starter kit / workbench element list all read from, so it never drifts.
const ELEMENT_ORDER := ["fire", "lightning", "ice", "wind", "nature", "water", "earth"]

# Spells are STRATAGEMS (Helldivers model, see docs/master_plan.md §3): rare, big,
# special attacks. Each non-default form has a `stratagem_cooldown` (seconds, per
# form, per player; skipped in the hub for practice) on top of its mana cost, and a
# damage multiplier (x the caster's Attack) far above the free basic.
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
		"spawn_offset": 128.0,
		"mana_cost": 0.0,
	},
	# ball travels, then detonates an AoE on the enemy it strikes (see
	# ball_projectile.gd). auto_hit is off so the ball deals no direct damage —
	# all of it comes from the explosion it spawns, so the struck enemy takes
	# exactly one explosion hit, not hit + explosion.
	"ball": {
		"scene": preload("res://scenes/spells/ball_projectile.tscn"),
		"damage": 6.0,
		"stratagem_cooldown": 20.0,
		"speed": 0.65,
		"size": 2.0,
		"lifetime": 1.1,
		"attack_cooldown": 0.5,
		"spawn_offset": 128.0,
		"mana_cost": 160.0,
		"auto_hit": false,
	},
	"bolt": {
		"scene": preload("res://scenes/spells/bolt_projectile.tscn"),
		"damage": 4.0,
		"stratagem_cooldown": 12.0,
		"speed": 2.1,
		"size": 0.8,
		"lifetime": 0.85,
		"attack_cooldown": 0.22,
		"spawn_offset": 128.0,
		"mana_cost": 120.0,
	},
	# rain is a stationary ground zone that ticks full damage each second to
	# anyone standing in it (see rain_projectile.gd); auto_hit off so the only
	# damage is the DoT, pierce/no-wall-stop so the zone persists its lifetime.
	"rain": {
		"scene": preload("res://scenes/spells/rain_projectile.tscn"),
		"damage": 15.0,
		"stratagem_cooldown": 45.0,
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
		"spawn_offset": 3000.0,
		"mana_cost": 110.0,
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
		"damage": 10.0,
		"stratagem_cooldown": 30.0,
		"speed": 0.0,
		"size": 0.7,
		"lifetime": 1.2,
		"attack_cooldown": 0.15,
		"spawn_offset": 0.0,
		"mana_cost": 90.0,
		"pierce": true,
		"stop_on_wall": false,
		"auto_hit": false,
		"dot": true,
		# close_range: the beam only reaches MAX_LENGTH, so an enemy closes to
		# roughly within it before casting (see enemy.gd).
		"close_range": 1200.0,
	},
	# burst is a stationary AoE centered on the caster that hits everyone in it
	# (multi-hit, not consumed by the first target).
	"burst": {
		"scene": preload("res://scenes/spells/burst_projectile.tscn"),
		"damage": 8.0,
		"stratagem_cooldown": 25.0,
		"speed": 0.0,
		"size": 10.0,
		"lifetime": 0.2,
		"attack_cooldown": 0.65,
		"spawn_offset": 0.0,
		"mana_cost": 140.0,
		"pierce": true,
		"stop_on_wall": false,
		# close_range: an AoE centered on the caster, so an enemy has to be near
		# the target for it to land. Enemies close to this distance before casting.
		"close_range": 360.0,
	},
	# cone is a fixed 45-degree wedge in front of the caster (speed 0, spawn at
	# the caster), piercing everyone inside it — the wedge hitbox lives in
	# cone_projectile.tscn. auto_hit is off so cone_projectile.gd can gate each
	# hit on line-of-sight (it won't cut through walls, same as the beam).
	"cone": {
		"scene": preload("res://scenes/spells/cone_projectile.tscn"),
		"damage": 5.0,
		"stratagem_cooldown": 15.0,
		"speed": 0.0,
		"size": 1.5,
		"lifetime": 0.125,
		"attack_cooldown": 0.35,
		"spawn_offset": 0.0,
		"mana_cost": 130.0,
		"pierce": true,
		"stop_on_wall": false,
		"auto_hit": false,
		# close_range: a short wedge in front of the caster (~150 * size reach), so
		# an enemy has to be near the target to catch them in it.
		"close_range": 720.0,
	},
	# wave rolls forward along the ground as a 640-wide wall, hits each target
	# once, stops at walls, and CARRIES enemies (wave_projectile.gd). Its motion is
	# fixed for players and enemies alike (fixed_motion: enemies don't flatten it),
	# with a short fixed reach (max_distance).
	"wave": {
		"scene": preload("res://scenes/spells/wave_projectile.tscn"),
		"damage": 5.0,
		"stratagem_cooldown": 18.0,
		"mana_cost": 130.0,
		"speed": 0.3,            # 1200 u/s: faster than every enemy's move_speed (500-900)
		"lifetime": 0.75,        # x BASE_LIFETIME 2.0 = 1.5 s
		"max_distance": 1800.0,
		"size": 1.0,             # the scene owns its rectangle; never scaled
		"attack_cooldown": 0.5,
		"spawn_offset": 160.0,
		"pierce": true,
		"stop_on_wall": false,
		"auto_hit": false,
		"carry": true,
		"fixed_motion": true,
	},
}

# Elemental "paradox tournament" matchup: each element beats the elements +1, +2,
# and +4 ahead of it on the ELEMENT_ORDER circle (a balanced non-transitive set —
# each beats 3, loses to 3). Built once from ELEMENT_ORDER in _static_init so adding
# or reordering elements needs no table edit. The old weapon-vs-weapon matchup was
# removed — weapons no longer affect the damage multiplier at all, only their flat
# stats.
const BEATS_OFFSETS := [1, 2, 4]
static var ELEMENT_BEATS: Dictionary = {}

static func _static_init() -> void:
	if OS.is_debug_build():
		var problem := validate_roster()
		if problem != "":
			push_error("SpellData roster: " + problem)
	var n := ELEMENT_ORDER.size()
	for i in n:
		var beats: Array = []
		for off in BEATS_OFFSETS:
			beats.append(ELEMENT_ORDER[(i + off) % n])
		ELEMENT_BEATS[ELEMENT_ORDER[i]] = beats

# Checks the weapon/form layout rules: every form is on exactly 3 weapons, every
# weapon has the same number of capable forms, and every pair of weapons shares the
# same number of forms (1 with 7 forms; 2 once there are 14). Returns "" when OK.
static func validate_roster() -> String:
	var counts := {}
	var per_weapon := -1
	for w in WEAPON_ORDER:
		var forms: Array = EQUIPPABLE_WEAPONS[w]["forms"]
		if per_weapon == -1:
			per_weapon = forms.size()
		elif forms.size() != per_weapon:
			return "%s has %d forms, expected %d" % [w, forms.size(), per_weapon]
		for f in forms:
			counts[f] = counts.get(f, 0) + 1
	for f in counts:
		if counts[f] != 3:
			return "form %s is on %d weapons, expected 3" % [f, counts[f]]
	var shared := -1
	for i in WEAPON_ORDER.size():
		for j in range(i + 1, WEAPON_ORDER.size()):
			var n := 0
			for f in EQUIPPABLE_WEAPONS[WEAPON_ORDER[i]]["forms"]:
				if EQUIPPABLE_WEAPONS[WEAPON_ORDER[j]]["forms"].has(f):
					n += 1
			if shared == -1:
				shared = n
			elif n != shared:
				return "%s/%s share %d forms, others share %d" % [WEAPON_ORDER[i], WEAPON_ORDER[j], n, shared]
	return ""

# Diablo-style diminishing-returns damage reduction from a Defense stat.
static func damage_reduction(defense: float) -> float:
	if defense <= 0.0:
		return 0.0
	return minf(DR_CAP, defense / (defense + DR_CONSTANT))

# True if the attacker's element beats the defender's — grants the +50 crit-rate /
# +50 crit-damage bonus for that hit (advantage only; neutral/disadvantage: no change).
static func has_advantage(attacker_element: String, defender_element: String) -> bool:
	return get_type_modifier(ELEMENT_BEATS, attacker_element, defender_element) > 0.0

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

# Element matchup only now — the weapon params are kept so callers don't change,
# but weapon type no longer influences the multiplier (the weapon matchup is gone).
static func get_damage_multiplier(
	_attacker_weapon: String,
	attacker_element: String,
	_defender_weapon: String,
	defender_element: String
) -> float:
	return 1.0 + get_type_modifier(ELEMENT_BEATS, attacker_element, defender_element)

func build_spell_data(weapon: String, element: String, form: String, rarity: String = "common", is_enemy: bool = false) -> Dictionary:
	# Unknown ids fall back instead of crashing a cast (weapon is carried only as an
	# identity tag now — it scales nothing).
	var element_data: Dictionary = ELEMENTS.get(element, ELEMENTS["default"])
	var form_data: Dictionary = FORMS.get(form, FORMS["default"])
	var cooldown_mult := ENEMY_COOLDOWN_MULT if is_enemy else 1.0
	# Enemy projectiles are FLAT: one speed, one size, one lifetime for every enemy —
	# no weapon/element/form scaling — so there's a single stat to balance. Stationary
	# forms (speed 0: rain/beam/burst/cone) stay stationary. Players keep full scaling.
	var form_moving: bool = form_data["speed"] > 0.0
	var proj_speed: float
	var proj_size: float
	var proj_lifetime: float
	if is_enemy and not form_data.get("fixed_motion", false):
		proj_speed = ENEMY_BASE_SPEED if form_moving else 0.0
		# Moving enemy shots stay flat-sized; a stationary zone (a lobbed rain) keeps
		# its form's area and a short life, or it would be a tiny 2 s dot.
		proj_size = ENEMY_BASE_SIZE if form_moving else BASE_SIZE * form_data.get("size", 1.0)
		proj_lifetime = ENEMY_BASE_LIFETIME if form_moving else minf(BASE_LIFETIME * form_data.get("lifetime", 1.0), 3.0)
	else:
		proj_speed = BASE_SPEED * element_data["speed"] * form_data["speed"]
		proj_size = BASE_SIZE * form_data.get("size", 1.0)
		proj_lifetime = BASE_LIFETIME * form_data.get("lifetime", 1.0)
	# Same for every weapon. pellets/spread stay in the dict so shape traits
	# (Split, Twin...) can rewrite them later (combat_redesign_plan §7.5).
	var damage_mult: float = form_data.get("damage", 1.0)
	var attack_cooldown: float = form_data.get("attack_cooldown", 0.35) * cooldown_mult
	var pellets := 1
	var spread_deg := 0.0
	return {
		"scene": form_data["scene"],
		"weapon": weapon,
		"element": element,
		"form": form,
		"rarity": rarity,
		# Damage is the caster's ATTACK (weapon + gear), set at spawn (spawn_spell_
		# local / spawn_projectile). Elements/weapons no longer scale it, but the FORM
		# does: a player's cast damage = Attack * damage_mult, so the mana-costing
		# forms actually out-damage the free basic (default = 1.0). Enemies ignore
		# this and stay flat (see enemy.gd). "damage" itself is a placeholder that's
		# always overridden at spawn.
		"damage": 0.0,
		"damage_mult": damage_mult,
		"speed": proj_speed,
		"size": proj_size,
		"lifetime": proj_lifetime,
		"attack_cooldown": attack_cooldown,
		# Basic-attack fan for the caster's weapon (1 = single shot; see cast_spell).
		"pellets": pellets,
		"spread_deg": spread_deg,
		"spawn_offset": form_data.get("spawn_offset", 288.0),
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
		# carry = drags enemies along (wave). fixed_motion = enemy casts keep the
		# form's own speed instead of the flat enemy bullet speed.
		"carry": form_data.get("carry", false),
		"fixed_motion": form_data.get("fixed_motion", false),
		# Attacker's crit stats — set from the caster's Crit Rate / Crit Damage at
		# spawn and stamped onto the Hitbox (setup_spell). The DEFENDER resolves crit
		# from these (+50 each on element advantage) at hit time; DoT ticks read the
		# same Hitbox fields per tick. Defaults 0 here (overridden at spawn).
		"attacker_crit_rate": 0.0,
		"attacker_crit_damage": 0.0,
		# How far a moving projectile may travel before it fizzles (PROJECTILE_MAX_
		# RANGE — a bit past the screen edge). Passed through the data dict rather
		# than read from SpellData in projectile.gd, because spell_data.gd preloads
		# the projectile scenes and a back-reference would form a compile cycle.
		"max_distance": form_data.get("max_distance", ENEMY_PROJECTILE_MAX_RANGE if is_enemy else PROJECTILE_MAX_RANGE),
		# Who fired it: drives Hitbox.from_player (no player-on-player friendly fire).
		"from_enemy": is_enemy,
	}

func build_weapon_spell_data(weapon_id: String, form_index: int) -> Dictionary:
	var weapon = EQUIPPABLE_WEAPONS.get(weapon_id, EQUIPPABLE_WEAPONS["tome"])
	var element: String = weapon["element"]
	var forms: Array = weapon["forms"]
	form_index = clamp(form_index, 0, forms.size() - 1)
	var form: String = forms[form_index]
	return build_spell_data(weapon_id, element, form)
