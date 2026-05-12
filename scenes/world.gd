extends Node2D

var stats = Stats
var rng = RandomNumberGenerator.new()

const PLAYER_SCENE = preload("res://scenes/characters/player.tscn")

const ZONE_SCENES = {
	"hub/main" : "res://scenes/levels/hub/hub_main.tscn",
	"hub/room_1" : "res://scenes/levels/hub/hub_room_1.tscn",
	"hub/room_2" : "res://scenes/levels/hub/hub_room_2.tscn",
	
	"dungeon/main" : "res://scenes/levels/dungeon/dungeon_main.tscn",
	"dungeon/room_1" : "res://scenes/levels/dungeon/dungeon_room_1.tscn",
	"dungeon/room_2" : "res://scenes/levels/dungeon/dungeon_room_2.tscn",
	
	"cemetery/main" : "res://scenes/levels/cemetery/cemetery_main.tscn",
}

const EXPEDITION_TARGETS = {
	"dungeon": {
		"zone": "dungeon",
		"room": "main",
		"spawn": "default",
	},
	"cemetery": {
		"zone": "cemetery",
		"room": "main",
		"spawn": "default",
	},
}

const PLAYER_SPRITES = [
	preload("res://assets/art/pixel_quest/wizard/wizard_blue.png"),
]

@onready var floor_container: Node2D = $floor_container
@onready var zone_objects: Node2D = $y_sort_root/zone_objects
@onready var players: Node2D = $y_sort_root/players
@export var zone_container: Node2D
@onready var leave_button: Button = $canvas_layer/leave_button

enum PartyState {
	HUB,
	COUNTDOWN,
	EXPEDITION
}

var party_state := PartyState.HUB
var expedition_zone := "hub"
var expedition_room := "main"
var expedition_countdown_time := 15

var shutting_down = false

var player_locations = {}
var player_cosmetics = {}
var player_steam_ids = {}
var player_steam_names = {}
var registered_peers = {}
var current_visible_ids = {}
var player_initialized_positions = {}
var player_visibility_locked = {}

var has_registered_with_server = false
var my_zone = "hub"
var my_room = "main"

