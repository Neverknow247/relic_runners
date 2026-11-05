extends Area2D
class_name Hurtbox

var owner_id: int = 0
# True on a PLAYER's hurtbox (set in player.gd). Used by Hitbox.can_hit to turn
# off friendly fire between players.
var is_player := false

var is_invincible = false:
	set(value):
		is_invincible = value
		disable.call_deferred(value)

signal hurt(hitbox, damage)

func take_hit(hitbox, damage):
	if is_invincible: return
	hurt.emit(hitbox, damage)

func disable(value):
	for child in get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			child.disabled = value
