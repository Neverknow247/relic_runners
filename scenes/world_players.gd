extends Node

var world

func setup(_world):
	world = _world

func generate_player_cosmetics(peer_id: int):
	var sprite_index = world.rng.randi_range(0, world.PLAYER_SPRITES.size() - 1)
	var color = Color(
		world.rng.randf_range(0.6, 1),
		world.rng.randf_range(0.6, 1),
		world.rng.randf_range(0.6, 1),
		1
	)
	var player_name = world.player_steam_names.get(peer_id, "Player %s" % peer_id)
	return {
		"sprite_index": sprite_index,
		"color": color,
		"name": player_name,
	}

func broadcast_all_cosmetics():
	if !world.multiplayer.is_server():
		return
	for viewer_id in world.player_locations.keys():
		for target_id in world.player_cosmetics.keys():
			if viewer_id == world.multiplayer.get_unique_id():
				world.client_apply_player_cosmetics(target_id, world.player_cosmetics[target_id])
			else:
				world.client_apply_player_cosmetics.rpc_id(
					viewer_id,
					target_id,
					world.player_cosmetics[target_id]
				)

func request_player_cosmetics(peer_id: int):
	if world.multiplayer.is_server():
		if world.player_cosmetics.has(peer_id):
			world.client_apply_player_cosmetics(peer_id, world.player_cosmetics[peer_id])
		return
	if !world.can_send_rpc():
		return
	world.server_request_player_cosmetics.rpc(peer_id)

func apply_player_cosmetics(peer_id: int, cosmetics: Dictionary) -> void:
	if !world.players.has_node(str(peer_id)):
		return
	var player = world.players.get_node(str(peer_id))
	var sprite_index: int = cosmetics["sprite_index"]
	var color: Color = cosmetics["color"]
	var player_name: String = cosmetics.get("name", "")
	if player_name.strip_edges() == "":
		player_name = "Player %s" % peer_id
	player.get_node("visual_root/sprite").texture = world.PLAYER_SPRITES[sprite_index]
	player.get_node("name_label").modulate = color
	var label = player.get_node("name_label")
	if label:
		label.text = player_name
		label.z_index = 100
	else:
		print("Missing name label on player: ", peer_id)
	if peer_id == world.multiplayer.get_unique_id():
		world.player_initialized_positions[peer_id] = true
		world.current_visible_ids[peer_id] = true
		world.set_player_active(player, true)

func spawn_player_locally(peer_id: int) -> void:
	if world.players.has_node(str(peer_id)):
		return
	var player = world.PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id, false)
	world.players.add_child(player)
	call_deferred("_finish_spawn_player_locally", peer_id)

func _finish_spawn_player_locally(peer_id: int) -> void:
	if !world.players.has_node(str(peer_id)):
		return
	var player = world.players.get_node(str(peer_id))
	# Only hide if this player has not already been placed.
	if !world.player_initialized_positions.get(peer_id, false):
		set_player_active(player, false)
	var sync = player.get_node_or_null("multiplayer_synchronizer")
	if sync:
		sync.root_path = NodePath("..")
		sync.set_multiplayer_authority(peer_id)
		# Do NOT make this true immediately during spawn.
		# Let update_all_synchronizer_visibility handle it.
		sync.public_visibility = false
	world.request_player_cosmetics(peer_id)

func remove_player_locally(peer_id: int):
	var node_name = str(peer_id)
	if world.players.has_node(node_name):
		world.players.get_node(node_name).queue_free()

func update_all_synchronizer_visibility(peer_ids: Array) -> void:
	for player in world.players.get_children():
		var sync = player.get_node_or_null("multiplayer_synchronizer")
		if sync == null:
			continue
		sync.public_visibility = true
		for peer_id in peer_ids:
			sync.set_visibility_for(peer_id, true)
		sync.set_visibility_for(world.multiplayer.get_unique_id(), true)
		sync.update_visibility()

func set_player_active(player: Node, active: bool):
	var visual_root = player.get_node_or_null("visual_root")
	if visual_root:
		visual_root.visible = active
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
