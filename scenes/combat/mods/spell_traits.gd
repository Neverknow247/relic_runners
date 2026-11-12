extends WeaponMod
# Spell-group, element and utility traits: overture / aftershock / conduit /
# rollcaster. (catalyst + attuned are resolved server-side in enemy.gd / Combat;
# walking_cast in player.gd's move_state — they only need their id.)

func modify_basic(player, weapon, sd: Dictionary) -> void:
	if id == "overture" and st(player, weapon).get("armed", false):
		sd["size"] = float(sd.get("size", 1.0)) * 3.0
		sd["damage_mult"] = float(sd.get("damage_mult", 1.0)) * 3.0

func on_basic_fire(player, weapon, _sd: Dictionary, cast: Dictionary) -> void:
	if id == "overture" and !derived(cast):
		st(player, weapon)["armed"] = false

func on_spell_cast(player, weapon, _sd: Dictionary, cast: Dictionary) -> void:
	if id == "overture" and !derived(cast):
		st(player, weapon)["armed"] = true

func on_projectile_expire(proj, pos: Vector2, cast: Dictionary) -> void:
	if id != "aftershock" or !is_spell_sd(proj.spell_data) or derived(cast) or proj.spell_data.get("_explosion", false):
		return
	var tree: SceneTree = proj.get_tree()
	var d: Dictionary = proj.spell_data.duplicate()
	var dmg: float = proj.hitbox.damage * 0.25
	var cid: int = proj.hitbox.caster_id
	tree.create_timer(0.35).timeout.connect(func():
		CombatFx.ring(tree, pos, 240.0, d.get("color", Color.WHITE), 0.35, 12.0)
		d["scene"] = BurstScene
		d["speed"] = 0.0
		d["size"] = 240.0 / 32.0
		d["lifetime"] = 0.2
		d["pierce"] = true
		d["auto_hit"] = true
		d["damage"] = dmg
		d["no_clear"] = true
		d["_fx"] = null
		d.erase("_explosion")
		WeaponMod._spawn_copy(tree, d, pos, Vector2.RIGHT, cid))

func on_kill(player, weapon, info: Dictionary) -> void:
	if id != "conduit" or !info.get("spell", false):
		return
	var s := st(player, weapon)
	var done: Array = s.get("refunded", [])
	var seed_v = info.get("seed", -1)
	if done.has(seed_v):
		return
	done.append(seed_v)
	if done.size() > 16:
		done.pop_front()
	s["refunded"] = done
	weapon.restore_mana(float(info.get("mana_cost", 0.0)) * 0.15)
	player.refresh_mana_ui()

func on_graze(player, _weapon, _bullet) -> void:
	if id != "rollcaster" or player.spell_cooldowns.is_empty():
		return
	var longest := ""
	for f in player.spell_cooldowns:
		if longest == "" or player.spell_cooldowns[f] > player.spell_cooldowns[longest]:
			longest = f
	player.spell_cooldowns[longest] = maxf(float(player.spell_cooldowns[longest]) - 1.0, 0.01)
	player.refresh_spell_ui()
