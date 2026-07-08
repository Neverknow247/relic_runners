extends Area2D
class_name OverflowChest

# Hub-only interactable, same open/close-a-panel shape as chest.gd, but it
# shows the player's take-only `overflow` container (see player.gd). It only
# exists to catch items that couldn't fit the stash when Starter Kit banked a
# full loadout — so it only appears while the local player's overflow actually
# holds something, and while it does, the expedition doors refuse to start
# (see expedition_door.gd). Purely local/per-player, like the stash.

var can_use := false
var panel_open := false
# Tracks the last visibility we applied so we only touch the node (and its
# collision) when the overflow's empty/non-empty state actually flips.
var _shown := true

func _ready() -> void:
	_apply_visibility(false)

func _process(_delta: float) -> void:
	var player = _local_player()
	var has_items: bool = player != null and player.overflow_has_items()
	if has_items != _shown:
		_apply_visibility(has_items)
	if !has_items:
		# Empty (and hidden) — nothing to interact with. If a panel was somehow
		# still open (e.g. the player emptied it while standing here), close it.
		if panel_open:
			_close_panel()
		return
	if can_use and Input.is_action_just_pressed("interact"):
		if panel_open:
			_close_panel()
		else:
			_open_panel()

func _apply_visibility(shown: bool) -> void:
	_shown = shown
	visible = shown
	# Turn the collision monitor off while hidden so it can't register the
	# player entering an invisible chest.
	monitoring = shown
	if !shown:
		can_use = false

func _on_body_entered(body: Node) -> void:
	if body.is_multiplayer_authority():
		can_use = true

func _on_body_exited(body: Node) -> void:
	if body.is_multiplayer_authority():
		can_use = false
		if panel_open:
			_close_panel()

func _open_panel() -> void:
	var player = _local_player()
	if player == null or !player.is_alive():
		return
	panel_open = true
	player.open_overflow_panel(self)

func _close_panel() -> void:
	panel_open = false
	var player = _local_player()
	if player != null:
		player.close_overflow_panel()

func _local_player():
	var world = get_tree().get_first_node_in_group("world")
	if world == null:
		return null
	return world.get_local_player()
