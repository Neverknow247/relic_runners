extends Control

@onready var lobby_host: Label = $h_box_container/lobby_host
@onready var lobby_player_count: Label = $h_box_container/lobby_player_count

var lobby_id : int

signal join_lobby(_lobby_id)

func _on_join_lobby_button_pressed() -> void:
	join_lobby.emit(lobby_id)
