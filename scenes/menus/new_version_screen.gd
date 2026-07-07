extends Control

var stats = Stats
var sounds = Sounds
var text = ""

@onready var exit_button = $CenterContainer/VBoxContainer/exit_button

func _ready():
	exit_button.grab_focus()

func _on_exit_button_pressed():
	if stats.dev_mode and text == "override":
		over_ride_version_control()
	else:
		get_tree().quit()

func over_ride_version_control():
	stats.save_data.version = "0.0.0"
	SaveAndLoad.update_save_data()

func _on_button_pressed():
	if Input.is_action_pressed("cheat_key_1") and Input.is_action_pressed("cheat_key_2") and Input.is_action_pressed("cheat_key_3"):
		stats.dev_mode = true
		$TextEdit.show()

func _on_text_edit_text_changed():
	text = $TextEdit.text
