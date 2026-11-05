extends CanvasLayer

# First-run controls card (and F1 to bring it back). Built in code so it needs no
# scene; the local player adds one in _ready. Dismissed by any key/click, or after
# AUTO_HIDE seconds. Remembers it was seen in Stats.save_data["seen_controls"].

const AUTO_HIDE := 20.0

const TEXT := """[b]CONTROLS[/b]   (F1 to show again)

WASD  move            Mouse  aim
Left click  fire your weapon (wand stream / orb heavy / tome spread)
Space  dodge roll (brief invulnerability)
F  shove (knock enemies back, interrupt their wind-up)

[b]Stratagem spells[/b]
Hold Right click + tap WASD codes (or hold Ctrl + arrow keys while moving)
A completed code is armed: release, then left click to call it in.
Each spell has a cooldown. Watch the list on screen.

Tab  bag / gear      E  interact      M  map      1 / 2  quick slots

[i]Enemies flash and swell before they attack. A red laser means the sniper is about to fire: roll![/i]"""

var _panel: PanelContainer
var _timer := 0.0

func _ready() -> void:
	layer = 50
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -1300
	_panel.offset_right = 1300
	_panel.offset_top = -700
	_panel.offset_bottom = 700
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.88)
	style.border_color = Color(0.9, 0.8, 0.4)
	style.set_border_width_all(6)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(60)
	_panel.add_theme_stylebox_override("panel", style)
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.add_theme_font_size_override("normal_font_size", 54)
	label.add_theme_font_size_override("bold_font_size", 66)
	label.add_theme_font_size_override("italics_font_size", 48)
	label.text = TEXT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(label)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	if Stats.save_data.get("seen_controls", false):
		_panel.visible = false
	else:
		_show()

func _show() -> void:
	_panel.visible = true
	_timer = AUTO_HIDE

func _hide() -> void:
	_panel.visible = false
	Stats.save_data["seen_controls"] = true

func _process(delta: float) -> void:
	if _panel.visible:
		_timer -= delta
		if _timer <= 0.0:
			_hide()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and !event.echo:
		if event.physical_keycode == KEY_F1:
			if _panel.visible:
				_hide()
			else:
				_show()
			get_viewport().set_input_as_handled()
			return
		if _panel.visible:
			_hide()
	elif event is InputEventMouseButton and event.pressed and _panel.visible:
		_hide()
