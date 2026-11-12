extends Node2D
# Dev-only: casts every element x form (player stratagem data) at enemy packs and
# prints a summary per cell; watch for SCRIPT ERROR lines.
var es := preload("res://scenes/enemies/enemy.tscn")
const FORMS := ["bolt", "ball", "rain", "beam", "burst", "cone", "wave"]
var packs := {}
func _ready() -> void:
	var sd := SpellData.new()
	var elements: Array = SpellData.ELEMENT_ORDER
	var only := OS.get_environment("ELEM")
	if only != "":
		elements = [only]
	for ei in elements.size():
		for fi in FORMS.size():
			var el: String = elements[ei]
			var form: String = FORMS[fi]
			var base := Vector2(fi * 6000, ei * 3000)
			var pack := []
			for k in 3:
				var e: Enemy = es.instantiate()
				e.archetype = "triangle"; e.name = "e_%s_%s_%d" % [el, form, k]
				e.position = base + Vector2(700 + k * 140, (k - 1) * 120)
				add_child(e)
				pack.append(e)
			packs[el + ":" + form] = pack
			if OS.get_environment("DBG") == el + ":" + form:
				pack[1].hurtbox.hurt.connect(func(h, d): print("DBG hurt d=", d, " el=", h.attacker_element, " hp=", pack[1].health, " dead=", pack[1].is_dead))
	await get_tree().physics_frame
	await get_tree().physics_frame
	for ei in elements.size():
		for fi in FORMS.size():
			var el: String = elements[ei]
			var form: String = FORMS[fi]
			var base := Vector2(fi * 6000, ei * 3000)
			for e in packs[el + ":" + form]:
				e.max_health = 1e6; e.health = 1e6; e.shield_up = false
			# a few enemy bullets flying at the caster spot
			for k in 3:
				var bd := sd.build_spell_data("tome", "fire", "default", "common", true)
				bd["damage"] = 10.0
				var b = bd["scene"].instantiate(); add_child(b)
				b.global_position = base + Vector2(500 + k * 60, 0)
				b.setup_spell(Vector2.LEFT, bd, 99, false)
			var d := sd.build_spell_data("staff", el, form)
			d["damage"] = 100.0 * d["damage_mult"]
			d["attack_ref"] = 100.0
			d["cast"] = {"seed": 1234}
			d["bespoke"] = ElementForms.bespoke_for(el, form)
			d["_fx"] = CastFx.callable()
			var p = d["scene"].instantiate(); add_child(p)
			var pos := base + (Vector2(840, 0) if d.get("targeted", false) else Vector2(160 if form != "wave" else 200, 0))
			if form in ["burst"]: pos = base + Vector2(840, 0)
			p.global_position = pos
			p.setup_spell(Vector2.RIGHT, d, 777, false)
	for i in 600:
		await get_tree().physics_frame
		if OS.get_environment("DBG") != "" and i % 30 == 0 and packs.has(OS.get_environment("DBG")):
			var e0 = packs[OS.get_environment("DBG")][1]
			print("DBG inv=", e0.hurtbox.is_invincible, " kb=", e0._knockback, " pull=", e0._pull_velocity, " sk=", e0._skewer_left, " carry=", e0._carry_velocity)
			print("DBG f=", i, " pos=", e0.global_position if is_instance_valid(e0) else "x", " hp=", e0.health if is_instance_valid(e0) else -1, " beams=", get_tree().get_nodes_in_group("dbg").size())
	for key in packs:
		var dmg := 0.0
		var masks := []
		for e in packs[key]:
			if is_instance_valid(e):
				dmg += 1e6 - e.health
				masks.append(e.status_mask)
		print("FX %-16s dmg=%7.0f masks=%s" % [key, dmg, masks])
	print("FX zones alive=", get_tree().get_nodes_in_group("x").size())
	sd.free()
	get_tree().quit()
