extends RefCounted
class_name WeaponMod

# Base hook interface for subclasses and traits (docs/combat_redesign_plan.md §6.3).
# Mods are STATELESS singletons: caster state lives in player.mod_state (see st()),
# projectile state on the projectile (meta / spell_data). Never reference
# SpellData / Player / Enemy here or in any mod script (preload cycle through the
# projectile scenes) — everything is duck-typed.
#
# Authority rule: anything that damages goes through a hitbox (take_hit) or
# take_secondary_hit on the server; anything that changes the caster (mana,
# cooldowns, heals, buffs) happens only in caster-side hooks; visuals anywhere.

var id := ""

# --- caster's own peer ---------------------------------------------------------
# Rewrite the basic's spell_data (pellets/spread/cooldown/damage_mult/size...).
# Must be PURE (called whenever the basic is previewed); consume state in on_basic_fire.
func modify_basic(_player, _weapon, _sd: Dictionary) -> void: pass
func on_basic_fire(_player, _weapon, _sd: Dictionary, _cast: Dictionary) -> void: pass
func on_spell_cast(_player, _weapon, _sd: Dictionary, _cast: Dictionary) -> void: pass
func on_roll(_player, _weapon, _phase: String) -> void: pass             # "start" / "end"
func on_graze(_player, _weapon, _bullet) -> void: pass                   # rolled through an enemy bullet
func on_kill(_player, _weapon, _info: Dictionary) -> void: pass          # {"pos","element","archetype","status_mask","spell","form","seed","mana_cost"}
func on_hurt(_player, _weapon, _amount: float) -> void: pass
func tick(_player, _weapon, _delta: float) -> void: pass
# Drawn on the caster's own screen (player.mod_canvas), local space of the player.
func draw(_player, _weapon, _canvas: CanvasItem) -> void: pass

# --- every peer that simulates the projectile --------------------------------------
func on_projectile_spawn(_proj, _cast: Dictionary) -> void: pass
func on_projectile_tick(_proj, _delta: float, _cast: Dictionary) -> void: pass
func on_projectile_hit(_proj, _hurtbox, _cast: Dictionary) -> void: pass
func on_projectile_wall(_proj, _cast: Dictionary) -> void: pass
func on_projectile_expire(_proj, _pos: Vector2, _cast: Dictionary) -> void: pass

# --- defender's authority (server, for enemies) ---------------------------------------
func on_hit_resolved(_defender, _hitbox, _damage: float, _advantage: bool) -> void: pass

# ====================================================================================
# Helpers
# ====================================================================================

const BaseProjectileScene := preload("res://scenes/spells/projectile.tscn")
const BurstScene := preload("res://scenes/spells/burst_projectile.tscn")

# Per-weapon, per-mod caster state.
func st(player, weapon) -> Dictionary:
	var key: String = (weapon.instance_id if weapon != null else "none") + ":" + id
	if !player.mod_state.has(key):
		player.mod_state[key] = {}
	return player.mod_state[key]

static func is_basic(proj) -> bool:
	return proj.spell_data.get("form", "default") == "default" or proj.spell_data.get("as_basic", false)

static func is_spell_sd(sd: Dictionary) -> bool:
	return sd.get("form", "default") != "default" and !sd.get("as_basic", false)

static func derived(cast: Dictionary) -> bool:
	return cast.has("tag")

static func server(node) -> bool:
	return node.multiplayer.multiplayer_peer == null or node.multiplayer.is_server()

static func caster_local(proj) -> bool:
	return proj.hitbox.caster_id == proj.multiplayer.get_unique_id()

static func local_player(tree: SceneTree):
	var world = tree.get_first_node_in_group("world")
	if world == null or world.players == null:
		return null
	return world.players.get_node_or_null(str(tree.get_multiplayer().get_unique_id()))

static func caster_node(proj):
	var world = proj.get_tree().get_first_node_in_group("world")
	if world == null or world.players == null:
		return null
	return world.players.get_node_or_null(str(proj.hitbox.caster_id))

static func enemy_of(hurtbox):
	if hurtbox == null or !is_instance_valid(hurtbox) or hurtbox.is_player:
		return null
	var e = hurtbox.get_parent()
	return e if e != null and "is_dead" in e and !e.is_dead else null

static func enemies_near(tree: SceneTree, pos: Vector2, radius: float, exclude = null) -> Array:
	var out := []
	for e in tree.get_nodes_in_group("enemies"):
		if e == exclude or !is_instance_valid(e) or e.is_dead:
			continue
		if e.global_position.distance_to(pos) <= radius:
			out.append(e)
	return out

static func nearest_enemy(tree: SceneTree, pos: Vector2, radius: float, exclude = null):
	var best = null
	var best_d := radius
	for e in tree.get_nodes_in_group("enemies"):
		if e == exclude or !is_instance_valid(e) or e.is_dead:
			continue
		var d: float = e.global_position.distance_to(pos)
		if d <= best_d:
			best_d = d
			best = e
	return best

