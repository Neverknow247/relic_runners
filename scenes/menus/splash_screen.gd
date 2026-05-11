extends Control

var stats = Stats
var sounds = Sounds
var utils = Utils

@onready var transition: Control = $transition

var easter_egg_audio = "angel_1_1"
var next_board = "res://scenes/menus/main_menu.tscn"

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#472d3c"))
	sounds.play_sound("smell_this_bread", 1, -15)
	await get_tree().create_timer(1.2).timeout
	start()

func start():
	await SaveAndLoad.load_settings()
	utils.set_volume()
	if await SaveAndLoad.load_data():
		stats["save_data"]["stats"]["power_on_count"] += 1
		stats.rng.randomize()
	await SaveAndLoad.save_all()
	finish()

func finish():
	transition.fade_out()
	await get_tree().create_timer(stats.transition_time).timeout
	get_tree().change_scene_to_file(next_board)
