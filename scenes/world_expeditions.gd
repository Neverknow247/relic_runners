extends Node

var world

func setup(_world):
	world = _world


func request_start_expedition(expedition_id: String):
	if !world.multiplayer.is_server():
		world.server_request_start_expedition.rpc(expedition_id)
		return

	start_expedition_countdown(expedition_id)


func start_expedition_countdown(expedition_id: String):
	if world.party_state != world.PartyState.HUB:
		return
	if !world.EXPEDITION_TARGETS.has(expedition_id):
		return

	world.party_state = world.PartyState.COUNTDOWN

	var target = world.EXPEDITION_TARGETS[expedition_id]
	world.expedition_zone = target["zone"]
	world.expedition_room = target["room"]

	world.broadcast_countdown_started.rpc(expedition_id, world.expedition_countdown_time)

	await get_tree().create_timer(world.expedition_countdown_time).timeout

	if world.party_state != world.PartyState.COUNTDOWN:
		return

	launch_expedition(expedition_id)


func launch_expedition(expedition_id: String):
	if !world.multiplayer.is_server():
		return

	var target = world.EXPEDITION_TARGETS[expedition_id]

	world.party_state = world.PartyState.EXPEDITION
	world.expedition_zone = target["zone"]
	world.expedition_room = target["room"]

	for peer_id in world.player_locations.keys():
		world.server_change_player_location(
			peer_id,
			target["zone"],
			target["room"],
			target["spawn"]
		)

	world.refresh_visibility_for_all()


func return_party_to_hub():
	if !world.multiplayer.is_server():
		return

	world.party_state = world.PartyState.HUB
	world.expedition_zone = "hub"
	world.expedition_room = "main"

	for peer_id in world.player_locations.keys():
		world.server_change_player_location(peer_id, "hub", "main", "default")

	world.refresh_visibility_for_all()
