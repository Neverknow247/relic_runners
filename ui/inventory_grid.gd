extends Control
class_name InventoryGrid

# Reusable drag-and-drop grid widget — used both for the player's own
# backpack panel and for a ground loot pile's panel, distinguished only by
# container_id ("player" vs a pickup's pickup_id). No item-icon art exists
# yet, so items render as a color + short label, same placeholder-art
# convention enemy.tscn uses for its color_rect + weapon_label.

const CELL_SIZE := 160.0
const CELL_PADDING := 6.0
const GRID_LINE_COLOR := Color(1, 1, 1, 0.25)

var inventory: Inventory
var container_id: String = ""
# Only set for the player's own grid — needed to route a ground->player
# claim through player.request_claim(). Ground-pile grids never need it,
# since dropping player->ground isn't built this pass.
var player_ref = null

# The instance_id currently being dragged out of THIS grid, so _draw() can
# hide it without the model ever being mutated until the drop actually
# resolves — a failed/cancelled drag just clears this, nothing to restore.
var dragging_instance_id := ""

# Right-click context menu (Use/Drop) — a plain Control popup built in code
# rather than a native PopupMenu, since PopupMenu is a Window and positions
# itself in actual screen pixels; this UI runs on a 3840x2160 canvas that
# gets stretched down to the real window, so a Window-based popup would
# show up in the wrong place. A child Control positioned in this grid's own
# local space sidesteps that entirely.
var context_menu: PanelContainer
var context_use_button: Button
var context_drop_button: Button
var context_split_button: Button
var context_item: Item = null

# Weapon stat tooltip — shown after the mouse sits still over a weapon item
# for HOVER_DELAY seconds. Works on any grid (including a loot pile you
# haven't claimed yet), not just the player's own — unlike the context menu,
# which needs player_ref for its actions.
const HOVER_DELAY := 0.5
var tooltip: PanelContainer
var tooltip_label: RichTextLabel
var tooltip_style: StyleBoxFlat
var hover_timer := 0.0
var hover_position := Vector2(-1, -1)

func _ready() -> void:
	context_menu = PanelContainer.new()
	context_menu.visible = false
	context_menu.z_index = 10
	var vbox := VBoxContainer.new()
	context_use_button = Button.new()
	context_use_button.text = "Use"
	context_use_button.custom_minimum_size = Vector2(180, 70)
	context_use_button.add_theme_font_size_override("font_size", 28)
	context_use_button.pressed.connect(_on_context_use_pressed)
	context_drop_button = Button.new()
	context_drop_button.text = "Drop"
	context_drop_button.custom_minimum_size = Vector2(180, 70)
	context_drop_button.add_theme_font_size_override("font_size", 28)
	context_drop_button.pressed.connect(_on_context_drop_pressed)
	context_split_button = Button.new()
	context_split_button.text = "Split"
	context_split_button.custom_minimum_size = Vector2(180, 70)
	context_split_button.add_theme_font_size_override("font_size", 28)
	context_split_button.pressed.connect(_on_context_split_pressed)
	vbox.add_child(context_use_button)
	vbox.add_child(context_drop_button)
	vbox.add_child(context_split_button)
	context_menu.add_child(vbox)
	add_child(context_menu)

	tooltip = PanelContainer.new()
	tooltip.visible = false
	tooltip.z_index = 20
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_style = ItemData.build_tooltip_style()
	tooltip.add_theme_stylebox_override("panel", tooltip_style)
	tooltip_label = ItemData.build_tooltip_label()
	tooltip.add_child(tooltip_label)
	add_child(tooltip)
	mouse_exited.connect(_on_mouse_exited)

func _on_mouse_exited() -> void:
	hover_position = Vector2(-1, -1)
	hover_timer = 0.0
	tooltip.visible = false

func _process(delta: float) -> void:
	if hover_position == Vector2(-1, -1) or tooltip.visible:
		return
	hover_timer += delta
	if hover_timer >= HOVER_DELAY:
		_try_show_tooltip()

