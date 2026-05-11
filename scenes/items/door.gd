extends Area2D

@export var target_zone := "hub"
@export var target_room := "main"
@export var target_spawn := "default"

var can_use := false

func _on_body_entered(body):
	if body.is_multiplayer_authority():
		can_use = true

func _on_body_exited(body):
	if body.is_multiplayer_authority():
		can_use = false

func _process(_delta):
	if !can_use:
		return

	if Input.is_action_just_pressed("interact"):
		var world = get_tree().get_first_node_in_group("world")

		if world:
			world.request_location_changes(
				target_zone,
				target_room,
				target_spawn
			)
