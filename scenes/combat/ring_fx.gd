extends Node2D
class_name RingFx

# Expanding, fading ring. Visual only.
var max_radius := 300.0
var color := Color.WHITE
var duration := 0.5
var width := 12.0
var filled := false
var _t := 0.0

func _ready() -> void:
	top_level = true
	z_index = 45

func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var k := clampf(_t / maxf(duration, 0.01), 0.0, 1.0)
	var r := max_radius * (0.25 + 0.75 * k)
	var c := color
	c.a = color.a * (1.0 - k)
	if filled:
		var f := c
		f.a *= 0.25
		draw_circle(Vector2.ZERO, r, f)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, c, width)
