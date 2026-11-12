extends Node2D
# Dev-only: renders the health vial at several health levels and saves PNGs.
func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	var ui: CanvasLayer = load("res://ui/health_ui.tscn").instantiate()
	add_child(ui)
	RenderingServer.set_default_clear_color(Color(0.18, 0.2, 0.24))
	for hp in [100, 70, 40, 12]:
		ui.update_health(hp, 100)
		await get_tree().create_timer(2.5).timeout
		var img := get_viewport().get_texture().get_image()
		img.get_region(Rect2i(0, 0, 640, 520)).save_png(out.path_join("vial_%d.png" % hp))
	# Mid-hit frame: show the ghost + slosh.
	ui.update_health(100, 100)
	await get_tree().create_timer(2.5).timeout
	ui.update_health(55, 100)
	await get_tree().create_timer(0.25).timeout
	get_viewport().get_texture().get_image().get_region(Rect2i(0, 0, 640, 520)).save_png(out.path_join("vial_hit.png"))
	get_tree().quit()
