extends Node2D
class_name Projectile

# These are always overwritten per-cast in setup_spell() from the values
# build_spell_data() computes (see SpellData.BASE_DAMAGE / BASE_SPEED /
# BASE_LIFETIME) — the 0 defaults are just placeholders, not real magic numbers.
@export var damage := 0.0
@export var speed := 0.0
@export var lifetime := 0.0

@onready var hitbox: Hitbox = $hitbox

var direction = Vector2.RIGHT
var projectile_type = "n/a"
# Per-form behavior, set from spell_data in setup_spell(). pierce = don't get
# destroyed when hitting a hurtbox (multi-hit AoE / persistent zones);
# stop_on_wall = get destroyed on a wall body. The full spell_data is kept so
# subclasses (e.g. ball_projectile.gd's explosion) can derive a follow-up cast.
var pierce := false
var stop_on_wall := true
var spell_data: Dictionary = {}
# How far this projectile may TRAVEL from its spawn point before it fizzles, so
# you can't snipe enemies from beyond the range they could ever notice you (kept
# in sync with the enemy detection radius via SpellData.ENGAGEMENT_RANGE). 0 = no
# cap. Only affects moving forms — stationary zones (rain/burst/cone) never
# travel, and the beam overrides _physics_process so it isn't touched.
var max_distance := 0.0
var _spawn_position := Vector2.ZERO
# Water basic (Quench): this many enemy bullets it can cancel on contact; the
# shot is consumed by the cancel. Each peer runs its own copy (like burst's clear).
var _quench := 0
# Event hook for element x form expressions and weapon mods (combat plan §6.2).
# spell_data["_fx"] is a Callable set by the caster (player.gd); this script never
# names the router (CastFx), which keeps it out of the preload cycle.
var _has_fx := false

func _fx(event: String, arg = null) -> void:
	if !_has_fx:
		return
	var cb = spell_data.get("_fx")
	if cb is Callable and cb.is_valid():
		cb.call(event, self, arg)
const QUENCH_RADIUS := 72.0

func setup(_direction: Vector2, _projectile_type:= "basic"):
	direction = _direction.normalized()
	projectile_type = _projectile_type
	rotation = direction.angle()

# Bullet visuals (the hitbox stays the radius-32 circle regardless). Drawn in local
# space, scaled by the node's scale (spell_data size) and rotated to face travel.
#  - Stationary zones (rain/beam/burst/cone, speed 0): the original black-ringed
#    circle, tinted by modulate.
#  - ENEMY shots: a dark-rimmed arrowhead diamond, element-coloured, white-hot core,
#    so hostile fire never looks like yours, even in a matching element.
#  - PLAYER shots: a black-outlined streak, tinted by modulate.
const VISUAL_RADIUS := 32.0
const OUTLINE_WIDTH := 6.0
var _enemy_shot := false
var _tint := Color.WHITE

func _draw() -> void:
	if speed <= 0.0:
		draw_circle(Vector2.ZERO, VISUAL_RADIUS, Color.BLACK)
		draw_circle(Vector2.ZERO, VISUAL_RADIUS - OUTLINE_WIDTH, Color.WHITE)
	elif _enemy_shot:
		var r := VISUAL_RADIUS + 8.0
		draw_colored_polygon(_diamond(r * 1.35, r), Color(0.06, 0.0, 0.04))
		draw_colored_polygon(_diamond(r * 1.1, r * 0.78), _tint)
		draw_circle(Vector2.ZERO, r * 0.34, _tint.lerp(Color.WHITE, 0.8))
	else:
		_draw_streak(VISUAL_RADIUS * 1.15, VISUAL_RADIUS * 0.62, Color.BLACK)
		_draw_streak(VISUAL_RADIUS * 1.15 - OUTLINE_WIDTH, VISUAL_RADIUS * 0.62 - OUTLINE_WIDTH, Color.WHITE)

# A diamond pointing along +x (travel direction): long axis `length`, half-width `w`.
func _diamond(length: float, w: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(length, 0), Vector2(0, w), Vector2(-length * 0.75, 0), Vector2(0, -w)])

