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
		# dungeon_main.tscn's doors/portals group picks one of its exit
		# portals at random as the arrival point (see world_rooms.gd's
		# get_spawn_global_position() and portal_group.gd) — cemetery_main
		# doesn't have a doors/portals group yet, so it still just uses its
		# single fixed "default" spawn_points marker.
		"spawn": "random_portal",
	},
	"cemetery": {
		"zone": "cemetery",
		"room": "main",
		"spawn": "default",
	},
}

@onready var world_players: Node = $world_players
@onready var world_rooms: Node = $world_rooms
@onready var world_expeditions: Node = $world_expeditions
@onready var world_loot: Node = $world_loot

@onready var floor_container: Node2D = $floor_container
@onready var zone_objects: Node2D = $y_sort_root/zone_objects
@onready var players: Node2D = $y_sort_root/players
@export var zone_container: Node2D
@onready var held_rooms_container: Node2D = $held_rooms
@onready var leave_button: Button = $canvas_layer/leave_button
@onready var esc_menu = $esc_menu

enum PartyState {
	HUB,
	# The host opened an expedition door: every player has a kit popup up, and
	# the party only travels once all of them have answered (see
	# world_expeditions.gd's kit-selection flow). COUNTDOWN is retained for the
	# enum's stability but is no longer entered.
	KIT_SELECTION,
	COUNTDOWN,
	EXPEDITION
}

var party_state := PartyState.HUB

# Kit-selection bookkeeping (server-only). pending_kit_expedition_id is which
# expedition the host opened; kit_expected_peers is the snapshot of who must
# answer; kit_answers is who has. See world_expeditions.gd.
var pending_kit_expedition_id := ""
var kit_expected_peers: Array = []
var kit_answers: Dictionary = {}
var expedition_zone := "hub"
var expedition_room := "main"
var expedition_countdown_time := 1

var shutting_down = false

var player_locations = {}
var player_cosmetics = {}
var player_steam_ids = {}
var player_steam_names = {}
var registered_peers = {}
var current_visible_ids = {}
var player_initialized_positions = {}

# room_key -> { peer_id: true }. Server-only. A peer is listed here for a room
# only once it has confirmed its OWN copy of that room's enemies is spawned
# (see enemy_spawner.gd -> notify_room_ready). Enemy replication to a peer is
# gated on this (world_rooms.gd's _refresh_room_entity_visibility) — otherwise
# the server, which marks enemies visible the instant a peer's LOCATION
# updates, starts syncing before the peer has spawned its enemies (they wait
# several frames on the nav map first), spamming "node not found" /
# "get_cached_object failed" for the whole load window.
var room_ready_peers: Dictionary = {}

var has_registered_with_server = false
var my_zone = "hub"
var my_room = "main"

func _ready() -> void:
	world_players.setup(self)
	world_rooms.setup(self)
	world_expeditions.setup(self)
	world_loot.setup(self)
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
			sync_ready_peers[my_id] = true # this line added
			player_steam_ids[my_id] = Steam.getSteamID()
			player_steam_names[my_id] = Steam.getFriendPersonaName(Steam.getSteamID())
			player_cosmetics[my_id] = generate_player_cosmetics(my_id)
			register_player(my_id)
			broadcast_all_cosmetics()
		else:
			if !players.has_node("1"):
				spawn_player_locally(1)
			start_client_registration()

func _unhandled_input(event: InputEvent) -> void:
	if !event.is_action_pressed("ui_cancel"):
		return
	if esc_menu.visible:
		esc_menu.toggle()
		return
	var local_player = get_local_player()
	if local_player != null and local_player.close_inventory_if_open():
		return
	esc_menu.toggle()

func can_send_rpc() -> bool:
	return multiplayer.multiplayer_peer != null \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

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

func _on_leave_pressed():
	cleanup_world()
	GlobalSteam.leave_lobby()
	get_tree().change_scene_to_file("res://scenes/menus/main_menu.tscn")

