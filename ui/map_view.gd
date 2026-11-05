extends Control

# Schematic minimap of the ACTIVE room: floor + wall tiles drawn as a scaled-down
# footprint, with LIVE markers for players and portals (portals colored by state).
# Tile geometry is cached in world space when the map opens (it never changes
# while you're looking); the world->map fit is recomputed each _draw from the
# control's current size, so markers always line up even before layout settles.

const PADDING := 24.0

# ExitPortal.State -> marker color. LOCKED/DISABLED read as "closed", CHARGING as
# "opening", OPEN as open, SPAWN_POINT as the entrance/arrival portal.
const PORTAL_COLORS := {
	0: Color(0.55, 0.55, 0.58),  # LOCKED   — inactive
	1: Color(0.95, 0.75, 0.15),  # CHARGING — opening
	2: Color(0.25, 0.9, 0.45),   # OPEN
	3: Color(0.5, 0.25, 0.25),   # DISABLED — closed/spent
	4: Color(0.35, 0.6, 1.0),    # SPAWN_POINT — entrance
}

var _floor_world: Array[Rect2] = []
var _wall_world: Array[Rect2] = []
# PERF: the floor/wall footprint is rasterized ONCE (on open) into this texture.
# Drawing tens of thousands of tile rects every frame is what made the game chug
# while the map was open; now each frame draws one texture plus a few markers.
var _tex: ImageTexture = null
var _bounds := Rect2()
var _has_map := false
# Recomputed at the top of every _draw from the current size + _bounds.
var _scale := 1.0
var _origin := Vector2.ZERO

func _ready() -> void:
	set_process(false)
	# Crisp tiles when the baked map texture is scaled up.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _process(_delta: float) -> void:
	queue_redraw()

# Rebuild the cached tile footprint for the active room. Call when the map opens.
func refresh_static() -> void:
	_floor_world.clear()
	_wall_world.clear()
	_has_map = false
	var world = get_tree().get_first_node_in_group("world")
	if world == null or world.world_rooms == null:
		return
	var wr = world.world_rooms
	var key: String = wr.active_key
	if key == "" or not wr.loaded_rooms.has(key):
		return
	var entry: Dictionary = wr.loaded_rooms[key]
	var floor_layers: Array = []
	var wall_layers: Array = []
	_collect_layers(entry.get("floor"), floor_layers)
	var scene = entry.get("scene")
	if scene != null and is_instance_valid(scene):
		_collect_layers(scene.get_node_or_null("wall_tiles"), wall_layers)
	_gather_cell_rects(floor_layers, _floor_world)
	_gather_cell_rects(wall_layers, _wall_world)
	if _floor_world.is_empty() and _wall_world.is_empty():
		return
	var b := Rect2()
	var first := true
	for r in _floor_world:
		b = r if first else b.merge(r)
		first = false
	for r in _wall_world:
		b = r if first else b.merge(r)
		first = false
	_bounds = b
	_bake_texture()
	_floor_world.clear()
	_wall_world.clear()
	_has_map = _tex != null

# One pixel per (smallest) tile, floor then walls on top.
const FLOOR_COLOR := Color(0.26, 0.29, 0.36)
const WALL_COLOR := Color(0.5, 0.52, 0.58)
const MAX_TEX_SIDE := 2048
func _bake_texture() -> void:
	_tex = null
	var cell := INF
	for r in _floor_world + _wall_world:
		cell = minf(cell, minf(r.size.x, r.size.y))
	if cell == INF or cell <= 0.0:
		return
	cell = maxf(cell, maxf(_bounds.size.x, _bounds.size.y) / float(MAX_TEX_SIDE))
	var w := clampi(int(ceil(_bounds.size.x / cell)), 1, MAX_TEX_SIDE)
	var h := clampi(int(ceil(_bounds.size.y / cell)), 1, MAX_TEX_SIDE)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for pair in [[_floor_world, FLOOR_COLOR], [_wall_world, WALL_COLOR]]:
		for r in pair[0]:
			var x0 := clampi(int((r.position.x - _bounds.position.x) / cell), 0, w - 1)
			var y0 := clampi(int((r.position.y - _bounds.position.y) / cell), 0, h - 1)
			var x1 := clampi(int(ceil((r.end.x - _bounds.position.x) / cell)), x0 + 1, w)
			var y1 := clampi(int(ceil((r.end.y - _bounds.position.y) / cell)), y0 + 1, h)
			img.fill_rect(Rect2i(x0, y0, x1 - x0, y1 - y0), pair[1])
	_tex = ImageTexture.create_from_image(img)

func _collect_layers(node, out: Array) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is TileMapLayer:
		out.append(node)
	for c in node.get_children():
		_collect_layers(c, out)

func _gather_cell_rects(layers: Array, out: Array) -> void:
	for layer in layers:
		var ts = layer.tile_set
		if ts == null:
			continue
		var tsize := Vector2(ts.tile_size)
		for cell in layer.get_used_cells():
			var center_global: Vector2 = layer.to_global(layer.map_to_local(cell))
			out.append(Rect2(center_global - tsize * 0.5, tsize))

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.08, 0.11))
	if not _has_map:
		return
	# Fit the room's world bounds into the control, preserving aspect + centered.
	var avail := size - Vector2(PADDING, PADDING) * 2.0
	if _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0 or avail.x <= 0.0 or avail.y <= 0.0:
		return
	_scale = minf(avail.x / _bounds.size.x, avail.y / _bounds.size.y)
	_origin = (size - _bounds.size * _scale) * 0.5
	if _tex != null:
		draw_texture_rect(_tex, Rect2(_origin, _bounds.size * _scale), false)
	_draw_portals()
	_draw_players()

func _world_to_map(p: Vector2) -> Vector2:
	return (p - _bounds.position) * _scale + _origin

func _rect_to_map(r: Rect2) -> Rect2:
	return Rect2(_world_to_map(r.position), r.size * _scale)

func _draw_portals() -> void:
	var world = get_tree().get_first_node_in_group("world")
	if world == null or world.world_rooms == null:
		return
	var wr = world.world_rooms
	var entry: Dictionary = wr.loaded_rooms.get(wr.active_key, {})
	var scene = entry.get("scene")
	if scene == null or not is_instance_valid(scene):
		return
	var portals = scene.get_node_or_null("doors/portals")
	if portals == null:
		return
	for portal in portals.get_children():
		if not ("state" in portal):
			continue
		var col: Color = PORTAL_COLORS.get(portal.state, Color.WHITE)
		var m := _world_to_map(portal.global_position)
		draw_circle(m, 10.0, col)
		draw_arc(m, 10.0, 0.0, TAU, 24, Color(0, 0, 0, 0.7), 2.5)

func _draw_players() -> void:
	var world = get_tree().get_first_node_in_group("world")
	if world == null or world.players == null:
		return
	var local = world.get_local_player()
	# Rooms load at huge world offsets, so a player in a DIFFERENT room sits far
	# outside this room's bounds — skip them (their dot would be meaningless here).
	var in_room := _bounds.grow(64.0)
	for p in world.players.get_children():
		if not (p is Node2D):
			continue
		if not in_room.has_point(p.global_position):
			continue
		var is_local: bool = p == local
		var m := _world_to_map(p.global_position)
		var col := Color(0.3, 0.85, 1.0) if is_local else Color(1.0, 0.8, 0.3)
		draw_circle(m, 8.0, col)
		draw_arc(m, 8.0, 0.0, TAU, 20, Color(0, 0, 0, 0.85), 2.5)
