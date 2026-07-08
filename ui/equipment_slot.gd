extends Button
class_name EquipmentSlot

# One gear slot ("backpack", "belt", or "cloak"). Accepts a drag from
# anywhere that carries a matching item — the player's own grid, a stash
# tab, or an unclaimed ground pile — routed through player.gd's equip_from()
# so equipping straight from a stash/loot pile doesn't require detouring
# through the main grid first. Dragging back OUT to unequip is supported for
# all three now, including backpack (see player.gd's unequip_backpack_to_
# grid() and DEFAULT_INVENTORY_SIZE — going bagless shrinks you down to a
# tiny 4x1, same "equip nothing" idea belt/cloak already had).

@export var slot_type: String = ""

var player = null

# Hover tooltip (same custom-panel pattern as weapon_slot_button.gd) so equipped
# gear shows its rolled trait + durability.
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
	if player == null:
		return
	var item: Item = player.get_equipped(slot_type)
	if item == null:
		return
	tooltip_label.text = ItemData.tooltip_text(item)
	tooltip_style.border_color = ItemData.tooltip_accent_color(item)
	tooltip.position = Vector2(0, size.y + 10)
	tooltip.visible = true

func setup(target_player) -> void:
	player = target_player
	refresh()

func refresh() -> void:
	if player == null:
		return
	var item: Item = player.get_equipped(slot_type)
	if item == null:
		text = slot_type.capitalize()
	else:
		text = "%s\n%s" % [slot_type.capitalize(), ItemData.get_def(item.type)["display_name"]]

func _get_drag_data(_at_position: Vector2) -> Variant:
	if player == null:
		return null
	var item: Item = player.get_equipped(slot_type)
	if item == null:
		return null
	var preview := Label.new()
	preview.text = text
	preview.add_theme_font_size_override("font_size", 28)
	set_drag_preview(preview)
	return {"item": item, "origin_container": "equip_" + slot_type}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or !data.has("item") or !data.has("origin_container"):
		return false
	var item: Item = data["item"]
	return ItemData.get_equip_slot(item.type) == slot_type

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if player == null:
		return
	player.equip_from(data["origin_container"], data["item"], slot_type)
