extends WeaponMod
# Basic-group traits: piercing / rebound / lingering / seeking.

func modify_basic(_player, _weapon, sd: Dictionary) -> void:
	if id == "piercing":
		sd["pierce_count"] = int(sd.get("pierce_count", 0)) + 1
		sd["pierce_falloff"] = 0.5

func on_projectile_wall(proj, cast: Dictionary) -> void:
	if !is_basic(proj):
		return
	match id:
		"rebound":
			if !proj.get_meta("bounced", false) and ricochet(proj):
				proj.set_meta("bounced", true)
		"lingering":
			if derived(cast) and cast.get("tag", "") == "lingering":
				return
			Callable(GroundZone, "spawn").call_deferred(proj.get_tree(), proj.global_position, GroundZone.src_of(proj.hitbox), {
				"radius": 120.0, "lifetime": 1.5, "tick_damage": maxf(proj.hitbox.attack_ref, 1.0) * 0.5,
				"tick_interval": 0.5, "color": Color(1.0, 0.95, 0.6, 0.7)})

func on_projectile_tick(proj, delta: float, _cast: Dictionary) -> void:
	if id == "seeking" and is_basic(proj):
		steer(proj, delta, 3.0, 700.0, deg_to_rad(25.0))
