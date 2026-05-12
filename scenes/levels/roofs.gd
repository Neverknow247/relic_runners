extends TileMapLayer

func make_translucent(_make_translucent):
	modulate = Color(1.0, 1.0, 1.0, 0.5) if _make_translucent else Color(1.0, 1.0, 1.0, 1.0)
