extends Node2D

# Headless perf bench (dev only, excluded from export): loads dungeon_main, spawns
# N enemies around a moving dummy player hurtbox, and reports average physics
# frame time. Run:
#   godot --headless --path . res://delete_before_export/perf_bench.tscn -- <enemy_count>

const HurtboxScene := preload("res://scenes/characters/hurtbox.tscn")
const EnemyScene := preload("res://scenes/enemies/enemy.tscn")

var _target: Node2D
var _frames := 0
var _phys_total := 0.0
var _proc_total := 0.0
var _nav_total := 0.0
var _enemies: Array = []
var _last_pos := {}
var _moved := 0.0
var _t := 0.0
var _count := 20
# Minimal stand-in for world.gd so enemy AI wakes up (it reads world.players etc).
var players: Node
class StubRooms:
	var loaded_rooms := {}
	var active_key := ""
	func room_key_at(_p) -> String:
		return ""
var world_rooms = StubRooms.new()
var my_zone := "dungeon"
var my_room := "main"
var shutting_down := false
func get_local_player():
	return null
func peers_in_room(_k: String) -> Array:
	return []
func credit_kill(_peer: int) -> void:
	pass
func spawn_loot(_a, _b, _c = {}, _d = 0) -> void:
	pass

func _ready() -> void:
	add_to_group("world")
	players = Node.new()
	players.name = "players"
	add_child(players)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_count = int(args[0])
	var room: Node = load("res://scenes/levels/dungeon/dungeon_main.tscn").instantiate()
	# Don't let the room's own spawner populate; we place our own pack.
	var spawner := room.get_node_or_null("enemies")
	if spawner != null:
		spawner.set_script(null)
	var mode := String(args[1]) if args.size() > 1 else ""
	if "nonav" in mode:
		room.get_node("navigation").free()
	if "nowalls" in mode:
		room.get_node("wall_tiles/walls").collision_enabled = false
	if "nofloor" in mode:
		for l in room.get_node("floor_tiles").get_children():
			l.collision_enabled = false
	if "noshadow" in mode and room.has_node("wall_shadows"):
		room.get_node("wall_shadows").free()
	add_child(room)
	# Dummy player: a body carrying a hurtbox on the player layer.
	_target = CharacterBody2D.new()
	_target.collision_layer = 2
	var hb: Area2D = HurtboxScene.instantiate()
	hb.collision_layer = 4
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 48.0
	shape.shape = circle
	hb.add_child(shape)
	_target.add_child(hb)
	_target.name = "1"
	players.add_child(_target)
	_target.global_position = Vector2(-3552, -5280) + Vector2(400, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var holder: Node2D = room.get_node_or_null("enemies") if room.get_node_or_null("enemies") else room
	var archetypes := ["triangle", "circle", "pentagon", "square"]
	for i in _count:
		var e = EnemyScene.instantiate()
		e.name = "bench_enemy_%d" % i
		e.archetype = archetypes[i % archetypes.size()]
		e.position = holder.to_local(_target.global_position + Vector2.RIGHT.rotated(TAU * i / _count) * 1400.0)
		holder.add_child(e)
		_enemies.append(e)
	print("BENCH spawned ", _count, " enemies")

func _physics_process(delta: float) -> void:
	if _target == null:
		return
	_t += delta
	# Strafe the dummy around so enemies chase, repath and re-aim.
	_target.global_position = Vector2(-3552, -5280) + Vector2(400, 0) + Vector2(cos(_t * 0.8), sin(_t * 1.1)) * 900.0
	_frames += 1
	for e in _enemies:
		if is_instance_valid(e):
			if _last_pos.has(e):
				_moved += e.global_position.distance_to(_last_pos[e])
			_last_pos[e] = e.global_position
	if _frames > 60:
		_phys_total += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		_proc_total += Performance.get_monitor(Performance.TIME_PROCESS)
		_nav_total += Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS)
	if _frames == 60 + 600:
		var n := 600.0
		print("BENCH enemies=%d avg_physics_ms=%.2f avg_process_ms=%.2f avg_nav_ms=%.2f nav_regions=%d nav_polys=%d nav_edges=%d phys_pairs=%d" % [_count, _phys_total / n * 1000.0, _proc_total / n * 1000.0, _nav_total / n * 1000.0, Performance.get_monitor(Performance.NAVIGATION_REGION_COUNT), Performance.get_monitor(Performance.NAVIGATION_POLYGON_COUNT), Performance.get_monitor(Performance.NAVIGATION_EDGE_COUNT), Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)])
		var engaged := 0
		var near := 0
		for e in _enemies:
			if is_instance_valid(e):
				if e.current_target != null:
					engaged += 1
				if e.global_position.distance_to(_target.global_position) < 2600:
					near += 1
		print("BENCH moved_per_enemy_per_s=%.0f engaged=%d near_target=%d of %d" % [_moved / max(_enemies.size(), 1) / (_frames / 60.0), engaged, near, _enemies.size()])
		get_tree().quit()