func can_send_rpc() -> bool:
	return multiplayer.multiplayer_peer != null \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _ready() -> void:
	add_to_group("world")
	shutting_down = false
	leave_button.pressed.connect(_on_leave_pressed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if multiplayer.is_server():
		rng.randomize()
	_connect_buttons()
	_connect_steam_client_signals()
	load_location_locally(my_zone, my_room)
	await get_tree().process_frame
	if multiplayer.multiplayer_peer != null:
		var my_id = multiplayer.get_unique_id()
		if multiplayer.is_server():
			player_steam_ids[my_id] = Steam.getSteamID()
			player_steam_names[my_id] = Steam.getFriendPersonaName(Steam.getSteamID())
			player_cosmetics[my_id] = generate_player_cosmetics(my_id)
			register_player(my_id)
			broadcast_all_cosmetics()
		else:
			if !players.has_node("1"):
				spawn_player_locally(1)
			start_client_registration()

func start_client_registration() -> void:
	if shutting_down:
		return
	if has_registered_with_server:
		return
	for i in range(10):
		if shutting_down:
			return
		if has_registered_with_server:
			return
		await get_tree().create_timer(0.5).timeout
		if !can_send_rpc():
			continue
		server_request_register_player.rpc(
			Steam.getSteamID(),
			GlobalSteam.logged_in_user
		)

@rpc("authority", "call_remote", "reliable")
func client_confirm_registration():
	has_registered_with_server = true

func _connect_buttons():
	$canvas_layer/go_hub_main_button.pressed.connect(func():request_location_changes("hub","main","default"))
	$canvas_layer/go_hub_room1_button.pressed.connect(func():request_location_changes("hub","room_1","default"))
	$canvas_layer/go_hub_room2_button.pressed.connect(func():request_location_changes("hub","room_2","default"))
	$canvas_layer/go_dungeon_main_button.pressed.connect(func():request_location_changes("dungeon","main","default"))
	$canvas_layer/go_dungeon_room1_button.pressed.connect(func():request_location_changes("dungeon","room_1","default"))
	$canvas_layer/go_dungeon_room2_button.pressed.connect(func():request_location_changes("dungeon","room_2","default"))

func _connect_steam_client_signals():
	if !GlobalSteam.remove_player.is_connected(_on_remove_player):
		GlobalSteam.remove_player.connect(_on_remove_player)

func _on_remove_player(peer_id: int):
	if !multiplayer.is_server():
		return
	player_locations.erase(peer_id)
	remove_player_locally(peer_id)
	refresh_visibility_for_all()

func register_player(peer_id: int):
	if !player_locations.has(peer_id):
		player_locations[peer_id] = {
			"zone": "hub",
			"room": "main",
			"spawn": "default",
		}
	if !player_cosmetics.has(peer_id) and player_steam_names.has(peer_id):
		player_cosmetics[peer_id] = generate_player_cosmetics(peer_id)
	if peer_id == multiplayer.get_unique_id():
		client_change_location("hub", "main", "default")
		client_set_visible_players([peer_id])
	else:
		client_change_location.rpc_id(peer_id, "hub", "main", "default")
	refresh_visibility_for_all()

@rpc("any_peer","call_remote","reliable")
func server_request_register_player(steam_id: int, steam_name: String):
	if !multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if registered_peers.has(sender_id):
		client_confirm_registration.rpc_id(sender_id)
		return
	registered_peers[sender_id] = true
	player_steam_ids[sender_id] = steam_id
	player_steam_names[sender_id] = steam_name
	if !player_cosmetics.has(sender_id):
		player_cosmetics[sender_id] = generate_player_cosmetics(sender_id)
	client_confirm_registration.rpc_id(sender_id)
	if party_state == PartyState.EXPEDITION:
		player_locations[sender_id] = {
			"zone": "hub",
			"room": "main",
			"spawn": "default",
		}
		client_change_location.rpc_id(sender_id, "hub", "main", "default")
	else:
		register_player(sender_id)
		var sender_loc = player_locations[sender_id]
		for other_id in player_locations.keys():
			if other_id == sender_id:
				continue
			var other_loc = player_locations[other_id]
			if other_loc["zone"] == sender_loc["zone"] and other_loc["room"] == sender_loc["room"]:
				client_place_remote_player_at_spawn.rpc_id(
					sender_id,
					other_id,
					other_loc["zone"],
					other_loc["room"],
					other_loc.get("spawn", "default")
				)
	broadcast_all_cosmetics()
	await get_tree().physics_frame
	refresh_visibility_for_all()

func generate_player_cosmetics(peer_id: int):
	var sprite_index = rng.randi_range(0, PLAYER_SPRITES.size()-1)
	var color = Color(
		rng.randf_range(0.6,1),
		rng.randf_range(0.6,1),
		rng.randf_range(0.6,1),
		1
	)
	var player_name = player_steam_names.get(peer_id, "Player %s" % peer_id)
	return {
		"sprite_index": sprite_index,
		"color": color,
		"name": player_name,
	}

func broadcast_all_cosmetics():
	if !multiplayer.is_server():
		return
	for viewer_id in player_locations.keys():
		for target_id in player_cosmetics.keys():
			if viewer_id == multiplayer.get_unique_id():
				client_apply_player_cosmetics(target_id, player_cosmetics[target_id])
			else:
				client_apply_player_cosmetics.rpc_id(viewer_id, target_id, player_cosmetics[target_id])

func request_location_changes(zone: String, room: String, spawn_point:= "default"):
	if !is_valid_location(zone,room):
		return
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		server_change_player_location(multiplayer.get_unique_id(), zone, room, spawn_point)
	else:
		server_request_location_change.rpc(zone, room, spawn_point)

@rpc("any_peer","call_remote","reliable")
func server_request_location_change(zone: String, room: String, spawn_point:= "default"):
	if !multiplayer.is_server():
		return
	if !is_valid_location(zone, room):
		return
	var sender_id = multiplayer.get_remote_sender_id()
	server_change_player_location(sender_id, zone, room, spawn_point)

func server_change_player_location(peer_id: int, zone: String, room: String, spawn_point:= "default"):
	if !player_locations.has(peer_id):
		register_player(peer_id)
	for viewer_id in player_locations.keys():
		if viewer_id == multiplayer.get_unique_id():
			client_prepare_player_room_change(peer_id)
		else:
			client_prepare_player_room_change.rpc_id(viewer_id, peer_id)
	player_locations[peer_id] = {
		"zone": zone,
		"room": room,
		"spawn": spawn_point,
	}
	if peer_id == multiplayer.get_unique_id():
		await client_change_location(zone, room, spawn_point)
	else:
		client_change_location.rpc_id(peer_id, zone, room, spawn_point)
	for other_id in player_locations.keys():
		if other_id == peer_id:
			continue
		var other_loc = player_locations[other_id]
		if other_loc["zone"] == zone and other_loc["room"] == room:
			if peer_id == multiplayer.get_unique_id():
				client_place_remote_player_at_spawn(
					other_id,
					other_loc["zone"],
					other_loc["room"],
					other_loc.get("spawn", "default")
				)
			else:
				client_place_remote_player_at_spawn.rpc_id(
					peer_id,
					other_id,
					other_loc["zone"],
					other_loc["room"],
					other_loc.get("spawn", "default")
				)
	await get_tree().physics_frame
	refresh_visibility_for_all()

@rpc("authority","call_remote","reliable")
func client_change_location(zone: String, room: String, spawn_point:= "default"):
	my_zone = zone
	my_room = room
	load_location_locally(zone, room)
	await get_tree().process_frame
	move_my_player_to_spawn(spawn_point)

@rpc("authority", "call_local", "reliable")
func client_prepare_player_room_change(peer_id: int):
	player_initialized_positions[peer_id] = false
	if players.has_node(str(peer_id)):
		var player = players.get_node(str(peer_id))
		set_player_active(player, false)
		player.global_position = Vector2(-99999, -99999)

@rpc("authority", "call_local", "reliable")
func client_place_remote_player_at_spawn(peer_id: int, zone: String, room: String, spawn_point: String):
	if !players.has_node(str(peer_id)):
		spawn_player_locally(peer_id)
	if my_zone == zone and my_room == room:
		var spawn_pos = get_spawn_global_position(spawn_point)
		var player = players.get_node(str(peer_id))
		player.global_position = spawn_pos
		player_initialized_positions[peer_id] = true
	else:
		player_initialized_positions[peer_id] = false

func move_my_player_to_spawn(spawn_point: String):
	var my_id = multiplayer.get_unique_id()
	if !players.has_node(str(my_id)):
		return
	var player = players.get_node(str(my_id))
	var spawn_pos = get_spawn_global_position(spawn_point)
	player.global_position = spawn_pos
	player_initialized_positions[my_id] = true
	current_visible_ids[my_id] = true
	set_player_active(player, true)
	if !multiplayer.is_server():
		server_confirm_spawn_ready.rpc()
	if multiplayer.is_server():
		for viewer_id in player_locations.keys():
			if viewer_id == my_id:
				continue
			if viewer_id == multiplayer.get_unique_id():
				client_place_remote_player_at_spawn(my_id, my_zone, my_room, spawn_point)
			else:
				client_place_remote_player_at_spawn.rpc_id(
					viewer_id,
					my_id,
					my_zone,
					my_room,
					spawn_point
				)

@rpc("any_peer", "call_remote", "reliable")
func server_confirm_spawn_ready():
	if !multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if !player_locations.has(sender_id):
		return
	var loc = player_locations[sender_id]
	player_initialized_positions[sender_id] = true
	for viewer_id in player_locations.keys():
		if viewer_id == sender_id:
			continue
		if viewer_id == multiplayer.get_unique_id():
			client_place_remote_player_at_spawn(
				sender_id,
				loc["zone"],
				loc["room"],
				loc.get("spawn", "default")
			)
		else:
			client_place_remote_player_at_spawn.rpc_id(
				viewer_id,
				sender_id,
				loc["zone"],
				loc["room"],
				loc.get("spawn", "default")
			)
	refresh_visibility_for_all()

func load_location_locally(zone: String, room: String):
	for child in zone_container.get_children():
		zone_container.remove_child(child)
		child.queue_free()
	for child in floor_container.get_children():
		floor_container.remove_child(child)
		child.queue_free()
	for child in zone_objects.get_children():
		zone_objects.remove_child(child)
		child.queue_free()
	var key = "%s/%s" % [zone, room]
	if !ZONE_SCENES.has(key):
		return
	var packed_scene = load(ZONE_SCENES[key])
	var scene_instance = packed_scene.instantiate()
	zone_container.add_child(scene_instance)
	var floor = scene_instance.get_node_or_null("floor_tiles")
	if floor:
		scene_instance.remove_child(floor)
		floor_container.add_child(floor)
	var objects = scene_instance.get_node_or_null("y_sort_objects")
	if objects:
		scene_instance.remove_child(objects)
		zone_objects.add_child(objects)

func refresh_visibility_for_all():
	if !multiplayer.is_server():
		return
	var known_ids = player_locations.keys()
	for viewer_id in player_locations.keys():
		if viewer_id == multiplayer.get_unique_id():
			client_set_known_players(known_ids)
		else:
			client_set_known_players.rpc_id(viewer_id, known_ids)
		var visible_ids = []
		for other_id in player_locations.keys():
			if can_players_see_each_other(viewer_id, other_id):
				visible_ids.append(other_id)
		if viewer_id == multiplayer.get_unique_id():
			client_set_visible_players(visible_ids)
		else:
			client_set_visible_players.rpc_id(viewer_id, visible_ids)

func can_players_see_each_other(a: int, b: int):
	if !player_locations.has(a):
		return false
	if !player_locations.has(b):
		return false
	var loc_a = player_locations[a]
	var loc_b = player_locations[b]
	return loc_a["zone"] == loc_b["zone"] and loc_a["room"] == loc_b["room"]

@rpc("authority", "call_remote", "reliable")
func client_set_visible_players(visible_ids):
	current_visible_ids.clear()
	var visible_lookup = {}
	for peer_id in visible_ids:
		visible_lookup[peer_id] = true
		current_visible_ids[peer_id] = true
		if !players.has_node(str(peer_id)):
			spawn_player_locally(peer_id)
	for child in players.get_children():
		var peer_id = int(child.name)
		var should_show = visible_lookup.has(peer_id) \
			and player_initialized_positions.get(peer_id, false)
		set_player_active(child, should_show)

func spawn_player_locally(peer_id: int):
	if players.has_node(str(peer_id)):
		return
	var player = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	players.add_child(player)
	set_player_active(player, false)
	player_initialized_positions[peer_id] = false
	var sync = player.get_node_or_null("multiplayer_synchronizer")
	if sync:
		sync.public_visibility = true
		sync.set_visibility_for(1, true)
	request_player_cosmetics(peer_id)

func remove_player_locally(peer_id: int):
	var node_name = str(peer_id)
	if players.has_node(node_name):
		players.get_node(node_name).queue_free()

@rpc("authority", "call_remote", "reliable")
func client_set_known_players(known_ids):
	for peer_id in known_ids:
		if !players.has_node(str(peer_id)):
			spawn_player_locally(peer_id)

func request_player_cosmetics(peer_id: int):
	if multiplayer.is_server():
		if player_cosmetics.has(peer_id):
			client_apply_player_cosmetics(peer_id, player_cosmetics[peer_id])
		return
	if !can_send_rpc():
		return
	server_request_player_cosmetics.rpc(peer_id)

@rpc("any_peer", "call_remote", "reliable")
func server_request_player_cosmetics(peer_id: int) -> void:
	if !multiplayer.is_server():
		return
	if !player_cosmetics.has(peer_id):
		player_cosmetics[peer_id] = generate_player_cosmetics(peer_id)
	var sender_id := multiplayer.get_remote_sender_id()
	client_apply_player_cosmetics.rpc_id(sender_id, peer_id, player_cosmetics[peer_id])

@rpc("authority", "call_remote", "reliable")
func client_apply_player_cosmetics(peer_id: int, cosmetics: Dictionary) -> void:
	if !players.has_node(str(peer_id)):
		return
	var player = players.get_node(str(peer_id))
	var sprite_index: int = cosmetics["sprite_index"]
	var color: Color = cosmetics["color"]
	var player_name: String = cosmetics.get("name","")
	if player_name.strip_edges() == "":
		player_name = "Player %s" % peer_id
	player.get_node("visual_root/sprite").texture = PLAYER_SPRITES[sprite_index]
	player.get_node("name_label").modulate = color
	var label = player.get_node("name_label")
	if label:
		label.text = player_name
		label.z_index = 100
	else:
		print("Missing name label on player: ", peer_id)
	if peer_id == multiplayer.get_unique_id():
		player_initialized_positions[peer_id] = true
		current_visible_ids[peer_id] = true
		set_player_active(player, true)

func set_player_active(player: Node, active: bool):
	var sprite = player.get_node_or_null("visual_root/sprite")
	if sprite:
		sprite.visible = active
	var label = player.get_node_or_null("name_label")
	if label:
		label.visible = active
	set_player_collision_active(player, active)

func set_player_collision_active(player: Node, active: bool):
	if player is CollisionObject2D:
		if !player.has_meta("original_collision_layer"):
			player.set_meta("original_collision_layer", player.collision_layer)
			player.set_meta("original_collision_mask", player.collision_mask)
		player.collision_layer = player.get_meta("original_collision_layer") if active else 0
		player.collision_mask = player.get_meta("original_collision_mask") if active else 0
	for child in player.get_children():
		if child is CollisionObject2D:
			if !child.has_meta("original_collision_layer"):
				child.set_meta("original_collision_layer", child.collision_layer)
				child.set_meta("original_collision_mask", child.collision_mask)
			child.collision_layer = child.get_meta("original_collision_layer") if active else 0
			child.collision_mask = child.get_meta("original_collision_mask") if active else 0

func is_valid_location(zone: String, room: String):
	var key = "%s/%s" % [zone, room]
	return ZONE_SCENES.has(key)

func get_spawn_global_position(spawn_point: String) -> Vector2:
	var spawn_path = "spawn_points/%s" % spawn_point
	if zone_container.get_child_count() > 0:
		var current_zone = zone_container.get_child(0)
		if current_zone.has_node(spawn_path):
			return current_zone.get_node(spawn_path).global_position
	print("Missing spawn point: ", spawn_path)
	return Vector2.ZERO

func request_start_expedition(expedition_id: String):
	if !multiplayer.is_server():
		server_request_start_expedition.rpc(expedition_id)
		return
	start_expedition_countdown(expedition_id)

@rpc("any_peer", "call_remote", "reliable")
func server_request_start_expedition(expedition_id: String):
	if !multiplayer.is_server():
		return
	start_expedition_countdown(expedition_id)

func start_expedition_countdown(expedition_id: String):
	if party_state != PartyState.HUB:
		return
	if !EXPEDITION_TARGETS.has(expedition_id):
		return
	party_state = PartyState.COUNTDOWN
	var target = EXPEDITION_TARGETS[expedition_id]
	expedition_zone = target["zone"]
	expedition_room = target["room"]
	broadcast_countdown_started.rpc(expedition_id, expedition_countdown_time)
	await get_tree().create_timer(expedition_countdown_time).timeout
	if party_state != PartyState.COUNTDOWN:
		return
	launch_expedition(expedition_id)

@rpc("authority", "call_local", "reliable")
func broadcast_countdown_started(expedition_id: String, seconds: int):
	print("Leaving for ", expedition_id, " in ", seconds, " seconds")

func launch_expedition(expedition_id: String):
	if !multiplayer.is_server():
		return
	var target = EXPEDITION_TARGETS[expedition_id]
	party_state = PartyState.EXPEDITION
	expedition_zone = target["zone"]
	expedition_room = target["room"]
	for peer_id in player_locations.keys():
		server_change_player_location(
			peer_id,
			target["zone"],
			target["room"],
			target["spawn"]
		)
	refresh_visibility_for_all()

func return_party_to_hub():
	if !multiplayer.is_server():
		return
	party_state = PartyState.HUB
	expedition_zone = "hub"
	expedition_room = "main"
	for peer_id in player_locations.keys():
		server_change_player_location(peer_id, "hub", "main", "default")
	refresh_visibility_for_all()

func _on_server_disconnected():
	cleanup_world()
	GlobalSteam.leave_lobby()
	get_tree().change_scene_to_file("res://scenes/menus/main_menu.tscn")

func _on_leave_pressed():
	cleanup_world()
	GlobalSteam.leave_lobby()
	get_tree().change_scene_to_file("res://scenes/menus/main_menu.tscn")

func cleanup_world():
	shutting_down = true
	if GlobalSteam.remove_player.is_connected(_on_remove_player):
		GlobalSteam.remove_player.disconnect(_on_remove_player)
	for child in players.get_children():
		child.set_process(false)
		child.set_physics_process(false)
		child.queue_free()
	for child in zone_container.get_children():
		child.queue_free()
	player_locations.clear()
	player_cosmetics.clear()
	player_steam_ids.clear()
	player_steam_names.clear()
	registered_peers.clear()
	has_registered_with_server = false
