extends RefCounted
class_name NavMeshBuilder

# Turns a hand-painted nav TileMapLayer (nav_1) into ONE baked NavigationPolygon.
#
# Why: painted nav tiles become one navigation region PER CELL (dungeon_main had
# 6,767), and every enemy path query has to search that whole graph. Profiling
# showed path following was ~80% of enemy cost and the empty map's navigation
# alone cost ~2 ms/frame. One merged mesh is a tiny fraction of that.
#
# How: greedy-merge the painted cells into rectangles (so the hand trimming is
# respected exactly), feed them to Godot's navmesh baker as traversable
# outlines (it unions them), and shrink by agent_radius so paths keep clear of
# walls. Coordinates are in the nav layer's LOCAL space; put the resulting
# NavigationRegion2D as a child of the layer so it shares its transform.

# 80 = enemy body radius (48) + 32 margin, so a path hugging the mesh edge
# still clears wall corners. 40 let bodies clip corners and jam in doorways.
const DEFAULT_AGENT_RADIUS := 80.0

static func build(layer: TileMapLayer, agent_radius := DEFAULT_AGENT_RADIUS) -> NavigationPolygon:
	var cells := layer.get_used_cells()
	if cells.is_empty() or layer.tile_set == null:
		return null
	var tsize := Vector2(layer.tile_set.tile_size)
	var geo := NavigationMeshSourceGeometryData2D.new()
	for r in merge_cells(cells):
		var top_left: Vector2 = layer.map_to_local(r.position) - tsize * 0.5
		var bottom_right: Vector2 = layer.map_to_local(r.position + r.size - Vector2i.ONE) + tsize * 0.5
		geo.add_traversable_outline(PackedVector2Array([
			top_left,
			Vector2(bottom_right.x, top_left.y),
			bottom_right,
			Vector2(top_left.x, bottom_right.y),
		]))
	var poly := NavigationPolygon.new()
	poly.agent_radius = agent_radius
	NavigationServer2D.bake_from_source_geometry_data(poly, geo)
	return poly

# Greedy rectangle cover of a set of cells (rows first, then grown downward).
static func merge_cells(cells: Array[Vector2i]) -> Array[Rect2i]:
	var todo := {}
	for c in cells:
		todo[c] = true
	var sorted: Array = cells.duplicate()
	sorted.sort_custom(func(a, b): return a.y < b.y if a.y != b.y else a.x < b.x)
	var rects: Array[Rect2i] = []
	for c in sorted:
		if !todo.has(c):
			continue
		var w := 1
		while todo.has(Vector2i(c.x + w, c.y)):
			w += 1
		var h := 1
		var grow := true
		while grow:
			for x in w:
				if !todo.has(Vector2i(c.x + x, c.y + h)):
					grow = false
					break
			if grow:
				h += 1
		for y in h:
			for x in w:
				todo.erase(Vector2i(c.x + x, c.y + y))
		rects.append(Rect2i(c, Vector2i(w, h)))
	return rects
