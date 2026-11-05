extends Control

const LOBBY_BUTTON = preload("res://scenes/menus/menu_items/lobby_button.tscn")
const WORLD_SCENE = "res://scenes/world.tscn"

@onready var host_public_button: Button = $margin/root/columns/host_col/host_public_button
@onready var host_private_button: Button = $margin/root/columns/host_col/host_private_button
@onready var host_name_edit: LineEdit = $margin/root/columns/host_col/host_name_edit
@onready var host_password_edit: LineEdit = $margin/root/columns/host_col/host_password_edit

@onready var refresh_button: Button = $margin/root/columns/join_col/public_row/refresh_button
@onready var lobby_v_box: VBoxContainer = $margin/root/columns/join_col/server_list_background/scroll/lobby_v_box
@onready var join_name_edit: LineEdit = $margin/root/columns/join_col/join_name_edit
@onready var join_password_edit: LineEdit = $margin/root/columns/join_col/join_password_edit
@onready var join_private_button: Button = $margin/root/columns/join_col/join_private_button

@onready var status_label: Label = $margin/root/status_label

func _ready() -> void:
	if !GlobalSteam.show_lobbies.is_connected(_show_lobbies):
		GlobalSteam.show_lobbies.connect(_show_lobbies)
	if !GlobalSteam.multiplayer_ready.is_connected(_on_multiplayer_ready):
		GlobalSteam.multiplayer_ready.connect(_on_multiplayer_ready)
	# Wire the buttons here (rather than in the scene) so the paths live in one
	# place with the @onready refs above.
	_add_play_solo_button()
	host_public_button.pressed.connect(_on_host_public_pressed)
	host_private_button.pressed.connect(_on_host_private_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	join_private_button.pressed.connect(_on_join_private_pressed)
	# Populate the public list right away.
	GlobalSteam.requestLobbyList()

# "Play Solo": a private, non-joinable game with a throwaway name/password, so a
# solo run is one click instead of filling in the private-host form. Reuses the
# normal host path (GlobalSteam.host_lobby), which still needs Steam running.
func _add_play_solo_button() -> void:
	var col := host_public_button.get_parent()
	var solo := Button.new()
	solo.name = "play_solo_button"
	solo.text = "Play Solo"
	solo.custom_minimum_size = Vector2(0, 200)
	solo.theme = host_public_button.theme
	col.add_child(solo)
	col.move_child(solo, host_public_button.get_index())
	solo.pressed.connect(_on_play_solo_pressed)

func _on_play_solo_pressed() -> void:
	_set_status("Starting a solo game…")
	GlobalSteam.host_lobby("solo", "solo_%d" % randi(), str(randi()))

func _on_host_public_pressed() -> void:
	_set_status("Creating public game…")
	GlobalSteam.host_lobby("public", "", "")

func _on_host_private_pressed() -> void:
	var server_name := host_name_edit.text.strip_edges()
	var password := host_password_edit.text.strip_edges()
	if server_name == "" or password == "":
		_set_status("Private games need a server name AND a password.")
		return
	_set_status("Creating private game '%s'…" % server_name)
	GlobalSteam.host_lobby("private", server_name, password)

func _on_refresh_pressed() -> void:
	_set_status("Refreshing public games…")
	GlobalSteam.requestLobbyList()

func _on_join_private_pressed() -> void:
	var server_name := join_name_edit.text.strip_edges()
	var password := join_password_edit.text.strip_edges()
	if server_name == "" or password == "":
		_set_status("Enter the private game's name AND password to join.")
		return
	_set_status("Searching for '%s'…" % server_name)
	# Refresh the lobby list first so join_private_lobby matches against a
	# current snapshot, then attempt the name+password match.
	GlobalSteam.requestLobbyList()
	await get_tree().create_timer(0.5).timeout
	if not GlobalSteam.join_private_lobby(server_name, password):
		_set_status("No private game found matching that name and password.")

func _on_multiplayer_ready() -> void:
	print("Multiplayer ready. Loading world.")
	get_tree().change_scene_to_file(WORLD_SCENE)

# Only PUBLIC lobbies belong in the browser — private ones are found by name +
# password (see _on_join_private_pressed), so listing them here would both leak
# their existence and let anyone click straight in with no password.
func _show_lobbies(_lobby_list: Array) -> void:
	for child in lobby_v_box.get_children():
		lobby_v_box.remove_child(child)
		child.queue_free()
	var public_lobbies: Array = []
	for lobby in _lobby_list:
		if Steam.getLobbyData(lobby, "visibility") != "private":
			public_lobbies.append(lobby)
	if public_lobbies.is_empty():
		_set_status("No public games found. Host one, or join a private game.")
	var count := 0
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 64)
	lobby_v_box.add_child(row)
	for lobby in public_lobbies:
		if count == 2:
			count = 0
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 64)
			lobby_v_box.add_child(row)
		var lobby_name: String = Steam.getLobbyData(lobby, "name")
		var lobby_num_members: int = Steam.getNumLobbyMembers(lobby)
		var lobby_button = LOBBY_BUTTON.instantiate()
		row.add_child(lobby_button)
		lobby_button["lobby_host"].text = lobby_name
		lobby_button["lobby_player_count"].text = "%s/%s" % [lobby_num_members, GlobalSteam.MAX_PLAYERS]
		lobby_button["lobby_id"] = lobby
		lobby_button.connect("join_lobby", _on_join_lobby)
		count += 1

func _on_join_lobby(_lobby_id) -> void:
	_set_status("Joining game…")
	GlobalSteam.join_lobby(_lobby_id)

func _set_status(msg: String) -> void:
	if status_label != null:
		status_label.text = msg
