@tool
extends TileMapLayer
## Editor-only navigation baker.
##
## Select the nav_1 node this is attached to and press the "Bake Nav From Floor"
## button in the inspector. It fills this layer with nav tiles derived from the
## level's floor tiles minus wall tiles as a STARTING POINT — then trim it by
## hand with the TileMap paint tools (erase outlying/decorative areas so enemies
## only spawn and path where you want) and save the scene.
##
## The baked cells are stored as ordinary static tile data in the .tscn. Nothing
## in here runs at game runtime — there is no _ready/_process, so the shipped
## nav is exactly whatever you baked-then-trimmed, no per-load rebake, no chug.
##
## Assumes floor/wall/nav tilesets share one tile size (256px native) so their
## cell coordinates line up 1:1 at scale 1.

## Atlas source id + coord of the walkable nav tile in nav_tiles.tres.
const NAV_SOURCE_ID := 2
const NAV_ATLAS := Vector2i(0, 0)

## Sibling containers on the level root that hold the floor/wall TileMapLayers.
const FLOOR_CONTAINER := "floor_tiles"
const WALL_CONTAINER := "wall_tiles"

@export_tool_button("Bake Nav From Floor") var _bake_action: Callable = _bake_from_floor
## Clears every nav tile from this layer (start over before a hand-repaint).
@export_tool_button("Clear Nav") var _clear_action: Callable = _clear_nav
## STEP 2, after painting/trimming: merges the painted nav tiles into ONE baked
## navmesh (child "nav_mesh" NavigationRegion2D, saved as <scene>_navmesh.tres)
## and turns this layer's per-cell navigation off. Per-cell nav made every enemy
## path query search thousands of regions; the merged mesh is ~20x smaller.
## Re-press after any repaint. The painted tiles stay as the source.
@export_tool_button("Build Nav Mesh From Painted Tiles") var _build_mesh_action: Callable = _build_nav_mesh

func _bake_from_floor() -> void:
	if not Engine.is_editor_hint():
		return
	# navigation node -> level root
	var level_root := get_parent().get_parent()
	if level_root == null:
		push_warning("nav_baker: no level root; nothing baked")
		return

	var walkable := {}
	var floor_root := level_root.get_node_or_null(FLOOR_CONTAINER)
	if floor_root != null:
		for child in floor_root.get_children():
			var layer := child as TileMapLayer
			if layer == null:
				continue
			for cell in layer.get_used_cells():
				walkable[cell] = true

	if walkable.is_empty():
		push_warning("nav_baker: no floor cells found; nothing baked")
		return

	var wall_root := level_root.get_node_or_null(WALL_CONTAINER)
	if wall_root != null:
		for child in wall_root.get_children():
			var layer := child as TileMapLayer
			if layer == null:
				continue
			for cell in layer.get_used_cells():
				walkable.erase(cell)

	clear()
	for cell: Vector2i in walkable.keys():
		set_cell(cell, NAV_SOURCE_ID, NAV_ATLAS)
	print("nav_baker: baked ", walkable.size(), " walkable cells — now trim by hand and save.")

func _build_nav_mesh() -> void:
	if not Engine.is_editor_hint():
		return
	var poly := NavMeshBuilder.build(self)
	if poly == null:
		push_warning("nav_baker: no painted nav tiles; nothing built")
		return
	var scene_path: String = owner.scene_file_path if owner != null else ""
	if scene_path == "":
		push_warning("nav_baker: save the scene first")
		return
	var res_path := scene_path.get_basename() + "_navmesh.tres"
	ResourceSaver.save(poly, res_path)
	poly = load(res_path)
	var region: NavigationRegion2D = get_node_or_null("nav_mesh")
	if region == null:
		region = NavigationRegion2D.new()
		region.name = "nav_mesh"
		add_child(region)
		region.owner = owner
	region.navigation_polygon = poly
	navigation_enabled = false
	print("nav_baker: built %s (%d polygons from %d cells); save the scene." % [res_path, poly.get_polygon_count(), get_used_cells().size()])

func _clear_nav() -> void:
	if not Engine.is_editor_hint():
		return
	clear()
	print("nav_baker: cleared nav tiles.")
