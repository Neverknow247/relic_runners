extends Projectile
class_name BallProjectile

# Travels like a normal projectile, but on striking an enemy it detonates a
# burst-style AoE at the impact point (damaging everyone nearby) instead of
# just dealing a single hit. Its own hitbox has auto_hit off (see FORMS), so all
# the ball's damage is delivered by the explosion — the struck enemy takes one
# explosion hit, not hit + explosion. Walls still stop it (base
# _on_hitbox_body_entered), but only an enemy triggers the explosion.

const ExplosionScene := preload("res://scenes/spells/burst_projectile.tscn")
# Explosion radius as a size multiplier (the burst scene is scaled by this).
const EXPLOSION_SIZE := 3.0
const EXPLOSION_LIFETIME := 0.3

var _exploded := false

func _on_hitbox_area_entered(area: Area2D) -> void:
	# Ignore the caster's own hurtbox; only an enemy detonates the ball.
	if not area is Hurtbox:
		return
	if hitbox.caster_id != 0 and area.owner_id == hitbox.caster_id:
		return
	if _exploded:
		return
	_exploded = true
	# Deferred: this fires from area_entered (a physics query flush), and adding
	# the explosion's own monitoring Area2D can't change physics state mid-flush.
	_explode.call_deferred()

func _explode() -> void:
	if spell_data.is_empty():
		queue_free()
		return
	var explosion = ExplosionScene.instantiate()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position
	# A stationary AoE at the impact point, carrying the ball's damage/element/
	# crit. auto_hit defaults true on the burst, so IT deals the damage.
	var exp_data := spell_data.duplicate()
	exp_data["speed"] = 0.0
	exp_data["spawn_offset"] = 0.0
	exp_data["lifetime"] = EXPLOSION_LIFETIME
	exp_data["size"] = EXPLOSION_SIZE
	exp_data["pierce"] = true
	exp_data["stop_on_wall"] = false
	exp_data["auto_hit"] = true
	explosion.setup_spell(direction, exp_data, hitbox.caster_id, hitbox.is_crit)
	queue_free()
