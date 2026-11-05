extends CanvasLayer

# The M-key map overlay. A read-only view (doesn't block movement — it updates
# live so you can watch yourself move). map_view.gd does the drawing; this just
# handles show/hide and tells the view when to (re)cache the room's tiles.

@onready var map_view: Control = $root/panel/margin/vbox/map_view

func _ready() -> void:
	visible = false

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	visible = true
	map_view.refresh_static()
	map_view.set_process(true)

func close() -> void:
	visible = false
	map_view.set_process(false)
