extends CharacterBody2D

var stats = Stats
var rand = RandomNumberGenerator.new()
var all_spell_data = SpellData.new()
var all_spell_recipes = SpellRecipes.new()

var spell_input_sequence: Array[int] = []

@onready var player_camera: Camera2D = $player_camera
@onready var spell_list_ui = $player_camera/spell_list_ui
@onready var visual_root: Node2D = $visual_root
@onready var animation_player: AnimationPlayer = $animation_player

@export var network_anim := "idle"
@export var network_rotation := 0.0
var aim_direction := Vector2.DOWN
var is_attacking := false

@export var equipped_weapon_data := {
	"id": "tome",
	"element": "fire",
	"forms": ["ball", "rain", "beam"]
}

var state = move_state
var has_dash = true
var dash_input_axis

var default_max_velocity = 100
var default_acceleration = 500
var friction = 500

var max_velocity = default_max_velocity
var acceleration = default_acceleration

var attack_locked := false
@export var attack_cooldown := 0.35
var attack_timer := 0.0

@export var controller_aim_deadzone := 0.25
var using_controller_aim := false

func check_weapon_switch():
	var changed := false
	if Input.is_action_just_pressed("1"):
		equipped_weapon_data["id"] = "tome"
		equipped_weapon_data["forms"] = ["ball", "rain", "beam"]
		changed = true
	if Input.is_action_just_pressed("2"):
		equipped_weapon_data["id"] = "orb"
		equipped_weapon_data["forms"] = ["bolt", "beam", "burst"]
		changed = true
	if Input.is_action_just_pressed("3"):
		equipped_weapon_data["id"] = "wand"
		equipped_weapon_data["forms"] = ["bolt", "ball", "cone"]
		changed = true
	if Input.is_action_just_pressed("4"):
		equipped_weapon_data["element"] = "fire"
		changed = true
	if Input.is_action_just_pressed("5"):
		equipped_weapon_data["element"] = "holy"
		changed = true
	if Input.is_action_just_pressed("6"):
		equipped_weapon_data["element"] = "air"
		changed = true
	if changed:
		spell_input_sequence.clear()
		refresh_spell_ui()

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int(), false)

func _ready() -> void:
	if is_multiplayer_authority():
		player_camera.make_current()
		spell_list_ui.visible = true
		spell_list_ui.setup(self)
	else:
		spell_list_ui.visible = false

func _process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if is_multiplayer_authority():
		update_aim()
		network_rotation = visual_root.rotation
		return
	if animation_player.current_animation != network_anim:
		animation_player.play(network_anim)
	visual_root.rotation = network_rotation

func _physics_process(delta):
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if !is_multiplayer_authority():
		return
	check_weapon_switch()
	attack_timer = max(attack_timer - delta, 0.0)
	state.call(delta)
	if is_multiplayer_authority():
		var world = get_tree().get_first_node_in_group("world")
		if world == null:
			return
		if world.shutting_down:
			return
		if !world.can_send_rpc():
			return
		world.server_send_player_state.rpc(global_position, network_anim, network_rotation)

func update_aim() -> void:
	var controller_aim := get_controller_aim_direction()
	if controller_aim != Vector2.ZERO:
		aim_direction = controller_aim
		using_controller_aim = true
	else:
		var mouse_pos := get_global_mouse_position()
		var mouse_direction := global_position.direction_to(mouse_pos)
		if mouse_direction.length() <= 0.01:
			return
		aim_direction = mouse_direction
		using_controller_aim = false
	visual_root.rotation = aim_direction.angle() + PI / 2

func get_controller_aim_direction() -> Vector2:
	var aim_vector := Vector2(
		Input.get_axis("aim_left", "aim_right"),
		Input.get_axis("aim_up", "aim_down")
	)
	if aim_vector.length() < controller_aim_deadzone:
		return Vector2.ZERO
	return aim_vector.normalized()

func record_attack_direction(input_num: int):
	spell_input_sequence.append(input_num)
	if spell_input_sequence.size() > 6:
		spell_input_sequence.clear()
		refresh_spell_ui()
		return
	if !has_relevant_spell_prefix(spell_input_sequence):
		spell_input_sequence.clear()
	refresh_spell_ui()

func move_state(delta):
	if Input.is_action_pressed("spell_mode"):
		apply_friction(delta)
		check_spell_mode_input()
		update_animations(Vector2.ZERO)
		attack_check()
		move_and_slide()
		return
	var raw_input = Vector2(Input.get_axis("left","right"), Input.get_axis("up","down"))
	var input_axis = snap_to_8_directions(raw_input)
	if is_moving(input_axis):
		apply_acceleration(delta, input_axis)
	else:
		apply_friction(delta)
	update_animations(input_axis)
	attack_check()
	move_and_slide()

func snap_to_8_directions(direction: Vector2) -> Vector2:
	if direction.length() < 0.2:
		return Vector2.ZERO
	var x := direction.x
	var y := direction.y
	if abs(x) < 0.35:
		x = 0.0
	if abs(y) < 0.35:
		y = 0.0
	if x == 0.0 and y == 0.0:
		return Vector2.ZERO
	return Vector2(sign(x), sign(y)).normalized()

func is_moving(_input_axis):
	return _input_axis != Vector2.ZERO

func apply_acceleration(delta, _input_axis):
	velocity = velocity.move_toward(_input_axis.normalized()*max_velocity,acceleration*delta)

