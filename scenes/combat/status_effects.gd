class_name StatusEffects

# Status-effect numbers (docs/combat_redesign_plan.md §4.4). Pure data, no
# references to SpellData or any projectile class (keeps it out of the preload
# cycle). StatusHolder reads these; Combat decides who gets what.

# Which status each element's hits apply. Lightning (chain) and wind (gale) are
# on-hit side effects, not statuses (see Combat.apply_on_hit).
const ELEMENT_STATUS := {
	"fire": "burn",
	"ice": "chill",
	"water": "soak",
	"nature": "seed",
	"earth": "sunder",
}

# Bits of the synced status_mask (visuals on every peer, late joiners included).
const BIT := {
	"burn": 1, "chill": 2, "frozen": 4, "soak": 8, "seed": 16, "staggered": 32,
	"overgrown": 64, "armor_broken": 128,
	# Player buffs (songs etc.)
	"haste": 256, "mend": 512, "pierce_basic": 1024, "quickstep": 2048,
	# Enemy debuffs from subclasses / songs
	"dirge": 4096, "dazzled": 8192, "effigy": 16384,
}

const DEFS := {
	# --- on enemies (player-cast) -------------------------------------------
	"burn": {
		"tick_interval": 0.5, "tick_frac": 0.06,     # of source Attack, per stack per tick
		"duration": 4.0,
		"basic_per_unit": 0.5, "basic_cap": 2.0,
		"spell_per_unit": 1.0, "spell_cap": 6.0,
		"jump_radius": 320.0,
	},
	"chill": {
		"max_slow": 0.4, "decay_delay": 1.5, "decay_per_sec": 12.0,
		"basic_per_unit": 7.0, "basic_cap": 60.0,
		"spell_per_unit": 14.0,
		"freeze_sec": 2.0, "freeze_immune_sec": 4.0,
		"gold_max_slow": 0.2,
	},
	"soak": {
		"basic_sec_per_unit": 1.5, "basic_cap": 3.0, "spell_sec": 6.0,
		"bullet_speed_mult": 0.75, "damage_mult": 0.8,
	},
	"seed": {"basic_sec": 4.0, "spell_sec": 8.0},
	"sunder": {
		"threshold": {"bronze": 2.0, "silver": 4.0, "gold": 8.0},
		"stagger_sec": 1.0, "stagger_immune_sec": 6.0, "shield_mult": 3.0,
	},
	"chain": {
		"basic_arcs": 1, "basic_frac": 0.2, "basic_radius": 320.0,
		"spell_arcs": 3, "spell_frac": 0.5, "spell_radius": 520.0,
	},
	"gale": {"basic_knockback_mult": 2.5},
	# Silver halves-ish hard CC; gold/guardian never freezes, stagger only via wind-up.
	"tier_cc_mult": {"bronze": 1.0, "silver": 0.6, "gold": 0.0},

	# --- on players (softened, enemy-cast) ----------------------------------
	"p_burn": {"tick_interval": 0.5, "tick_frac_max_hp": 0.01, "duration": 2.0},
	"p_chill": {"slow": 0.25, "duration": 1.5},
	"p_soak": {"duration": 3.0, "basic_mult": 0.8},
	"p_seed": {"lifesteal": 0.5, "lifesteal_cap_frac": 0.1},
	"p_sunder": {"push": 350.0},
	"p_chain": {"frac": 0.4, "radius": 400.0, "delay": 0.3},
	"p_gale": {"push": 250.0},
	"p_max_slow": 0.25,

	# --- nature bloom ----------------------------------------------------------
	"bloom": {"heal": 10.0, "radius": 300.0, "overgrown_mult": 2.0, "cap_per_min": 150.0},
}

const ELEMENT_COLORS := {
	"burn": Color(1.0, 0.45, 0.1), "chill": Color(0.6, 0.9, 1.0), "frozen": Color(0.75, 0.95, 1.0),
	"soak": Color(0.3, 0.55, 1.0), "seed": Color(0.45, 0.85, 0.3), "staggered": Color(0.85, 0.7, 0.4),
}

static func bit(id: String) -> int:
	return BIT.get(id, 0)