func _on_server_disconnected():
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
	# Frees every loaded room (active + held) plus each room's extracted
	# floor/objects, and clears world_rooms' tracking — replaces the old
	# manual zone_container loop + clear_held_rooms(), which missed the
	# extracted floor_tiles/y_sort_objects.
	world_rooms.free_all_rooms()
	player_locations.clear()
	player_cosmetics.clear()
	player_steam_ids.clear()
	player_steam_names.clear()
	registered_peers.clear()
	has_registered_with_server = false

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
				# Place the existing other ON the joiner...
				client_place_remote_player_at_spawn.rpc_id(
					sender_id,
					other_id,
					other_loc["zone"],
					other_loc["room"],
					other_loc.get("spawn", "default")
				)
				# ...and the joiner ON the existing other, so the existing player
				# sees the newcomer immediately (not only once the expedition
				# starts). See the matching note in server_change_player_location.
				if other_id == multiplayer.get_unique_id():
					client_place_remote_player_at_spawn(
						sender_id,
						sender_loc["zone"],
						sender_loc["room"],
						sender_loc.get("spawn", "default")
					)
				else:
					client_place_remote_player_at_spawn.rpc_id(
						other_id,
						sender_id,
						sender_loc["zone"],
						sender_loc["room"],
						sender_loc.get("spawn", "default")
					)
	broadcast_all_cosmetics()
	await get_tree().physics_frame
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
		client_refresh_players(
			player_locations.keys(),
			get_visible_ids_for(peer_id),
			sync_ready_peers.keys()
		)
	else:
		client_change_location.rpc_id(peer_id, "hub", "main", "default")
	refresh_visibility_for_all()

func _on_remove_player(peer_id: int):
	if !multiplayer.is_server():
		return
	player_locations.erase(peer_id)
	remove_player_locally(peer_id)
	# A player quitting/disconnecting mid-expedition never goes through
	# server_change_player_location (that's only for normal in-game location
	# changes, e.g. walking through a portal) — without this, if the last
	# non-hub player leaves this way, party_state stays stuck at EXPEDITION
	# forever and the whole lobby has to be rehosted to start a new run.
	world_expeditions.check_expedition_still_active()
	clear_peer_room_ready(peer_id)
	# A player disconnecting mid-kit-selection shouldn't wedge the party waiting
	# on an answer that'll never come — drop them from the expected set and
	# re-check whether everyone remaining has now answered.
	world_expeditions.handle_kit_peer_left(peer_id)
	refresh_visibility_for_all()

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
	# This peer is leaving its current room — its enemy-readiness is now stale;
	# it re-confirms after loading the next room's enemies.
	clear_peer_room_ready(peer_id)
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
	world_expeditions.check_expedition_still_active()
	if peer_id == multiplayer.get_unique_id():
		await client_change_location(zone, room, spawn_point)
	else:
		client_change_location.rpc_id(peer_id, zone, room, spawn_point)
	for other_id in player_locations.keys():
		if other_id == peer_id:
			continue
		var other_loc = player_locations[other_id]
		if other_loc["zone"] == zone and other_loc["room"] == room:
			# Place the co-located other ON the mover, so the mover sees them...
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
			# ...and place the mover ON the other, so existing players actually
			# see the newcomer. Without this reverse placement the other's
			# player_initialized_positions[peer_id] never flips true, so
			# client_refresh_players keeps them hidden — the "joined the hub but
			# stayed invisible until the expedition started" bug (which only
			# self-corrected because launch moves everyone, running this loop
			# for every pair).
			if other_id == multiplayer.get_unique_id():
				client_place_remote_player_at_spawn(peer_id, zone, room, spawn_point)
			else:
				client_place_remote_player_at_spawn.rpc_id(
					other_id, peer_id, zone, room, spawn_point
				)
	await get_tree().physics_frame
	refresh_visibility_for_all()