func apply_friction(delta):
	velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

func update_animations(input_vector: Vector2) -> void:
	if is_attacking:
		return
	if input_vector != Vector2.ZERO:
		play_anim("walk")
	else:
		play_anim("idle")

func play_anim(anim_name: String):
	if animation_player.current_animation != anim_name:
		animation_player.play(anim_name)
	if is_multiplayer_authority():
		network_anim = anim_name
		network_rotation = visual_root.rotation

func equip_weapon(weapon_data: Dictionary):
	equipped_weapon_data = weapon_data

func check_spell_mode_input():
	if Input.is_action_just_pressed("left"):
		record_attack_direction(0)
	if Input.is_action_just_pressed("up"):
		record_attack_direction(1)
	if Input.is_action_just_pressed("right"):
		record_attack_direction(2)
	if Input.is_action_just_pressed("down"):
		record_attack_direction(3)

func get_spell_data():
	print(spell_input_sequence)
	var weapon_id: String = equipped_weapon_data["id"]
	var weapon_element: String = equipped_weapon_data["element"]
	var weapon_forms: Array = equipped_weapon_data["forms"]
	if spell_input_sequence.is_empty():
		return all_spell_data.build_spell_data(
			weapon_id,
			weapon_element,
			"default"
		)
	var recipe := all_spell_recipes.get_spell_recipe_from_sequence(spell_input_sequence)
	if recipe.is_empty():
		return all_spell_data.build_spell_data(
			weapon_id,
			weapon_element,
			"default"
		)
	var recipe_element: String = recipe["element"]
	var recipe_form: String = recipe["form"]
	if recipe_element != weapon_element:
		return all_spell_data.build_spell_data(
			weapon_id,
			weapon_element,
			"default"
		)
	if !weapon_forms.has(recipe_form):
		return all_spell_data.build_spell_data(
			weapon_id,
			weapon_element,
			"default"
		)
	return all_spell_data.build_spell_data(
		weapon_id,
		recipe_element,
		recipe_form
	)

#func cast_spell(spell_data: Dictionary):
	#var direction = get_facing_direction()
	#var spawn_position = global_position + direction * spell_data["spawn_offset"]
	#spawn_spell.rpc(
		#spawn_position,
		#direction,
		#spell_data["weapon"],
		#spell_data["element"],
		#spell_data["form"]
	#)
	#spell_input_sequence.clear()
	#refresh_spell_ui()

func cast_spell(spell_data: Dictionary):
	var direction = get_facing_direction()
	var spawn_position = global_position + direction * spell_data["spawn_offset"]
	var world = get_tree().get_first_node_in_group("world")
	if world == null:
		return
	if world.shutting_down:
		return
	if !world.can_send_rpc():
		return
	if multiplayer.is_server():
		world.server_request_spawn_spell(
			spawn_position,
			direction,
			spell_data["weapon"],
			spell_data["element"],
			spell_data["form"]
		)
	else:
		world.server_request_spawn_spell.rpc(
			spawn_position,
			direction,
			spell_data["weapon"],
			spell_data["element"],
			spell_data["form"]
		)
	spell_input_sequence.clear()
	refresh_spell_ui()

#@rpc("any_peer", "call_local", "reliable")
func spawn_spell_local(
	origin_position: Vector2,
	direction: Vector2,
	weapon: String,
	element: String,
	form: String
) -> void:
	var spell_data = all_spell_data.build_spell_data(
		weapon,
		element,
		form
	)
	var projectile = spell_data["scene"].instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = origin_position
	projectile.setup_spell(direction.normalized(), spell_data)

func refresh_spell_ui() -> void:
	if !is_multiplayer_authority():
		return
	if has_node("player_camera/spell_list_ui"):
		spell_list_ui.refresh()

func has_relevant_spell_prefix(sequence: Array) -> bool:
	var element: String = equipped_weapon_data["element"]
	var forms: Array = equipped_weapon_data["forms"]
	var recipes: Array = all_spell_recipes.get_available_recipes(element, forms)
	for recipe in recipes:
		var recipe_sequence: Array = recipe["sequence"]
		if sequence.size() > recipe_sequence.size():
			continue
		var matches := true
		for i in sequence.size():
			if sequence[i] != recipe_sequence[i]:
				matches = false
				break
		if matches:
			return true
	return false

func get_facing_direction() -> Vector2:
	return aim_direction.normalized()

func attack_check():
	if Input.is_action_pressed("attack") and attack_timer <= 0.0:
		var spell_data = get_spell_data()
		cast_spell(spell_data)
		attack_timer = spell_data["attack_cooldown"]
		is_attacking = true
		play_anim("attack")
		state = attack_state

func attack_state(delta):
	if Input.is_action_pressed("spell_mode"):
		apply_friction(delta)
		check_spell_mode_input()
	else:
		var raw_input = Vector2(Input.get_axis("left", "right"), Input.get_axis("up", "down"))
		var input_axis = snap_to_8_directions(raw_input)
		if is_moving(input_axis):
			apply_acceleration(delta, input_axis)
		else:
			apply_friction(delta)
	update_aim()
	attack_check()
	move_and_slide()
	if !Input.is_action_pressed("attack"):
		is_attacking = false
		state = move_state

func _on_roof_sense_body_entered(body: Node2D) -> void:
	body.make_translucent(self, true)

func _on_roof_sense_body_exited(body: Node2D) -> void:
	body.make_translucent(self, false)
