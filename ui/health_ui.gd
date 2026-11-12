extends CanvasLayer

# Heart-vial health display: health_bar.png (white liquid mask) is coloured and
# animated by health_vial.gdshader; health_front.png (glass + border) sits on top.

@onready var liquid: TextureRect = $vial/liquid
@onready var value_label: Label = $vial/value_label

# The heart is narrow at the tip and wide at the lobes, so a straight height
# mapping would make the first half of your health look like barely a sip.
# Map health -> surface height by liquid AREA instead, so 50% HP = half the potion.
const AREA_SAMPLES := 128
var _area_to_height: PackedFloat32Array = PackedFloat32Array()

const FILL_SPEED := 6.0          # how fast the real surface catches up (per second, exponential)
const GHOST_DELAY := 0.45        # seconds the "lost health" ghost lingers before draining
const GHOST_SPEED := 1.8
const SLOSH_DECAY := 2.2

var _target := 1.0
var _fill := 1.0
var _ghost := 1.0
var _ghost_wait := 0.0
var _slosh := 0.0
var _mat: ShaderMaterial

func _ready() -> void:
	_mat = liquid.material as ShaderMaterial
	_build_area_table()

func update_health(current: float, max_value: float, barrier_value: float = 0.0) -> void:
	var frac := clampf(current / maxf(max_value, 1.0), 0.0, 1.0)
	var new_target := _height_for_area(frac)
	if new_target < _target - 0.001:
		# Took damage: ghost holds at the old level, liquid sloshes.
		_ghost = maxf(_ghost, _fill)
		_ghost_wait = GHOST_DELAY
		_slosh = clampf(_slosh + 0.35 + (_target - new_target) * 2.0, 0.0, 1.0)
		_mat.set_shader_parameter("slosh_dir", -1.0 if randf() < 0.5 else 1.0)
	_target = new_target
	if barrier_value > 0.0:
		value_label.text = "%d/%d  +%d" % [roundi(current), roundi(max_value), roundi(barrier_value)]
	else:
		value_label.text = "%d/%d" % [roundi(current), roundi(max_value)]

func _process(delta: float) -> void:
	_fill = lerpf(_fill, _target, 1.0 - exp(-FILL_SPEED * delta))
	if _ghost_wait > 0.0:
		_ghost_wait -= delta
	else:
		_ghost = move_toward(_ghost, _fill, GHOST_SPEED * delta * maxf(_ghost - _fill, 0.15))
	_slosh = move_toward(_slosh, 0.0, SLOSH_DECAY * delta * maxf(_slosh, 0.2))
	_mat.set_shader_parameter("fill", _fill)
	_mat.set_shader_parameter("ghost_fill", _ghost)
	_mat.set_shader_parameter("slosh", _slosh)

# Reads the mask once: its vertical bounds (fed to the shader, so repainting the
# PNG just works) and a cumulative area table from the bottom up.
func _build_area_table() -> void:
	var tex := liquid.texture
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	var full_h := float(img.get_height())
	var used := img.get_used_rect()
	if used.size.y <= 0:
		return
	_mat.set_shader_parameter("liquid_top", used.position.y / full_h)
	_mat.set_shader_parameter("liquid_bottom", used.end.y / full_h)
	var crop := img.get_region(used)
	crop.resize(AREA_SAMPLES, AREA_SAMPLES, Image.INTERPOLATE_BILINEAR)
	# cum[i] = area of rows from the bottom up to i rows high.
	var cum := PackedFloat32Array()
	cum.resize(AREA_SAMPLES + 1)
	cum[0] = 0.0
	for i in AREA_SAMPLES:
		var y := AREA_SAMPLES - 1 - i
		var row := 0.0
		for x in AREA_SAMPLES:
			row += crop.get_pixel(x, y).a
		cum[i + 1] = cum[i] + row
	var total := cum[AREA_SAMPLES]
	if total <= 0.0:
		return
	# Invert: for each area fraction, the height fraction that holds it.
	_area_to_height.resize(AREA_SAMPLES + 1)
	var j := 0
	for k in AREA_SAMPLES + 1:
		var want := total * float(k) / AREA_SAMPLES
		while j < AREA_SAMPLES and cum[j + 1] < want:
			j += 1
		var seg := cum[mini(j + 1, AREA_SAMPLES)] - cum[j]
		var t := 0.0 if seg <= 0.0 else clampf((want - cum[j]) / seg, 0.0, 1.0)
		_area_to_height[k] = (float(j) + t) / AREA_SAMPLES

func _height_for_area(frac: float) -> float:
	if _area_to_height.is_empty():
		return frac
	var f := frac * AREA_SAMPLES
	var i := mini(int(f), AREA_SAMPLES - 1)
	return lerpf(_area_to_height[i], _area_to_height[i + 1], f - i)
