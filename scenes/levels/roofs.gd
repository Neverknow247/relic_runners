extends TileMapLayer

var normal_alpha = 1.0
var hidden_alpha = 0.35
var fade_speed = 10.0
var target_alpha = 1.0

func _process(delta: float) -> void:
	var color = modulate
	color.a = lerp(color.a, target_alpha, delta * fade_speed)
	modulate = color

func make_translucent(_body, _make_translucent):
	if !_body.is_multiplayer_authority():
		return
	else:
		target_alpha = hidden_alpha if _make_translucent else normal_alpha
