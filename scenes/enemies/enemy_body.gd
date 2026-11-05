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
# Elite affix ids (see Enemy.AFFIXES) drawn as marks around the glyph, and whether
# a Shielded enemy's shield is still up.
var affixes: Array = []
var shield_up := false

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
		"hexagon":
			_draw_ngon(6)
		_:  # "square" (and any unknown archetype) — axis-aligned box
			var rect := Rect2(-half_size, -half_size, half_size * 2.0, half_size * 2.0)
			draw_rect(rect, fill_color, true)
			draw_rect(rect, border_color, false, border_width)
	_draw_affix_marks()

# Readable at a glance: armored = heavy dark outer ring, shielded = a bright ring in
# its element colour (gone once broken), warder = dashed red ring, fast = two
# chevrons above.
func _draw_affix_marks() -> void:
	var r := half_size * 1.25
	if affixes.has("armored"):
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(0.15, 0.15, 0.18), 14.0, true)
	if affixes.has("shielded") and shield_up:
		draw_arc(Vector2.ZERO, r + 18.0, 0.0, TAU, 48, fill_color.lightened(0.45), 10.0, true)
	if affixes.has("warder"):
		for k in 12:
			var a0 := TAU * k / 12.0
			draw_arc(Vector2.ZERO, r + 36.0, a0, a0 + TAU / 24.0, 6, Color(1.0, 0.25, 0.2), 8.0, true)
	if affixes.has("fast"):
		for k in 2:
			var y := -half_size * 1.55 - k * 26.0
			draw_polyline(PackedVector2Array([Vector2(-22, y + 14), Vector2(0, y), Vector2(22, y + 14)]), Color(1.0, 0.9, 0.3), 8.0, true)

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
