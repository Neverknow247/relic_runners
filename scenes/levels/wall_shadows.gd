extends Node2D

# Fake "drop shadow" for wall tiles.
#
# A DirectionalLight2D's 2D shadows are PARALLEL rays with no length limit, so walls
# throw shadows all the way across the floor — huge, not what we want. Instead we
# clone the wall TileMapLayer as a dark, semi-transparent copy shifted a few pixels
# and drawn UNDER the real walls. That gives small, uniform shadows with exact control
# over length + direction — and it stays dynamic: `shadow_offset` IS the sun (its
# direction = away from the sun, its length = sun height), so animating that vector
# later makes the sun "move" and the shadows sweep with it.

@export var walls_path: NodePath = ^"../wall_tiles/walls"
# Small = short shadows. Direction points away from the sun. Tunable live in the
# inspector; rotate it over time for a moving sun.
@export var shadow_offset := Vector2(48, 84)
@export var shadow_color := Color(0.0, 0.0, 0.0, 0.35)

var _shadow: TileMapLayer

func _ready() -> void:
	var walls := get_node_or_null(walls_path) as TileMapLayer
	if walls == null:
		push_warning("wall_shadows: no TileMapLayer at %s" % [walls_path])
		return
	# Clone the wall tiles, tint translucent black, strip collision/navigation (it's
	# purely decorative) and any inherited script, then offset it.
	_shadow = walls.duplicate() as TileMapLayer
	_shadow.name = "wall_shadow"
	_shadow.set_script(null)
	_shadow.modulate = shadow_color
	_shadow.collision_enabled = false
	_shadow.navigation_enabled = false
	_shadow.position = walls.position + shadow_offset
	# First child of the wall container: draws over the floor, under the real walls
	# (floor and walls share z_index, so tree order decides).
	var container := walls.get_parent()
	container.add_child(_shadow)
	container.move_child(_shadow, 0)

# Later, for a moving sun, drive shadow_offset here, e.g.:
#   _shadow.position = walls.position + shadow_offset.rotated(angle)
# with `angle` advancing over the day. Left off while the sun is static.
