extends WeaponMod
# Totem — Idolkeeper: a spell plants a spirit idol at your feet (8 s, one at a
# time). While it stands your basics are repeated from the idol toward your aim at
# 25%. Casting again moves it and it pulses your element where it lands.

const LIFE := 8.0

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func on_spell_cast(player, weapon, _sd: Dictionary, cast: Dictionary) -> void:
	if derived(cast):
		return
	var s := st(player, weapon)
	var had := _now() < float(s.get("idol_until", 0.0))
	s["idol_pos"] = player.global_position
	s["idol_until"] = _now() + LIFE
	var x: Dictionary = cast.get("x", {})
	x["idol"] = player.global_position
	cast["x"] = x
	if had:
		player.spawn_derived_cast(player.global_position, Vector2.RIGHT, "burst", {"tag": "idol", "dm": 0.12, "sz": 0.45})

func on_basic_fire(player, weapon, _sd: Dictionary, cast: Dictionary) -> void:
	if derived(cast):
		return
	var s := st(player, weapon)
	if _now() >= float(s.get("idol_until", 0.0)):
		return
	var o: Vector2 = s["idol_pos"]
	var dir: Vector2 = (player.aim_point() - o).normalized()
	player.spawn_derived_cast(o + dir * 60.0, dir, "default", {"tag": "idol", "dm": 0.25})

# Every peer: show the idol where the caster planted it.
func on_projectile_spawn(proj, cast: Dictionary) -> void:
	var p = cast.get("x", {}).get("idol", null)
	if !(p is Vector2) or proj.spell_data.get("_explosion", false):
		return
	var caster = caster_node(proj)
	if caster == null:
		return
	var old = caster.get_meta("idol_node") if caster.has_meta("idol_node") else null
	if old != null and is_instance_valid(old):
		old.queue_free()
	var m := IdolMarker.new()
	m.global_position = p
	m.color = proj.spell_data.get("color", Color.WHITE)
	m.life = LIFE
	proj.get_tree().current_scene.add_child(m)
	caster.set_meta("idol_node", m)

class IdolMarker extends Node2D:
	var color := Color.WHITE
	var life := 8.0
	var _t := 0.0
	func _ready() -> void:
		top_level = true
		z_index = 6
	func _process(delta: float) -> void:
		_t += delta
		if _t >= life:
			queue_free()
		queue_redraw()
	func _draw() -> void:
		var bob := sin(_t * 3.0) * 6.0
		draw_rect(Rect2(-22, -70 + bob, 44, 90), Color(0.35, 0.22, 0.15, 0.95))
		draw_rect(Rect2(-30, -78 + bob, 60, 18), color)
		draw_circle(Vector2(-9, -40 + bob), 6.0, color)
		draw_circle(Vector2(9, -40 + bob), 6.0, color)
		draw_arc(Vector2.ZERO, 70.0, 0.0, TAU * (1.0 - _t / life), 32, Color(color, 0.5), 4.0)
