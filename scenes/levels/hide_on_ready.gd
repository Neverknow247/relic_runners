extends Node2D

func _ready() -> void:
	# NOT `visible = false` — TileMapLayer ties its baked navigation regions'
	# enabled state to is_visible_in_tree(), so hiding this node that way
	# would also silently disable navigation for any TileMapLayer children
	# (exactly what was happening: every NavigationServer2D query returned
	# Vector2.ZERO because the whole map had nothing registered on it).
	# Zero alpha hides it from rendering without touching the visible flag,
	# so navigation stays live while it's still invisible in-game.
	modulate.a = 0.0
