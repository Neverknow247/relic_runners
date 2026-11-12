extends WeaponMod
# Tome — Pagewarden: a spell tears out 3 pages that orbit you; each blocks one
# enemy bullet (on your own screen — your damage resolves on your peer). While
# pages remain, every 3rd basic also flings a page as a slow homing shot.

const ORBIT := 120.0

func _pages(player, weapon) -> int:
	return int(st(player, weapon).get("pages", 0))

func on_spell_cast(player, weapon, _sd: Dictionary, cast: Dictionary) -> void:
	if !derived(cast):
		st(player, weapon)["pages"] = 3

func _page_pos(player, i: int, n: int) -> Vector2:
	var t := Time.get_ticks_msec() / 1000.0
	return player.global_position + Vector2.from_angle(TAU * i / maxf(n, 1) + t * 2.5) * ORBIT

func tick(player, weapon, _delta: float) -> void:
	var n := _pages(player, weapon)
	if n <= 0:
		return
	for b in player.get_tree().get_nodes_in_group("enemy_bullets"):
		if !is_instance_valid(b):
			continue
		for i in n:
			if b.global_position.distance_to(_page_pos(player, i, n)) <= 64.0:
				Fx.puff(player.get_tree(), b.global_position, Color(0.95, 0.92, 0.8), 0.6)
				b.queue_free()
				st(player, weapon)["pages"] = n - 1
				return

func on_basic_fire(player, weapon, _sd: Dictionary, cast: Dictionary) -> void:
	if derived(cast):
		return
	var s := st(player, weapon)
	s["count"] = int(s.get("count", 0)) + 1
	if int(s["count"]) % 3 != 0 or _pages(player, weapon) <= 0:
		return
	s["pages"] = _pages(player, weapon) - 1
	var o := _page_pos(player, 0, 1)
	player.spawn_derived_cast(o, (player.aim_point() - o).normalized(), "default",
		{"tag": "page", "dm": 0.8, "spd": 0.5, "x": {"home": 1}})

func on_projectile_tick(proj, delta: float, cast: Dictionary) -> void:
	if cast.get("x", {}).get("home", 0):
		steer(proj, delta, 5.0, 1000.0)

func draw(player, weapon, canvas: CanvasItem) -> void:
	var n := _pages(player, weapon)
	for i in n:
		var p: Vector2 = _page_pos(player, i, n) - player.global_position
		canvas.draw_rect(Rect2(p - Vector2(14, 18), Vector2(28, 36)), Color(0.95, 0.92, 0.8, 0.95))
		canvas.draw_line(p + Vector2(-8, -6), p + Vector2(8, -6), Color(0.4, 0.3, 0.2), 3.0)
		canvas.draw_line(p + Vector2(-8, 4), p + Vector2(8, 4), Color(0.4, 0.3, 0.2), 3.0)
