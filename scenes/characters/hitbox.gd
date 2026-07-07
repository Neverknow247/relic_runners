extends Area2D
class_name Hitbox

@export var damage = 1
var caster_id: int = 0
var attacker_weapon: String = ""
var attacker_element: String = ""

func _on_area_entered(hurtbox: Area2D) -> void:
	if not hurtbox is Hurtbox:
		return
	if caster_id != 0 and hurtbox.owner_id == caster_id:
		return
	hurtbox.take_hit(self, damage)
