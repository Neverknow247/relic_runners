extends Node2D
class_name Projectile

@export var damage := 10.0
@export var speed = 1000.0
@export var lifetime = 3.0

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

func setup(_direction: Vector2, _projectile_type:= "basic"):
	direction = _direction.normalized()
	projectile_type = _projectile_type
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	position += direction * speed * delta

func setup_spell(_direction: Vector2, _spell_data: Dictionary, caster_id: int = 0, crit: bool = false):
	spell_data = _spell_data
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
	get_tree().create_timer(lifetime).timeout.connect(queue_free)

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
