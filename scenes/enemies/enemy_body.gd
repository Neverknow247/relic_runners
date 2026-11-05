extends Node2D
class_name EnemyBody

# The enemy's body glyph. Encodes its identity at a glance:
#   SHAPE  = archetype  (pentagon / triangle / circle / square)
#   FILL   = element    (fire red, water blue, …)
#   BORDER = tier       (bronze / silver / gold)

var shape := "square"
var fill_color := Color(0.7, 0.1, 0.1)
var border_color := Color(0.72, 0.45, 0.2)
var half_size := 64.0
var border_width := 16.0

func configure(p_shape: String, p_fill: Color, p_border: Color, p_half_size := 64.0, p_border_width := 16.0) -> void:
	shape = p_shape
	fill_color = p_fill
	border_color = p_border
	half_size = p_half_size
	border_width = p_border_width
	queue_redraw()

func _draw() -> void:
	match shape:
		"circle":
			draw_circle(Vector2.ZERO, half_size, fill_color)
			draw_arc(Vector2.ZERO, half_size - border_width * 0.5, 0.0, TAU, 48, border_color, border_width, true)
		"triangle":
			_draw_ngon(3)
		"pentagon":
			_draw_ngon(5)
		_:  # "square" (and any unknown archetype) — axis-aligned box
			var rect := Rect2(-half_size, -half_size, half_size * 2.0, half_size * 2.0)
			draw_rect(rect, fill_color, true)
			draw_rect(rect, border_color, false, border_width)

# Filled regular N-gon with a vertex pointing straight up, plus an outline border.
func _draw_ngon(sides: int) -> void:
	var pts := PackedVector2Array()
	for i in sides:
		var ang := -PI / 2.0 + TAU * float(i) / float(sides)
		pts.append(Vector2(cos(ang), sin(ang)) * half_size)
	draw_colored_polygon(pts, fill_color)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, border_color, border_width, true)
