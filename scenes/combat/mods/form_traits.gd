extends WeaponMod
# Form traits: cluster (ball) / forked (bolt) / undertow (wave) / downpour (rain) /
# prism_beam (beam) / afterimage (burst) / backdraft (cone).

func _form(proj) -> String:
	return proj.spell_data.get("form", "")

func on_projectile_spawn(proj, cast: Dictionary) -> void:
	match id:
		"cluster":
			if _form(proj) == "ball" and proj.spell_data.get("_explosion", false) and !derived(cast):
				var tree: SceneTree = proj.get_tree()
				var rng := RandomNumberGenerator.new()
				rng.seed = int(cast.get("seed", 0))
				var base := rng.randf() * TAU
				for i in 3:
					var p: Vector2 = proj.global_position + Vector2.from_angle(base + TAU * i / 3.0) * 200.0
					local_burst(proj, p, 120.0, proj.hitbox.damage * 0.25, true)
					CombatFx.ring(tree, p, 120.0, proj.spell_data.get("color", Color.WHITE), 0.3, 10.0)
		"downpour":
			if _form(proj) == "rain" and "_call_down_left" in proj:
				proj._call_down_left = minf(proj._call_down_left, 0.5)
		"prism_beam":
			if _form(proj) == "beam" and "cutoff_mask" in proj:
				proj.cutoff_mask = 1

func on_projectile_hit(proj, hurtbox, cast: Dictionary) -> void:
	if id == "forked" and _form(proj) == "bolt" and !proj.spell_data.get("_forked", false) and !hurtbox.is_player:
		var origin: Vector2 = hurtbox.global_position + proj.direction * 90.0
		for a in [-0.45, 0.45]:
			spawn_local_copy(proj, origin, proj.direction.rotated(a), {"dm": 0.5, "_forked": true})

func on_projectile_expire(proj, pos: Vector2, cast: Dictionary) -> void:
	if id == "undertow" and _form(proj) == "wave" and !proj.spell_data.get("_undertow", false) and !derived(cast):
		spawn_local_copy(proj, pos - proj.direction * 60.0, -proj.direction, {"dm": 0.5, "_undertow": true})

func tick(player, weapon, _delta: float) -> void:
	if id != "afterimage":
		return
	var s := st(player, weapon)
	var hist: Array = s.get("hist", [])
	var now := Time.get_ticks_msec()
	hist.append([now, player.global_position])
	while hist.size() > 2 and now - int(hist[1][0]) > 1000:
		hist.pop_front()
	s["hist"] = hist

func on_spell_cast(player, weapon, sd: Dictionary, cast: Dictionary) -> void:
	if derived(cast):
		return
	var dir: Vector2 = sd.get("_dir", player.aim_direction)
	match id:
		"afterimage":
			if sd.get("form", "") == "burst":
				var hist: Array = st(player, weapon).get("hist", [])
				var p: Vector2 = hist[0][1] if !hist.is_empty() else player.global_position
				player.get_tree().create_timer(0.15).timeout.connect(func():
					if is_instance_valid(player):
						player.spawn_derived_cast(p, dir, "burst", {"tag": "afterimage", "dm": 0.5}))
		"backdraft":
			if sd.get("form", "") == "cone":
				player.spawn_derived_cast(player.global_position, -dir, "cone", {"tag": "backdraft", "dm": 0.5, "sz": 0.5})
