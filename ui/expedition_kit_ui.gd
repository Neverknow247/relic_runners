extends CanvasLayer

# Party kit prompt. The host opens an expedition door, which puts this popup up
# on every player (world.gd's client_show_kit_prompt). Each player picks their
# own loadout via player.answer_expedition_kit() (or cancels, aborting the whole
# start); the party only travels once everyone has answered. The chosen kit is
# recorded now but applied at travel time, not on click.

@onready var starter_button: Button = $center_container/panel_container/margin_container/v_box_container/starter_button
@onready var custom_button: Button = $center_container/panel_container/margin_container/v_box_container/custom_button
@onready var cancel_button: Button = $center_container/panel_container/margin_container/v_box_container/cancel_button

var player = null
var expedition_id := ""

func _ready() -> void:
	visible = false
	starter_button.pressed.connect(_on_starter_pressed)
	custom_button.pressed.connect(_on_custom_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)

func open(target_player, exp_id: String) -> void:
	player = target_player
	expedition_id = exp_id
	visible = true

func _close() -> void:
	visible = false

func _on_starter_pressed() -> void:
	_confirm("starter")

func _on_custom_pressed() -> void:
	_confirm("custom")

func _on_cancel_pressed() -> void:
	var p = player
	_close()
	if p != null:
		p.cancel_expedition_kit()

func _confirm(kit: String) -> void:
	# Snapshot before closing, since _close() drops the references.
	var p = player
	_close()
	if p != null:
		p.answer_expedition_kit(kit)

# Closed by the server (someone cancelled, or a disconnect aborted the start) —
# just hide, no report back (that would loop).
func force_close() -> void:
	_close()
