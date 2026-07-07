extends Node2D
class_name Projectile

@export var damage := 10.0
@export var speed = 1000.0
@export var lifetime = 3.0

@onready var hitbox: Hitbox = $hitbox

var direction = Vector2.RIGHT
var projectile_type = "n/a"

func setup(_direction: Vector2, _projectile_type:= "basic"):
	direction = _direction.normalized()
	projectile_type = _projectile_type
	rotation = direction.angle()

func _ready() -> void:
	await get_tree().create_timer(lifetime).timeout
	queue_free()

func _physics_process(delta: float) -> void:
	position += direction * speed * delta

func setup_spell(_direction: Vector2, spell_data: Dictionary, caster_id: int = 0):
	setup(_direction, spell_data["element"])
	speed = spell_data["speed"]
	damage = spell_data["damage"]
	lifetime = spell_data["lifetime"]
	scale = Vector2.ONE * spell_data["size"]
	modulate = spell_data["color"]
	hitbox.caster_id = caster_id
	hitbox.damage = damage
	hitbox.attacker_weapon = spell_data["weapon"]
	hitbox.attacker_element = spell_data["element"]

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	pass
	queue_free()

func _on_hitbox_area_entered(area: Area2D) -> void:
	if area is Hurtbox and hitbox.caster_id != 0 and area.owner_id == hitbox.caster_id:
		return
	queue_free()

func _on_hitbox_body_entered(_body: Node2D) -> void:
	queue_free()