# A capsule along +x: half-length `half_len`, radius `r`.
func _draw_streak(half_len: float, r: float, color: Color) -> void:
	draw_rect(Rect2(-half_len, -r, half_len * 2.0, r * 2.0), color)
	draw_circle(Vector2(half_len, 0), r, color)
	draw_circle(Vector2(-half_len, 0), r, color)

func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	if _quench > 0 and !_enemy_shot:
		_try_quench()
	if _has_fx:
		_fx("tick", delta)
	# Fizzle once we've travelled the cap's worth of distance. Cheap distance_to
	# only matters for speed > 0 forms; stationary zones sit at _spawn_position so
	# this never trips for them.
	if max_distance > 0.0 and global_position.distance_to(_spawn_position) >= max_distance:
		_expire()

func _try_quench() -> void:
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		if is_instance_valid(b) and b != self and b.global_position.distance_to(global_position) <= QUENCH_RADIUS:
			Fx.puff(get_tree(), b.global_position, Color(0.4, 0.65, 1.0), 0.7)
			b.queue_free()
			_quench -= 1
			if _quench <= 0:
				Fx.puff(get_tree(), global_position, _tint, 0.6)
				queue_free()
			return

# Shared bullet erase (water forms): frees enemy bullets within `radius` of `center`.
func erase_enemy_bullets(center: Vector2, radius: float) -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		if is_instance_valid(b) and b.global_position.distance_to(center) <= radius:
			Fx.puff(get_tree(), b.global_position, Color(0.4, 0.65, 1.0), 0.6)
			b.queue_free()
			n += 1
	return n

# The projectile has reached the end of its life (travelled its max distance or
# its lifetime timer ran out). Base behavior is to just disappear; subclasses
# override to do something first (ball_projectile.gd detonates its explosion).
func _expire() -> void:
	_fx("expire", global_position)
	queue_free()

# The node that cast this projectile — a player (under world.players, keyed by
# peer id) or an enemy (in the "enemies" group, matched by name.hash()), or null
# if it can't be found. Used by forms that follow or line-of-sight-check from the
# caster (beam follows it; rain raycasts from it). hitbox.caster_id is set by
# setup_spell, so this is valid any time after that.
func _resolve_caster() -> Node2D:
	var world = get_tree().get_first_node_in_group("world")
	if world != null and world.players.has_node(str(hitbox.caster_id)):
		return world.players.get_node(str(hitbox.caster_id))
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.name.hash() == hitbox.caster_id:
			return e
	return null

