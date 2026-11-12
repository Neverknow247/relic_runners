extends Node2D
# Dev-only: Trickshot cone reflection off a wall + Pagewarden pages on the caster
# (orbit node created from the cast, blocks a bullet, flung page removes one).
var players := Node2D.new()
var my_zone := "dungeon"
var my_room := "r0"
var shutting_down := false
var player_locations := {}
func can_send_rpc() -> bool: return true
func survival_active() -> bool: return false
func peers_in_room(_k): return []
func server_request_spawn_spell(o, d, w, e, f, a = 0.0, cr = 0.0, cd = 0.0, r = "common", cast = {}) -> void: pass
func _ready() -> void:
	add_to_group("world")
	players.name = "players"; add_child(players)
	var p = load("res://scenes/characters/player.tscn").instantiate()
	p.name = str(multiplayer.get_unique_id()); players.add_child(p)
	var wall := StaticBody2D.new(); wall.collision_layer = 1
	var cs := CollisionShape2D.new(); var rs := RectangleShape2D.new(); rs.size = Vector2(64, 3000)
	cs.shape = rs; wall.add_child(cs); wall.position = Vector2(500, 0); add_child(wall)
	await get_tree().physics_frame
	# Trickshot cone toward the wall
	var w := Weapon.new("wand", "rare"); w.subclass = "trickshot"; w.traits = []; w.forms = ["cone"]
	p.weapon_slots[p.active_slot] = w
	p.aim_direction = Vector2.RIGHT
	var before := get_tree().get_nodes_in_group("x").size()
	p.cast_spell(p.all_spell_data.build_spell_data("wand", "fire", "cone", "rare"), true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var cones := 0
	for c in get_tree().current_scene.get_children():
		if c is ConeProjectile:
			cones += 1
			print("GAP cone pos=", c.global_position.round(), " dir=", c.direction.round(), " scale=", c.scale.x, " reflected=", c.spell_data.get("_reflected", false))
	print("GAP cones=", cones)
	# Pagewarden
	var t := Weapon.new("tome", "rare"); t.subclass = "pagewarden"; t.traits = []; t.forms = ["ball"]
	p.weapon_slots[p.active_slot] = t
	p.cast_spell(p.all_spell_data.build_spell_data("tome", "fire", "ball", "rare"), true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var orbit = p.get_node_or_null("page_orbit")
	print("GAP orbit=", orbit != null, " pages=", orbit.pages if orbit else -1)
	var sd := SpellData.new()
	var bd := sd.build_spell_data("tome", "fire", "default", "common", true)
	bd["damage"] = 1.0
	var b = bd["scene"].instantiate(); add_child(b)
	b.global_position = p.global_position + orbit.page_offset(0) + Vector2(40, 0)
	b.setup_spell(Vector2.LEFT, bd, 99, false)
	for i in 15:
		await get_tree().physics_frame
	print("GAP after bullet pages=", orbit.pages, " bullet freed=", !is_instance_valid(b) or b.is_queued_for_deletion())
	for i in 3:
		p.attack_timer = 0.0
		p.cast_spell(p.get_spell_data(), true)
		await get_tree().physics_frame
	await get_tree().physics_frame
	print("GAP after 3 basics pages=", orbit.pages)
	sd.free()
	get_tree().quit()
