extends Camera2D

# The player's camera: trauma-based screen shake + look-ahead toward the aim.
# Only does anything for the LOCAL player's camera (the only current one); remote
# players' cameras are inert copies.

# Shake: trauma 0..1 decays linearly; offset = trauma^2 * MAX (squared so small
# hits barely shake and big ones really kick).
const SHAKE_MAX_OFFSET := 90.0
const TRAUMA_DECAY := 1.8
# Look-ahead: lean toward where you're aiming so you see more of what you're
# shooting at than what's behind you. Fraction of the cursor offset, capped.
const LOOK_AHEAD_FRACTION := 0.22
const LOOK_AHEAD_MAX := 650.0
const LOOK_AHEAD_SMOOTH := 7.0

var trauma := 0.0
var _look := Vector2.ZERO
var _noise_t := 0.0

func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)

func _process(delta: float) -> void:
	var p := get_parent()
	if p == null or !is_current():
		return
	if p.has_method("is_multiplayer_authority") and multiplayer.multiplayer_peer != null and !p.is_multiplayer_authority():
		return
	# Look-ahead (skipped while a menu has the mouse).
	var target := Vector2.ZERO
	var inv = p.get("inventory_ui")
	var menu_open: bool = inv != null and inv.visible
	if !menu_open and p is Node2D:
		var to_mouse: Vector2 = get_global_mouse_position() - (p as Node2D).global_position
		target = (to_mouse * LOOK_AHEAD_FRACTION).limit_length(LOOK_AHEAD_MAX)
	_look = _look.lerp(target, clampf(LOOK_AHEAD_SMOOTH * delta, 0.0, 1.0))
	# Shake.
	var shake := Vector2.ZERO
	if trauma > 0.0:
		_noise_t += delta * 60.0
		var s := trauma * trauma
		shake = Vector2(sin(_noise_t * 1.7) + randf_range(-0.5, 0.5), cos(_noise_t * 2.3) + randf_range(-0.5, 0.5)) * SHAKE_MAX_OFFSET * s
		trauma = maxf(trauma - TRAUMA_DECAY * delta, 0.0)
	offset = _look + shake
