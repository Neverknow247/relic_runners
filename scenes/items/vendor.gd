extends Area2D
class_name VendorStation

# Hub vendor: interact to open/close the buy/sell panel (ui/vendor_ui.gd, owned by
# the local player). Purely local, like the crafting bench: gold and items are
# per-player save data.

var can_use := false

func _on_body_entered(body: Node) -> void:
	if body.is_multiplayer_authority():
		can_use = true

func _on_body_exited(body: Node) -> void:
	if body.is_multiplayer_authority():
		can_use = false
		var lp = _local_player()
		if lp != null and lp.vendor_ui != null:
			lp.vendor_ui.close_panel()

func _process(_delta: float) -> void:
	if !can_use or !Input.is_action_just_pressed("interact"):
		return
	var lp = _local_player()
	if lp == null or !lp.is_alive() or lp.vendor_ui == null:
		return
	if lp.vendor_ui.is_open():
		lp.vendor_ui.close_panel()
	else:
		lp.vendor_ui.open_panel()

func _local_player():
	var world = get_tree().get_first_node_in_group("world")
	return world.get_local_player() if world != null else null
