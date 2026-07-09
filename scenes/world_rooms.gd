extends Node

var world

# room_key -> { "scene": Node, "floor": Node|null, "objects": Node|null }.
# Every room a peer has loaded lives here. Crucially, a room's `scene` node
# NEVER moves once added under world.zone_container — a "held" room (one the
# server has walked out of while another peer is still standing in it) is just
# made invisible in place, NOT reparented. That keeps its node path identical
# on every peer, which is mandatory: MultiplayerSynchronizer and every rpc()
# resolve nodes by path, so reparenting a room on the server alone (the old
# held_rooms wrapper approach) desynced enemy replication and made exit-portal
# activation RPCs fail to resolve for whoever was still inside. Hidden nodes
# keep running their process/physics/replication — visibility only affects
# rendering — so enemies keep patrolling and portal timers keep ticking for
# the remaining occupant, exactly as intended.
var loaded_rooms: Dictionary = {}
# The room currently shown as THIS peer's own view. "" when nothing is loaded.
var active_key: String = ""

func setup(_world):
	world = _world

func load_location_locally(zone: String, room: String, _old_zone: String = "", _old_room: String = ""):
	# Ground-loot piles live under zone_objects (world-level, not inside a room
	# scene) and sync by pickup_id, not node path — so unlike enemies/portals
	# they're safe to free freely. Clear this peer's own pile view on every room
	# change, matching the old blanket zone_objects free; the server-side model
	# (world_loot.active_pickups) persists, and other peers' views are their own.
	_clear_local_loot_pickups()
	_deactivate_current()
	var key = "%s/%s" % [zone, room]
	if loaded_rooms.has(key):
		# Re-entering a room that stayed alive in the background (another peer
		# never left, or the server held it) — reveal the exact same live
		# instance rather than reloading fresh.
		_show_room(key)
		active_key = key
		return
	if !world.ZONE_SCENES.has(key):
		active_key = ""
		return
	var packed_scene = load(world.ZONE_SCENES[key])
	var scene_instance = packed_scene.instantiate()
	# Set before add_child() (i.e. before _ready() runs) so enemy_spawner.gd
	# knows which room it is and can restore this room's saved state.
	var new_enemies = scene_instance.get_node_or_null("enemies")
	if new_enemies and "room_key" in new_enemies:
		new_enemies.room_key = key
	# Same idea for portal_group.gd -- it needs a room-unique seed
	# component to pick the same arrival portal on every peer.
	var portals = scene_instance.get_node_or_null("doors/portals")
	if portals and "room_key" in portals:
		portals.room_key = key
	world.zone_container.add_child(scene_instance)
	# floor_tiles / y_sort_objects get pulled out into the shared floor/object
	# containers for correct render ordering; we keep references so a held room
	# can hide (and later re-show) its own extracted pieces, and freeing a room
	# frees exactly its own.
	var floor_node = null
	var _floor = scene_instance.get_node_or_null("floor_tiles")
	if _floor:
		scene_instance.remove_child(_floor)
		world.floor_container.add_child(_floor)
		floor_node = _floor
	var objects_node = null
	var objects = scene_instance.get_node_or_null("y_sort_objects")
	if objects:
		scene_instance.remove_child(objects)
		world.zone_objects.add_child(objects)
		objects_node = objects
	# Each location loads at its own distinct world offset (deterministic per
	# key, identical on every peer) so different rooms never overlap in world
	# space. This is what stops a held room's walls (kept in place by design so
	# node paths stay stable) from colliding with whatever room you're actually
	# standing in — e.g. a held dungeon's walls bleeding into the hub as
	# invisible collision. Everything downstream (spawn points, enemy/loot/
	# player positions) uses global coordinates, so the offset is transparent
	# and stays consistent across peers.
	var offset := _location_offset(key)
	scene_instance.position += offset
	if floor_node:
		floor_node.position += offset
	if objects_node:
		objects_node.position += offset
	loaded_rooms[key] = {"scene": scene_instance, "floor": floor_node, "objects": objects_node}
	active_key = key

const LOCATION_SPACING := 100000.0

func _location_offset(key: String) -> Vector2:
	var idx: int = world.ZONE_SCENES.keys().find(key)
	if idx < 0:
		idx = 0
	return Vector2(0, idx * LOCATION_SPACING)

# Hides (server, someone else still there) or frees (everyone else) the room
# currently shown as this peer's view, before a new one replaces it. Clients
# never hold — their local copy is purely visual — so they always free and
# thus never accumulate more than one loaded room.
func _deactivate_current() -> void:
	if active_key == "" or !loaded_rooms.has(active_key):
		active_key = ""
		return
	if world.multiplayer.is_server() and _room_still_occupied(active_key):
		_hide_room(active_key)
	else:
		_free_room(active_key)
	active_key = ""

# True if any OTHER connected peer's current location still matches room_key.
# Safe to call once the server's own player_locations entry has already been
# updated to its NEW location (server_change_player_location always does that
# before load_location_locally runs) — so the server's own departure doesn't
# count as "occupied".
func _room_still_occupied(room_key: String) -> bool:
	for loc in world.player_locations.values():
		if "%s/%s" % [loc["zone"], loc["room"]] == room_key:
			return true
	return false

