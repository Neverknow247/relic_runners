extends CanvasLayer

# The map board: what an expedition door opens for the host. Lists every MapDef
# (scenes/maps/defs) grouped by style and ladder tier, with its raid length. A
# map with `unlock_after` stays locked until you've EXTRACTED from that map at
# least once (Stats.save_data.unlocks.extracted), which is the ladder: clear E1
# to open E2. Launching hands the id to the existing kit-selection flow.
# Built in code; the local player owns one (player.open_map_board).

var _panel: PanelContainer
var _list: VBoxContainer

func _ready() -> void:
	layer = 40
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -1200
	_panel.offset_right = 1200
	_panel.offset_top = -760
	_panel.offset_bottom = 760
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.09, 0.94)
	style.border_color = Color(0.9, 0.8, 0.4)
	style.set_border_width_all(6)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(56)
	_panel.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 30)
	_panel.add_child(col)
	var title := Label.new()
	title.text = "Choose a map"
	title.add_theme_font_size_override("font_size", 84)
	col.add_child(title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 22)
	col.add_child(_list)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 120)
	close.add_theme_font_size_override("font_size", 56)
	close.pressed.connect(close_board)
	col.add_child(close)
	add_child(_panel)
	_panel.visible = false

func is_open() -> bool:
	return _panel.visible

func open_board() -> void:
	_rebuild()
	_panel.visible = true

func close_board() -> void:
	_panel.visible = false

static func extracted_count(map_id: String) -> int:
	var unlocks: Dictionary = Stats.save_data.get("unlocks", {})
	return int(unlocks.get("extracted", {}).get(map_id, 0))

static func is_unlocked(def: MapDef) -> bool:
	return def.unlock_after == "" or extracted_count(def.unlock_after) > 0

func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var defs: Array = MapRegistry.all_defs()
	defs.sort_custom(func(a, b): return a.style < b.style if a.style != b.style else a.tier < b.tier)
	for def in defs:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 30)
		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_font_size_override("font_size", 56)
		var mins := int(def.duration_sec / 60.0)
		var clock := ("%d min raid" % mins) if def.duration_sec > 0.0 else "no raid clock"
		info.text = "%s   [%s, %s]   cleared x%d" % [def.display_name, def.style.capitalize(), clock, extracted_count(def.id)]
		row.add_child(info)
		var go := Button.new()
		go.custom_minimum_size = Vector2(520, 120)
		go.add_theme_font_size_override("font_size", 52)
		if is_unlocked(def):
			go.text = "Launch"
			go.pressed.connect(_launch.bind(def.id))
		else:
			var gate := MapRegistry.get_def(def.unlock_after)
			go.text = "Extract from %s" % (gate.display_name if gate != null else def.unlock_after)
			go.disabled = true
		row.add_child(go)
		_list.add_child(row)

func _launch(map_id: String) -> void:
	close_board()
	var world = get_tree().get_first_node_in_group("world")
	if world != null and world.multiplayer.is_server():
		world.request_begin_kit_selection(map_id)

func _unhandled_input(event: InputEvent) -> void:
	if _panel.visible and event.is_action_pressed("ui_cancel"):
		close_board()
		get_viewport().set_input_as_handled()
