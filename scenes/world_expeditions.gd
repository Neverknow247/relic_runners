extends Node

var world

func setup(_world):
	world = _world


# --- Host-driven, party-gated kit selection -------------------------------
# The host opened an expedition door. Put a kit popup up on every player and
# wait for all of them to answer before the party actually travels; any single
# player's cancel aborts the whole thing (see handle_kit_cancel). Server-only.
func begin_kit_selection(expedition_id: String):
	if world.party_state != world.PartyState.HUB:
		return
	if !world.EXPEDITION_TARGETS.has(expedition_id):
		return
	world.party_state = world.PartyState.KIT_SELECTION
	world.pending_kit_expedition_id = expedition_id
	# Snapshot who must answer right now — joins mid-selection aren't added,
	# leaves are removed (see handle_kit_peer_left).
	world.kit_expected_peers = world.player_locations.keys().duplicate()
	world.kit_answers.clear()
	world.client_show_kit_prompt.rpc(expedition_id)

func handle_kit_answer(peer_id: int):
	if world.party_state != world.PartyState.KIT_SELECTION:
		return
	world.kit_answers[peer_id] = true
	_launch_if_all_answered()

func handle_kit_cancel():
	if world.party_state != world.PartyState.KIT_SELECTION:
		return
	world.party_state = world.PartyState.HUB
	_reset_kit_state()
	world.client_cancel_kit_prompt.rpc()

func handle_kit_peer_left(peer_id: int):
	if world.party_state != world.PartyState.KIT_SELECTION:
		return
	world.kit_expected_peers.erase(peer_id)
	world.kit_answers.erase(peer_id)
	if world.kit_expected_peers.is_empty():
		# Nobody left to answer — abort back to hub.
		world.party_state = world.PartyState.HUB
		_reset_kit_state()
		world.client_cancel_kit_prompt.rpc()
		return
	_launch_if_all_answered()

func _launch_if_all_answered():
	for peer_id in world.kit_expected_peers:
		if !world.kit_answers.has(peer_id):
			return
	var expedition_id: String = world.pending_kit_expedition_id
	_reset_kit_state()
	launch_expedition(expedition_id)

func _reset_kit_state():
	world.pending_kit_expedition_id = ""
	world.kit_expected_peers = []
	world.kit_answers.clear()


func launch_expedition(expedition_id: String):
	if !world.multiplayer.is_server():
		return

	var target = world.EXPEDITION_TARGETS[expedition_id]

	world.party_state = world.PartyState.EXPEDITION
	world.expedition_zone = target["zone"]
	world.expedition_room = target["room"]
	world.world_loot.clear_active_pickups()
	world.world_rooms.clear_held_rooms()
	# Everyone's about to reload into fresh rooms — drop all stale enemy-ready
	# confirmations; each peer re-confirms per room as it loads.
	world.room_ready_peers.clear()

	# Fresh seed every launch so the room's enemy layout (enemy_spawner.gd)
	# is actually different each time, not just different-per-room. Sent
	# before the location-change RPCs below so it lands before any peer's
	# copy of the room scene finishes loading and reads it.
	world.broadcast_expedition_seed.rpc(randi())

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
	world.world_loot.clear_active_pickups()
	world.world_rooms.clear_held_rooms()
	world.room_ready_peers.clear()

	for peer_id in world.player_locations.keys():
		world.server_change_player_location(peer_id, "hub", "main", "default")

	world.refresh_visibility_for_all()


# Players now trickle back individually through an exit_portal rather than
# the whole party being force-teleported at once, so nothing was ever
# resetting party_state back to HUB once the last one left — it stayed
# stuck at EXPEDITION forever, permanently blocking start_expedition_
# countdown()'s "must be in HUB" guard from ever passing again. Called
# (server-only, see world.gd's server_change_player_location) after every
# individual location change; once nobody's left in the expedition zone,
# the expedition is effectively over even though nobody explicitly ended it.
func check_expedition_still_active() -> void:
	if world.party_state != world.PartyState.EXPEDITION:
		return
	for loc in world.player_locations.values():
		if loc["zone"] != "hub":
			return
	world.party_state = world.PartyState.HUB
	world.expedition_zone = "hub"
	world.expedition_room = "main"
	world.world_loot.clear_active_pickups()
