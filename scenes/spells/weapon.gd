class_name Weapon
extends RefCounted

var instance_id: String
var type: String
var element: String
var rarity: String = "common"
var forms: Array
# Every weapon has its own mana pool (not the player) — every spell costs
# mana to cast (see SpellData.FORMS' mana_cost, deducted in player.gd's
# cast_spell()). Flat 1000 base for every weapon type for now; a future pass can
# vary max_mana per type here without touching anything that reads it.
var mana: float
var max_mana: float
# Extra max mana granted by the WIELDER's gear (the "mana" gear stat — ItemData.
# GEAR_STAT_POOL). Mana lives on the weapon, but gear lives on the player, so the
# player pushes this in on every gear/equip change (player._refresh_gear_effects)
# and clamps the pool to the new cap. NOT persisted — it's re-derived from live
# gear each time. effective_max_mana() = max_mana + this.
var bonus_max_mana: float = 0.0
var durability: float
var max_durability: float
# The weapon's Attack stat — the base damage of every spell cast with it (plus the
# player's gear Attack bonuses). Rolled once at creation; persisted so it doesn't
# re-roll on load. See the combat stats rework.
var attack: float
# Crit stats (uncommon+ weapons only). Uncommon rolls ONE of these; rare rolls both.
# Fed into the player's get_crit_rate()/get_crit_damage() and resolved at the
# defender's hit handler. See ItemData.WEAPON_CRIT_BY_RARITY.
var crit_rate: float = 0.0
var crit_damage: float = 0.0

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
	max_mana = 1000.0 * mult
	mana = max_mana
	max_durability = 100.0 * mult
	durability = max_durability
	# Attack is a flat, rarity-based roll (base 100): common = 100, uncommon 105-110,
	# rare 110-120. Crit stats: uncommon gets ONE random crit stat (+5-10%), rare gets
	# BOTH (+10-20%). See ItemData.WEAPON_ATTACK_BY_RARITY / WEAPON_CRIT_BY_RARITY.
	var atk_band: Array = ItemData.WEAPON_ATTACK_BY_RARITY.get(rarity, ItemData.WEAPON_ATTACK_BY_RARITY["rare"])
	attack = randi_range(int(atk_band[0]), int(atk_band[1]))
	if rarity != "common":
		var crit_band: Array = ItemData.WEAPON_CRIT_BY_RARITY.get(rarity, ItemData.WEAPON_CRIT_BY_RARITY["rare"])
		if rarity == "uncommon":
			# Exactly one random crit stat.
			if randi() % 2 == 0:
				crit_rate = randi_range(int(crit_band[0]), int(crit_band[1]))
			else:
				crit_damage = randi_range(int(crit_band[0]), int(crit_band[1]))
		else:
			# rare (and higher, for now) roll both.
			crit_rate = randi_range(int(crit_band[0]), int(crit_band[1]))
			crit_damage = randi_range(int(crit_band[0]), int(crit_band[1]))

# Total mana capacity: the weapon's own pool plus the wielder's gear "mana" bonus.
func effective_max_mana() -> float:
	return max_mana + bonus_max_mana

func use_mana(amount: float) -> void:
	mana = clamp(mana - amount, 0.0, effective_max_mana())

func restore_mana(amount: float) -> void:
	mana = clamp(mana + amount, 0.0, effective_max_mana())

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
		"attack": attack,
		"crit_rate": crit_rate,
		"crit_damage": crit_damage,
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
	weapon.attack = data.get("attack", weapon.attack)
	weapon.crit_rate = data.get("crit_rate", weapon.crit_rate)
	weapon.crit_damage = data.get("crit_damage", weapon.crit_damage)
	return weapon
