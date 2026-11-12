extends WeaponMod
# Instrument — Echo: every spell echoes — 1.2 s later a ghost repeats it from the
# same spot at 40% (a local copy on every peer). Every 4th basic echoes a second
# ghost shot 0.25 s later.

func on_projectile_spawn(proj, cast: Dictionary) -> void:
	if !is_spell_sd(proj.spell_data) or derived(cast) or proj.spell_data.get("_echo", false) or proj.spell_data.get("_explosion", false):
		return
	var tree: SceneTree = proj.get_tree()
	var d: Dictionary = proj.spell_data.duplicate()
	d["damage"] = float(d.get("damage", 0.0)) * 0.4
	d["_echo"] = true
	var pos: Vector2 = proj._spawn_position
	var dir: Vector2 = proj.direction
	var cid: int = proj.hitbox.caster_id
	tree.create_timer(1.2).timeout.connect(func():
		CombatFx.ring(tree, pos, 140.0, Color(0.85, 0.75, 1.0, 0.8), 0.3, 8.0)
		WeaponMod._spawn_copy(tree, d, pos, dir, cid))

func on_basic_fire(player, weapon, sd: Dictionary, cast: Dictionary) -> void:
	if derived(cast):
		return
	var s := st(player, weapon)
	s["n"] = int(s.get("n", 0)) + 1
	if int(s["n"]) % 4 != 0:
		return
	var pos: Vector2 = sd.get("_spawn_pos", player.global_position)
	var dir: Vector2 = sd.get("_dir", player.aim_direction)
	player.get_tree().create_timer(0.25).timeout.connect(func():
		if is_instance_valid(player):
			player.spawn_derived_cast(pos, dir, "default", {"tag": "echo", "dm": 0.5}))
