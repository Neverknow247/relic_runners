class_name CombatFx

# Local-only combat visuals shared by status code (no networking here; callers
# decide which peers run them). No SpellData references.

# A jagged lightning line through `points`, fading out fast.
static func arc(tree: SceneTree, points: PackedVector2Array, color: Color = Color(1.0, 0.95, 0.4)) -> void:
	if tree == null or tree.current_scene == null or points.size() < 2:
		return
	var line := Line2D.new()
	line.top_level = true
	line.z_index = 60
	line.width = 10.0
	line.default_color = color
	var jag := PackedVector2Array()
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		jag.append(a)
		var n := (b - a).orthogonal().normalized()
		for k in range(1, 4):
			var t := k / 4.0
			jag.append(a.lerp(b, t) + n * randf_range(-28.0, 28.0))
	jag.append(points[points.size() - 1])
	line.points = jag
	tree.current_scene.add_child(line)
	var tw := line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.25)
	tw.tween_callback(line.queue_free)
	Sounds.play_sfx("tap", points[0], -8.0, 0.0)

# An expanding ring (blooms, pulses, ripples).
static func ring(tree: SceneTree, pos: Vector2, radius: float, color: Color, duration: float = 0.5, width: float = 12.0) -> void:
	if tree == null or tree.current_scene == null:
		return
	var r := RingFx.new()
	r.global_position = pos
	r.max_radius = radius
	r.color = color
	r.duration = duration
	r.width = width
	tree.current_scene.add_child(r)