@rpc("authority","call_remote","reliable")
func client_change_location(zone: String, room: String, spawn_point:= "default"):
	# Runs locally on every peer's own machine whenever THEIR OWN location
	# changes (called directly for the local peer, .rpc_id()'d to others) —
	# the correct per-peer hook for "I just arrived in the hub", since
	# stats.save_data (and the inventory/weapons inside it) is per-peer
	# local state, not something the server can save on anyone's behalf.
	var arriving_in_hub := zone == "hub" and my_zone != "hub"
	var leaving_hub := zone != "hub" and my_zone == "hub"
	var old_zone: String = my_zone
	var old_room: String = my_room
	my_zone = zone
	my_room = room
	load_location_locally(zone, room, old_zone, old_room)
	if leaving_hub:
		# Apply the kit this player picked at the door — deferred until now (the
		# actual moment of travel) so a cancelled start never reshuffled anyone.
		# Must run BEFORE the disk wipe below: apply_starter_kit() banks into the
		# stash/overflow (which the wipe leaves intact) and stands up the fresh
		# loadout; Custom Kit is a no-op and can leave the weapon slot empty.
		var local_player = get_local_player()
		if local_player != null:
			local_player.apply_pending_kit()
		# Optimistically wipe the ON-DISK save the instant you head out —
		# not just when you actually die or use the Quit/Leave buttons —
		# so ANY ungraceful way the game stops running mid-expedition
		# (closing the window directly, a crash, alt+F4, power loss) leaves
		# you exactly as if you'd died: nothing saved beyond what you took
		# in with you. In-memory gameplay is untouched (you still have your
		# stuff for the rest of this session); only the persisted snapshot
		# is cleared, and only a successful return to hub below writes your
		# real (possibly loot-enriched) backpack back to disk.
		Stats.save_data["items"] = {}
		Stats.save_data["equipment"] = {}
		SaveAndLoad.save_all()
	if arriving_in_hub:
		var local_player = get_local_player()
		if local_player != null:
			# Covers returning through an exit portal, not just dying (death
			# already fully heals as part of _finish_death()) — any trip back
			# to the hub means a clean slate.
			local_player.health = local_player.max_health
		SaveAndLoad.save_all()
	await get_tree().process_frame
	move_my_player_to_spawn(spawn_point)

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

func load_location_locally(zone: String, room: String, old_zone: String = "", old_room: String = ""):
	world_rooms.load_location_locally(zone, room, old_zone, old_room)

func is_valid_location(zone: String, room: String):
	return world_rooms.is_valid_location(zone, room)

func get_spawn_global_position(spawn_point: String) -> Vector2:
	return world_rooms.get_spawn_global_position(spawn_point)

func get_visible_ids_for(viewer_id: int) -> Array:
	var visible_ids := []
	# The server keeps simulating enemies in rooms it's holding for other peers
	# even when its own player isn't there (e.g. the host died and went to the
	# hub). Those enemies need the room's players ACTIVE (collision on) to detect
	# and fight them — so on the server, also count players in any room it has
	# loaded. They're at that room's world offset (off-screen from the server's
	# own view), so activating them causes no visual bleed.
	var server_simulates := viewer_id == multiplayer.get_unique_id() and multiplayer.is_server()
	for other_id in player_locations.keys():
		if can_players_see_each_other(viewer_id, other_id):
			visible_ids.append(other_id)
		elif server_simulates and server_has_players_room_loaded(other_id):
			visible_ids.append(other_id)
	return visible_ids

# True if the SERVER has loaded (is simulating) the room this peer is in — used
# so the host keeps that room's players/projectiles live for its enemies even
# while the host itself is elsewhere.
func server_has_players_room_loaded(peer_id: int) -> bool:
	if !multiplayer.is_server() or !player_locations.has(peer_id):
		return false
	var loc = player_locations[peer_id]
	return world_rooms.loaded_rooms.has("%s/%s" % [loc["zone"], loc["room"]])

