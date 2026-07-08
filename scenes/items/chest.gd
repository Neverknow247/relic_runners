extends Area2D
class_name Chest

# door.gd's interact pattern, adapted the same way loot_pickup.gd was:
# instead of an instant single-key action, it opens/closes a UI panel.
# Unlike a loot pile, the chest holds no data of its own at all — every
# player who opens it sees their own personal stash (player.stash_tabs),
# purely local, never networked. The chest itself is just an interaction
# trigger, not a container.

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
	local_player.open_stash_panel(self)

func _close_panel() -> void:
	panel_open = false
	var world = get_tree().get_first_node_in_group("world")
	if world == null:
		return
	var local_player = world.get_local_player()
	if local_player:
		local_player.close_stash_panel()