func setup_spell(_direction: Vector2, _spell_data: Dictionary, caster_id: int = 0, crit: bool = false):
	spell_data = _spell_data
	# global_position is set by the spawner BEFORE this call, so it's the true
	# spawn point to measure travel from. max_distance comes in via the data dict
	# (built by SpellData.build_spell_data) rather than referencing SpellData
	# here — a back-reference would form a preload compile cycle. 0 = uncapped.
	_spawn_position = global_position
	max_distance = spell_data.get("max_distance", 0.0)
	setup(_direction, spell_data["element"])
	speed = spell_data["speed"]
	damage = spell_data["damage"]
	lifetime = spell_data["lifetime"]
	scale = Vector2.ONE * spell_data["size"]
	_enemy_shot = spell_data.get("from_enemy", false)
	_tint = spell_data["color"]
	# Enemy shots draw their colours explicitly (see _draw); tinting the whole node
	# would muddy the dark rim and the white core.
	modulate = Color.WHITE if _enemy_shot and speed > 0.0 else spell_data["color"]
	# Moving enemy bullets are findable so a player's burst can clear them.
	if _enemy_shot and speed > 0.0:
		add_to_group("enemy_bullets")
	_play_spawn_sound()
	queue_redraw()
	pierce = spell_data.get("pierce", false)
	stop_on_wall = spell_data.get("stop_on_wall", true)
	hitbox.caster_id = caster_id
	hitbox.damage = damage
	hitbox.auto_hit = spell_data.get("auto_hit", true)
	hitbox.attacker_weapon = spell_data["weapon"]
	hitbox.attacker_element = spell_data["element"]
	# The attacker's crit stats ride along so the DEFENDER resolves crit at hit time.
	hitbox.attacker_crit_rate = spell_data.get("attacker_crit_rate", 0.0)
	hitbox.attacker_crit_damage = spell_data.get("attacker_crit_damage", 0.0)
	hitbox.is_crit = crit
	hitbox.from_player = not spell_data.get("from_enemy", false)
	hitbox.enemy_zone = spell_data.get("from_enemy", false) and spell_data.get("speed", 0.0) <= 0.0
	var dm: float = spell_data.get("damage_mult", 1.0)
	hitbox.attack_ref = spell_data.get("attack_ref", damage / maxf(dm, 0.01))
	hitbox.is_spell = spell_data.get("form", "default") != "default"
	hitbox.cast = spell_data.get("cast", {})
	_quench = int(spell_data.get("quench", 0))
	var cb = spell_data.get("_fx")
	_has_fx = cb is Callable and cb.is_valid()
	if _has_fx:
		# Deferred so subclass setup (rain's wall clamp, wave sizing) is done first.
		_fx.call_deferred("spawn")
	# Free after the form's ACTUAL lifetime. Started here (not in _ready) because
	# lifetime is only known once setup_spell runs — the stationary pierce forms
	# (burst/cone/beam/rain) rely on this timer for their whole duration since
	# they don't die on hit. Moving shots die at lifetime OR max_distance — never
	# on leaving a screen: each peer simulates its own copy, so a screen-exit free
	# on the HOST deleted shots still flying toward a distant client (lost hits).
	get_tree().create_timer(lifetime).timeout.connect(_expire)

# Every peer spawns its own copy of every shot, so playing here gives everyone the
# sound, positioned where it was fired.
func _play_spawn_sound() -> void:
	var form: String = spell_data.get("form", "default")
	if _enemy_shot:
		Sounds.play_sfx("enemy_shoot", global_position, -6.0)
	elif form != "default":
		Sounds.play_sfx("spell_cast", global_position)
	else:
		# Every weapon fires the same basic, so one basic-shot sound for all.
		Sounds.play_sfx("shoot_wand", global_position, -4.0)

func _on_hitbox_area_entered(area: Area2D) -> void:
	# Pass over anything this projectile can't damage — the caster's own hurtbox,
	# and allied enemies (so an enemy bullet doesn't die on an enemy in the way).
	if area is Hurtbox and not hitbox.can_hit(area):
		return
	# Rolled through: the bullet keeps flying (EtG-style) rather than vanishing on
	# an invulnerable player. (Only the victim's own peer knows its i-frames, so
	# other peers may still show it popping; damage is decided on the victim.)
	if area is Hurtbox and area.is_player:
		var owner_node = area.get_parent()
		if owner_node != null and owner_node.has_method("is_invulnerable") and owner_node.is_invulnerable():
			return
	# Only where THIS overlap delivers the damage (auto_hit). Forms that drive their
	# own damage (cone/beam/rain/wave ticks) fire "hit" from their own loops.
	if area is Hurtbox and hitbox.auto_hit:
		_fx("hit", area)
	# Piercing forms (AoE zones, wedges, beams) pass through hurtboxes instead
	# of being consumed by the first one they touch.
	if pierce:
		return
	Fx.puff(get_tree(), global_position, _tint, scale.x)
	Sounds.play_sfx("hit", global_position, -3.0)
	# A stratagem connecting should feel like one.
	if !_enemy_shot and spell_data.get("form", "default") != "default":
		Fx.shatter(get_tree(), global_position, _tint, 0.9)
		Fx.shake_at(get_tree(), global_position, 0.3)
	_fx("expire", global_position)
	queue_free()

func _on_hitbox_body_entered(_body: Node2D) -> void:
	if stop_on_wall:
		_fx("wall")
		if !stop_on_wall or is_queued_for_deletion():
			return   # a mod (ricochet) kept us alive / already handled it
		Fx.puff(get_tree(), global_position, _tint, scale.x * 0.7)
		_fx("expire", global_position)
		queue_free()
