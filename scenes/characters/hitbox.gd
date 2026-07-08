extends Area2D
class_name Hitbox

@export var damage = 1
# When false, this hitbox never applies damage on area-enter — the owner drives
# damage itself instead (rain's per-second DoT ticks, ball's explosion). The
# projectile's own _on_hitbox_area_entered still fires for detection either way,
# since that's a separate signal connection.
@export var auto_hit := true
var caster_id: int = 0
var attacker_weapon: String = ""
var attacker_element: String = ""
# Set at spawn from a crit roll made once by the caster (see spell_data.gd's
# roll_crit()) and transmitted through the spawn RPC — never re-rolled here,
# so every peer that reads this agrees on the same result.
var is_crit: bool = false

func _on_area_entered(hurtbox: Area2D) -> void:
	if not auto_hit:
		return
	if not hurtbox is Hurtbox:
		return
	if caster_id != 0 and hurtbox.owner_id == caster_id:
		return
	hurtbox.take_hit(self, damage)
