extends Node2D
# Dev-only: list disconnected islands of painted nav cells (4-neighbour).
func _ready() -> void:
	for level in OS.get_cmdline_user_args():
		var room: Node = load("res://scenes/levels/%s/%s_main.tscn" % [level, level]).instantiate()
		var nav: TileMapLayer = room.get_node("navigation/nav_1")
		var todo := {}
		for c in nav.get_used_cells():
			todo[c] = true
		var comps: Array = []
		while !todo.is_empty():
			var start: Vector2i = todo.keys()[0]
			var stack := [start]
			todo.erase(start)
			var cells: Array = []
			while !stack.is_empty():
				var c: Vector2i = stack.pop_back()
				cells.append(c)
				for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					if todo.has(c + d):
						todo.erase(c + d)
						stack.append(c + d)
			comps.append(cells)
		comps.sort_custom(func(a, b): return a.size() > b.size())
		print("ISLANDS %s: %d components, main=%d cells" % [level, comps.size(), comps[0].size()])
		var comp_of := {}
		for i in comps.size():
			for c in comps[i]:
				comp_of[c] = i
		for i in range(1, comps.size()):
			print("  island %d cells at world %s" % [comps[i].size(), nav.map_to_local(comps[i][0])])
		for m in room.find_children("*", "Node2D", true, false):
			if m is Marker2D or m.name.begins_with("exit") or m.name.contains("portal") or m.name.contains("container"):
				var cell := nav.local_to_map(nav.to_local(m.global_position)) if m.is_inside_tree() else nav.local_to_map(m.position)
				var comp: int = comp_of.get(cell, -1)
				if comp != 0:
					print("  MARKER %s at %s -> %s" % [m.get_path() if m.is_inside_tree() else String(m.name), m.position, "OFF-NAV" if comp == -1 else "island %d" % comp])
		room.free()
	get_tree().quit()
