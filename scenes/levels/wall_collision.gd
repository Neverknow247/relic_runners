extends Node2D

# Replaces the wall TileMapLayer's PER-TILE collision with MERGED, seamless collision
# boxes.
#
# The wall layer is SCALED (0.25), and Godot builds one collision box per tile. Adjacent
# scaled tile boxes leave sub-pixel-misaligned SEAMS at every tile boundary, and a
# CharacterBody2D (player or enemy) catches on those internal edges — you "walk into a
# wall and get stuck" right at a tile boundary, unable to slide free. Greedy-meshing the
# wall cells into a handful of big rectangles removes every internal seam along flat runs,
# so bodies glide cleanly; only genuine concave corners between merged rects remain (which
# move_and_slide handles fine). The merged body is on layer 1 (walls) exactly like the
# tileset, so LOS / player / enemy collision are otherwise unchanged. Collision isn't
# networked, so every peer builds the identical body independently.

@export var walls_path: NodePath = ^"../wall_tiles/walls"

func _ready() -> void:
	var walls: TileMapLayer = get_node_or_null(walls_path) as TileMapLayer
	if walls == null:
		push_warning("wall_collision: no TileMapLayer at %s" % [walls_path])
		return
	var cells: Array[Vector2i] = walls.get_used_cells()
	if cells.is_empty():
		return
	var ts: float = float(walls.tile_set.tile_size.x)
	var body := StaticBody2D.new()
	body.name = "merged_wall_collision"
	body.collision_layer = 1
	body.collision_mask = 0
	# Everything below is in the walls layer's LOCAL space (tile units, pre-scale), and
	# the body is parented UNDER the walls layer — so it inherits the exact same transform
	# (scale 0.25 + position, wherever the world places the level) and the collision always
	# lines up with the tiles no matter where/how the level is positioned. Each merged rect
	# is ONE big shape, so the 0.25 scale can't reintroduce per-tile seams.
	for r in _greedy_rects(cells):
		var c0 := walls.map_to_local(r.position)                          # top-left cell center
		var c1 := walls.map_to_local(r.position + r.size - Vector2i.ONE)  # bottom-right cell center
		var shape := RectangleShape2D.new()
		shape.size = Vector2(r.size.x * ts, r.size.y * ts)
		var cs := CollisionShape2D.new()
		cs.shape = shape
		cs.position = (c0 + c1) * 0.5
		body.add_child(cs)
	walls.add_child(body)
	# The seamless body now carries the collision — turn off the tilemap's own per-tile
	# collision so the two don't overlap (and so the seams are actually gone).
	walls.collision_enabled = false

# Greedy-mesh occupied cells into maximal rectangles: for each not-yet-covered cell,
# extend right as far as the row stays solid, then extend that whole width downward as
# far as every row underneath is solid. Produces a small, non-overlapping cover.
func _greedy_rects(cells: Array[Vector2i]) -> Array[Rect2i]:
	var occ := {}
	for c in cells:
		occ[c] = true
	var order := cells.duplicate()
	order.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var visited := {}
	var rects: Array[Rect2i] = []
	for c: Vector2i in order:
		if visited.has(c):
			continue
		var w := 1
		while occ.has(Vector2i(c.x + w, c.y)) and not visited.has(Vector2i(c.x + w, c.y)):
			w += 1
		var h := 1
		while true:
			var ny: int = c.y + h
			var row_ok := true
			for dx in range(w):
				var cc := Vector2i(c.x + dx, ny)
				if not occ.has(cc) or visited.has(cc):
					row_ok = false
					break
			if not row_ok:
				break
			h += 1
		for dy in range(h):
			for dx in range(w):
				visited[Vector2i(c.x + dx, c.y + dy)] = true
		rects.append(Rect2i(c.x, c.y, w, h))
	return rects
