extends Projectile
class_name BurstProjectile

# A stationary AoE centred where it spawns (the burst stratagem, and the ball's
# detonation). A PLAYER's burst also deletes enemy bullets inside its radius — the
# "get me out of this" use of the stratagem — and kicks the screen.
func setup_spell(_direction: Vector2, _spell_data: Dictionary, caster_id: int = 0, crit: bool = false):
	super.setup_spell(_direction, _spell_data, caster_id, crit)
	if _enemy_shot:
		return
	var radius := VISUAL_RADIUS * scale.x
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		if is_instance_valid(b) and b.global_position.distance_to(global_position) <= radius:
			Fx.puff(get_tree(), b.global_position, b._tint, 0.6)
			b.queue_free()
	Fx.shatter(get_tree(), global_position, _tint, clampf(scale.x / 6.0, 0.8, 2.0))
	Fx.shake_at(get_tree(), global_position, 0.45)
