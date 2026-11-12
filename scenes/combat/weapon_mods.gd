class_name WeaponMods

# Registry of mod scripts (subclasses + traits). Lazy singleton cache: one
# stateless instance per id. Must not reference SpellData (CastFx/projectile path).

const SCRIPTS := {
	# subclasses
	"glyphscribe": preload("res://scenes/combat/mods/glyphscribe.gd"),
	"annotator": preload("res://scenes/combat/mods/annotator.gd"),
	"pagewarden": preload("res://scenes/combat/mods/pagewarden.gd"),
	"trickshot": preload("res://scenes/combat/mods/trickshot.gd"),
	"duelist": preload("res://scenes/combat/mods/duelist.gd"),
	"overflow": preload("res://scenes/combat/mods/overflow.gd"),
	"vaulter": preload("res://scenes/combat/mods/vaulter.gd"),
	"janus": preload("res://scenes/combat/mods/janus.gd"),
	"leywalker": preload("res://scenes/combat/mods/leywalker.gd"),
	"constellation": preload("res://scenes/combat/mods/constellation.gd"),
	"eclipse": preload("res://scenes/combat/mods/eclipse.gd"),
	"refractor": preload("res://scenes/combat/mods/refractor.gd"),
	"lamplighter": preload("res://scenes/combat/mods/lamplighter.gd"),
	"darklantern": preload("res://scenes/combat/mods/darklantern.gd"),
	"flarekeeper": preload("res://scenes/combat/mods/flarekeeper.gd"),
	"songweaver": preload("res://scenes/combat/mods/songweaver.gd"),
	"echo": preload("res://scenes/combat/mods/echo.gd"),
	"dissonant": preload("res://scenes/combat/mods/dissonant.gd"),
	"idolkeeper": preload("res://scenes/combat/mods/idolkeeper.gd"),
	"three_faced": preload("res://scenes/combat/mods/three_faced.gd"),
	"hexbinder": preload("res://scenes/combat/mods/hexbinder.gd"),
	# traits (one script per group; the instance's `id` picks the behaviour)
	"split": preload("res://scenes/combat/mods/shape_traits.gd"),
	"torrent": preload("res://scenes/combat/mods/shape_traits.gd"),
	"heavy": preload("res://scenes/combat/mods/shape_traits.gd"),
	"twin": preload("res://scenes/combat/mods/shape_traits.gd"),
	"piercing": preload("res://scenes/combat/mods/basic_traits.gd"),
	"rebound": preload("res://scenes/combat/mods/basic_traits.gd"),
	"lingering": preload("res://scenes/combat/mods/basic_traits.gd"),
	"seeking": preload("res://scenes/combat/mods/basic_traits.gd"),
	"overture": preload("res://scenes/combat/mods/spell_traits.gd"),
	"aftershock": preload("res://scenes/combat/mods/spell_traits.gd"),
	"conduit": preload("res://scenes/combat/mods/spell_traits.gd"),
	"rollcaster": preload("res://scenes/combat/mods/spell_traits.gd"),
	"cluster": preload("res://scenes/combat/mods/form_traits.gd"),
	"forked": preload("res://scenes/combat/mods/form_traits.gd"),
	"undertow": preload("res://scenes/combat/mods/form_traits.gd"),
	"downpour": preload("res://scenes/combat/mods/form_traits.gd"),
	"prism_beam": preload("res://scenes/combat/mods/form_traits.gd"),
	"afterimage": preload("res://scenes/combat/mods/form_traits.gd"),
	"backdraft": preload("res://scenes/combat/mods/form_traits.gd"),
	# catalyst / attuned / walking_cast have no hooks: enemy.gd, Combat and
	# player.gd read the trait id straight off the cast / weapon.
}

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
