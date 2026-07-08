extends PanelContainer
class_name TrashCanButton

# Replaces the old right-click "Trash" context menu entry — a deliberate
# drag target instead of a menu option sitting right next to Use/Drop, since
# a stray right-click-then-misclick was too easy a way to lose an item by
# accident. Only accepts items already sitting in one of the player's own
# containers (main grid or a stash tab) — same scope right-click Trash had,
# never offered for an unclaimed ground pile or an equipped slot.

var player = null

func setup(target_player) -> void:
	player = target_player

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if player == null or typeof(data) != TYPE_DICTIONARY:
		return false
	if !data.has("item") or !data.has("origin_container"):
		return false
	var origin: String = data["origin_container"]
	return origin == "player" or origin.begins_with("stash_")

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if player == null:
		return
	player.trash_item(data["item"], data["origin_container"])
