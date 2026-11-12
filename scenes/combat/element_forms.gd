class_name ElementForms

# Element x form expressions for PLAYER stratagems (docs/combat_redesign_plan.md
# §5.2). The generic element status (Combat.apply_on_hit) always applies through
# the normal hit; these are each cell's extra expression. Six cells are BESPOKE
# (★): their form script checks spell_data["bespoke"] and hands behaviour over.
#
# Authority: runs on every peer that simulates the projectile. Anything that
# changes an ENEMY (freeze, stagger, push, pull, burn stacks, secondary damage)
# runs only where _server(proj) is true; spawned zones/bursts run everywhere and
# deal damage through take_hit (defender authority); heals only the local caster.
# Must never name SpellData / Enemy / Player — duck-typed fx_* calls on enemies.

const BurstScene := preload("res://scenes/spells/burst_projectile.tscn")
# Projectile.VISUAL_RADIUS (the base circle that `size` scales).
const PROJ_RADIUS := 32.0

const BESPOKE := {
	"fire:wave": "wildfire",
	"lightning:rain": "thunderstorm",
	"wind:ball": "tornado",
	"nature:rain": "grove",
	"water:wave": "tidal",
	"earth:rain": "boulderfall",
}

static func bespoke_for(element: String, form: String) -> String:
	return BESPOKE.get(element + ":" + form, "")

