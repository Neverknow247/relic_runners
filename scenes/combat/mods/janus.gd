extends WeaponMod
# Staff — Janus: every 3rd basic also fires backward; every spell casts a
# half-strength mirrored copy behind you.

func on_basic_fire(player, weapon, sd: Dictionary, cast: Dictionary) -> void:
	if derived(cast):
		return
	var s := st(player, weapon)
	s["n"] = int(s.get("n", 0)) + 1
	if int(s["n"]) % 3 == 0:
		var dir: Vector2 = sd.get("_dir", player.aim_direction)
		player.spawn_derived_cast(player.global_position - dir * float(sd.get("spawn_offset", 128.0)), -dir, "default", {"tag": "janus"})

func on_spell_cast(player, _weapon, sd: Dictionary, cast: Dictionary) -> void:
	if derived(cast):
		return
	var dir: Vector2 = sd.get("_dir", player.aim_direction)
	var spawn: Vector2 = sd.get("_spawn_pos", player.global_position)
	var mirrored: Vector2 = player.global_position - (spawn - player.global_position)
	player.spawn_derived_cast(mirrored, -dir, sd.get("form", "default"), {"tag": "janus", "dm": 0.5})
