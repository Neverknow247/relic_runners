extends CharacterBody2D

var stats = Stats
var rand = RandomNumberGenerator.new()

@onready var sprite: Sprite2D = $sprite
@onready var animation_player: AnimationPlayer = $animation_player

var state = move_state
var has_dash = true
var dash_input_axis

var default_max_velocity = 100
var default_acceleration = 500
var friction = 500

var max_velocity = default_max_velocity
var acceleration = default_acceleration

var last_facing = Vector2.ZERO

func _ready() -> void:
	if is_multiplayer_authority():
		$camera_2d.make_current()

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _physics_process(delta):
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if !is_multiplayer_authority():
		return
	state.call(delta)

func move_state(delta):
	var input_axis = Vector2(Input.get_axis("left","right"),Input.get_axis("up","down"))
	if is_moving(input_axis):
		apply_acceleration(delta,input_axis)
	else:
		apply_friction(delta)
	update_animations(input_axis)
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
				animation_player.play("run_side")
			elif input_vector.y == -1.0:
				animation_player.play("run_up_side")
			else:
				animation_player.play("run_down_side")
		else:
			if input_vector.y == -1:
				animation_player.play("run_up")
			else:
				animation_player.play("run_down")
	else:
		if abs(last_facing.x) == 1:
			if last_facing.y == 0.0:
				animation_player.play("idle_side")
			elif last_facing.y == -1.0:
				animation_player.play("idle_up_side")
			else:
				animation_player.play("idle_down_side")
		else:
			if last_facing.y == -1:
				animation_player.play("idle_up")
			else:
				animation_player.play("idle_down")

func _on_roof_sense_body_entered(body: Node2D) -> void:
	body.make_translucent(self, true)

func _on_roof_sense_body_exited(body: Node2D) -> void:
	body.make_translucent(self, false)