static func handle(key: String, event: String, proj, arg) -> void:
	match key:
		# --- fire ------------------------------------------------------------
		"fire:bolt":
			if event == "expire" or event == "wall":
				_zone(proj, _pos(proj, arg) - proj.direction * 200.0, {"shape": "rect", "length": 400.0, "width": 110.0,
					"rotation": proj.direction.angle(), "lifetime": 2.5, "tick_damage": _atk(proj) * 0.35,
					"color": _col(proj)})
		"fire:ball":
			if event == "spawn" and _is_explosion(proj):
				_zone(proj, proj.global_position, {"radius": _explosion_radius(proj), "lifetime": 3.0,
					"tick_damage": _atk(proj) * 0.4, "color": _col(proj)})
		"fire:rain":
			if event == "hit" and _server(proj):
				_enemy_call(arg, "fx_burn", [1.0, _atk(proj), proj.hitbox.caster_id])
		"fire:beam":
			if event == "hit" and _server(proj):
				var n := _count(proj, arg)
				# Ramp: after 0.6 s (3 ticks at 0.2) on one target, stacks double.
				_enemy_call(arg, "fx_burn", [1.0 if n > 3 else 0.5, _atk(proj), proj.hitbox.caster_id])
		"fire:burst":
			if event == "spawn":
				var r := _radius(proj)
				_zone(proj, proj.global_position, {"shape": "ring", "radius": r + 60.0, "inner": r - 20.0,
					"lifetime": 2.0, "tick_damage": _atk(proj) * 0.4, "color": _col(proj)})
		"fire:cone":
			if event == "hit" and _server(proj):
				_enemy_call(arg, "fx_burn", [3.0, _atk(proj), proj.hitbox.caster_id])
		"fire:wave":   # ★ Wildfire
			if event == "tick":
				_trail(proj, 150.0, {"radius": 190.0, "lifetime": 4.0, "tick_damage": _atk(proj) * 0.35,
					"color": _col(proj)})

		# --- lightning ---------------------------------------------------------
		"lightning:bolt":
			if event == "hit" and _server(proj):
				_enemy_call(arg, "fx_chain", [proj.hitbox.damage * 0.5, 3, 0.5, 520.0, proj.hitbox.caster_id, true])
		"lightning:ball":
			if event == "hit" and _server(proj) and _is_explosion(proj):
				_enemy_call(arg, "fx_chain", [proj.hitbox.damage * 0.5, 1, 1.0, 520.0, proj.hitbox.caster_id, false])
		"lightning:rain":   # ★ Thunderstorm
			if event == "tick":
				_strikes(proj, 8, 150.0, 1.4, "lightning")
		"lightning:beam":
			if event == "hit" and _server(proj) and _count(proj, arg) % 2 == 1:
				_enemy_call(arg, "fx_chain", [_beam_tick(proj) * 2.0, 2, 0.5, 520.0, proj.hitbox.caster_id, false])
		"lightning:burst":
			if event == "hit" and _server(proj):
				_enemy_call(arg, "fx_chain", [proj.hitbox.damage, 1, 0.3, 640.0, proj.hitbox.caster_id, false])
		"lightning:cone":
			if event == "hit" and _server(proj):
				_enemy_call(arg, "fx_chain", [proj.hitbox.damage, 1, 0.4, 640.0, proj.hitbox.caster_id, false])
		"lightning:wave":
			if event == "tick" and _server(proj) and _every(proj, "arc", arg, 0.3):
				var carried: Array = proj._carried.values() if "_carried" in proj else []
				for i in range(carried.size() - 1):
					var a = carried[i]
					var b = carried[i + 1]
					if is_instance_valid(a) and is_instance_valid(b):
						b.take_secondary_hit(proj.hitbox.damage * 0.1, "lightning", proj.hitbox.caster_id)
						a.fx_arc_visual(PackedVector2Array([a.global_position, b.global_position]))

		# --- ice ----------------------------------------------------------------
		"ice:bolt":
			if event == "hit" and !arg.is_player:
				var e = arg.get_parent()
				if e != null and "status_mask" in e and e.status_mask & StatusEffects.bit("frozen") != 0:
					_burst(proj, e.global_position, 240.0, proj.hitbox.damage * 0.6)
		"ice:ball":
			if event == "hit" and _server(proj) and _is_explosion(proj):
				_enemy_call(arg, "fx_freeze", [1.0])
		"ice:rain":
			if event == "spawn":
				_zone(proj, proj.global_position, {"radius": _radius(proj), "lifetime": proj.lifetime,
					"slow": 0.3, "color": Color(0.75, 0.95, 1.0, 0.35)})
		"ice:beam":
			if event == "hit" and _server(proj) and _count(proj, arg) == 5:
				_enemy_call(arg, "fx_freeze", [1.5])
		"ice:burst":
			if event == "hit" and _server(proj):
				_enemy_call(arg, "fx_freeze", [1.5])
		"ice:cone":
			if event == "hit" and _server(proj):
				_enemy_call(arg, "fx_chill", [100.0])
		"ice:wave":
			if event == "expire" and _server(proj) and "_carried" in proj:
				for e in proj._carried.values():
					if is_instance_valid(e):
						e.fx_freeze(1.5)

		# --- wind ----------------------------------------------------------------
		"wind:bolt":
			if event == "hit" and _server(proj):
				_enemy_call(arg, "fx_skewer", [proj.direction * 1800.0, 0.6, proj.hitbox.damage * 0.5, proj.hitbox.caster_id])
		"wind:ball":   # ★ Tornado (ball_projectile skips its explosion)
			if event == "expire":
				_zone(proj, _pos(proj, arg), {"radius": 280.0, "lifetime": 3.0, "velocity": proj.direction * 350.0,
					"pull": 900.0, "tick_damage": proj.hitbox.damage / 6.0, "blocks_bullets": true,
					"visual": "vortex", "color": Color(0.8, 1.0, 0.9, 0.85)})
		"wind:rain":
			if event == "spawn":
				_zone(proj, proj.global_position, {"radius": _radius(proj), "lifetime": proj.lifetime,
					"pull": 500.0, "visual": "vortex", "color": Color(0.8, 1.0, 0.9, 0.35)})
		"wind:beam":
			if event == "hit" and _server(proj):
				_enemy_call(arg, "fx_push", [Vector2.RIGHT.rotated(proj.rotation) * 1500.0])
		"wind:burst":
			if event == "spawn":
				_reflect_bullets(proj, proj.global_position, _radius(proj) * 1.5, -1.0)
			elif event == "hit" and _server(proj):
				var e = arg.get_parent()
				if e != null:
					_enemy_call(arg, "fx_push", [(e.global_position - proj.global_position).normalized() * 4200.0])
		"wind:cone":
			if event == "spawn":
				_reflect_bullets(proj, proj.global_position, 650.0, cos(PI / 4.0))
			elif event == "hit" and _server(proj):
				_enemy_call(arg, "fx_push", [proj.direction * 3200.0])
		"wind:wave":
			if event == "spawn":
				proj.max_distance *= 1.5
				proj.lifetime *= 1.5
				proj.spell_data["fling_mult"] = 3.0

		# --- nature ---------------------------------------------------------------
		"nature:bolt":
			pass   # spell seed = overgrown (double bloom) is the generic spell status
		"nature:ball":
			if event == "spawn" and _is_explosion(proj):
				var r := _explosion_radius(proj)
				_zone(proj, proj.global_position, {"shape": "ring", "radius": r + 90.0, "inner": r - 10.0,
					"lifetime": 2.0, "slow": 0.45, "color": Color(0.35, 0.6, 0.2, 0.6)})
		"nature:rain":   # ★ Sanctuary Grove: heals players inside each tick
			if event == "tick" and proj._call_down_left <= 0.0 and _every(proj, "grove", arg, 1.0):
				var me = _local_player(proj)
				if me != null and me.global_position.distance_to(proj.global_position) <= _radius(proj):
					me.heal_capped(8.0, "grove")
		"nature:beam":
			if event == "hit" and _caster_is_local(proj):
				var me = _local_player(proj)
				if me != null:
					me.heal_capped(_beam_tick(proj) * 0.03, "lifelink")
		"nature:burst":
			pass   # spell seed (8 s, overgrown) covers "dies within 4 s blooms"
		"nature:cone":
			if event == "spawn":
				_zone(proj, proj.global_position + proj.direction * 330.0, {"radius": 330.0, "lifetime": 3.0,
					"tick_damage": _atk(proj) * 0.1, "tick_interval": 0.5, "color": Color(0.5, 0.8, 0.35, 0.45)})
		"nature:wave":
			if event == "tick":
				_trail(proj, 160.0, {"radius": 200.0, "lifetime": 4.0, "root_seeded": true,
					"color": Color(0.35, 0.7, 0.25, 0.45)})

		# --- water -------------------------------------------------------------------
		"water:bolt":
			if event == "tick":
				proj.erase_enemy_bullets(proj.global_position, 96.0)
		"water:ball":
			if event == "spawn" and _is_explosion(proj):
				proj.erase_enemy_bullets(proj.global_position, _explosion_radius(proj) * 1.5)
		"water:rain":
			if event == "tick":
				proj.erase_enemy_bullets(proj.global_position, _radius(proj))
		"water:beam":
			if event == "tick":
				_erase_along(proj, Vector2.RIGHT.rotated(proj.rotation), 1360.0, 70.0)
			elif event == "hit" and _server(proj):
				var e = arg.get_parent()
				if e != null and "status_mask" in e and e.status_mask & StatusEffects.bit("soak") != 0:
					_enemy_call(arg, "fx_push", [Vector2.RIGHT.rotated(proj.rotation) * 700.0])
		"water:burst":
			if event == "spawn":
				proj.erase_enemy_bullets(proj.global_position, _radius(proj) * 2.0)
		"water:cone":
			if event == "spawn":
				_erase_cone(proj, proj.global_position, proj.direction, 650.0, cos(PI / 4.0))
		"water:wave":   # ★ Tidal Wave: 50% wider, erases every bullet it crosses
			if event == "spawn":
				if proj.has_method("set_width_mult"):
					proj.set_width_mult(1.5)
			elif event == "tick":
				var hw: float = 320.0 * float(proj.width_mult)
				_erase_along(proj, proj.direction.orthogonal(), hw * 2.0, 80.0, proj.global_position - proj.direction.orthogonal() * hw)

		# --- earth ----------------------------------------------------------------------
		"earth:bolt":
			if event == "hit":
				proj.pierce = false   # staggers the first enemy and stops (spell sunder = stagger)
		"earth:ball":
			if event == "hit" and _server(proj) and _is_explosion(proj):
				_enemy_call(arg, "fx_armor_break", [6.0])
		"earth:rain":   # ★ Boulderfall
			if event == "tick":
				_strikes(proj, 5, 180.0, 1.6, "earth", true)
		"earth:beam":
			if event == "hit" and _server(proj):
				_enemy_call(arg, "fx_armor_break", [0.5])
				_enemy_call(arg, "fx_shield_crack", [_beam_tick(proj) * 3.0])
		"earth:burst":
			if event == "hit" and _server(proj):
				var e = arg.get_parent()
				if e != null:
					_enemy_call(arg, "fx_push", [(e.global_position - proj.global_position).normalized() * 2600.0])
		"earth:cone":
			if event == "spawn":
				_zone(proj, proj.global_position + proj.direction * 520.0, {"shape": "rect", "length": 120.0,
					"width": 520.0, "rotation": proj.direction.angle(), "lifetime": 3.0, "blocks_bullets": true,
					"visual": "rubble", "color": Color(0.6, 0.45, 0.25, 1.0)})
		"earth:wave":
			if event == "spawn":
				proj.spell_data["slam_frac"] = 1.0
				proj.spell_data["slam_stagger"] = true

