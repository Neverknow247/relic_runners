extends Node2D
class_name StatusVisuals

# Draws status overlays from a synced bitmask on ANY peer (status_mask on the
# owning player/enemy). Pure visuals.

var mask := 0:
	set(value):
		mask = value
		set_process(mask != 0)
		queue_redraw()
var radius := 72.0
var _t := 0.0

func _ready() -> void:
	z_index = 3
	set_process(mask != 0)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _has(id: String) -> bool:
	return mask & StatusEffects.bit(id) != 0

func _draw() -> void:
	if mask == 0:
		return
	var C := StatusEffects.ELEMENT_COLORS
	if _has("frozen"):
		var pts := PackedVector2Array()
		for i in 6:
			pts.append(Vector2.from_angle(TAU * i / 6.0 + PI / 6.0) * radius * 1.05)
		draw_colored_polygon(pts, Color(0.75, 0.95, 1.0, 0.45))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.9, 1.0, 1.0, 0.9), 6.0)
	elif _has("chill"):
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(C["chill"], 0.7), 6.0)
	if _has("burn"):
		for i in 5:
			var a := TAU * i / 5.0 + _t * 2.5
			var flick := 10.0 + 6.0 * sin(_t * 14.0 + i)
			draw_circle(Vector2.from_angle(a) * radius * 0.8, flick, Color(C["burn"], 0.85))
	if _has("soak"):
		for i in 3:
			var x := (i - 1) * radius * 0.5
			var y := -radius + fmod(_t * 90.0 + i * 37.0, radius * 0.9)
			draw_circle(Vector2(x, y), 9.0, Color(C["soak"], 0.8))
	if _has("seed"):
		var big := 1.5 if _has("overgrown") else 1.0
		for i in 4:
			var a := TAU * i / 4.0 - _t * 0.8
			draw_circle(Vector2.from_angle(a) * radius * 0.95, 9.0 * big, Color(C["seed"], 0.9))
	if _has("staggered"):
		for i in 3:
			var a := TAU * i / 3.0 + _t * 5.0
			var p := Vector2(0, -radius * 1.15) + Vector2.from_angle(a) * 28.0
			draw_circle(p, 9.0, Color(1.0, 0.9, 0.35, 0.95))
	if _has("armor_broken"):
		draw_line(Vector2(-radius * 0.5, -radius * 0.6), Vector2(radius * 0.4, radius * 0.5), Color(0.2, 0.15, 0.1, 0.8), 6.0)
	if _has("dazzled"):
		draw_arc(Vector2(0, -radius * 1.1), 20.0, 0.0, TAU, 16, Color(1.0, 0.95, 0.6, 0.9), 5.0)
	if _has("dirge"):
		draw_arc(Vector2.ZERO, radius * 1.15, 0.0, TAU, 40, Color(0.5, 0.3, 0.7, 0.6), 4.0)
	if _has("effigy"):
		draw_arc(Vector2.ZERO, radius * 1.25, 0.0, TAU, 6, Color(0.7, 0.2, 0.6, 0.85), 6.0)
	if _has("haste"):
		draw_line(Vector2(-radius, radius * 0.6), Vector2(-radius * 1.5, radius * 0.6), Color(1, 1, 1, 0.6), 5.0)
	if _has("mend"):
		draw_line(Vector2(radius * 0.8, -radius), Vector2(radius * 0.8, -radius * 0.6), Color(0.4, 1.0, 0.4, 0.9), 6.0)
		draw_line(Vector2(radius * 0.6, -radius * 0.8), Vector2(radius, -radius * 0.8), Color(0.4, 1.0, 0.4, 0.9), 6.0)
