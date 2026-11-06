extends Node2D

# Dev-only nav probe: drops simple path-following bodies (enemy-sized, radius 48,
# wall mask) on random painted nav cells, sends each to a random far cell, and
# reports how many arrive vs get stuck. Isolates navmesh geometry from AI logic.
#   godot --headless --path . res://delete_before_export/nav_probe.tscn -- <level> <mode> [postprocess]
# mode: old (per-cell tiles) | r<N> (merged mesh, agent radius N)

var _agents: Array = []
var _goals: Array = []
var _last: Array = []
var _stuck_time: Array = []
var _reached: Array = []
var _t := 0.0
var SIM := float(OS.get_environment("SIM")) if OS.get_environment("SIM") != "" else 40.0
const SPEED := 600.0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var level := String(args[0]) if args.size() > 0 else "dungeon"
	var mode := String(args[1]) if args.size() > 1 else "old"
	var post := int(args[2]) if args.size() > 2 else 1
	var pdd := float(args[3]) if args.size() > 3 else 192.0
	var room: Node = load("res://scenes/levels/%s/%s_main.tscn" % [level, level]).instantiate()
	var spawner := room.get_node_or_null("enemies")
	if spawner != null:
		spawner.set_script(null)
	var nav: TileMapLayer = room.get_node("navigation/nav_1")
	var region: NavigationRegion2D = nav.get_node_or_null("nav_mesh")
	if mode == "old":
		nav.navigation_enabled = true
		if region:
			region.free()
	elif mode.begins_with("r"):
		region.navigation_polygon = NavMeshBuilder.build(nav, float(mode.substr(1)))
	add_child(room)
	var cells := nav.get_used_cells()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in 60:
		var a := CharacterBody2D.new()
		a.collision_layer = 0
		a.collision_mask = 1
		a.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
		var cs := CollisionShape2D.new()
		var c := CircleShape2D.new()
		c.radius = 48.0
		cs.shape = c
		a.add_child(cs)
		var ag := NavigationAgent2D.new()
		ag.name = "ag"
		ag.path_desired_distance = pdd
		ag.target_desired_distance = 64.0
		ag.path_postprocessing = post
		a.add_child(ag)
		add_child(a)
		var s: Vector2i = cells[rng.randi() % cells.size()]
		var g: Vector2i = cells[rng.randi() % cells.size()]
		while Vector2(g - s).length() < 12:
			g = cells[rng.randi() % cells.size()]
		a.global_position = nav.to_global(nav.map_to_local(s))
		_agents.append(a)
		_goals.append(nav.to_global(nav.map_to_local(g)))
		_last.append(a.global_position)
		_stuck_time.append(0.0)
		_reached.append(-1.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for i in _agents.size():
		_agents[i].get_node("ag").target_position = _goals[i]

func _physics_process(delta: float) -> void:
	if _agents.is_empty():
		return
	_t += delta
	for i in _agents.size():
		var a: CharacterBody2D = _agents[i]
		if _reached[i] >= 0.0:
			continue
		var ag: NavigationAgent2D = a.get_node("ag")
		if a.global_position.distance_to(_goals[i]) < 200.0:
			_reached[i] = _t
			a.velocity = Vector2.ZERO
			continue
		if ag.is_navigation_finished():
			a.velocity = Vector2.ZERO
		else:
			a.velocity = a.global_position.direction_to(ag.get_next_path_position()) * SPEED
		a.move_and_slide()
		if a.global_position.distance_to(_last[i]) < SPEED * delta * 0.25:
			_stuck_time[i] += delta
		_last[i] = a.global_position
	if _t >= SIM:
		var reached := 0
		var tsum := 0.0
		var stuck := 0
		var unreach := 0
		for i in _agents.size():
			if _reached[i] >= 0.0:
				reached += 1
				tsum += _reached[i]
			else:
				var ag: NavigationAgent2D = _agents[i].get_node("ag")
				if ag.get_final_position().distance_to(_goals[i]) > 200.0:
					unreach += 1
				else:
					stuck += 1
			if _stuck_time[i] > 1.0 and _reached[i] < 0.0:
				pass
		var stuck_s := 0.0
		for v in _stuck_time:
			stuck_s += v
		for i in _agents.size():
			if _stuck_time[i] > 2.0:
				var ag2: NavigationAgent2D = _agents[i].get_node("ag")
				print("STUCK %.1fs at %s next=%s goal=%s" % [_stuck_time[i], _agents[i].global_position.round(), ag2.get_next_path_position().round(), _goals[i].round()])
		print("PROBE reached=%d/%d avg_time=%.1f not_reached=%d (no_path=%d) total_stuck_s=%.1f" % [reached, _agents.size(), tsum / maxf(reached, 1), _agents.size() - reached, unreach, stuck_s])
		get_tree().quit()
