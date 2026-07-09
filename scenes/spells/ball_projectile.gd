extends Projectile
class_name BallProjectile

# Travels like a normal projectile, but ALWAYS detonates a burst-style AoE when
# it ends — on striking an enemy, hitting a wall, running out its lifetime, or
# reaching its max travel distance. Its own hitbox has auto_hit off (see FORMS),
# so all the ball's damage is delivered by that explosion.

const ExplosionScene := preload("res://scenes/spells/burst_projectile.tscn")
# Explosion radius as a size multiplier (the burst scene is scaled by this).
const EXPLOSION_SIZE := 6.0
const EXPLOSION_LIFETIME := 0.3

var _exploded := false

func _on_hitbox_area_entered(area: Area2D) -> void:
	# Ignore the caster's own hurtbox; only an enemy detonates the ball early.
	if not area is Hurtbox:
		return
	if hitbox.caster_id != 0 and area.owner_id == hitbox.caster_id:
		return
	_expire()

func _on_hitbox_body_entered(_body: Node2D) -> void:
	# A fireball bursts on the wall it hits rather than silently vanishing.
	_expire()

# Every termination path (impact, wall, lifetime, max distance) funnels here so
# the ball explodes exactly once no matter how it ends.
func _expire() -> void:
	if _exploded:
		return
	_exploded = true
	# Deferred: _expire can fire from area/body_entered (a physics query flush),
	# and adding the explosion's monitoring Area2D can't happen mid-flush. Harmless
	# from the lifetime-timer / max-distance paths too.
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