# A local (non-networked) copy of a projectile — every peer simulating `proj`
# spawns the same copy, so no RPC is needed (forks, shards, echoes, undertow).
# `over` overwrites spell_data keys; dm/sz/lt multiply damage/size/lifetime.
static func spawn_local_copy(proj, pos: Vector2, dir: Vector2, over: Dictionary = {}) -> void:
	var d: Dictionary = proj.spell_data.duplicate()
	d["damage"] = float(d.get("damage", 0.0)) * float(over.get("dm", 1.0))
	d["size"] = float(d.get("size", 1.0)) * float(over.get("sz", 1.0))
	d["lifetime"] = float(d.get("lifetime", 1.0)) * float(over.get("lt", 1.0))
	for k in over:
		if k in ["dm", "sz", "lt"]:
			continue
		d[k] = over[k]
	var caster_id: int = proj.hitbox.caster_id
	Callable(WeaponMod, "_spawn_copy").call_deferred(proj.get_tree(), d, pos, dir, caster_id)

static func _spawn_copy(tree: SceneTree, d: Dictionary, pos: Vector2, dir: Vector2, caster_id: int) -> void:
	if tree == null or tree.current_scene == null or d.get("scene") == null:
		return
	var p = d["scene"].instantiate()
	tree.current_scene.add_child(p)
	p.global_position = pos
	p.setup_spell(dir, d, caster_id, false)

# A small plain shot built from `proj`'s identity (element/caster/crit), as a basic.
static func spawn_shard(proj, pos: Vector2, dir: Vector2, damage: float, size: float = 0.6, lifetime: float = 0.4, extra: Dictionary = {}) -> void:
	var d: Dictionary = proj.spell_data.duplicate()
	d["scene"] = BaseProjectileScene
	d["form"] = "default"
	d["speed"] = 3600.0
	d["size"] = size
	d["lifetime"] = lifetime
	d["damage"] = damage
	d["pierce"] = false
	d["auto_hit"] = true
	d["stop_on_wall"] = true
	d["quench"] = 0
	d["_fx"] = null
	d["bespoke"] = ""
	d["pierce_count"] = 0
	for k in extra:
		d[k] = extra[k]
	var caster_id: int = proj.hitbox.caster_id
	Callable(WeaponMod, "_spawn_copy").call_deferred(proj.get_tree(), d, pos, dir, caster_id)

# A one-shot AoE at `pos` with `proj`'s identity (no further fx, no bullet clear).
static func local_burst(proj, pos: Vector2, radius: float, damage: float, as_spell: bool = false) -> void:
	var d: Dictionary = proj.spell_data.duplicate()
	d["scene"] = BurstScene
	d["speed"] = 0.0
	d["size"] = radius / 32.0
	d["lifetime"] = 0.2
	d["pierce"] = true
	d["stop_on_wall"] = false
	d["auto_hit"] = true
	d["damage"] = damage
	d["no_clear"] = true
	d["_fx"] = null
	d["quench"] = 0
	d.erase("_explosion")
	if !as_spell:
		d["as_basic"] = true
	var caster_id: int = proj.hitbox.caster_id
	Callable(WeaponMod, "_spawn_copy").call_deferred(proj.get_tree(), d, pos, proj.direction, caster_id)

# Reflect off the wall just hit (ricochet). Returns false if no wall normal found.
static func ricochet(proj) -> bool:
	var space = proj.get_world_2d().direct_space_state
	var back: Vector2 = proj.global_position - proj.direction * 140.0
	var q := PhysicsRayQueryParameters2D.create(back, proj.global_position + proj.direction * 140.0)
	q.collision_mask = 1
	q.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return false
	var n: Vector2 = hit["normal"]
	proj.direction = proj.direction.bounce(n).normalized()
	proj.rotation = proj.direction.angle()
	proj.global_position = hit["position"] + n * 24.0
	# Survive this wall; stop on the next one.
	proj.stop_on_wall = false
	proj.get_tree().create_timer(0.06).timeout.connect(func():
		if is_instance_valid(proj):
			proj.stop_on_wall = true)
	return true

# Steer toward the nearest enemy (homing / seeking). max_total < 0 = unlimited.
static func steer(proj, delta: float, turn_rate: float, radius: float, max_total: float = -1.0) -> void:
	var target = nearest_enemy(proj.get_tree(), proj.global_position + proj.direction * radius * 0.5, radius)
	if target == null:
		return
	var want: Vector2 = (target.global_position - proj.global_position).normalized()
	var ang: float = proj.direction.angle_to(want)
	var step := clampf(ang, -turn_rate * delta, turn_rate * delta)
	if max_total >= 0.0:
		var used: float = proj.get_meta("steer_used", 0.0)
		step = clampf(step, -(max_total - used), max_total - used)
		proj.set_meta("steer_used", used + absf(step))
	proj.direction = proj.direction.rotated(step)
	proj.rotation = proj.direction.angle()
