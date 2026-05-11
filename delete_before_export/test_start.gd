extends Node2D

@export var player_scene: PackedScene

@onready var host_button: Button = $v_box_container/host_button
@onready var join_button: Button = $v_box_container/join_button
@onready var id_prompt: LineEdit = $v_box_container/id_prompt
@onready var lobby_list: VBoxContainer = $v_box_container2/scroll_container/lobby_list

func _ready() -> void:
	GlobalSteam.add_player.connect(_add_player)
	GlobalSteam.remove_player.connect(_remove_player)
	GlobalSteam.show_lobbies.connect(_show_lobbies)

func _add_player(id : int = 1):
	var player = player_scene.instantiate()
	player.name = str(id)
	call_deferred("add_child",player)

func _remove_player(id : int):
	if !self.has_node(str(id)):
		return
	self.get_node(str(id)).queue_free()

func _on_host_button_pressed() -> void:
	print("Host Button Pressed")
	host_button.disabled = true
	GlobalSteam.host_lobby()

func _on_id_prompt_text_changed(new_text: String) -> void:
	join_button.disabled = (new_text.length() == 0)

func _on_join_button_pressed() -> void:
	join_button.disabled = true
	GlobalSteam.join_lobby(id_prompt.text.to_int())

func _on_get_lobby_list_button_pressed() -> void:
	GlobalSteam.requestLobbyList()

func _show_lobbies(_lobby_list):
	var all_lobbies = lobby_list.get_children()
	for lobby in all_lobbies:
		lobby_list.remove_child(lobby)
		lobby.queue_free()
	for lobby in _lobby_list:
		var new_lobby = RichTextLabel.new()
		lobby_list.add_child(new_lobby)
		new_lobby.fit_content = true
		new_lobby.selection_enabled = true
		new_lobby.add_theme_font_size_override("normal_font_size",24)
		new_lobby.text = str(lobby)
