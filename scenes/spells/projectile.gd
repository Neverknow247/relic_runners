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

func setup(_direction: Vector2, _projectile_type:= "basic"):
	direction = _direction.normalized()
	projectile_type = _projectile_type
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	# Fizzle once we've travelled the cap's worth of distance. Cheap distance_to
	# only matters for speed > 0 forms; stationary zones sit at _spawn_position so
	# this never trips for them.
	if max_distance > 0.0 and global_position.distance_to(_spawn_position) >= max_distance:
		_expire()

# The projectile has reached the end of its life (travelled its max distance or
# its lifetime timer ran out). Base behavior is to just disappear; subclasses
# override to do something first (ball_projectile.gd detonates its explosion).
func _expire() -> void:
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
	modulate = spell_data["color"]
	pierce = spell_data.get("pierce", false)
	stop_on_wall = spell_data.get("stop_on_wall", true)
	hitbox.caster_id = caster_id
	hitbox.damage = damage
	hitbox.auto_hit = spell_data.get("auto_hit", true)
	hitbox.attacker_weapon = spell_data["weapon"]
	hitbox.attacker_element = spell_data["element"]
	hitbox.is_crit = crit
	# Free after the form's ACTUAL lifetime. Started here (not in _ready) because
	# lifetime is only known once setup_spell runs — the stationary pierce forms
	# (burst/cone/beam/rain) rely on this timer for their whole duration since
	# they don't die on hit or by leaving the screen.
	get_tree().create_timer(lifetime).timeout.connect(_expire)

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	pass
	queue_free()

func _on_hitbox_area_entered(area: Area2D) -> void:
	# Never react to the caster's own hurtbox.
	if area is Hurtbox and hitbox.caster_id != 0 and area.owner_id == hitbox.caster_id:
		return
	# Piercing forms (AoE zones, wedges, beams) pass through hurtboxes instead
	# of being consumed by the first one they touch.
	if pierce:
		return
	queue_free()

func _on_hitbox_body_entered(_body: Node2D) -> void:
	if stop_on_wall:
		queue_free()
