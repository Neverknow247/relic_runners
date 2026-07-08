extends Area2D
class_name LootPickup

# door.gd's interact pattern, adapted for a consumable/shared world object:
# a door just toggles can_use, but a loot pile also needs to open/close a
# transfer UI panel (not an instant single-keypress collect — see the
# inventory plan) and to disappear identically for every peer once claimed,
# not just locally.

var pickup_id := ""
# Local display mirror of the pile's server-tracked contents — updated by
# world.gd's broadcast_item_claimed whenever anyone (including us) claims
# something from it.
var inventory: Inventory
var can_use := false
var panel_open := false

func setup(_pickup_id: String, inventory_dict: Dictionary) -> void:
	pickup_id = _pickup_id
	inventory = Inventory.from_dict(inventory_dict)
	add_to_group("loot_pickups")

func _on_body_entered(body: Node) -> void:
	# Guard against the multiplayer peer being gone: during teardown (esc-menu
	# Leave / death penalty) bodies exit areas while the peer is being torn
	# down, and is_multiplayer_authority() calls get_unique_id(), which errors
	# with no peer assigned.
	if multiplayer.multiplayer_peer == null:
		return
	if body.is_multiplayer_authority():
		can_use = true

func _on_body_exited(body: Node) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if body.is_multiplayer_authority():
		can_use = false
		if panel_open:
			_close_panel()

func _process(_delta: float) -> void:
	if !can_use:
		return
	if Input.is_action_just_pressed("interact"):
		if panel_open:
			_close_panel()
		else:
			_open_panel()

func _open_panel() -> void:
	var world = get_tree().get_first_node_in_group("world")
	if world == null:
		return
	var local_player = world.get_local_player()
	if local_player == null or !local_player.is_alive():
		return
	panel_open = true
	local_player.open_loot_panel(self)

func _close_panel() -> void:
	panel_open = false
	var world = get_tree().get_first_node_in_group("world")
	if world == null:
		return
	var local_player = world.get_local_player()
	if local_player:
		local_player.close_loot_panel()

# Called by world.gd's broadcast_item_claimed on every peer, including
# whoever didn't win the claim, so the pile stays visually in sync for
# everyone looking at it.
func remove_item_locally(item_instance_id: String) -> void:
	if inventory == null:
		return
	inventory.remove_item(item_instance_id)
	_refresh_open_panel()
	if inventory.placements.is_empty():
		if panel_open:
			_close_panel()
		queue_free()

# Called by world.gd's broadcast_item_added on every peer whenever a player
# drops something that merges into this pile, so it stays in sync even for
# peers who never touched the drop themselves.
func add_item_locally(item_dict: Dictionary) -> void:
	if inventory == null:
		return
	inventory.try_stack_or_place(Item.from_dict(item_dict))
	_refresh_open_panel()

func _refresh_open_panel() -> void:
	if !panel_open:
		return
	var world = get_tree().get_first_node_in_group("world")
	var local_player = world.get_local_player() if world else null
	if local_player and local_player.inventory_ui.loot_grid.container_id == pickup_id:
		local_player.inventory_ui.refresh()