# --- helpers ---------------------------------------------------------------------------

static func _server(proj) -> bool:
	return proj.multiplayer.multiplayer_peer == null or proj.multiplayer.is_server()

static func _caster_is_local(proj) -> bool:
	return proj.hitbox.caster_id == proj.multiplayer.get_unique_id()

static func _local_player(proj):
	var world = proj.get_tree().get_first_node_in_group("world")
	if world == null or world.players == null:
		return null
	var me = world.players.get_node_or_null(str(proj.multiplayer.get_unique_id()))
	return me if me != null and me.has_method("heal_capped") else null

static func _atk(proj) -> float:
	return maxf(proj.hitbox.attack_ref, 1.0)

static func _col(proj) -> Color:
	var c: Color = proj.spell_data.get("color", Color.WHITE)
	c.a = 0.7
	return c

static func _pos(proj, arg) -> Vector2:
	return arg if arg is Vector2 else proj.global_position

static func _radius(proj) -> float:
	return PROJ_RADIUS * proj.scale.x

static func _is_explosion(proj) -> bool:
	return proj.spell_data.get("_explosion", false)

static func _explosion_radius(proj) -> float:
	return PROJ_RADIUS * proj.scale.x

# Beam tick damage (the beam spreads its damage over 0.2 s ticks).
static func _beam_tick(proj) -> float:
	return proj.hitbox.damage * 0.2 / maxf(proj.lifetime, 0.01)