func _try_show_tooltip() -> void:
	var entry = _find_placement_at(_pixel_to_cell(hover_position))
	if entry == null:
		return
	# Every item now gets a tooltip (name + description + any live stats), not
	# just weapons.
	tooltip_label.text = ItemData.tooltip_text(entry["item"])
	tooltip_style.border_color = ItemData.tooltip_accent_color(entry["item"])
	tooltip.position = hover_position + Vector2(20, 20)
	tooltip.visible = true

func setup(inv: Inventory, cid: String, player_node = null) -> void:
	inventory = inv
	container_id = cid
	player_ref = player_node
	custom_minimum_size = Vector2(inv.width * CELL_SIZE, inv.height * CELL_SIZE)
	size = custom_minimum_size
	queue_redraw()

func refresh() -> void:
	context_menu.visible = false
	tooltip.visible = false
	hover_timer = 0.0
	queue_redraw()

# Only the player's own grid supports right-click Use/Drop — a ground pile
# you haven't claimed yet doesn't offer either (player_ref is only ever set
# on the player's own grid; see inventory_ui.gd's show_loot_panel()). The
# hover tooltip works on any grid though, so it's handled before that gate.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.position != hover_position:
		hover_position = event.position
		hover_timer = 0.0
		tooltip.visible = false
	if player_ref == null:
		return
	if event is InputEventMouseButton and event.pressed:
		# Shift + left-click: instantly move the clicked item to the OTHER open
		# panel (loot/stash/overflow <-> backpack) instead of dragging it.
		if event.button_index == MOUSE_BUTTON_LEFT and event.shift_pressed:
			var entry = _find_placement_at(_pixel_to_cell(event.position))
			if entry != null:
				player_ref.quick_transfer_item(entry["item"], container_id)
				accept_event()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			# Use/Drop only apply to the player's own storage — never an
			# unclaimed ground pile (which sets container_id to a pickup id).
			if !_is_own_storage(container_id):
				return
			var entry = _find_placement_at(_pixel_to_cell(event.position))
			if entry == null:
				context_menu.visible = false
				return
			context_item = entry["item"]
			context_use_button.visible = ItemData.is_usable(context_item.type)
			context_split_button.visible = context_item.quantity > 1 and ItemData.is_stackable(context_item.type)
			context_menu.position = event.position
			context_menu.visible = true
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and context_menu.visible:
			context_menu.visible = false

func _on_context_use_pressed() -> void:
	if context_item != null and player_ref != null:
		player_ref.use_item(context_item, container_id)
	context_menu.visible = false

func _on_context_drop_pressed() -> void:
	if context_item != null and player_ref != null:
		player_ref.drop_item(context_item, container_id)
	context_menu.visible = false

func _on_context_split_pressed() -> void:
	if context_item != null and player_ref != null:
		player_ref.split_item(context_item, container_id)
	context_menu.visible = false

func _pixel_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(pos.x / CELL_SIZE), int(pos.y / CELL_SIZE))

func _find_placement_at(cell: Vector2i) -> Variant:
	for entry in inventory.placements:
		var footprint := ItemData.get_footprint(entry["item"].type)
		if cell.x >= entry["x"] and cell.x < entry["x"] + footprint.x \
				and cell.y >= entry["y"] and cell.y < entry["y"] + footprint.y:
			return entry
	return null

