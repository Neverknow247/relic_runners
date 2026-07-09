extends Node

var stats = Stats

var volume_settings = {
	"master_volume" = .5,
	"music_volume" = 1,
	"sounds_volume" = 1,
	"voice_volume" = 1
}

const master_bus_name = "Master"
const music_bus_name = "Music"
const sounds_bus_name = "Sounds"
const voice_bus_name = "Voice"

@onready var master_bus = AudioServer.get_bus_index(master_bus_name)
@onready var music_bus = AudioServer.get_bus_index(music_bus_name)
@onready var sounds_bus = AudioServer.get_bus_index(sounds_bus_name)
@onready var voice_bus = AudioServer.get_bus_index(voice_bus_name)

func _ready():
	if DisplayServer.window_get_mode() != window_mode:
		DisplayServer.window_set_mode(window_mode)
	_apply_mouse_mode()

# Confine the cursor to the game window so it can't accidentally click out
# (kept VISIBLE, not fully captured, since this is a mouse-aim game — the cursor
# position still matters for aiming). The OS releases confinement on alt-tab.
var mouse_capture = true:
	get:
		return mouse_capture
	set(value):
		mouse_capture = value
		_apply_mouse_mode()

func _apply_mouse_mode():
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED if mouse_capture else Input.MOUSE_MODE_VISIBLE

func set_volume():
	AudioServer.set_bus_volume_db(master_bus, linear_to_db(volume_settings["master_volume"]))
	AudioServer.set_bus_volume_db(music_bus, linear_to_db(volume_settings["music_volume"]))
	AudioServer.set_bus_volume_db(sounds_bus, linear_to_db(volume_settings["sounds_volume"]))
	AudioServer.set_bus_volume_db(voice_bus, linear_to_db(volume_settings["voice_volume"]))

var squash_and_stretch = true
var screen_shake = true

var window_mode = 0:
	get:
		return window_mode
	set(value):
		window_mode = value
		DisplayServer.window_set_mode(value)

var seperate_core = false:
	get:
		return seperate_core
	set(value):
		seperate_core = value
		ProjectSettings.set_setting("physics/2d/run_on_separate_thread",value)

func instantiate_scene_on_world(scene:PackedScene,position:Vector2):
	var world = get_tree().current_scene
	var instance = scene.instantiate()
	world.add_child(instance)
	instance.global_position = position
	return instance
