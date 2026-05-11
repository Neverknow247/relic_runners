extends Control

@onready var fade = $fade
@onready var animation_player: AnimationPlayer = $animation_player

func _ready() -> void:
	show()
	fade_in()

func fade_in():
	animation_player.play("fade_in")

func fade_out():
	animation_player.play("fade_out")
