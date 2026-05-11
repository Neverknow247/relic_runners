extends Control

const LOBBY_BUTTON = preload("res://scenes/menus/menu_items/lobby_button.tscn")
const WORLD_SCENE = "res://scenes/world.tscn"

@onready var host_button: Button = $margin_container/v_box_container/margin_container/v_box_container/host_button
@onready var refresh_button: Button = $margin_container/v_box_container/margin_container/v_box_container/v_box_container/refresh_button
@onready var lobby_v_box: VBoxContainer = $margin_container/v_box_container/server_list_background/margin_container2/scroll_container/lobby_v_box

func _ready() -> void:
	if !GlobalSteam.show_lobbies.is_connected(_show_lobbies):
		GlobalSteam.show_lobbies.connect(_show_lobbies)
	if !GlobalSteam.multiplayer_ready.is_connected(_on_multiplayer_ready):
		GlobalSteam.multiplayer_ready.connect(_on_multiplayer_ready)

func _on_host_button_pressed() -> void:
	DiscordPresence.set_host_presence()
	print("Host Button Pressed")
	host_button.disabled = true
	GlobalSteam.host_lobby()

func _on_refresh_button_pressed() -> void:
	GlobalSteam.requestLobbyList()

func _on_multiplayer_ready():
	print("Multiplayer ready. Loading world.")
	get_tree().change_scene_to_file(WORLD_SCENE)

func _show_lobbies(_lobby_list):
	for child in lobby_v_box.get_children():
		lobby_v_box.remove_child(child)
		child.queue_free()
	var count = 0
	var new_lobby_h_box = HBoxContainer.new()
	lobby_v_box.add_child(new_lobby_h_box)
	new_lobby_h_box.add_theme_constant_override("separation",64)
	for lobby in _lobby_list:
		if count == 2:
			count = 0
			new_lobby_h_box = HBoxContainer.new()
			lobby_v_box.add_child(new_lobby_h_box)
			new_lobby_h_box.add_theme_constant_override("separation",64)
		var lobby_name : String = Steam.getLobbyData(lobby, "name")
		var lobby_num_members : int = Steam.getNumLobbyMembers(lobby)
		var new_lobby_button = LOBBY_BUTTON.instantiate()
		new_lobby_h_box.add_child(new_lobby_button)
		new_lobby_button["lobby_host"].text = lobby_name
		new_lobby_button["lobby_player_count"].text = "%s/16"%[lobby_num_members]
		new_lobby_button["lobby_id"] = lobby
		new_lobby_button.connect("join_lobby",_on_join_lobby)
		count += 1

func _on_join_lobby(_lobby_id):
	GlobalSteam.join_lobby(_lobby_id)
