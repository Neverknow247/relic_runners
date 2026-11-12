extends WeaponMod
# Orb — Constellation: each basic hit lights a mote that orbits you (max 5); a
# spell launches every mote as a homing dart (weak element signature); getting hit
# knocks one loose.
const MAX_MOTES := 5

func on_projectile_hit(proj, hurtbox, cast: Dictionary) -> void:
	if !is_basic(proj) or derived(cast) or hurtbox.is_player or !caster_local(proj):
		return
	var c = caster_node(proj)
	if c == null:
		return
	var s := st(c, c.get_equipped_weapon())
	s["motes"] = mini(MAX_MOTES, int(s.get("motes", 0)) + 1)

func on_spell_cast(player, weapon, _sd: Dictionary, cast: Dictionary) -> void:
	if derived(cast):
		return
	var s := st(player, weapon)
	var n: int = s.get("motes", 0)
	s["motes"] = 0
	var t := Time.get_ticks_msec() / 1000.0
	for i in n:
		var origin: Vector2 = player.global_position + Vector2.from_angle(TAU * i / maxf(n, 1) + t * 2.0) * 110.0
		player.spawn_derived_cast(origin, (player.aim_point() - origin).normalized(), "default",
			{"tag": "mote", "dm": 0.6, "x": {"home": 1}})

func on_projectile_tick(proj, delta: float, cast: Dictionary) -> void:
	if cast.get("x", {}).get("home", 0):
		steer(proj, delta, 7.0, 1100.0)

func on_hurt(player, weapon, _amount: float) -> void:
	var s := st(player, weapon)
	s["motes"] = maxi(int(s.get("motes", 0)) - 1, 0)

func draw(player, weapon, canvas: CanvasItem) -> void:
	var n: int = st(player, weapon).get("motes", 0)
	var t := Time.get_ticks_msec() / 1000.0
	for i in n:
		var p := Vector2.from_angle(TAU * i / MAX_MOTES + t * 2.0) * 110.0
		canvas.draw_circle(p, 14.0, Color(1.0, 0.95, 0.6, 0.9))
		canvas.draw_circle(p, 7.0, Color.WHITE)
