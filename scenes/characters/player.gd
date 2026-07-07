extends CharacterBody2D

var stats = Stats
var rand = RandomNumberGenerator.new()
var all_spell_data = SpellData.new()
var all_spell_recipes = SpellRecipes.new()

var spell_input_sequence: Array[int] = []

@onready var player_camera: Camera2D = $player_camera
@onready var spell_list_ui = $player_camera/spell_list_ui
@onready var visual_root: Node2D = $visual_root
@onready var legs: Sprite2D = $visual_root/legs
@onready var sprite: Sprite2D = $visual_root/sprite
@onready var legs_animation_player: AnimationPlayer = $legs_animation_player
@onready var body_animation_player: AnimationPlayer = $body_animation_player
@onready var hurtbox: Hurtbox = $hurtbox

# Legs and the upper body are animated and rotated completely
# independently: legs always reflect movement (walk/idle), even mid-attack,
# while the upper body (sprite) rotates to face aim and plays its own
# idle/attack animation. visual_root itself never rotates — it's just a
# grouping node — so each of its two children can spin on their own without
# affecting the other.
@export var network_anim := "idle"
@export var network_body_anim := "idle"
@export var network_rotation := 0.0
@export var network_legs_rotation := 0.0
var aim_direction := Vector2.DOWN
var is_attacking := false

@export var max_health := 100.0
var health := max_health
var is_dead := false

var weapon_slots: Array[Weapon] = [Weapon.new("tome"), Weapon.new("wand")]
var active_slot: int = 0

var state = move_state
var has_dash = true
var dash_input_axis

var default_max_velocity = 300
var default_acceleration = 1500
var friction = 1500

var max_velocity = default_max_velocity
var acceleration = default_acceleration

var attack_locked := false
@export var attack_cooldown := 0.35
var attack_timer := 0.0

@export var controller_aim_deadzone := 0.25
var using_controller_aim := false

func check_weapon_swap():
	if Input.is_action_just_pressed("swap_weapon"):
		active_slot = 1 - active_slot
		spell_input_sequence.clear()
		refresh_spell_ui()

func get_equipped_weapon() -> Weapon:
	return weapon_slots[active_slot]

func persist_weapon_slots() -> void:
	stats.save_data["weapons"] = weapon_slots.map(func(w): return w.to_dict())

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int(), false)

func _ready() -> void:
	hurtbox.owner_id = name.to_int()
	hurtbox.hurt.connect(_on_hurtbox_hurt)
	if is_multiplayer_authority():
		player_camera.make_current()
		spell_list_ui.visible = true
		spell_list_ui.setup(self)
		var saved: Array = stats.save_data.get("weapons", [])
		if saved.is_empty():
			persist_weapon_slots()
		else:
			weapon_slots.assign(saved.map(func(w): return Weapon.from_dict(w)))
	else:
		spell_list_ui.visible = false

func _on_hurtbox_hurt(hitbox, damage) -> void:
	if !is_multiplayer_authority():
		return
	var final_damage: float = damage
	if hitbox != null and "attacker_weapon" in hitbox and "attacker_element" in hitbox:
		var equipped := get_equipped_weapon()
		var multiplier := SpellData.get_damage_multiplier(
			hitbox.attacker_weapon,
			hitbox.attacker_element,
			equipped.type,
			equipped.element
		)
		final_damage = damage * multiplier
	take_damage(final_damage)

func take_damage(amount: float) -> void:
	if is_dead:
		return
	health = clamp(health - amount, 0.0, max_health)
	if health <= 0.0:
		die()

func die() -> void:
	is_dead = true
	hurtbox.is_invincible = true
	# TODO: respawn/death UI not designed yet

func _process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if is_multiplayer_authority():
		update_aim()
		network_rotation = sprite.rotation
		network_legs_rotation = legs.rotation
		return
	if legs_animation_player.current_animation != network_anim:
		legs_animation_player.play(network_anim)
	if body_animation_player.current_animation != network_body_anim:
		body_animation_player.play(network_body_anim)
	sprite.rotation = network_rotation
	legs.rotation = network_legs_rotation

func _physics_process(delta):
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if !is_multiplayer_authority():
		return
	check_weapon_swap()
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
	sprite.rotation = aim_direction.angle() + PI / 2

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
	if Input.is_action_pressed("spell_mode_1"):
		apply_friction(delta)
		check_spell_mode_1_input()
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
	update_legs_rotation(input_axis)
	if Input.is_action_pressed("spell_mode_2"):
		check_spell_mode_2_input()
	update_animations(input_axis)
	attack_check()
	move_and_slide()

