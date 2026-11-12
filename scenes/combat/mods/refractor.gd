extends WeaponMod
# Orb — Refractor: basic shots refract on hit into 2 weak shards at +/-30 degrees;
# spells refract when they end, throwing 3 shards outward. Local copies (no RPC).

func on_projectile_hit(proj, hurtbox, cast: Dictionary) -> void:
	if !is_basic(proj) or proj.spell_data.get("_shard", false) or hurtbox.is_player or derived(cast):
		return
	var origin: Vector2 = hurtbox.global_position + proj.direction * 90.0
	for a in [-PI / 6.0, PI / 6.0]:
		spawn_shard(proj, origin, proj.direction.rotated(a), maxf(proj.hitbox.attack_ref, 1.0) * 0.25, 0.5, 0.3, {"_shard": true})

func on_projectile_expire(proj, pos: Vector2, cast: Dictionary) -> void:
	if !is_spell_sd(proj.spell_data) or derived(cast) or proj.spell_data.get("_explosion", false):
		return
	for i in 3:
		var d: Vector2 = proj.direction.rotated(TAU * i / 3.0)
		spawn_shard(proj, pos + d * 60.0, d, maxf(proj.hitbox.attack_ref, 1.0) * 0.6, 0.7, 0.45, {"_shard": true})
