extends CanvasLayer
class_name ThreatPing

# "Something's coming from over there": a pulsing arrow on the screen edge pointing
# at a world position (an incoming portal wave), or a ring on the spot itself when
# it's already on screen. Local and cosmetic; spawned by ThreatPing.show_at.

const DURATION := 2.8
const EDGE_MARGIN := 140.0

var world_pos := Vector2.ZERO
var color := Color(1.0, 0.35, 0.25)
var _t := 0.0
var _draw_node: Control

static func show_at(tree: SceneTree, pos: Vector2, tint := Color(1.0, 0.35, 0.25)) -> void:
	if tree == null or tree.current_scene == null:
		return
	var ping := ThreatPing.new()
	ping.world_pos = pos
	ping.color = tint
	tree.current_scene.add_child(ping)

func _ready() -> void:
	layer = 30
	_draw_node = Control.new()
	_draw_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_node.draw.connect(_on_draw)
	add_child(_draw_node)

func _process(delta: float) -> void:
	_t += delta
	if _t >= DURATION:
		queue_free()
		return
	_draw_node.queue_redraw()

func _on_draw() -> void:
	var vp := _draw_node.get_viewport()
	var cam := vp.get_camera_2d()
	if cam == null:
		return
	var size := _draw_node.get_viewport_rect().size
	# World -> screen through the canvas transform (camera zoom/offset included).
	var screen_pos: Vector2 = vp.get_canvas_transform() * world_pos
	var pulse := 0.55 + 0.45 * absf(sin(_t * 9.0))
	var c := Color(color, pulse * (1.0 - _t / DURATION * 0.5))
	var rect := Rect2(Vector2(EDGE_MARGIN, EDGE_MARGIN), size - Vector2(EDGE_MARGIN, EDGE_MARGIN) * 2.0)
	if rect.has_point(screen_pos):
		_draw_node.draw_arc(screen_pos, 120.0 + 40.0 * pulse, 0.0, TAU, 40, c, 14.0, true)
		return
	var centre := size * 0.5
	var dir := (screen_pos - centre).normalized()
	# Clamp to the margin rectangle along dir.
	var tx := INF if absf(dir.x) < 0.0001 else (rect.size.x * 0.5) / absf(dir.x)
	var ty := INF if absf(dir.y) < 0.0001 else (rect.size.y * 0.5) / absf(dir.y)
	var p := centre + dir * minf(tx, ty)
	var perp := Vector2(-dir.y, dir.x)
	var tip := p + dir * 60.0
	_draw_node.draw_colored_polygon(PackedVector2Array([tip, p - dir * 40.0 + perp * 55.0, p - dir * 40.0 - perp * 55.0]), c)