func _draw() -> void:
	if inventory == null:
		return
	for x in range(inventory.width + 1):
		draw_line(
			Vector2(x * CELL_SIZE, 0),
			Vector2(x * CELL_SIZE, inventory.height * CELL_SIZE),
			GRID_LINE_COLOR, 2.0
		)
	for y in range(inventory.height + 1):
		draw_line(
			Vector2(0, y * CELL_SIZE),
			Vector2(inventory.width * CELL_SIZE, y * CELL_SIZE),
			GRID_LINE_COLOR, 2.0
		)
	var font := ThemeDB.fallback_font
	for entry in inventory.placements:
		var item: Item = entry["item"]
		if item.instance_id == dragging_instance_id:
			continue
		var footprint := ItemData.get_footprint(item.type)
		var def := ItemData.get_def(item.type)
		var rect := Rect2(
			entry["x"] * CELL_SIZE + CELL_PADDING,
			entry["y"] * CELL_SIZE + CELL_PADDING,
			footprint.x * CELL_SIZE - CELL_PADDING * 2,
			footprint.y * CELL_SIZE - CELL_PADDING * 2
		)
		draw_rect(rect, def["color"])
		draw_string(font, rect.position + Vector2(12, 48), def["icon_label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 48)
		if item.quantity > 1:
			draw_string(
				font, rect.position + Vector2(12, rect.size.y - 12),
				str(item.quantity), HORIZONTAL_ALIGNMENT_LEFT, -1, 36
			)

func _get_drag_data(at_position: Vector2) -> Variant:
	var entry = _find_placement_at(_pixel_to_cell(at_position))
	if entry == null:
		return null
	var item: Item = entry["item"]
	dragging_instance_id = item.instance_id
	tooltip.visible = false
	hover_timer = 0.0
	queue_redraw()
	var def := ItemData.get_def(item.type)
	var footprint := ItemData.get_footprint(item.type)
	var preview := ColorRect.new()
	preview.color = def["color"]
	preview.custom_minimum_size = Vector2(footprint.x * CELL_SIZE, footprint.y * CELL_SIZE)
	preview.modulate.a = 0.85
	set_drag_preview(preview)
	return {"item": item, "origin_container": container_id}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	# The overflow chest is take-only — you can drag items OUT of it, but never
	# deposit into it (see player.gd's overflow container). Reject all drops
	# onto an overflow grid so nothing can be stashed there.
	if container_id == "overflow":
		return false
	return typeof(data) == TYPE_DICTIONARY and data.has("item") and data.has("origin_container")

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var item: Item = data["item"]
	var origin_container: String = data["origin_container"]
	var cell := _pixel_to_cell(at_position)
	if origin_container == container_id:
		# combine_or_move so dropping a stack onto a same-type stack in the SAME
		# container (e.g. stash-to-stash) merges instead of no-op'ing.
		inventory.combine_or_move(item.instance_id, cell.x, cell.y)
		if player_ref != null:
			player_ref.persist_container(container_id)
	elif origin_container.begins_with("equip_") and _is_own_storage(container_id) and player_ref != null:
		player_ref.unequip_to_grid(origin_container.trim_prefix("equip_"), container_id, cell.x, cell.y)
	elif origin_container.begins_with("quick_") and _is_own_storage(container_id) and player_ref != null:
		player_ref.unequip_quick_slot_to_grid(int(origin_container.trim_prefix("quick_")), container_id, cell.x, cell.y)
	elif player_ref != null and _is_own_storage(origin_container) and _is_own_storage(container_id):
		# Both sides are the same player's own storage (backpack <-> a stash
		# tab) — a plain local move, no claim/RPC involved either way.
		player_ref.move_between_own_containers(origin_container, item.instance_id, container_id, cell.x, cell.y)
	elif container_id == "player" and player_ref != null:
		# Pass the exact cell dropped on so the claimed item lands there (if it
		# still fits when the claim resolves) instead of always auto-placing.
		player_ref.request_claim(origin_container, item.instance_id, "inventory", cell.x, cell.y)
	# else: dropping a player-owned item onto a ground pile isn't built this
	# pass (see plan) — the drag data is simply discarded.
	dragging_instance_id = ""
	queue_redraw()

func _is_own_storage(cid: String) -> bool:
	# "overflow" counts as own storage so items can be dragged OUT of the
	# overflow chest into the bag/stash (dropping INTO it is separately blocked
	# in _can_drop_data). Same local move machinery as backpack <-> stash.
	return cid == "player" or cid.begins_with("stash_") or cid == "overflow"

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		dragging_instance_id = ""
		queue_redraw()
