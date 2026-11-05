extends CanvasLayer

# The reel-in minigame (driven by fishing_spot.gd). A marker sweeps back and
# forth across a track; click ("attack") while it's inside the target zone to
# land the catch. Difficulty scales with the catch's rarity — rarer fish get a
# smaller zone and a faster marker. Only ever begin()-run on the local player's
# own copy; remote copies sit idle (processing off).

var _active := false
var _callback: Callable
var _t := 0.0          # sweep phase (triangle wave)
var _speed := 1.0      # sweeps per second
var _zone_min := 0.0   # target zone, as fractions of the track [0..1]
var _zone_max := 1.0
var _arm := 0.0        # brief input lockout so the opening press doesn't count
var _time_left := 0.0

const ARM_TIME := 0.2
const TIME_LIMIT := 5.0

@onready var track: Control = $root/panel/margin/vbox/track
@onready var zone: ColorRect = $root/panel/margin/vbox/track/zone
@onready var marker: ColorRect = $root/panel/margin/vbox/track/marker
@onready var result_label: Label = $root/panel/margin/vbox/result_label

func _ready() -> void:
	visible = false
	set_process(false)

# rarity_index 0 (common) .. 4 (legendary). callback is called with a single
# bool (landed?) exactly once when the minigame resolves.
func begin(rarity_index: int, callback: Callable) -> void:
	_callback = callback
	_active = true
	_t = 0.0
	_arm = ARM_TIME
	_time_left = TIME_LIMIT
	var f: float = clampf(float(rarity_index) / 4.0, 0.0, 1.0)
	var zone_frac: float = lerpf(0.30, 0.08, f)
	_speed = lerpf(0.8, 1.8, f)
	var lo: float = randf() * (1.0 - zone_frac)
	_zone_min = lo
	_zone_max = lo + zone_frac
	zone.color = ItemData.rarity_color(ItemData.RARITY_ORDER[clampi(rarity_index, 0, 4)])
	result_label.text = ""
	visible = true
	set_process(true)

func _process(delta: float) -> void:
	if !_active:
		return
	if _arm > 0.0:
		_arm -= delta
	_time_left -= delta
	var w: float = track.size.x
	var h: float = track.size.y
	zone.position = Vector2(_zone_min * w, 0.0)
	zone.size = Vector2((_zone_max - _zone_min) * w, h)
	_t += _speed * 2.0 * delta
	var frac: float = absf(fmod(_t, 2.0) - 1.0)
	marker.size = Vector2(marker.size.x, h)
	marker.position = Vector2(frac * w - marker.size.x * 0.5, 0.0)
	if _arm <= 0.0 and Input.is_action_just_pressed("attack"):
		_finish(frac >= _zone_min and frac <= _zone_max)
	elif _time_left <= 0.0:
		_finish(false)

func _finish(landed: bool) -> void:
	_active = false
	set_process(false)
	visible = false
	var cb := _callback
	_callback = Callable()
	if cb.is_valid():
		cb.call(landed)