func can_players_see_each_other(a: int, b: int):
	if !player_locations.has(a):
		return false
	if !player_locations.has(b):
		return false
	var loc_a = player_locations[a]
	var loc_b = player_locations[b]
	return loc_a["zone"] == loc_b["zone"] and loc_a["room"] == loc_b["room"]

# Peer ids whose current location matches room_key ("zone/room"). Used to scope
# room-local RPCs (e.g. exit-portal state) to peers that actually have the room.
func peers_in_room(room_key: String) -> Array:
	var ids := []
	for peer_id in player_locations.keys():
		var loc = player_locations[peer_id]
		if "%s/%s" % [loc["zone"], loc["room"]] == room_key:
			ids.append(peer_id)
	return ids

# --- Per-peer "room enemies spawned" handshake ----------------------------
# Called by enemy_spawner.gd on every peer once that room's enemies actually
# exist, so the server only begins replicating a room's enemies to a peer that
# can resolve them (see room_ready_peers' comment).
func notify_room_ready(room_key: String) -> void:
	if room_key == "":
		return
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_mark_room_ready(multiplayer.get_unique_id(), room_key)
	else:
		server_notify_room_ready.rpc(room_key)

@rpc("any_peer", "call_remote", "reliable")
func server_notify_room_ready(room_key: String) -> void:
	if !multiplayer.is_server():
		return
	_mark_room_ready(multiplayer.get_remote_sender_id(), room_key)

func _mark_room_ready(peer_id: int, room_key: String) -> void:
	if !room_ready_peers.has(room_key):
		room_ready_peers[room_key] = {}
	room_ready_peers[room_key][peer_id] = true
	# Now that this peer's copy of the room's enemies exists, (re)compute enemy
	# visibility so it starts receiving their sync.
	world_rooms.refresh_all_entity_visibility()

func peer_ready_in_room(peer_id: int, room_key: String) -> bool:
	return room_ready_peers.get(room_key, {}).has(peer_id)

# A peer changing rooms or disconnecting invalidates its readiness everywhere —
# it'll re-confirm after loading its next room.
func clear_peer_room_ready(peer_id: int) -> void:
	for room_key in room_ready_peers.keys():
		room_ready_peers[room_key].erase(peer_id)

@rpc("authority", "call_remote", "reliable")
func client_set_known_players(_known_ids):
	push_warning("client_set_known_players is deprecated")

@rpc("authority", "call_remote", "reliable")
func client_set_visible_players(_visible_ids):
	push_warning("client_set_visible_players is deprecated")

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
	await get_tree().process_frame
	if !players.has_node(str(peer_id)):
		return
	var player = players.get_node(str(peer_id))
	if my_zone == zone and my_room == room:
		var spawn_pos = get_spawn_global_position(spawn_point)
		player.global_position = spawn_pos
		player_initialized_positions[peer_id] = true
		current_visible_ids[peer_id] = true
		set_player_active(player, true)
	else:
		player_initialized_positions[peer_id] = false
		current_visible_ids.erase(peer_id)
		set_player_active(player, false)

func spawn_player_locally(peer_id: int):
	world_players.spawn_player_locally(peer_id)

func remove_player_locally(peer_id: int):
	world_players.remove_player_locally(peer_id)

func set_player_active(player: Node, active: bool):
	world_players.set_player_active(player, active)

func set_player_collision_active(player: Node, active: bool):
	world_players.set_player_collision_active(player, active)

func generate_player_cosmetics(peer_id: int):
	return world_players.generate_player_cosmetics(peer_id)

func broadcast_all_cosmetics():
	world_players.broadcast_all_cosmetics()

