extends Node2D
# Dev-only: a stub world + a real player.tscn, casting basics/spells/rolls with every
# subclass and trait to smoke-test the caster-side mod hooks.
var players := Node2D.new()
var my_zone := "dungeon"
var my_room := "r0"
var shutting_down := false
var player_locations := {}
func can_send_rpc() -> bool: return true
func survival_active() -> bool: return false
func peers_in_room(_k): return []
func server_request_spawn_spell(o, d, w, e, f, a = 0.0, cr = 0.0, cd = 0.0, r = "common", cast = {}) -> void:
	pass
func _ready() -> void:
	add_to_group("world")
	players.name = "players"
	add_child(players)
	var p = load("res://scenes/characters/player.tscn").instantiate()
	p.name = str(multiplayer.get_unique_id())
	players.add_child(p)
	await get_tree().physics_frame
	var es := preload("res://scenes/enemies/enemy.tscn")
	for k in 3:
		var e = es.instantiate(); e.archetype = "triangle"; e.name = "ce%d" % k
		e.position = Vector2(800 + k * 150, 0); add_child(e)
	await get_tree().physics_frame
	var n := 0
	for id in WeaponMods.SCRIPTS.keys():
		var sub := WeaponSubclasses.is_known(id)
		var wtype: String = WeaponSubclasses.SUBCLASSES[id]["weapon"] if sub else "staff"
		var w := Weapon.new(wtype, "rare")
		w.subclass = id if sub else ""
		w.traits = [] if sub else [id]
		for f in SpellData.get_capable_forms(wtype):
			w.forms.append(f)
		w.forms = w.forms.slice(0, 3)
		p.weapon_slots[p.active_slot] = w
		for i in 4:
			p.cast_spell(p.get_spell_data(), true)
			await get_tree().physics_frame
		for f in w.forms:
			var sd: Dictionary = p.all_spell_data.build_spell_data(wtype, w.element, f, "rare")
			p.cast_spell(sd, true)
			await get_tree().physics_frame
		p._start_roll()
		for i in 30:
			await get_tree().physics_frame
		p.notify_graze(null)
		p.on_kill_credited({"spell": true, "form": "bolt", "seed": 5})
		n += 1
	print("CASTER smoke done mods=", n)
	get_tree().quit()
