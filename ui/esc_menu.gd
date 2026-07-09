extends CanvasLayer

# Lives on world.tscn (not per-player like the inventory/spell UI) since
# quitting/leaving is a whole-session action, not a per-character one — each
# peer's own local world.tscn instance gets exactly one of these.

@onready var resume_button: Button = $panel_container/margin_container/v_box_container/resume_button
@onready var settings_button: Button = $panel_container/margin_container/v_box_container/settings_button
@onready var quit_button: Button = $panel_container/margin_container/v_box_container/quit_button
@onready var leave_button: Button = $panel_container/margin_container/v_box_container/leave_button
@onready var settings_menu: CanvasLayer = $settings_menu

func _ready() -> void:
	visible = false
	resume_button.pressed.connect(_close)
	settings_button.pressed.connect(func(): settings_menu.open())
	quit_button.pressed.connect(_on_quit_pressed)
	leave_button.pressed.connect(_on_leave_pressed)

func _close() -> void:
	visible = false
	# settings_menu is its own CanvasLayer, so hiding this one doesn't hide it —
	# do it explicitly so it never gets orphaned on screen.
	settings_menu.visible = false

func toggle() -> void:
	visible = !visible
	if !visible:
		settings_menu.visible = false

func _on_quit_pressed() -> void:
	await _apply_death_penalty_and_save()
	var world = get_tree().get_first_node_in_group("world")
	if world:
		world.cleanup_world()
	GlobalSteam.leave_lobby()
	get_tree().quit()

func _on_leave_pressed() -> void:
	await _apply_death_penalty_and_save()
	var world = get_tree().get_first_node_in_group("world")
	if world:
		world.cleanup_world()
	GlobalSteam.leave_lobby()
	get_tree().change_scene_to_file("res://scenes/menus/main_menu.tscn")

# Quitting/leaving mid-expedition counts as dying — same "lose the backpack
# and everything in it" penalty, just immediate instead of the 60s downed
# wait. Then saves — this is the manual save point the auto-save-on-hub-
# arrival doesn't otherwise cover (e.g. quitting mid-expedition still keeps
# whatever loadout/equipment changes happened since the last save).
func _apply_death_penalty_and_save() -> void:
	var world = get_tree().get_first_node_in_group("world")
	var local_player = world.get_local_player() if world else null
	if local_player != null and local_player.lose_everything_if_in_expedition():
		# The drop-bag request just fired off an RPC — give it a moment to
		# actually leave the machine before cleanup_world()/quit() tears the
		# connection down, or it may never actually reach the server.
		await get_tree().create_timer(0.3).timeout
	SaveAndLoad.save_all()
