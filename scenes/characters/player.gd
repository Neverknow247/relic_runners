extends CharacterBody2D

var stats = Stats
var rand = RandomNumberGenerator.new()
var all_spell_data = SpellData.new()
var all_spell_recipes = SpellRecipes.new()

var spell_input_sequence: Array[int] = []

@onready var visual_root: Node2D = $visual_root
@onready var sprite: Sprite2D = $visual_root/sprite
@onready var animation_player: AnimationPlayer = $animation_player
@onready var spell_origin: Marker2D = $spell_origin

@export var network_anim := "idle_down"
@export var network_flip_h := false
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

var last_facing = Vector2.ZERO

func check_event():
	if Input.is_action_pressed("1"):
		equipped_weapon_data["id"] = "tome"
		equipped_weapon_data["forms"] = ["ball", "rain", "beam"]
	if Input.is_action_pressed("2"):
		equipped_weapon_data["id"] = "orb"
		equipped_weapon_data["forms"] = ["ball", "rain", "beam"]
	if Input.is_action_pressed("3"):
		equipped_weapon_data["id"] = "wand"
		equipped_weapon_data["forms"] = ["ball", "rain", "beam"]
	if Input.is_action_pressed("4"):
		equipped_weapon_data["element"] = "fire"
	if Input.is_action_pressed("5"):
		equipped_weapon_data["element"] = "holy"
	if Input.is_action_pressed("6"):
		equipped_weapon_data["element"] = "air"

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	if is_multiplayer_authority():
		$camera_2d.make_current()

func _process(delta: float) -> void:
	if is_multiplayer_authority():
		visual_root.position = Vector2.ZERO
		return
	if animation_player.current_animation != network_anim:
		animation_player.play(network_anim)
		sprite.flip_h = network_flip_h

func _physics_process(delta):
	check_event()
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if !is_multiplayer_authority():
		return
	state.call(delta)

func record_attack_direction(input_num: int):
	spell_input_sequence.append(input_num)
	if spell_input_sequence.size() > 6:
		spell_input_sequence.pop_front()

func move_state(delta):
	var input_axis = Vector2(Input.get_axis("left","right"),Input.get_axis("up","down"))
	if is_moving(input_axis):
		apply_acceleration(delta,input_axis)
	else:
		apply_friction(delta)
	update_animations(input_axis)
	check_spell_input()
	attack_check()
	move_and_slide()

func is_moving(_input_axis):
	return _input_axis != Vector2.ZERO

func apply_acceleration(delta, _input_axis):
	velocity = velocity.move_toward(_input_axis.normalized()*max_velocity,acceleration*delta)

func apply_friction(delta):
	velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

func update_animations(input_vector):
	var facing = input_vector
	if facing != Vector2.ZERO:
		last_facing = input_vector
		sprite.flip_h = facing.x != 1
	if input_vector != Vector2.ZERO:
		if abs(input_vector.x) == 1:
			if input_vector.y == 0.0:
				play_anim("run_side")
			elif input_vector.y == -1.0:
				play_anim("run_up_side")
			else:
				play_anim("run_down_side")
		else:
			if input_vector.y == -1:
				play_anim("run_up")
			else:
				play_anim("run_down")
	else:
		if abs(last_facing.x) == 1:
			if last_facing.y == 0.0:
				play_anim("idle_side")
			elif last_facing.y == -1.0:
				play_anim("idle_up_side")
			else:
				play_anim("idle_down_side")
		else:
			if last_facing.y == -1:
				play_anim("idle_up")
			else:
				play_anim("idle_down")

func play_anim(anim_name: String):
	if animation_player.current_animation != anim_name:
		animation_player.play(anim_name)
	if is_multiplayer_authority():
		network_anim = anim_name
		network_flip_h = sprite.flip_h

func equip_weapon(weapon_data: Dictionary):
	equipped_weapon_data = weapon_data

func check_spell_input():
	if Input.is_action_just_pressed("spell_up"):
		record_attack_direction(1)
	if Input.is_action_just_pressed("spell_right"):
		record_attack_direction(2)
	if Input.is_action_just_pressed("spell_down"):
		record_attack_direction(3)
	if Input.is_action_just_pressed("spell_left"):
		record_attack_direction(4)

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

func cast_spell():
	var spell_data = get_spell_data()
	var direction = get_facing_direction()
	var projectile = spell_data["scene"].instantiate()
	#print(spell_input_sequence)
	print(spell_data["weapon"], ": ", spell_data["element"], " ", spell_data["form"])
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = spell_origin.global_position + direction * 18
	projectile.setup_spell(direction, spell_data)
	spell_input_sequence.clear()

func get_facing_direction():
	if last_facing == Vector2.ZERO:
		return Vector2.DOWN
	return last_facing.normalized()

func attack_check():
	if (Input.is_action_pressed("attack_1")):
		cast_spell()
		if abs(last_facing.x) == 1:
			if last_facing.y == 0.0:
				play_anim("attack_1_side")
			elif last_facing.y == -1.0:
				play_anim("attack_1_up_side")
			else:
				play_anim("attack_1_down_side")
		else:
			if last_facing.y == -1:
				play_anim("attack_1_up")
			else:
				play_anim("attack_1_down")
		state = attack_state

func attack_state(delta):
	apply_friction(delta)
	move_and_slide()
	if not animation_player.is_playing() or !animation_player.current_animation.contains("attack"):
		state = move_state

#func snap_visual_to_body():
	#if has_node("visual_root"):
		#$visual_root.position = Vector2.ZERO
	#reset_physics_interpolation()

func _on_roof_sense_body_entered(body: Node2D) -> void:
	body.make_translucent(self, true)

func _on_roof_sense_body_exited(body: Node2D) -> void:
	body.make_translucent(self, false)
