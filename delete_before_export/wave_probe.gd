extends Node2D
# Dev-only: a player-cast wave carries a bronze triangle and a bronze pentagon
# toward a wall; prints positions, health (slam) and that the wave stops.
var tri: Enemy
var pent: Enemy
var wave: Node2D
var t := 0.0
func _ready() -> void:
	print("WAVE recipe fire: ", SpellRecipes.new().get_available_recipes("fire", ["wave"]))
	print("WAVE range player=", SpellData.get_effective_range("staff", "fire", "wave"), " enemy=", SpellData.get_effective_range("staff", "fire", "wave", true))
	var sd := SpellData.new()
	var ed := sd.build_spell_data("staff", "fire", "wave", "common", true)
	print("WAVE enemy speed=", ed["speed"], " life=", ed["lifetime"], " maxd=", ed["max_distance"], " carry=", ed["carry"])
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new(); rs.size = Vector2(64, 2000)
	cs.shape = rs; wall.add_child(cs); wall.position = Vector2(1500, 0)
	add_child(wall)
	var es := load("res://scenes/enemies/enemy.tscn")
	tri = es.instantiate(); tri.archetype = "triangle"; tri.name = "tri"; tri.position = Vector2(500, -150); add_child(tri)
	pent = es.instantiate(); pent.archetype = "pentagon"; pent.name = "pent"; pent.position = Vector2(500, 150); add_child(pent)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var data := sd.build_spell_data("staff", "fire", "wave")
	data["damage"] = 100.0
	wave = data["scene"].instantiate()
	get_tree().current_scene.add_child(wave)
	wave.global_position = Vector2(160, 0)
	wave.setup_spell(Vector2.RIGHT, data, 12345, false)
	print("WAVE hp0 tri=", tri.health, " pent=", pent.health)
	sd.free()
func _physics_process(delta: float) -> void:
	t += delta
	if int(t * 10) != int((t - delta) * 10) and t < 2.0 and is_instance_valid(tri) and is_instance_valid(pent):
		print("WAVE t=%.1f wave=%s tri=%.0f hp %.0f  pent=%.0f hp %.0f" % [t, str(wave.global_position.x) if is_instance_valid(wave) else "gone", tri.global_position.x, tri.health, pent.global_position.x, pent.health])
	if t > 2.2:
		get_tree().quit()