# Legs face whichever direction you're actually walking, independent of
# where visual_root/the body is aiming — only updates while moving, so
# they just stay put facing the last walked direction once you stop.
func update_legs_rotation(input_axis: Vector2) -> void:
	if input_axis != Vector2.ZERO:
		legs.rotation = input_axis.angle() + PI / 2

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
	# Legs always reflect movement, even mid-attack — only the upper body's
	# animation is gated by is_attacking (see play_body_anim/attack_check).
	if input_vector != Vector2.ZERO:
		play_legs_anim("walk")
	else:
		play_legs_anim("idle")

func play_legs_anim(anim_name: String):
	if legs_animation_player.current_animation != anim_name:
		legs_animation_player.play(anim_name)
	if is_multiplayer_authority():
		network_anim = anim_name

func play_body_anim(anim_name: String):
	if body_animation_player.current_animation != anim_name:
		body_animation_player.play(anim_name)
	if is_multiplayer_authority():
		network_body_anim = anim_name

func equip_weapon(weapon: Weapon, slot: int) -> void:
	weapon_slots[slot] = weapon
	persist_weapon_slots()

func check_spell_mode_1_input():
	if Input.is_action_just_pressed("left"):
		record_attack_direction(0)
	if Input.is_action_just_pressed("up"):
		record_attack_direction(1)
	if Input.is_action_just_pressed("right"):
		record_attack_direction(2)
	if Input.is_action_just_pressed("down"):
		record_attack_direction(3)

func check_spell_mode_2_input():
	if Input.is_action_just_pressed("spell_mode_2_left"):
		record_attack_direction(0)
	if Input.is_action_just_pressed("spell_mode_2_up"):
		record_attack_direction(1)
	if Input.is_action_just_pressed("spell_mode_2_right"):
		record_attack_direction(2)
	if Input.is_action_just_pressed("spell_mode_2_down"):
		record_attack_direction(3)

func get_default_spell_data():
	var weapon_id: String = get_equipped_weapon().type
	var weapon_element: String = get_equipped_weapon().element
	return all_spell_data.build_spell_data(
		weapon_id,
		weapon_element,
		"default"
	)

func get_spell_data():
	print(spell_input_sequence)
	var weapon_id: String = get_equipped_weapon().type
	var weapon_element: String = get_equipped_weapon().element
	var weapon_forms: Array = get_equipped_weapon().forms
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

func cast_spell(spell_data: Dictionary, reset_sequence: bool = true):
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
	if reset_sequence:
		spell_input_sequence.clear()
		refresh_spell_ui()

#@rpc("any_peer", "call_local", "reliable")
func spawn_spell_local(
	origin_position: Vector2,
	direction: Vector2,
	weapon: String,
	element: String,
	form: String,
	caster_id: int = -1
) -> void:
	if caster_id == -1:
		caster_id = name.to_int()
	var spell_data = all_spell_data.build_spell_data(
		weapon,
		element,
		form
	)
	var projectile = spell_data["scene"].instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = origin_position
	projectile.setup_spell(direction.normalized(), spell_data, caster_id)

func refresh_spell_ui() -> void:
	if !is_multiplayer_authority():
		return
	if has_node("player_camera/spell_list_ui"):
		spell_list_ui.refresh()

func has_relevant_spell_prefix(sequence: Array) -> bool:
	var element: String = get_equipped_weapon().element
	var forms: Array = get_equipped_weapon().forms
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
	var holding_spell_mode := Input.is_action_pressed("spell_mode_1") or Input.is_action_pressed("spell_mode_2")
	if Input.is_action_pressed("attack") and attack_timer <= 0.0:
		var spell_data = get_default_spell_data() if holding_spell_mode else get_spell_data()
		cast_spell(spell_data, !holding_spell_mode)
		attack_timer = spell_data["attack_cooldown"]
		is_attacking = true
		play_body_anim("attack")
		state = attack_state

func attack_state(delta):
	# Legs keep walking/idling off actual movement the whole time — only
	# the upper body is doing the "attack" animation here.
	if Input.is_action_pressed("spell_mode_1"):
		apply_friction(delta)
		check_spell_mode_1_input()
		update_animations(Vector2.ZERO)
	else:
		var raw_input = Vector2(Input.get_axis("left", "right"), Input.get_axis("up", "down"))
		var input_axis = snap_to_8_directions(raw_input)
		if is_moving(input_axis):
			apply_acceleration(delta, input_axis)
		else:
			apply_friction(delta)
		update_legs_rotation(input_axis)
		update_animations(input_axis)
		if Input.is_action_pressed("spell_mode_2"):
			check_spell_mode_2_input()
	update_aim()
	attack_check()
	move_and_slide()
	if !Input.is_action_pressed("attack"):
		is_attacking = false
		play_body_anim("idle")
		state = move_state

func _on_roof_sense_body_entered(body: Node2D) -> void:
	body.make_translucent(self, true)

func _on_roof_sense_body_exited(body: Node2D) -> void:
	body.make_translucent(self, false)