func _clear_local_loot_pickups() -> void:
	for pickup in world.get_tree().get_nodes_in_group("loot_pickups"):
		pickup.queue_free()

func _hide_room(room_key: String) -> void:
	_set_room_visible(room_key, false)

func _show_room(room_key: String) -> void:
	_set_room_visible(room_key, true)

func _set_room_visible(room_key: String, vis: bool) -> void:
	var entry = loaded_rooms.get(room_key)
	if entry == null:
		return
	for part in ["scene", "floor", "objects"]:
		var node = entry[part]
		if node != null and is_instance_valid(node):
			node.visible = vis

# Snapshots this room's enemies (who died / where survivors ended up) so a
# later revisit can restore it, then frees the scene plus its extracted floor/
# objects and drops it from tracking.
func _free_room(room_key: String) -> void:
	var entry = loaded_rooms.get(room_key)
	if entry == null:
		return
	var scene = entry["scene"]
	if scene != null and is_instance_valid(scene):
		var old_enemies = scene.get_node_or_null("enemies")
		if old_enemies and old_enemies.has_method("save_state"):
			old_enemies.save_state()
		scene.queue_free()
	for part in ["floor", "objects"]:
		var node = entry[part]
		if node != null and is_instance_valid(node):
			node.queue_free()
	loaded_rooms.erase(room_key)

# Frees every held (non-active) room whose last occupant has left. Called after
# each location change/disconnect (see world.gd's refresh_visibility_for_all).
func cleanup_empty_held_rooms() -> void:
	if !world.multiplayer.is_server():
		return
	for room_key in loaded_rooms.keys().duplicate():
		if room_key == active_key:
			continue
		if !_room_still_occupied(room_key):
			_free_room(room_key)

# Force-frees every held (non-active) room — used when a whole expedition ends
# (launch_expedition()/return_party_to_hub()), so a stale backgrounded room
# never leaks into the next run. The active room is left alone; the location
# change that follows replaces it normally.
func clear_held_rooms() -> void:
	for room_key in loaded_rooms.keys().duplicate():
		if room_key == active_key:
			continue
		_free_room(room_key)

# Full reset — frees active + held rooms and clears tracking. For world
# teardown (disconnect/shutdown).
func free_all_rooms() -> void:
	for room_key in loaded_rooms.keys().duplicate():
		_free_room(room_key)
	loaded_rooms.clear()
	active_key = ""

# Recomputes which connected peers each loaded room's enemies replicate to —
# covers both this peer's own active room and every held room, since a held
# room's remaining occupant(s) still need live enemy sync.
func refresh_all_entity_visibility() -> void:
	if !world.multiplayer.is_server():
		return
	for room_key in loaded_rooms.keys():
		var scene = loaded_rooms[room_key]["scene"]
		if scene != null and is_instance_valid(scene):
			_refresh_room_entity_visibility(scene, room_key)

func _refresh_room_entity_visibility(scene_instance: Node, room_key: String) -> void:
	var enemies_node = scene_instance.get_node_or_null("enemies")
	if enemies_node == null:
		return
	var occupant_ids := []
	for peer_id in world.player_locations.keys():
		var loc = world.player_locations[peer_id]
		if "%s/%s" % [loc["zone"], loc["room"]] == room_key:
			occupant_ids.append(peer_id)
	var connected_peers = world.multiplayer.get_peers()
	for enemy in enemies_node.get_children():
		var sync = enemy.get_node_or_null("multiplayer_synchronizer")
		if sync == null:
			continue
		sync.public_visibility = false
		for connected_id in connected_peers:
			sync.set_visibility_for(connected_id, false)
		for peer_id in occupant_ids:
			# Only replicate to a peer that has confirmed its own copy of this
			# room's enemies exists — otherwise its client would get sync for
			# nodes it hasn't spawned yet (see world.gd's room_ready_peers).
			if connected_peers.has(peer_id) and world.peer_ready_in_room(peer_id, room_key):
				sync.set_visibility_for(peer_id, true)
		sync.update_visibility()

func is_valid_location(zone: String, room: String):
	var key = "%s/%s" % [zone, room]
	return world.ZONE_SCENES.has(key)

func get_spawn_global_position(spawn_point: String) -> Vector2:
	var current_zone = null
	if active_key != "" and loaded_rooms.has(active_key):
		current_zone = loaded_rooms[active_key]["scene"]
	if spawn_point == "random_portal":
		if current_zone != null:
			var portals = current_zone.get_node_or_null("doors/portals")
			if portals and portals.has_method("get_spawn_global_position"):
				return portals.get_spawn_global_position()
		print("No doors/portals group found for random_portal spawn")
		return Vector2(100, 100)
	var spawn_path = "spawn_points/%s" % spawn_point
	if current_zone != null and current_zone.has_node(spawn_path):
		return current_zone.get_node(spawn_path).global_position
	print("Missing spawn point: ", spawn_path)
	return Vector2(100, 100)
