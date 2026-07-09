extends Area2D
class_name CraftingBench

# Hub interactable, same shape as weapon_workbench.gd: interacting opens/closes
# the crafting panel (turn recipe ingredients into their output). Purely local —
# inventory/materials are per-player save data, so nothing here is networked.

var can_use := false
var panel_open := false

func _on_body_entered(body: Node) -> void:
	if body.is_multiplayer_authority():
		can_use = true

func _on_body_exited(body: Node) -> void:
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
	local_player.open_crafting_panel(self)

func _close_panel() -> void:
	panel_open = false
	var world = get_tree().get_first_node_in_group("world")
	if world == null:
		return
	var local_player = world.get_local_player()
	if local_player:
		local_player.close_crafting_panel()
