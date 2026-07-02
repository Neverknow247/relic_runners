extends Node

var world

func setup(_world):
	world = _world

func load_location_locally(zone: String, room: String):
	for child in world.zone_container.get_children():
		world.zone_container.remove_child(child)
		child.queue_free()
	for child in world.floor_container.get_children():
		world.floor_container.remove_child(child)
		child.queue_free()
	for child in world.zone_objects.get_children():
		world.zone_objects.remove_child(child)
		child.queue_free()
	var key = "%s/%s" % [zone, room]
	if !world.ZONE_SCENES.has(key):
		return
	var packed_scene = load(world.ZONE_SCENES[key])
	var scene_instance = packed_scene.instantiate()
	world.zone_container.add_child(scene_instance)
	var _floor = scene_instance.get_node_or_null("floor_tiles")
	if _floor:
		scene_instance.remove_child(_floor)
		world.floor_container.add_child(_floor)
	var objects = scene_instance.get_node_or_null("y_sort_objects")
	if objects:
		scene_instance.remove_child(objects)
		world.zone_objects.add_child(objects)

func is_valid_location(zone: String, room: String):
	var key = "%s/%s" % [zone, room]
	return world.ZONE_SCENES.has(key)

func get_spawn_global_position(spawn_point: String) -> Vector2:
	var spawn_path = "spawn_points/%s" % spawn_point
	if world.zone_container.get_child_count() > 0:
		var current_zone = world.zone_container.get_child(0)
		if current_zone.has_node(spawn_path):
			return current_zone.get_node(spawn_path).global_position
	print("Missing spawn point: ", spawn_path)
	return Vector2(100, 100)
