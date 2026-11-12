class_name WeaponSubclasses

# Weapon subclasses (docs/combat_redesign_plan.md §7.3): the weapon type is your
# class, the rolled subclass is your D&D-style subclass. 3 per weapon type; only
# `built` ones roll. Each id has a mod script in scenes/combat/mods/ (WeaponMods).

const SUBCLASSES := {
	# Tome (ball, rain, beam)
	"glyphscribe": {"weapon": "tome", "name": "Glyphscribe", "built": true,
		"desc": "Spells leave a glyph where they end. Basic hits on enemies standing on a glyph apply your element at spell strength; every 6th basic hit stamps a small glyph."},
	"annotator": {"weapon": "tome", "name": "Annotator", "built": true,
		"desc": "Basic hits write marks on enemies (max 5). A spell that hits a marked enemy pops every mark as a small blast."},
	"pagewarden": {"weapon": "tome", "name": "Pagewarden", "built": true,
		"desc": "Casting a spell tears out 3 pages that orbit you and each block one enemy bullet. While pages remain, every 3rd basic also flings a homing page."},
	# Wand (bolt, ball, cone)
	"trickshot": {"weapon": "wand", "name": "Trickshot", "built": true,
		"desc": "Basic shots and spells ricochet once off walls. A ricocheted hit applies your element at double strength."},
	"duelist": {"weapon": "wand", "name": "Duelist", "built": true,
		"desc": "Rolling through an enemy bullet loads a Riposte: your next basic is a fast piercing counter-shot. A spell cast with Riposte loaded staggers what it hits."},
	"overflow": {"weapon": "wand", "name": "Overflow", "built": true,
		"desc": "For 3 s after a spell, your basic takes that spell's shape in miniature."},
	# Staff (bolt, beam, wave)
	"vaulter": {"weapon": "staff", "name": "Vaulter", "built": true,
		"desc": "Landing a roll sends a ground ripple forward. The first basic within 0.6 s of a roll is a wide Sweep. Every spell ends in a ripple that pushes enemies outward."},
	"janus": {"weapon": "staff", "name": "Janus", "built": true,
		"desc": "Every 3rd basic also fires backward, and every spell casts a half-strength mirrored copy behind you."},
	"leywalker": {"weapon": "staff", "name": "Leywalker", "built": true,
		"desc": "Spells draw a ley line along their path for 5 s. Basic shots that cross a line fork along it in both directions."},
	# Orb (bolt, rain, burst)
	"constellation": {"weapon": "orb", "name": "Constellation", "built": true,
		"desc": "Each basic hit lights a mote that orbits you (max 5). Casting a spell launches every mote as a homing dart. Getting hit knocks one loose."},
	"eclipse": {"weapon": "orb", "name": "Eclipse", "built": true,
		"desc": "Each spell flips the orb between Sun and Moon. Sun: basics splash, spells end in a flare. Moon: basics pierce, spells pass through the first wall."},
	"refractor": {"weapon": "orb", "name": "Refractor", "built": true,
		"desc": "Basic shots refract on hit into 2 weak shards. Spells refract when they end, throwing 3 shards outward."},
	# Lantern (wave, rain, cone)
	"lamplighter": {"weapon": "lantern", "name": "Lamplighter", "built": true,
		"desc": "Spells leave a light zone where they end. Enemies in light are Dazzled; basics fired from light pierce. Basic impacts leave small embers of light."},
	"darklantern": {"weapon": "lantern", "name": "Darklantern", "built": true,
		"desc": "Spells leave shadow zones in which players cannot be seen. Your basic makes no gunfire noise."},
	"flarekeeper": {"weapon": "lantern", "name": "Flarekeeper", "built": true,
		"desc": "Spells plant a flare that enemies target for 2.5 s. Every 8th basic sticks a mini-flare to what it hits."},
	# Instrument (cone, beam, burst)
	"songweaver": {"weapon": "instrument", "name": "Songweaver", "built": true,
		"desc": "Each basic plays a note from your movement direction (still = Rest). Three notes make a bar; a bar that matches a song buffs you and nearby allies. A spell plays the song's Finale."},
	"echo": {"weapon": "instrument", "name": "Echo", "built": true,
		"desc": "Every spell echoes: 1.2 s later a ghost repeats it at 40%. Every 4th basic echoes a second ghost shot."},
	"dissonant": {"weapon": "instrument", "name": "Dissonant", "built": true,
		"desc": "Basics mark enemies with Dissonance. A spell that hits a marked enemy makes it shriek, damaging enemies around it."},
	# Totem (ball, wave, burst)
	"idolkeeper": {"weapon": "totem", "name": "Idolkeeper", "built": true,
		"desc": "Casting a spell plants a spirit idol (8 s). While it stands, your basics are repeated from the idol at 25%. Casting again moves it and it pulses your element."},
	"three_faced": {"weapon": "totem", "name": "Three-Faced", "built": true,
		"desc": "The totem rotates faces on each spell. Wrath: basics pop in small blasts. Guard: basic hits grant barrier. Trick: every 5th basic swaps you with a decoy."},
	"hexbinder": {"weapon": "totem", "name": "Hexbinder", "built": true,
		"desc": "The first enemy your basic hits becomes the Effigy for 6 s: 30% of damage you deal to others is also dealt to it, and spells that hit it splash your element."},
}

static var BY_WEAPON: Dictionary = {}

static func _static_init() -> void:
	for id in SUBCLASSES:
		var d: Dictionary = SUBCLASSES[id]
		if !d.get("built", false):
			continue
		if !BY_WEAPON.has(d["weapon"]):
			BY_WEAPON[d["weapon"]] = []
		BY_WEAPON[d["weapon"]].append(id)

static func is_known(id: String) -> bool:
	return SUBCLASSES.has(id)

static func display(id: String) -> String:
	return SUBCLASSES.get(id, {}).get("name", "")

static func desc(id: String) -> String:
	return SUBCLASSES.get(id, {}).get("desc", "")

static func roll(weapon_type: String, rng: RandomNumberGenerator) -> String:
	var pool: Array = BY_WEAPON.get(weapon_type, [])
	if pool.is_empty():
		return ""
	return pool[rng.randi() % pool.size()]
