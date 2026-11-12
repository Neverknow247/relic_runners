class_name CastFx

# Projectile event router (docs/combat_redesign_plan.md §6.2). projectile.gd never
# names this class: player.gd stores Callable(CastFx, "dispatch") in spell_data["_fx"]
# and the projectile calls it. Routes to (1) ElementForms (stratagem element x form
# expressions) and (2) the casting weapon's mods. Enemy casts never get here.
# Must never name SpellData / Enemy / Player (compile cycle via projectile scenes).

# event: spawn | tick (arg = delta) | hit (arg = hurtbox) | wall | expire (arg = pos) | land
static func dispatch(event: String, proj, arg = null) -> void:
	if proj == null or !is_instance_valid(proj):
		return
	var sd: Dictionary = proj.spell_data
	if sd.get("from_enemy", false):
		return
	if sd.get("form", "default") != "default" and !sd.get("no_element_fx", false):
		ElementForms.handle(String(sd.get("element", "")) + ":" + String(sd.get("form", "")), event, proj, arg)
	var cast: Dictionary = sd.get("cast", {})
	if cast.is_empty():
		return
	for mod in WeaponMods.for_cast(cast):
		match event:
			"spawn":
				mod.on_projectile_spawn(proj, cast)
			"hit":
				mod.on_projectile_hit(proj, arg, cast)
			"wall":
				mod.on_projectile_wall(proj, cast)
			"expire":
				mod.on_projectile_expire(proj, arg if arg is Vector2 else proj.global_position, cast)

static func callable() -> Callable:
	return Callable(CastFx, "dispatch")