func request_player_cosmetics(peer_id: int):
	world_players.request_player_cosmetics(peer_id)

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
	var color: Color = cosmetics["color"]
	var player_name: String = cosmetics.get("name","")
	if player_name.strip_edges() == "":
		player_name = "Player %s" % peer_id
	player.get_node("name_label").modulate = color
	player.get_node("visual_root").modulate = color
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

# --- Expedition kit selection (host-driven, party-gated) ------------------
# Only the host activates an expedition door (see expedition_door.gd). Since
# only the host does this, it always runs server-side directly.
func request_begin_kit_selection(expedition_id: String):
	if !multiplayer.is_server():
		return
	world_expeditions.begin_kit_selection(expedition_id)

# Every peer opens its kit popup; the host's own call runs locally (call_local).
@rpc("authority", "call_local", "reliable")
func client_show_kit_prompt(expedition_id: String):
	var local_player = get_local_player()
	if local_player != null:
		local_player.prompt_expedition_kit(expedition_id)

# A player answered (picked Starter/Custom). Choice is applied locally at travel
# time; the server just needs to know they've committed.
func report_kit_answer():
	if multiplayer.is_server():
		world_expeditions.handle_kit_answer(multiplayer.get_unique_id())
	else:
		server_report_kit_answer.rpc()

@rpc("any_peer", "call_remote", "reliable")
func server_report_kit_answer():
	if !multiplayer.is_server():
		return
	world_expeditions.handle_kit_answer(multiplayer.get_remote_sender_id())

# Any player can cancel, which aborts the whole start for everyone.
func report_kit_cancel():
	if multiplayer.is_server():
		world_expeditions.handle_kit_cancel()
	else:
		server_report_kit_cancel.rpc()

@rpc("any_peer", "call_remote", "reliable")
func server_report_kit_cancel():
	if !multiplayer.is_server():
		return
	world_expeditions.handle_kit_cancel()

# Everyone's popup closes and their pending choice is discarded.
@rpc("authority", "call_local", "reliable")
func client_cancel_kit_prompt():
	var local_player = get_local_player()
	if local_player != null:
		local_player.hide_kit_prompt()

@rpc("authority", "call_local", "reliable")
func broadcast_expedition_seed(seed_value: int):
	# Every peer loads the same room scene independently with no networked
	# node spawning, so anything that needs to look "randomized" per
	# expedition (like enemy_spawner.gd's group rolls) has to derive from
	# this shared, server-picked seed instead of real per-peer randomness —
	# otherwise each peer would roll a different, mismatched layout.
	Stats.expedition_seed = seed_value
	# A new expedition is a new instance — clear out where enemies were
	# left in every room from the last one so this one starts fresh.
	Stats.expedition_room_state = {}

func launch_expedition(expedition_id: String):
	world_expeditions.launch_expedition(expedition_id)

func return_party_to_hub():
	world_expeditions.return_party_to_hub()

func get_local_player() -> Node:
	var my_id := multiplayer.get_unique_id()
	return players.get_node(str(my_id)) if players.has_node(str(my_id)) else null

func spawn_pool_loot(position: Vector2, pool_id: String, rolls_min: int, rolls_max: int, weapon_override: Dictionary) -> void:
	world_loot.roll_pool_loot(position, pool_id, rolls_min, rolls_max, weapon_override)

@rpc("authority", "call_local", "reliable")
func broadcast_loot_pickup_spawned(pickup_id: String, position: Vector2, inventory_dict: Dictionary) -> void:
	# This whole call chain originates from an Area2D's area_entered signal
	# (hitbox -> hurtbox -> take_damage -> die() -> here), which fires while
	# the physics server is still mid-flush of this frame's collision
	# queries — adding a new Area2D (the pickup) to the tree right now tries
	# to register its shapes with the physics server immediately and hits
	# "Can't change this state while flushing queries". Deferring the actual
	# spawn to the next idle frame sidesteps that entirely.
	_spawn_loot_pickup_deferred.call_deferred(pickup_id, position, inventory_dict)

