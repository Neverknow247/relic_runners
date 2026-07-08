extends Button
class_name QuickSlotButton

# One of the belt's quick slots (count is whatever the equipped belt
# grants — see player.gd's _resize_quick_slots_for_belt(); inventory_ui.gd
# creates exactly one of these per current slot) — only usable items
# (health_potion, mana_crystal, ...) can be dropped in, and only while a
# belt is actually equipped.

@export var slot_index: int = 0

var player = null

# Hover tooltip (same custom-panel pattern as weapon_slot_button.gd, since a
# native Control tooltip is a Window and mispositions on the scaled canvas).
const HOVER_DELAY := 0.5
var tooltip: PanelContainer
var tooltip_label: RichTextLabel
var tooltip_style: StyleBoxFlat
var hover_timer := 0.0
var is_hovering := false

func _ready() -> void:
	tooltip = PanelContainer.new()
	tooltip.visible = false
	tooltip.z_index = 20
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_style = ItemData.build_tooltip_style()
	tooltip.add_theme_stylebox_override("panel", tooltip_style)
	tooltip_label = ItemData.build_tooltip_label()
	tooltip.add_child(tooltip_label)
	add_child(tooltip)
	mouse_entered.connect(func(): is_hovering = true; hover_timer = 0.0)
	mouse_exited.connect(func(): is_hovering = false; hover_timer = 0.0; tooltip.visible = false)

func _process(delta: float) -> void:
	if !is_hovering or tooltip.visible:
		return
	hover_timer += delta
	if hover_timer >= HOVER_DELAY:
		_try_show_tooltip()

func _try_show_tooltip() -> void:
	if !_has_valid_slot():
		return
	var item: Item = player.quick_slots[slot_index]
	if item == null:
		return
	tooltip_label.text = ItemData.tooltip_text(item)
	tooltip_style.border_color = ItemData.tooltip_accent_color(item)
	tooltip.position = Vector2(0, size.y + 10)
	tooltip.visible = true

func setup(target_player) -> void:
	player = target_player

func _has_valid_slot() -> bool:
	return player != null and slot_index >= 0 and slot_index < player.quick_slots.size()

func refresh() -> void:
	if player == null:
		return
	disabled = player.equipped_belt == null
	if !_has_valid_slot():
		return
	var item: Item = player.quick_slots[slot_index]
	if item == null:
		text = "Quick %d\n(empty)" % (slot_index + 1)
	else:
		text = "Quick %d\n%s x%d" % [
			slot_index + 1, ItemData.get_def(item.type)["display_name"], item.quantity,
		]

func _get_drag_data(_at_position: Vector2) -> Variant:
	if !_has_valid_slot():
		return null
	var item: Item = player.quick_slots[slot_index]
	if item == null:
		return null
	var preview := Label.new()
	preview.text = text
	preview.add_theme_font_size_override("font_size", 28)
	set_drag_preview(preview)
	return {"item": Item.new(item.type, item.quantity), "origin_container": "quick_" + str(slot_index)}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if !_has_valid_slot():
		return false
	if typeof(data) != TYPE_DICTIONARY or !data.has("item") or !data.has("origin_container"):
		return false
	var item: Item = data["item"]
	return ItemData.is_usable(item.type)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if player == null:
		return
	player.equip_from(data["origin_container"], data["item"], "quick_" + str(slot_index))
