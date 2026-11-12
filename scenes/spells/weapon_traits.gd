class_name WeaponTraits

# Rolled weapon traits (docs/combat_redesign_plan.md §7.5). Count by rarity; at most
# one per group; form traits need the form in the weapon type's capability list.
# Spread and stream (Split / Torrent) can roll on any weapon. Shape traits keep the
# basic's theoretical DPS at the 2.857 x Attack baseline.

const COUNT_BY_RARITY := {"common": 0, "uncommon": 1, "rare": 2, "epic": 3, "legendary": 3, "mythic": 4}
const RARITY_ORDER := ["common", "uncommon", "rare", "epic", "legendary", "mythic"]

const TRAITS := {
	# shape (one per weapon)
	"split": {"name": "Split", "group": "shape", "min_rarity": "uncommon", "weight": 10, "built": true,
		"desc": "Basic fires a 3-shot fan."},
	"torrent": {"name": "Torrent", "group": "shape", "min_rarity": "uncommon", "weight": 10, "built": true,
		"desc": "Basic becomes a light, fast stream."},
	"heavy": {"name": "Heavy", "group": "shape", "min_rarity": "uncommon", "weight": 10, "built": true,
		"desc": "Basic becomes a slow, fat shot that pierces one enemy and knocks back hard."},
	"twin": {"name": "Twin", "group": "shape", "min_rarity": "uncommon", "weight": 10, "built": true,
		"desc": "Basic fires two parallel shots."},
	# basic
	"piercing": {"name": "Piercing", "group": "basic", "min_rarity": "uncommon", "weight": 8, "built": true,
		"desc": "Basic passes through one enemy; the second hit deals 50%."},
	"rebound": {"name": "Rebound", "group": "basic", "min_rarity": "uncommon", "weight": 8, "built": true,
		"excludes_subclass": "trickshot", "desc": "Basic bounces once off walls."},
	"lingering": {"name": "Lingering", "group": "basic", "min_rarity": "uncommon", "weight": 8, "built": true,
		"desc": "A basic that hits a wall leaves a spark mine for 1.5 s."},
	"seeking": {"name": "Seeking", "group": "basic", "min_rarity": "rare", "weight": 6, "built": true,
		"desc": "Basic bends toward the nearest enemy in its path."},
	# spell
	"overture": {"name": "Overture", "group": "spell", "min_rarity": "uncommon", "weight": 8, "built": true,
		"desc": "The first basic after a spell is a triple-size shot at 3x damage."},
	"aftershock": {"name": "Aftershock", "group": "spell", "min_rarity": "rare", "weight": 6, "built": true,
		"desc": "Spells pulse a second time where they end, for 25%."},
	"conduit": {"name": "Conduit", "group": "spell", "min_rarity": "rare", "weight": 6, "built": true,
		"desc": "Killing an enemy with a spell refunds 15% of its mana cost (once per cast)."},
	# element
	"catalyst": {"name": "Catalyst", "group": "element", "min_rarity": "rare", "weight": 6, "built": true,
		"desc": "Enemies that die under your element's effect spread it to neighbours."},
	"attuned": {"name": "Attuned", "group": "element", "min_rarity": "rare", "weight": 6, "built": true,
		"desc": "Your basic builds its element effect 50% faster."},
	# utility
	"rollcaster": {"name": "Rollcaster", "group": "utility", "min_rarity": "rare", "weight": 6, "built": true,
		"desc": "Rolling through an enemy bullet takes 1 s off your longest stratagem cooldown."},
	"walking_cast": {"name": "Walking Cast", "group": "utility", "min_rarity": "rare", "weight": 6, "built": true,
		"desc": "Walk at 40% speed while entering a code instead of standing still."},
	# form (need the form in the weapon type's capability list)
	"cluster": {"name": "Cluster", "group": "form", "requires_form": "ball", "min_rarity": "rare", "weight": 5, "built": true,
		"desc": "Ball detonations throw 3 bomblets."},
	"forked": {"name": "Forked", "group": "form", "requires_form": "bolt", "min_rarity": "rare", "weight": 5, "built": true,
		"desc": "Bolts split in two on their first hit."},
	"undertow": {"name": "Undertow", "group": "form", "requires_form": "wave", "min_rarity": "rare", "weight": 5, "built": true,
		"desc": "Waves roll back to you at half damage."},
	"downpour": {"name": "Downpour", "group": "form", "requires_form": "rain", "min_rarity": "rare", "weight": 5, "built": true,
		"desc": "Rain lands after 0.5 s instead of 1 s."},
	"prism_beam": {"name": "Prism Beam", "group": "form", "requires_form": "beam", "min_rarity": "rare", "weight": 5, "built": true,
		"desc": "Beams are not cut off by the first enemy."},
	"afterimage": {"name": "Afterimage", "group": "form", "requires_form": "burst", "min_rarity": "rare", "weight": 5, "built": true,
		"desc": "A second burst fires where you stood 1 s earlier."},
	"backdraft": {"name": "Backdraft", "group": "form", "requires_form": "cone", "min_rarity": "rare", "weight": 5, "built": true,
		"desc": "Cones also fire a half-size cone behind you."},
}

static func is_known(id: String) -> bool:
	return TRAITS.has(id)

static func display(id: String) -> String:
	return TRAITS.get(id, {}).get("name", id)

static func desc(id: String) -> String:
	return TRAITS.get(id, {}).get("desc", "")

static func _rank(rarity: String) -> int:
	return maxi(RARITY_ORDER.find(rarity), 0)

# capable_forms: the weapon type's capability list (SpellData.get_capable_forms).
static func roll(rarity: String, capable_forms: Array, subclass: String, rng: RandomNumberGenerator) -> Array:
	var count: int = COUNT_BY_RARITY.get(rarity, 0)
	var out: Array = []
	if count <= 0:
		return out
	var used_groups := {}
	var need_rare := _rank(rarity) >= _rank("legendary")
	for i in count:
		var pool: Array = []
		var total := 0
		for id in TRAITS:
			var t: Dictionary = TRAITS[id]
			if !t.get("built", false) or used_groups.has(t["group"]):
				continue
			if _rank(t["min_rarity"]) > _rank(rarity):
				continue
			if t.has("requires_form") and !capable_forms.has(t["requires_form"]):
				continue
			if t.get("excludes_subclass", "") == subclass and subclass != "":
				continue
			if need_rare and i == count - 1 and _rank(t["min_rarity"]) < _rank("rare"):
				continue
			pool.append(id)
			total += int(t["weight"])
		if pool.is_empty():
			break
		var pick := rng.randi() % maxi(total, 1)
		for id in pool:
			pick -= int(TRAITS[id]["weight"])
			if pick < 0:
				out.append(id)
				used_groups[TRAITS[id]["group"]] = true
				if _rank(TRAITS[id]["min_rarity"]) >= _rank("rare"):
					need_rare = false
				break
	return out
