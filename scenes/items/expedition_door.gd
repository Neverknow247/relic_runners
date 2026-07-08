extends Area2D

@export var expedition_id := "dungeon"

var can_use := false

func _process(_delta):
	if !can_use:
		return
	if Input.is_action_just_pressed("interact"):
		var world = get_tree().get_first_node_in_group("world")
		if world == null:
			return
		# Only the host opens an expedition door. Doing so puts the kit popup up
		# on every player; the party travels once all have answered (see
		# world_expeditions.gd's kit-selection flow). A non-host pressing this
		# does nothing.
		if !world.multiplayer.is_server():
			return
		var local_player = world.get_local_player()
		if local_player == null or !local_player.is_alive():
			return
		# Blocked while the host's overflow chest holds anything — clear it (so
		# those items aren't left behind) before starting. See player.gd's
		# overflow container.
		if local_player.overflow_has_items():
			return
		world.request_begin_kit_selection(expedition_id)

func _on_body_entered(body):
	if body.is_multiplayer_authority():
		can_use = true

func _on_body_exited(body):
	if body.is_multiplayer_authority():
		can_use = false
