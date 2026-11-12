extends Node2D
class_name GroundZone

# One shared lingering-area node (docs/combat_redesign_plan.md §6.4): scorch,
# trails, ice floor, grove, spore cloud, brambles, rubble, vortex, glyphs, light.
# Spawned on EVERY peer by the code that simulates the parent effect (each peer
# runs its own copy, like projectiles). Damage goes through Hurtbox.take_hit with
# the zone's own Hitbox, so it lands once (defender authority). Enemy-state pulls,
# slows and roots run on the server only; heals only for the local player.
# Must not reference SpellData / Enemy / Player (preload cycle): duck-typed.

const HitboxScene := preload("res://scenes/characters/hitbox.tscn")

var shape := "circle"           # circle | ring | rect
var radius := 200.0
var inner := 0.0                 # ring inner radius
var length := 400.0              # rect (along local +x)
var width := 120.0
var lifetime := 3.0
var tick_damage := 0.0           # per tick, to enemies inside (through take_hit)
var tick_interval := 0.5
var heal_per_tick := 0.0         # local player inside
var blocks_bullets := false      # erases enemy bullets inside
var slow := 0.0                  # server: enemies inside move this much slower
var pull := 0.0                  # server: u/s toward the centre
var root_seeded := false         # server: seeded enemies inside are rooted
var velocity := Vector2.ZERO
var color := Color(1, 1, 1, 0.5)
var visual := "zone"             # zone | rubble | vortex | glyph | light | trail
var zone_group := ""
var hitbox: Hitbox = null
var on_enemy_inside: Callable    # optional, server, (enemy) per frame

var _age := 0.0
var _tick_left := 0.15

static func spawn(tree: SceneTree, pos: Vector2, src_hitbox, opts: Dictionary) -> GroundZone:
	if tree == null or tree.current_scene == null:
		return null
	var z := GroundZone.new()
	for k in opts:
		if k in z:
			z.set(k, opts[k])
	z.global_position = pos
	z.rotation = opts.get("rotation", 0.0)
	z._src = src_hitbox if src_hitbox is Dictionary else src_of(src_hitbox)
	tree.current_scene.add_child(z)
	return z

# The hitbox fields a zone inherits from its source (copied, so the source may die).
static func src_of(hb) -> Dictionary:
	if hb == null or !is_instance_valid(hb):
		return {}
	return {"caster_id": hb.caster_id, "attacker_weapon": hb.attacker_weapon,
		"attacker_element": hb.attacker_element, "from_player": hb.from_player,
		"attack_ref": hb.attack_ref, "is_spell": hb.is_spell, "cast": hb.cast}

var _src: Dictionary = {}

func _ready() -> void:
	z_index = 3 if visual != "light" else 2
	if zone_group != "":
		add_to_group(zone_group)
	hitbox = HitboxScene.instantiate()
	hitbox.auto_hit = false
	hitbox.collision_mask = 12          # player + enemy hurtboxes, never walls
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = _bound_radius()
	cs.shape = circle
	hitbox.add_child(cs)
	add_child(hitbox)
	if !_src.is_empty():
		hitbox.caster_id = _src["caster_id"]
		hitbox.attacker_weapon = _src["attacker_weapon"]
		hitbox.attacker_element = _src["attacker_element"]
		hitbox.attacker_crit_rate = 0.0
		hitbox.attacker_crit_damage = 0.0
		hitbox.from_player = _src["from_player"]
		hitbox.enemy_zone = !_src["from_player"]
		hitbox.attack_ref = _src["attack_ref"]
		hitbox.is_spell = _src["is_spell"]
		hitbox.cast = _src["cast"]
	_src = {}

func _bound_radius() -> float:
	if shape == "rect":
		return Vector2(length * 0.5, width * 0.5).length()
	return radius

func inside(p: Vector2) -> bool:
	var l := (p - global_position).rotated(-rotation)
	match shape:
		"ring":
			var d := l.length()
			return d >= inner and d <= radius
		"rect":
			return absf(l.x) <= length * 0.5 and absf(l.y) <= width * 0.5
	return l.length() <= radius