static func _enemy_call(hurtbox, method: String, args: Array) -> void:
	if hurtbox == null or !is_instance_valid(hurtbox) or hurtbox.is_player:
		return
	var e = hurtbox.get_parent()
	if e != null and e.has_method(method) and !e.is_dead:
		e.callv(method, args)

# Per-target hit counter on the projectile (beam ramps / freeze ray).
static func _count(proj, hurtbox) -> int:
	var counts: Dictionary = proj.get_meta("fx_counts", {})
	var n: int = int(counts.get(hurtbox.owner_id, 0)) + 1
	counts[hurtbox.owner_id] = n
	proj.set_meta("fx_counts", counts)
	return n

# True once every `interval` seconds of "tick" deltas.
static func _every(proj, key: String, delta, interval: float) -> bool:
	var t: float = float(proj.get_meta("fx_t_" + key, 0.0)) + (float(delta) if delta != null else 0.0)
	if t >= interval:
		proj.set_meta("fx_t_" + key, t - interval)
		return true
	proj.set_meta("fx_t_" + key, t)
	return false

# Deferred: hit/wall events fire inside physics callbacks, where adding an Area2D
# is not allowed. The source hitbox's fields are copied now (the projectile may be
# gone by the time the deferred call runs).
static func _zone(proj, pos: Vector2, opts: Dictionary) -> void:
	Callable(GroundZone, "spawn").call_deferred(proj.get_tree(), pos, GroundZone.src_of(proj.hitbox), opts)

# Drops a zone every `step` units the projectile travels.
static func _trail(proj, step: float, opts: Dictionary) -> void:
	var last: Vector2 = proj.get_meta("fx_trail", proj._spawn_position)
	if proj.global_position.distance_to(last) >= step:
		proj.set_meta("fx_trail", proj.global_position)
		_zone(proj, proj.global_position, opts)

# A one-shot AoE at `pos` carrying the projectile's element (no further fx).
static func _burst(proj, pos: Vector2, radius: float, damage: float, flags: Dictionary = {}) -> void:
	var d: Dictionary = proj.spell_data.duplicate()
	d["speed"] = 0.0
	d["size"] = radius / PROJ_RADIUS
	d["lifetime"] = 0.2
	d["pierce"] = true
	d["stop_on_wall"] = false
	d["auto_hit"] = true
	d["damage"] = damage
	d["no_clear"] = true
	d["_fx"] = null
	d.erase("_explosion")
	for k in flags:
		d[k] = flags[k]
	Callable(ElementForms, "_spawn_burst").call_deferred(proj.get_tree(), pos, d, proj.direction, proj.hitbox.caster_id)

