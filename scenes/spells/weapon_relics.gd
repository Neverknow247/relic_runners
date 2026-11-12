class_name WeaponRelics

# Named unique weapons (relics) — hook only, nothing rolls these yet
# (docs/combat_redesign_plan.md §7.1). Shape:
#   "id": {"type": "tome", "name": "...", "subclass": "glyphscribe",
#          "traits": ["split"], "mods": ["some_relic_mod"]}
# Weapon.mod_ids() appends a relic's extra mods; ItemData.display_name prefers its name.
const RELICS := {}

static func get_relic(id: String) -> Dictionary:
	return RELICS.get(id, {})
