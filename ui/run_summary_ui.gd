extends CanvasLayer
class_name RunSummaryUI

# Post-run card shown when the local player gets back to the hub from an
# expedition: extracted or died, which map, how long, kills, and how much they
# carried home. Fed by world.gd's per-run tracking. Dismissed by any key/click or
# after AUTO_HIDE seconds. Built in code.

const AUTO_HIDE := 12.0

var _t := 0.0
var _panel: PanelContainer

static func show_summary(parent: Node, extracted: bool, map_name: String, seconds: float, kills: int, items_carried: int) -> void:
	var ui := RunSummaryUI.new()
	parent.add_child(ui)
	ui._build(extracted, map_name, seconds, kills, items_carried)

func _build(extracted: bool, map_name: String, seconds: float, kills: int, items_carried: int) -> void:
	layer = 45
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -900
	_panel.offset_right = 900
	_panel.offset_top = -480
	_panel.offset_bottom = 480
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.92)
	style.border_color = Color(0.4, 0.95, 0.5) if extracted else Color(0.95, 0.3, 0.25)
	style.set_border_width_all(8)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(60)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", 60)
	label.add_theme_font_size_override("bold_font_size", 96)
	var secs := int(seconds)
	var headline := "[color=#66ee88]EXTRACTED[/color]" if extracted else "[color=#ff5544]LOST IN THE FIELD[/color]"
	var carried_line := ("Brought home: %d item stack(s)" % items_carried) if extracted else "Your gear was left in a death bag"
	label.text = "[b]%s[/b]\n%s\n\nTime: %d:%02d\nKills: %d\n%s\n\n[font_size=40](any key to close)[/font_size]" % [
		headline, map_name, floori(secs / 60.0), secs % 60, kills, carried_line]
	_panel.add_child(label)
	add_child(_panel)

func _process(delta: float) -> void:
	_t += delta
	if _t >= AUTO_HIDE:
		queue_free()

func _input(event: InputEvent) -> void:
	# A short grace period so the click/keypress that ended the run doesn't close it.
	if _t < 0.6:
		return
	if (event is InputEventKey or event is InputEventMouseButton) and event.pressed:
		queue_free()