static func _spawn_burst(tree: SceneTree, pos: Vector2, d: Dictionary, dir: Vector2, caster_id: int) -> void:
	if tree == null or tree.current_scene == null:
		return
	var b = BurstScene.instantiate()
	tree.current_scene.add_child(b)
	b.global_position = pos
	b.setup_spell(dir, d, caster_id, false)

# Thunderstorm / Boulderfall: `count` seeded strikes spread over the zone's active
# time. Same seed on every peer -> same spots; the server's copies deal damage.
static func _strikes(proj, count: int, radius: float, dmg_mult: float, kind: String, rubble: bool = false) -> void:
	if proj._call_down_left > 0.0:
		return
	var done: int = proj.get_meta("fx_strikes", 0)
	if done >= count:
		return
	var active: float = maxf(proj.lifetime - 1.0, 1.0)
	var interval: float = minf(active / count, 0.6 if kind == "earth" else 99.0)
	var t: float = float(proj.get_meta("fx_strike_t", interval)) + proj.get_physics_process_delta_time()
	if t < interval:
		proj.set_meta("fx_strike_t", t)
		return
	proj.set_meta("fx_strike_t", 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(proj.spell_data.get("cast", {}).get("seed", 0)) + done * 7919
	var zr := _radius(proj) * 0.9
	var pos: Vector2 = proj.global_position + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * zr
	proj.set_meta("fx_strikes", done + 1)
	var dmg: float = proj.hitbox.damage / count * dmg_mult
	if kind == "lightning":
		CombatFx.arc(proj.get_tree(), PackedVector2Array([pos + Vector2(rng.randf_range(-120, 120), -1100), pos]))
	else:
		CombatFx.ring(proj.get_tree(), pos, radius, Color(0.6, 0.45, 0.25), 0.4, 16.0)
		Fx.shake_at(proj.get_tree(), pos, 0.3)
	_burst(proj, pos, radius, dmg)
	if rubble:
		_zone(proj, pos, {"radius": 120.0, "lifetime": 6.0, "blocks_bullets": true, "visual": "rubble",
			"color": Color(0.6, 0.45, 0.25, 1.0)})

# Turn enemy bullets around (wind). min_dot < -0.5 = all directions; otherwise only
# bullets in front of the caster within the cone.
static func _reflect_bullets(proj, center: Vector2, radius: float, min_dot: float) -> void:
	for b in proj.get_tree().get_nodes_in_group("enemy_bullets"):
		if !is_instance_valid(b):
			continue
		var to: Vector2 = b.global_position - center
		if to.length() > radius:
			continue
		if min_dot > -0.5 and to.normalized().dot(proj.direction) < min_dot:
			continue
		b.direction = -b.direction
		b.rotation = b.direction.angle()
		b.remove_from_group("enemy_bullets")
		b._enemy_shot = false
		b.hitbox.from_player = true
		b.hitbox.enemy_zone = false
		b.hitbox.caster_id = proj.hitbox.caster_id
		b.queue_redraw()

static func _erase_cone(proj, center: Vector2, dir: Vector2, radius: float, min_dot: float) -> void:
	for b in proj.get_tree().get_nodes_in_group("enemy_bullets"):
		if !is_instance_valid(b):
			continue
		var to: Vector2 = b.global_position - center
		if to.length() <= radius and to.normalized().dot(dir) >= min_dot:
			Fx.puff(proj.get_tree(), b.global_position, Color(0.4, 0.65, 1.0), 0.6)
			b.queue_free()

# Erase bullets within `half_w` of the segment origin -> origin + dir * length.
static func _erase_along(proj, dir: Vector2, length: float, half_w: float, origin = null) -> void:
	var o: Vector2 = origin if origin is Vector2 else proj.global_position
	for b in proj.get_tree().get_nodes_in_group("enemy_bullets"):
		if !is_instance_valid(b):
			continue
		var l: Vector2 = b.global_position - o
		var along := l.dot(dir)
		if along >= 0.0 and along <= length and absf(l.dot(dir.orthogonal())) <= half_w:
			Fx.puff(proj.get_tree(), b.global_position, Color(0.4, 0.65, 1.0), 0.6)
			b.queue_free()
