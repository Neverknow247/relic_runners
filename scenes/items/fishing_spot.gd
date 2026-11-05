extends Area2D
class_name FishingSpot

# Hand-placed fishing spot. Server-authoritative (Godot default authority =
# peer 1), same shape as loot_container.gd, but REUSABLE — no per-expedition
# lock, just a short cooldown between casts. Flow:
#   1. A player standing here with a Fishing Rod in hand presses interact.
#   2. Server rolls the pending catch and tells that player its rarity.
#   3. That player runs the reel minigame (rarer catch = harder — fishing_ui.gd).
#   4. On a landed reel the server spawns that exact catch as a ground pile here;
#      a miss lets it get away.
# spot_type keys into ItemData.FISHING_SPOTS for its label/color/loot pool.

@export var spot_type := "pond"

const COOLDOWN := 0.8

# Local (interacting-client) state: whether a cast is in progress here and a
# brief lockout after one resolves, so a single spot can't be spammed.
var can_use := false
var _busy := false
var _cooldown := 0.0

# Server state: peer_id -> {"type": String, "qty": int}, the catch rolled at the
# bite and awarded (or lost) when that peer's reel resolves.
var _pending: Dictionary = {}

@onready var color_rect: ColorRect = $visual_root/color_rect
@onready var status_label: Label = $visual_root/status_label

func _ready() -> void:
	_update_visual()

func _on_body_entered(body: Node) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if body.is_multiplayer_authority():
		can_use = true

func _on_body_exited(body: Node) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if body.is_multiplayer_authority():
		can_use = false

func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	if !can_use:
		return
	var has_rod := _local_has_rod()
	status_label.text = _label() if has_rod else "%s\n(needs Fishing Rod)" % _label()
	if _busy or _cooldown > 0.0 or !has_rod:
		return
	if Input.is_action_just_pressed("interact"):
		_start_fishing()

func _label() -> String:
	return ItemData.FISHING_SPOTS.get(spot_type, {}).get("display_name", "Fishing Spot")

func _local_has_rod() -> bool:
	var world = get_tree().get_first_node_in_group("world")
	if world == null:
		return false
	var lp = world.get_local_player()
	return lp != null and lp.has_fishing_rod_equipped()

# --- Cast → bite ----------------------------------------------------------
func _start_fishing() -> void:
	_busy = true
	if is_multiplayer_authority():
		_server_begin_bite(multiplayer.get_unique_id())
	else:
		server_request_bite.rpc()

@rpc("any_peer", "call_remote", "reliable")
func server_request_bite() -> void:
	if !is_multiplayer_authority():
		return
	_server_begin_bite(multiplayer.get_remote_sender_id())

# Server: roll this peer's pending catch and hand them its rarity so their reel
# minigame can scale difficulty. An empty pool just releases the client.
func _server_begin_bite(peer: int) -> void:
	var world = get_tree().get_first_node_in_group("world")
	if world == null:
		return
	var catch: Dictionary = world.roll_fishing_catch(spot_type)
	if catch.is_empty():
		if peer == multiplayer.get_unique_id():
			_release()
		else:
			_release.rpc_id(peer)
		return
	var qty_range: Array = ItemData.get_drop_qty(catch["type"])
	var qty: int = max(world.rng.randi_range(qty_range[0], qty_range[1]), 1)
	_pending[peer] = {"type": catch["type"], "qty": qty}
	if peer == multiplayer.get_unique_id():
		deliver_bite(catch["rarity"])
	else:
		deliver_bite.rpc_id(peer, catch["rarity"])

# Runs on the requesting client — kick off its reel minigame.
@rpc("authority", "call_remote", "reliable")
func deliver_bite(rarity_index: int) -> void:
	var world = get_tree().get_first_node_in_group("world")
	var lp = world.get_local_player() if world else null
	if lp == null or lp.fishing_ui == null:
		_on_minigame_result(false)
		return
	lp.fishing_ui.begin(rarity_index, Callable(self, "_on_minigame_result"))

# Bite couldn't be produced — just clear the client's busy state.
@rpc("authority", "call_remote", "reliable")
func _release() -> void:
	_busy = false
	_cooldown = COOLDOWN

# --- Reel → award ---------------------------------------------------------
# Runs on the requesting client when the minigame ends.
func _on_minigame_result(success: bool) -> void:
	_busy = false
	_cooldown = COOLDOWN
	if is_multiplayer_authority():
		_server_finish_reel(multiplayer.get_unique_id(), success)
	else:
		server_reel.rpc(success)

@rpc("any_peer", "call_remote", "reliable")
func server_reel(success: bool) -> void:
	if !is_multiplayer_authority():
		return
	_server_finish_reel(multiplayer.get_remote_sender_id(), success)

func _server_finish_reel(peer: int, success: bool) -> void:
	var data: Dictionary = _pending.get(peer, {})
	_pending.erase(peer)
	if !success or data.is_empty():
		return
	var world = get_tree().get_first_node_in_group("world")
	if world:
		world.spawn_fished_item(global_position, data["type"], data["qty"])

func _update_visual() -> void:
	var def: Dictionary = ItemData.FISHING_SPOTS.get(spot_type, {})
	color_rect.color = def.get("color", Color(0.35, 0.55, 0.7))
	status_label.text = def.get("display_name", "Fishing Spot")
