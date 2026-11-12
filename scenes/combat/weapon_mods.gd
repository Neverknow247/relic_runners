class_name WeaponMods

# Registry of mod scripts (subclasses + traits). Lazy singleton cache: one
# stateless instance per id. Must not reference SpellData (CastFx/projectile path).

const SCRIPTS := {}

static var _cache := {}

static func get_mod(id: String) -> WeaponMod:
	if _cache.has(id):
		return _cache[id]
	var scr = SCRIPTS.get(id)
	var m: WeaponMod = null
	if scr != null:
		m = scr.new()
		m.id = id
	_cache[id] = m
	return m

static func for_ids(ids: Array) -> Array:
	var out := []
	for id in ids:
		var m := get_mod(String(id))
		if m != null:
			out.append(m)
	return out

# Mods of the casting weapon, from a cast dict ({"sub": id, "tr": [ids]}).
static func for_cast(cast: Dictionary) -> Array:
	if cast.is_empty():
		return []
	var ids := []
	var sub: String = cast.get("sub", "")
	if sub != "":
		ids.append(sub)
	for t in cast.get("tr", []):
		ids.append(t)
	return for_ids(ids)

static func for_weapon(weapon) -> Array:
	if weapon == null or !weapon.has_method("mod_ids"):
		return []
	return for_ids(weapon.mod_ids())
