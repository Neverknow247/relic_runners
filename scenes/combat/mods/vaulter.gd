extends WeaponMod
# Staff — Vaulter: landing a roll sends a half-width ground ripple forward (basic
# damage, shoves); the first basic within 0.6 s of a roll is a wide Sweep; every
# spell ends in a ripple ring that pushes enemies outward.

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func on_roll(player, weapon, phase: String) -> void:
	if phase != "end":
		return
	var dir: Vector2 = player._roll_direction
	player.spawn_derived_cast(player.global_position + dir * 160.0, dir, "wave",
		{"tag": "ripple", "dm": 0.2, "lt": 0.45, "x": {"ripple": 1}})
	st(player, weapon)["sweep_until"] = _now() + 0.6

func on_basic_fire(player, weapon, sd: Dictionary, cast: Dictionary) -> void:
	if derived(cast):
		return
	var s := st(player, weapon)
	if _now() < float(s.get("sweep_until", 0.0)):
		s["sweep_until"] = 0.0
		sd["_suppress"] = true
		player.spawn_derived_cast(player.global_position, sd.get("_dir", player.aim_direction), "cone",
			{"tag": "sweep", "dm": 0.3, "sz": 0.7})

func on_projectile_spawn(proj, cast: Dictionary) -> void:
	if cast.get("x", {}).get("ripple", 0) and proj.has_method("set_width_mult"):
		proj.set_width_mult(0.5)

func on_projectile_expire(proj, pos: Vector2, cast: Dictionary) -> void:
	if !is_spell_sd(proj.spell_data) or derived(cast) or proj.spell_data.get("_explosion", false):
		return
	CombatFx.ring(proj.get_tree(), pos, 320.0, Color(0.85, 0.95, 0.7), 0.45, 14.0)
	if server(proj):
		for e in enemies_near(proj.get_tree(), pos, 320.0):
			e.fx_push((e.global_position - pos).normalized() * 2200.0)