func _server() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	if velocity != Vector2.ZERO:
		global_position += velocity * delta
	if blocks_bullets:
		for b in get_tree().get_nodes_in_group("enemy_bullets"):
			if is_instance_valid(b) and inside(b.global_position):
				Fx.puff(get_tree(), b.global_position, color, 0.5)
				b.queue_free()
	var server := _server()
	var do_tick := false
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = tick_interval
		do_tick = true
	if do_tick and heal_per_tick > 0.0:
		var world = get_tree().get_first_node_in_group("world")
		if world != null and world.players != null:
			var me = world.players.get_node_or_null(str(multiplayer.get_unique_id()))
			if me != null and me.has_method("heal_capped") and inside(me.global_position):
				me.heal_capped(heal_per_tick, "zone")
	if hitbox == null:
		return
	for area in hitbox.get_overlapping_areas():
		if not area is Hurtbox or not hitbox.can_hit(area):
			continue
		if !inside(area.global_position):
			continue
		if do_tick and tick_damage > 0.0:
			area.take_hit(hitbox, tick_damage)
		if area.is_player or !server:
			continue
		var e = area.get_parent()
		if e == null or !e.has_method("fx_slow"):
			continue
		if slow > 0.0:
			e.fx_slow(slow, 0.25)
		if pull > 0.0:
			e.fx_pull(global_position, pull)
		if root_seeded and e.status_mask & StatusEffects.bit("seed") != 0:
			e.fx_root(0.3)
		if on_enemy_inside.is_valid():
			on_enemy_inside.call(e)
	queue_redraw()

func _draw() -> void:
	var k := 1.0 - clampf((_age - lifetime + 0.4) / 0.4, 0.0, 1.0)
	var c := color
	c.a *= k
	match visual:
		"rubble":
			var rng := RandomNumberGenerator.new()
			rng.seed = 1234
			var n := 7 if shape != "rect" else 9
			for i in n:
				var p: Vector2
				if shape == "rect":
					p = Vector2(lerpf(-length * 0.45, length * 0.45, float(i) / (n - 1)), rng.randf_range(-width * 0.3, width * 0.3))
				else:
					p = Vector2.from_angle(rng.randf() * TAU) * rng.randf() * radius * 0.8
				var r := rng.randf_range(26.0, 46.0)
				draw_circle(p, r, Color(0.25, 0.18, 0.1, c.a))
				draw_circle(p + Vector2(-4, -5), r * 0.75, Color(0.55, 0.42, 0.28, c.a))
		"vortex":
			for i in 3:
				var a0 := _age * 6.0 + TAU * i / 3.0
				draw_arc(Vector2.ZERO, radius * (0.4 + 0.2 * i), a0, a0 + 2.2, 24, c, 10.0)
		"light":
			draw_circle(Vector2.ZERO, radius, Color(c.r, c.g, c.b, c.a * 0.22))
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(c.r, c.g, c.b, c.a * 0.6), 4.0)
		"glyph":
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, c, 6.0)
			draw_arc(Vector2.ZERO, radius * 0.7, _age, _age + TAU, 6, c, 4.0)
			var tri := PackedVector2Array()
			for i in 3:
				tri.append(Vector2.from_angle(_age * 0.5 + TAU * i / 3.0) * radius * 0.7)
			tri.append(tri[0])
			draw_polyline(tri, c, 4.0)
		_:
			match shape:
				"ring":
					draw_arc(Vector2.ZERO, (radius + inner) * 0.5, 0.0, TAU, 48, c, maxf(radius - inner, 8.0))
				"rect":
					draw_rect(Rect2(-length * 0.5, -width * 0.5, length, width), Color(c.r, c.g, c.b, c.a * 0.45))
				_:
					draw_circle(Vector2.ZERO, radius, Color(c.r, c.g, c.b, c.a * 0.4))
					draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, c, 5.0)
