extends Node2D
# Dev-only: ASCII dump of nav (n) / wall (W) / neither (.) around a world point.
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var room: Node = load("res://scenes/levels/%s/%s_main.tscn" % [a[0], a[0]]).instantiate()
	var nav: TileMapLayer = room.get_node("navigation/nav_1")
	var walls: TileMapLayer = room.get_node("wall_tiles/walls")
	var nc := nav.local_to_map(Vector2(float(a[1]), float(a[2])))
	var r := int(a[3])
	for y in range(-r, r + 1):
		var row := ""
		for x in range(-r, r + 1):
			var c := nc + Vector2i(x, y)
			var ch := "."
			if nav.get_cell_source_id(c) != -1: ch = "n"
			if walls.get_cell_source_id(walls.local_to_map(nav.map_to_local(c))) != -1: ch = "W" if ch == "." else "X"
			if x == 0 and y == 0: ch = "@"
			row += ch
		print("DUMP ", row)
	room.free()
	get_tree().quit()