func _spawn_loot_pickup_deferred(pickup_id: String, position: Vector2, inventory_dict: Dictionary) -> void:
	# (No hub gate: each location loads at its own world offset now, so an
	# expedition death bag broadcast to a peer already in the hub spawns far
	# off-screen at the expedition's coords rather than on top of them — while
	# legitimate hub drops still spawn normally at hub coords.)
	var pickup = preload("res://scenes/items/loot_pickup.tscn").instantiate()
	zone_objects.add_child(pickup)
	pickup.global_position = position
	pickup.setup(pickup_id, inventory_dict)

func request_claim_item(pickup_id: String, item_instance_id: String, destination: String = "inventory") -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_handle_claim_request(pickup_id, item_instance_id, multiplayer.get_unique_id(), destination)
	else:
		server_request_claim_item.rpc(pickup_id, item_instance_id, destination)

@rpc("any_peer", "call_remote", "reliable")
func server_request_claim_item(pickup_id: String, item_instance_id: String, destination: String = "inventory") -> void:
	if !multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_handle_claim_request(pickup_id, item_instance_id, sender_id, destination)

func _handle_claim_request(pickup_id: String, item_instance_id: String, claimer_id: int, destination: String = "inventory") -> void:
	var item: Item = world_loot.claim_item(pickup_id, item_instance_id)
	if item == null:
		return
	broadcast_item_claimed.rpc(pickup_id, item_instance_id, claimer_id, item.to_dict(), destination)

@rpc("authority", "call_local", "reliable")
func broadcast_item_claimed(pickup_id: String, item_instance_id: String, claimer_id: int, item_dict: Dictionary, destination: String = "inventory") -> void:
	for pickup in get_tree().get_nodes_in_group("loot_pickups"):
		if pickup.pickup_id == pickup_id:
			pickup.remove_item_locally(item_instance_id)
			break
	if claimer_id == multiplayer.get_unique_id() and players.has_node(str(claimer_id)):
		players.get_node(str(claimer_id)).receive_claimed_item(item_dict, destination)

