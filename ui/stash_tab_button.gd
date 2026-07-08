extends Button
class_name StashTabButton

# Selecting a tab is still a click (see inventory_ui.gd's .pressed connect),
# but this also doubles as a drop target: dragging an item straight onto a
# tab button places it into that tab (if it fits) without needing to select
# the tab and drag into its grid as two separate steps.

@export var tab_index: int = 0

var player = null

func setup(target_player) -> void:
	player = target_player

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return player != null and typeof(data) == TYPE_DICTIONARY \
		and data.has("item") and data.has("origin_container")

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if player == null:
		return
	player.drop_item_into_stash_tab(tab_index, data["item"], data["origin_container"])
