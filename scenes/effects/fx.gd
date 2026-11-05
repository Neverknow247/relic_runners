extends RefCounted
class_name Fx

# Cosmetic combat feedback ("juice"). Every function here is purely local and
# visual, safe to call on any peer: nothing touches gameplay state, so peers can
# disagree on a particle without desyncing anything.

# Burst of shards in `color` (enemy death, big impacts). `size` scales spread
# and shard size; 1.0 suits a ~60-unit enemy body.
static func shatter(tree: SceneTree, pos: Vector2, color: Color, size := 1.0) -> void:
	_burst(tree, pos, color, 18, 0.5, 700.0 * size, 1400.0 * size, 14.0 * size, 26.0 * size)

# Small puff where a projectile ends (hit or wall).
static func puff(tree: SceneTree, pos: Vector2, color: Color, size := 1.0) -> void:
	_burst(tree, pos, color, 7, 0.22, 250.0 * size, 600.0 * size, 8.0 * size, 14.0 * size)

static func _burst(tree: SceneTree, pos: Vector2, color: Color, amount: int, life: float,
		vel_min: float, vel_max: float, scale_min: float, scale_max: float) -> void:
	if tree == null or tree.current_scene == null:
		return
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = life
	p.direction = Vector2.RIGHT
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = vel_min
	p.initial_velocity_max = vel_max
	p.damping_min = vel_max * 1.5
	p.damping_max = vel_max * 2.0
	p.scale_amount_min = scale_min
	p.scale_amount_max = scale_max
	p.angle_min = 0.0
	p.angle_max = 360.0
	var ramp := Gradient.new()
	ramp.set_color(0, color.lightened(0.35))
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	p.z_index = 50
	tree.current_scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	tree.create_timer(life + 0.1).timeout.connect(p.queue_free)

# White-hot flash on a CanvasItem: snaps its modulate bright, eases back.
# Uses self_modulate when asked so it doesn't fight other tweens on modulate.
static func flash(node: CanvasItem, use_self_modulate := false, strength := 2.6, duration := 0.1) -> void:
	if node == null or !is_instance_valid(node) or !node.is_inside_tree():
		return
	var prop := "self_modulate" if use_self_modulate else "modulate"
	var base: Color = node.get(prop)
	node.set(prop, Color(strength, strength, strength, base.a))
	var t := node.create_tween()
	t.tween_property(node, prop, Color(1, 1, 1, base.a), duration)

# Screen shake on the LOCAL player's camera (no-op for anyone else).
# amount 0..1 trauma; it decays on its own (see camera_shake.gd).
static func shake(tree: SceneTree, amount: float) -> void:
	if tree == null:
		return
	var world = tree.get_first_node_in_group("world")
	if world == null or !world.has_method("get_local_player"):
		return
	var lp = world.get_local_player()
	if lp == null or !("player_camera" in lp) or lp.player_camera == null:
		return
	if lp.player_camera.has_method("add_trauma"):
		lp.player_camera.add_trauma(amount)

# Shake only if `pos` is near enough to the local player to matter (e.g. an
# enemy dying on screen), scaled down with distance.
static func shake_at(tree: SceneTree, pos: Vector2, amount: float, radius := 2600.0) -> void:
	if tree == null:
		return
	var world = tree.get_first_node_in_group("world")
	if world == null or !world.has_method("get_local_player"):
		return
	var lp = world.get_local_player()
	if lp == null:
		return
	var d: float = lp.global_position.distance_to(pos)
	if d < radius:
		shake(tree, amount * (1.0 - d / radius))
