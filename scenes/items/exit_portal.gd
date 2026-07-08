extends Area2D
class_name ExitPortal

# Server-authoritative like enemy.gd (no set_multiplayer_authority() call,
# so this stays at the Godot default — peer 1/server). Any player can
# activate it from LOCKED; the server alone runs the actual timers and
# broadcasts each state change (plus that phase's duration) to every peer,
# so everyone's local copy can independently count down the display without
# needing continuous per-frame sync.

enum State { LOCKED, CHARGING, OPEN, DISABLED, SPAWN_POINT }

# 1-2 minutes to open, then a 30s window to actually use it.
@export var charge_time := 90.0
@export var open_duration := 30.0

var state: State = State.LOCKED
var phase_time_remaining := 0.0
var can_use := false

@onready var color_rect: ColorRect = $visual_root/color_rect
@onready var status_label: Label = $visual_root/status_label

func _ready() -> void:
	_update_visual()

func _on_body_entered(body: Node) -> void:
	# During teardown (esc-menu Leave / death penalty) the peer is torn down
	# while bodies exit areas; is_multiplayer_authority() calls get_unique_id(),
	# which errors with no peer assigned.
	if multiplayer.multiplayer_peer == null:
		return
	if body.is_multiplayer_authority():
		can_use = true

func _on_body_exited(body: Node) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if body.is_multiplayer_authority():
		can_use = false

func _process(delta: float) -> void:
	if state == State.CHARGING or state == State.OPEN:
		phase_time_remaining = max(phase_time_remaining - delta, 0.0)
		_update_visual()
	if !can_use:
		return
	if !Input.is_action_just_pressed("interact"):
		return
	match state:
		State.LOCKED:
			request_activate()
		State.OPEN:
			var world = get_tree().get_first_node_in_group("world")
			if world:
				world.request_location_changes("hub", "main", "default")
		_:
			pass  # CHARGING, DISABLED, or SPAWN_POINT — interact does nothing

# Called locally (no RPC — see portal_group.gd) on whichever portal was
# deterministically picked as this expedition's arrival point. Permanently
# excludes it from ever functioning as an exit — _start_charging()'s own
# "must be LOCKED" guard means it can never progress past this.
func mark_as_spawn_point() -> void:
	state = State.SPAWN_POINT
	_update_visual()

func request_activate() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if is_multiplayer_authority():
		_start_charging()
	else:
		server_request_activate.rpc()

@rpc("any_peer", "call_remote", "reliable")
func server_request_activate() -> void:
	if !is_multiplayer_authority():
		return
	_start_charging()

func _start_charging() -> void:
	if state != State.LOCKED:
		return
	state = State.CHARGING
	broadcast_portal_state.rpc(State.CHARGING, charge_time)
	await get_tree().create_timer(charge_time).timeout
	if !is_inside_tree() or state != State.CHARGING:
		return
	state = State.OPEN
	broadcast_portal_state.rpc(State.OPEN, open_duration)
	await get_tree().create_timer(open_duration).timeout
	if !is_inside_tree() or state != State.OPEN:
		return
	state = State.DISABLED
	broadcast_portal_state.rpc(State.DISABLED, 0.0)

@rpc("authority", "call_local", "reliable")
func broadcast_portal_state(new_state: State, time_remaining: float) -> void:
	state = new_state
	phase_time_remaining = time_remaining
	_update_visual()

func _update_visual() -> void:
	match state:
		State.LOCKED:
			color_rect.color = Color(0.4, 0.4, 0.4)
			status_label.text = "Exit Portal\n(inactive)"
		State.CHARGING:
			color_rect.color = Color(0.9, 0.7, 0.1)
			status_label.text = "Exit Portal\nOpening in %d s" % ceili(phase_time_remaining)
		State.OPEN:
			color_rect.color = Color(0.2, 0.85, 0.4)
			status_label.text = "Exit Portal\nOPEN — %d s" % ceili(phase_time_remaining)
		State.DISABLED:
			color_rect.color = Color(0.25, 0.2, 0.2)
			status_label.text = "Exit Portal\n(closed)"
		State.SPAWN_POINT:
			color_rect.color = Color(0.3, 0.5, 0.8)
			status_label.text = "Arrival Point"
