extends CanvasLayer

# Always-visible, read-only reflection of the belt's quick slots (drag/drop
# still only happens in the inventory panel's own QuickSlotButtons — this is
# just "what do I currently have loaded"). Hidden entirely with no belt
# equipped, same as the row inside the inventory panel.

@onready var row: HBoxContainer = $row

func update(slots: Array) -> void:
	visible = slots.size() > 0
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	for i in slots.size():
		row.add_child(_build_slot_box(i, slots[i]))

func _build_slot_box(index: int, item) -> PanelContainer:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(140, 140)
	var style := StyleBoxFlat.new()
	style.bg_color = ItemData.get_def(item.type)["color"] if item != null else Color(0.15, 0.15, 0.15, 0.85)
	box.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(0, 0, 0, 1) if item != null else Color(1, 1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 1) if item != null else Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if item == null:
		label.text = "[%d]\n(empty)" % (index + 1)
	else:
		var def := ItemData.get_def(item.type)
		label.text = "[%d]\n%s x%d" % [index + 1, def["icon_label"], item.quantity]
	box.add_child(label)
	return box
