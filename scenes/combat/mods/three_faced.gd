extends WeaponMod
# Totem — Three-Faced: the totem rotates faces on each spell cast.
#   0 Wrath: basics pop in small blasts.
#   1 Guard: basic hits grant 2 barrier (cap 30).
#   2 Trick: every 5th basic leaves a decoy that enemies shoot at and blinks you ahead.
# The face rides cast["x"]["face"] so every peer agrees.

const FACE_COLORS := [Color(1.0, 0.4, 0.3), Color(0.45, 0.75, 1.0), Color(0.75, 0.45, 1.0)]

func _face(player, weapon) -> int:
	return int(st(player, weapon).get("face", 0))

func on_spell_cast(player, weapon, _sd: Dictionary, cast: Dictionary) -> void:
	if !derived(cast):
		var s := st(player, weapon)
		s["face"] = (_face(player, weapon) + 1) % 3

func on_basic_fire(player, weapon, sd: Dictionary, cast: Dictionary) -> void:
	var x: Dictionary = cast.get("x", {})
	x["face"] = _face(player, weapon)
	cast["x"] = x
	if derived(cast) or _face(player, weapon) != 2:
		return
	var s := st(player, weapon)
	s["n"] = int(s.get("n", 0)) + 1
	if int(s["n"]) % 5 == 0:
		var here: Vector2 = player.global_position
		player.request_taunt(here, 1.5, 1500.0)
		CombatFx.ring(player.get_tree(), here, 90.0, FACE_COLORS[2], 1.5, 8.0)
		var dir: Vector2 = sd.get("_dir", player.aim_direction)
		player.move_and_collide(dir * 260.0)

func on_projectile_hit(proj, hurtbox, cast: Dictionary) -> void:
	if !is_basic(proj) or hurtbox.is_player or derived(cast):
		return
	match int(cast.get("x", {}).get("face", 0)):
		0:
			local_burst(proj, hurtbox.global_position, 110.0, maxf(proj.hitbox.attack_ref, 1.0) * 0.25)
		1:
			if caster_local(proj):
				var c = caster_node(proj)
				if c != null:
					c.barrier = minf(c.barrier + 2.0, maxf(30.0, c.max_barrier))

func draw(player, weapon, canvas: CanvasItem) -> void:
	canvas.draw_circle(Vector2(0, -140), 14.0, FACE_COLORS[_face(player, weapon)])
