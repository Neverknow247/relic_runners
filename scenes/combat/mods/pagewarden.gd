extends WeaponMod
# Tome — Pagewarden: a spell tears out 3 pages that orbit you; each blocks one
# enemy bullet. While pages remain, every 3rd basic also flings a page as a slow
# homing shot.
#
# Pages are shared state: the spell's cast carries x.pages, and every peer that
# spawns the spell puts a PageOrbit on the caster's player node. Each peer's orbit
# draws the pages and blocks its own copies of enemy bullets (the caster's copy is
# the one that decides damage, like burst's bullet clear). A flung page is a
# derived cast tagged "page", so its spawn removes a page on every peer.

func on_spell_cast(_player, _weapon, _sd: Dictionary, cast: Dictionary) -> void:
	if derived(cast):
		return
	var x: Dictionary = cast.get("x", {})
	x["pages"] = 3
	cast["x"] = x

func on_projectile_spawn(proj, cast: Dictionary) -> void:
	var caster = caster_node(proj)
	if caster == null:
		return
	if cast.get("tag", "") == "page":
		var o = _orbit(caster)
		if o != null:
			o.pages = maxi(o.pages - 1, 0)
		return
	if int(cast.get("x", {}).get("pages", 0)) > 0 and !proj.spell_data.get("_explosion", false):
		var orbit = _orbit(caster)
		if orbit == null:
			orbit = PageOrbit.new()
			orbit.name = "page_orbit"
			caster.add_child(orbit)
		orbit.pages = 3

func on_basic_fire(player, weapon, _sd: Dictionary, cast: Dictionary) -> void:
	if derived(cast):
		return
	var s := st(player, weapon)
	s["count"] = int(s.get("count", 0)) + 1
	var orbit = _orbit(player)
	if int(s["count"]) % 3 != 0 or orbit == null or orbit.pages <= 0:
		return
	var o: Vector2 = player.global_position + orbit.page_offset(0)
	player.spawn_derived_cast(o, (player.aim_point() - o).normalized(), "default",
		{"tag": "page", "dm": 0.8, "spd": 0.5, "x": {"home": 1}})

func on_projectile_tick(proj, delta: float, cast: Dictionary) -> void:
	if cast.get("x", {}).get("home", 0):
		steer(proj, delta, 5.0, 1000.0)

static func _orbit(caster):
	var o = caster.get_node_or_null("page_orbit")
	return o if o != null and is_instance_valid(o) and !o.is_queued_for_deletion() else null

class PageOrbit extends Node2D:
	const RADIUS := 120.0
	var pages := 0
	func _ready() -> void:
		z_index = 20
	func page_offset(i: int) -> Vector2:
		var t := Time.get_ticks_msec() / 1000.0
		return Vector2.from_angle(TAU * i / maxf(pages, 1) + t * 2.5) * RADIUS
	func _process(_delta: float) -> void:
		if pages <= 0:
			queue_redraw()
			return
		var center: Vector2 = get_parent().global_position
		for b in get_tree().get_nodes_in_group("enemy_bullets"):
			if !is_instance_valid(b):
				continue
			for i in pages:
				if b.global_position.distance_to(center + page_offset(i)) <= 64.0:
					Fx.puff(get_tree(), b.global_position, Color(0.95, 0.92, 0.8), 0.6)
					b.queue_free()
					pages -= 1
					break
			if pages <= 0:
				break
		queue_redraw()
	func _draw() -> void:
		for i in pages:
			var p := page_offset(i)
			draw_rect(Rect2(p - Vector2(14, 18), Vector2(28, 36)), Color(0.95, 0.92, 0.8, 0.95))
			draw_line(p + Vector2(-8, -6), p + Vector2(8, -6), Color(0.4, 0.3, 0.2), 3.0)
			draw_line(p + Vector2(-8, 4), p + Vector2(8, 4), Color(0.4, 0.3, 0.2), 3.0)
