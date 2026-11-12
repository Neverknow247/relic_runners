extends WeaponMod
# Orb — Eclipse: each spell flips the orb between Sun and Moon. Sun: basics pop in a
# small splash, spells end in a flare. Moon: basics pierce, spells pass through the
# first wall they meet. The phase rides cast["x"]["moon"] so every peer agrees.

func _moon(player, weapon) -> bool:
	return st(player, weapon).get("moon", false)

func modify_basic(player, weapon, sd: Dictionary) -> void:
	if _moon(player, weapon):
		sd["pierce_count"] = int(sd.get("pierce_count", 0)) + 1

func on_basic_fire(player, weapon, _sd: Dictionary, cast: Dictionary) -> void:
	var x: Dictionary = cast.get("x", {})
	x["moon"] = 1 if _moon(player, weapon) else 0
	cast["x"] = x

func on_spell_cast(player, weapon, _sd: Dictionary, cast: Dictionary) -> void:
	if derived(cast):
		return
	var s := st(player, weapon)
	s["moon"] = !s.get("moon", false)
	var x: Dictionary = cast.get("x", {})
	x["moon"] = 1 if s["moon"] else 0
	cast["x"] = x

func on_projectile_hit(proj, hurtbox, cast: Dictionary) -> void:
	if is_basic(proj) and !cast.get("x", {}).get("moon", 0) and !hurtbox.is_player and !derived(cast):
		local_burst(proj, hurtbox.global_position, 110.0, maxf(proj.hitbox.attack_ref, 1.0) * 0.25)

func on_projectile_wall(proj, cast: Dictionary) -> void:
	if is_spell_sd(proj.spell_data) and cast.get("x", {}).get("moon", 0) and !proj.get_meta("phased", false):
		proj.set_meta("phased", true)
		proj.stop_on_wall = false
		proj.get_tree().create_timer(0.35).timeout.connect(func():
			if is_instance_valid(proj):
				proj.stop_on_wall = true)

func on_projectile_expire(proj, pos: Vector2, cast: Dictionary) -> void:
	if is_spell_sd(proj.spell_data) and !cast.get("x", {}).get("moon", 0) and !derived(cast) and !proj.spell_data.get("_explosion", false):
		CombatFx.ring(proj.get_tree(), pos, 260.0, Color(1.0, 0.85, 0.4), 0.4, 16.0)
		local_burst(proj, pos, 260.0, proj.hitbox.damage * 0.3, true)

func draw(player, weapon, canvas: CanvasItem) -> void:
	var p := Vector2(0, -140)
	if _moon(player, weapon):
		canvas.draw_circle(p, 16.0, Color(0.75, 0.8, 1.0))
		canvas.draw_circle(p + Vector2(7, -4), 14.0, Color(0.1, 0.1, 0.2))
	else:
		canvas.draw_circle(p, 16.0, Color(1.0, 0.85, 0.35))
