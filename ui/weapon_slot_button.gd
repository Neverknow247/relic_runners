extends Button
class_name WeaponSlotButton

# Hand and holster are the only two weapon slots, so "drag one onto the
# other" and "toggle active_slot" are the same operation — there's nothing
# else that specific gesture could mean with only 2 slots. Clicking
# intentionally does nothing here (no .pressed connection) — swapping is
# drag-only per the user's request, not a click.
#
# This slot also accepts a weapon Item dragged in from the player's own
# inventory grid, to actually equip it. Dragging OUT to the grid unequips it
# (leaving the slot empty — see player.gd's null-safe get_equipped_weapon()
# callers) — the drag payload below does double duty: WeaponSlotButton's own
# _can_drop_data() still recognizes "weapon_slot_drag" for the hand<->holster
# swap, while InventoryGrid recognizes "item"/"origin_container" the exact
# same way it already does for EquipmentSlot's belt/cloak unequip drag.

@export var role: String = "hand"  # "hand" or "holster"

var player = null

# Same durability/mana hover tooltip as inventory_grid.gd's weapon items,
# reimplemented here since this is a Button (mouse_entered/exited), not a
# custom-drawn grid — 2x the size of inventory_grid's own, per request.
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
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _on_mouse_entered() -> void:
	is_hovering = true
	hover_timer = 0.0

func _on_mouse_exited() -> void:
	is_hovering = false
	hover_timer = 0.0
	tooltip.visible = false

func _process(delta: float) -> void:
	if !is_hovering or tooltip.visible:
		return
	hover_timer += delta
	if hover_timer >= HOVER_DELAY:
		_try_show_tooltip()

func _try_show_tooltip() -> void:
	if player == null:
		return
	var weapon: Weapon = player.weapon_slots[_current_slot_index()]
	if weapon == null:
		return
	# Reuse the shared item tooltip (name + description + durability/mana/forms)
	# by wrapping the equipped Weapon as an Item.
	var item = player._wrap_weapon_as_item(weapon)
	tooltip_label.text = ItemData.tooltip_text(item)
	tooltip_style.border_color = ItemData.tooltip_accent_color(item)
	tooltip.position = Vector2(0, size.y + 10)
	tooltip.visible = true

func setup(target_player) -> void:
	player = target_player

func _current_slot_index() -> int:
	return player.active_slot if role == "hand" else 1 - player.active_slot

func _get_drag_data(_at_position: Vector2) -> Variant:
	if player == null:
		return null
	tooltip.visible = false
	hover_timer = 0.0
	var preview := Label.new()
	preview.text = text
	preview.add_theme_font_size_override("font_size", 32)
	set_drag_preview(preview)
	var weapon: Weapon = player.weapon_slots[_current_slot_index()]
	if weapon == null:
		# Nothing equipped here — only the hand<->holster swap gesture makes
		# sense, there's nothing to unequip out to the grid.
		return {"weapon_slot_drag": true, "source": self}
	return {
		"weapon_slot_drag": true,
		"source": self,
		"item": Item.new(weapon.type, 1),
		"origin_container": "equip_" + role,
	}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if data.has("weapon_slot_drag"):
		return data.get("source") != self
	if data.has("item"):
		var item: Item = data["item"]
		return ItemData.get_equip_slot(item.type) == "weapon"
	return false

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if player == null:
		return
	if data.has("weapon_slot_drag"):
		player.swap_to_weapon_slot(1 - player.active_slot)
	elif data.has("item"):
		player.equip_from(data["origin_container"], data["item"], role)
