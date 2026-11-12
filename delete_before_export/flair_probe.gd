extends Node2D
# Dev-only: weapon flair rolls, save migration stability, and a projectile-side
# smoke test of every mod's projectile hooks (no player node needed).
var es := preload("res://scenes/enemies/enemy.tscn")
func _ready() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	for w in SpellData.WEAPON_ORDER:
		var line := "FLAIR %-10s " % w
		for r in ["common", "uncommon", "rare", "legendary"]:
			var wp := Weapon.new(w, r)
			line += "%s:%s%s  " % [r.substr(0, 1), wp.subclass, str(wp.traits)]
		print(line)
	# migration: an old save dict without flair keys
	var old := Weapon.new("orb", "rare").to_dict()
	old.erase("subclass"); old.erase("traits"); old.erase("v")
	var a := Weapon.from_dict(old); var b := Weapon.from_dict(old)
	print("FLAIR migrate stable=", a.subclass == b.subclass and a.traits == b.traits, " ", a.subclass, a.traits)
	var bad := Weapon.new("tome").to_dict(); bad["subclass"] = "nope"; bad["traits"] = ["split", "bogus"]
	var c := Weapon.from_dict(bad)
	print("FLAIR unknown -> ", c.subclass, c.traits)
	# smoke: every mod id on each form's projectile events
	var sd := SpellData.new()
	var pack := []
	for k in 4:
		var e: Enemy = es.instantiate(); e.archetype = "triangle"; e.name = "fe%d" % k
		e.position = Vector2(700 + k * 150, (k - 2) * 100); add_child(e); pack.append(e)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for e in pack: e.max_health = 1e7; e.health = 1e7
	var ids: Array = WeaponMods.SCRIPTS.keys()
	for id in ids:
		for form in ["default", "bolt", "ball", "rain", "beam", "burst", "cone", "wave"]:
			var d := sd.build_spell_data("staff", "fire", form)
			d["damage"] = 100.0 * d["damage_mult"]; d["attack_ref"] = 100.0
			var is_sub := WeaponSubclasses.is_known(id)
			d["cast"] = {"seed": 99, "sub": id} if is_sub else {"seed": 99, "tr": [id]}
			d["_fx"] = CastFx.callable()
			var p = d["scene"].instantiate(); add_child(p)
			p.global_position = Vector2(840, 0) if d.get("targeted", false) else Vector2(160, 0)
			p.setup_spell(Vector2.RIGHT, d, 777, false)
		for i in 20:
			await get_tree().physics_frame
	for i in 240:
		await get_tree().physics_frame
	var dmg := 0.0
	for e in pack:
		if is_instance_valid(e): dmg += 1e7 - e.health
	print("FLAIR smoke done, pack dmg=", dmg)
	sd.free()
	get_tree().quit()
