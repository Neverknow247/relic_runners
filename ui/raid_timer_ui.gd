extends CanvasLayer

# Extraction raid clock (top-centre). Shown only while the local player is on an
# expedition whose MapDef has a duration_sec. Reads world.raid_seconds_left();
# turns amber under 5 minutes and red + pulsing under 1, with a chime at each.
# Built in code; the local player adds one in _ready.

const WARN_SECONDS := 300.0
const CRITICAL_SECONDS := 60.0

var _label: Label
var _warned_5 := false
var _warned_1 := false

func _ready() -> void:
	layer = 20
	_label = Label.new()
	_label.anchor_left = 0.5
	_label.anchor_right = 0.5
	_label.offset_left = -600
	_label.offset_right = 600
	_label.offset_top = 40
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 96)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 18)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_label.visible = false

func _process(_delta: float) -> void:
	var world = get_tree().get_first_node_in_group("world")
	if world == null or !world.has_method("raid_seconds_left") or world.my_zone == "hub":
		_label.visible = false
		_warned_5 = false
		_warned_1 = false
		return
	# Survival maps: show the day clock instead of a raid countdown.
	if world.has_method("survival_active") and world.survival_active():
		_show_day_clock(world)
		return
	var left: float = world.raid_seconds_left()
	if left < 0.0:
		_label.visible = false
		return
	_label.visible = true
	var secs := int(ceil(left))
	_label.text = "EXTRACT  %d:%02d" % [floori(secs / 60.0), secs % 60]
	if left <= CRITICAL_SECONDS:
		_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
		_label.modulate.a = 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() / 180.0))
		if !_warned_1:
			_warned_1 = true
			Sounds.play_sfx("sniper_windup", null, 0.0, 0.0)
	elif left <= WARN_SECONDS:
		_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.25))
		_label.modulate.a = 1.0
		if !_warned_5:
			_warned_5 = true
			Sounds.play_sfx("armed", null, 0.0, 0.0)
	else:
		_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
		_label.modulate.a = 1.0

func _show_day_clock(world) -> void:
	_label.visible = true
	_label.modulate.a = 1.0
	var secs := int(ceil(world.seconds_to_phase_change()))
	var t := "%d:%02d" % [floori(secs / 60.0), secs % 60]
	var day: int = world.survival_day()
	var map: MapDef = Stats.current_map()
	if world.is_night():
		_label.add_theme_color_override("font_color", Color(0.6, 0.7, 1.0))
		_label.text = "NIGHT %d  -  dawn in %s  -  portals sealed" % [day, t]
	else:
		_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
		var portal_note := "portals open" if day >= map.extract_from_day else "portals open on day %d" % map.extract_from_day
		_label.text = "DAY %d  -  dusk in %s  -  %s" % [day, t, portal_note]
