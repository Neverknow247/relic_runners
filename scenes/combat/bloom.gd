extends Node2D
class_name Bloom

# Nature's signature: a seeded enemy dies into a healing bloom. Spawned on every
# peer in the room (enemy._show_bloom); each peer heals only ITS OWN player if
# inside, so no RPC is needed for the heal. Capped per player (player.heal_capped).

var heal := 10.0
var radius := 300.0
var _t := 0.0
const DURATION := 0.6

static func spawn(tree: SceneTree, pos: Vector2, heal_amount: float, r: float) -> void:
	if tree == null or tree.current_scene == null:
		return
	var b := Bloom.new()
	b.global_position = pos
	b.heal = heal_amount
	b.radius = r
	tree.current_scene.add_child(b)

func _ready() -> void:
	top_level = true
	z_index = 4
	var world = get_tree().get_first_node_in_group("world")
	if world != null and world.players != null:
		var me = world.players.get_node_or_null(str(multiplayer.get_unique_id()))
		if me != null and me.has_method("heal_capped") and me.global_position.distance_to(global_position) <= radius:
			me.heal_capped(heal, "bloom")
	Sounds.play_sfx("armed", global_position, -6.0, 0.0)

func _process(delta: float) -> void:
	_t += delta
	if _t >= DURATION:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var k := _t / DURATION
	var c := Color(0.45, 0.95, 0.4, 0.8 * (1.0 - k))
	draw_circle(Vector2.ZERO, radius * k, Color(c.r, c.g, c.b, c.a * 0.25))
	draw_arc(Vector2.ZERO, radius * k, 0.0, TAU, 48, c, 10.0)
	for i in 6:
		var a := TAU * i / 6.0 + k * 1.5
		draw_circle(Vector2.from_angle(a) * radius * 0.5 * k, 18.0 * (1.0 - k) + 6.0, c)
