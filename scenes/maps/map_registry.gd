extends RefCounted
class_name MapRegistry

# Every playable map. An explicit list (not a folder scan) because exported builds
# remap .tres files, so DirAccess listings differ between editor and export.
const MAP_PATHS := [
	"res://scenes/maps/defs/village.tres",
	"res://scenes/maps/defs/dungeon.tres",
]

static var _defs: Dictionary = {}

static func _ensure_loaded() -> void:
	if !_defs.is_empty():
		return
	for path in MAP_PATHS:
		var def := load(path) as MapDef
		if def == null or def.id == "":
			push_warning("MapRegistry: bad MapDef at %s" % path)
			continue
		_defs[def.id] = def

static func get_def(map_id: String) -> MapDef:
	_ensure_loaded()
	return _defs.get(map_id)

static func has_map(map_id: String) -> bool:
	_ensure_loaded()
	return _defs.has(map_id)

static func all_defs() -> Array:
	_ensure_loaded()
	return _defs.values()