func request_drop_item(position: Vector2, item_dict: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		world_loot.drop_item(position, item_dict)
	else:
		server_request_drop_item.rpc(position, item_dict)

@rpc("any_peer", "call_remote", "reliable")
func server_request_drop_item(position: Vector2, item_dict: Dictionary) -> void:
	if !multiplayer.is_server():
		return
	world_loot.drop_item(position, item_dict)

@rpc("authority", "call_local", "reliable")
func broadcast_item_added(pickup_id: String, item_dict: Dictionary) -> void:
	for pickup in get_tree().get_nodes_in_group("loot_pickups"):
		if pickup.pickup_id == pickup_id:
			pickup.add_item_locally(item_dict)
			break

func request_drop_death_bag(position: Vector2, items: Array) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		world_loot.drop_death_bag(position, items)
	else:
		server_request_drop_death_bag.rpc(position, items)

@rpc("any_peer", "call_remote", "reliable")
func server_request_drop_death_bag(position: Vector2, items: Array) -> void:
	if !multiplayer.is_server():
		return
	world_loot.drop_death_bag(position, items)

@rpc("any_peer", "unreliable")
func server_send_player_state(pos: Vector2, anim: String, rotation: float):
	if !multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	var server_id = multiplayer.get_unique_id()
	for viewer_id in player_locations.keys():
		if viewer_id == sender_id:
			continue
		if !can_players_see_each_other(viewer_id, sender_id):
			continue
		if viewer_id == server_id:
			client_receive_player_state(sender_id, pos, anim, rotation)
		else:
			client_receive_player_state.rpc_id(
				viewer_id,
				sender_id,
				pos,
				anim,
				rotation
			)

@rpc("authority", "unreliable")
func client_receive_player_state(peer_id: int, pos: Vector2, anim: String, rotation: float):
	if !players.has_node(str(peer_id)):
		return
	var player = players.get_node(str(peer_id))
	player.global_position = pos
	player.network_anim = anim
	player.network_rotation = rotation




#test area:
var sync_ready_peers := {}
var has_confirmed_sync_ready := false

@rpc("any_peer", "call_remote", "reliable")
func server_confirm_sync_ready():
	if !multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	sync_ready_peers[sender_id] = true
	refresh_visibility_for_all()

@rpc("authority", "call_remote", "reliable")
func client_refresh_players(known_ids, visible_ids, sync_ready_ids):
	for peer_id in known_ids:
		if !players.has_node(str(peer_id)):
			spawn_player_locally(peer_id)
	await get_tree().process_frame
	await get_tree().process_frame
	if multiplayer.is_server():
		world_players.update_all_synchronizer_visibility(sync_ready_ids)
	current_visible_ids.clear()
	var visible_lookup = {}
	for peer_id in visible_ids:
		visible_lookup[peer_id] = true
		current_visible_ids[peer_id] = true
	for child in players.get_children():
		var peer_id = int(child.name)
		var should_show = visible_lookup.has(peer_id) \
			and player_initialized_positions.get(peer_id, false)
		set_player_active(child, should_show)
	if !multiplayer.is_server() and !has_confirmed_sync_ready:
		has_confirmed_sync_ready = true
		server_confirm_sync_ready.rpc()

func refresh_visibility_for_all():
	if !multiplayer.is_server():
		return
	# A held-in-background room (see world_rooms.gd) whose last remaining
	# occupant just left has no reason to keep existing — free it before
	# recomputing who sees what, so the visibility pass below never wastes
	# work on a room about to disappear.
	world_rooms.cleanup_empty_held_rooms()
	world_rooms.refresh_all_entity_visibility()
	var known_ids = player_locations.keys()
	var sync_ready_ids = sync_ready_peers.keys()
	for viewer_id in player_locations.keys():
		var visible_ids = get_visible_ids_for(viewer_id)
		if viewer_id == multiplayer.get_unique_id():
			client_refresh_players(known_ids, visible_ids, sync_ready_ids)
		else:
			client_refresh_players.rpc_id(viewer_id, known_ids, visible_ids, sync_ready_ids)

@rpc("any_peer", "call_remote", "reliable")
func server_request_spawn_spell(origin_position: Vector2, direction: Vector2, weapon: String, element: String, form: String, is_crit: bool = false, rarity: String = "common") -> void:
	if !multiplayer.is_server():
		return
	var caster_id := multiplayer.get_remote_sender_id()
	if caster_id == 0:
		caster_id = multiplayer.get_unique_id()
	var server_id := multiplayer.get_unique_id()
	for viewer_id in player_locations.keys():
		var can_see: bool = can_players_see_each_other(viewer_id, caster_id)
		if viewer_id == server_id:
			# Also spawn on the server when it's simulating the caster's room but
			# its own player isn't there (host in hub) — otherwise the caster's
			# spell never exists on the authority and its enemies take no damage.
			if can_see or server_has_players_room_loaded(caster_id):
				client_spawn_spell(caster_id, origin_position, direction, weapon, element, form, is_crit, rarity)
		elif can_see:
			client_spawn_spell.rpc_id(viewer_id, caster_id, origin_position, direction, weapon, element, form, is_crit, rarity)

@rpc("authority", "call_remote", "reliable")
func client_spawn_spell(caster_id: int, origin_position: Vector2, direction: Vector2, weapon: String, element: String, form: String, is_crit: bool = false, rarity: String = "common") -> void:
	if !players.has_node(str(caster_id)):
		return
	var caster = players.get_node(str(caster_id))
	if caster.has_method("spawn_spell_local"):
		caster.spawn_spell_local(origin_position, direction, weapon, element, form, -1, is_crit, rarity)
