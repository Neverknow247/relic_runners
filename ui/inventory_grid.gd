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
const HOVER_DELAY := 0.05
var tooltip: PanelContainer
var tooltip_label: RichTextLabel
var tooltip_style: StyleBoxFlat
var hover_timer := 0.0
var hover_position := Vector2(-1, -1)
# The item the cursor is currently over. The dwell timer only restarts when this
# CHANGES (moving onto a different item, or off items) — moving the mouse within the
# same item leaves the tooltip alone. Without this the old code reset + hid the
# tooltip on every pixel of motion, so it flickered and felt twitchy. "" = no item.
var hovered_instance_id := ""
# Click-vs-drag tracking for the click-to-grab held-item system: a left press+release
# with no drag between them (a click) grabs/drops via inventory_ui; a press+move is a
# normal native drag. `_get_drag_data` clears this when a real drag begins.
var _click_candidate := false

# The held-item manager lives on inventory_ui — reached through the player. null on a
# grid with no player_ref (before setup).
func _iui():
	return player_ref.inventory_ui if player_ref != null else null

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
	hovered_instance_id = ""
	hover_timer = 0.0
	tooltip.visible = false

func _process(delta: float) -> void:
	# No item tooltips while an item is held on the cursor.
	var iui = _iui()
	if iui != null and iui.is_holding():
		if tooltip.visible:
			tooltip.visible = false
		return
	if hovered_instance_id == "" or tooltip.visible:
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
	hovered_instance_id = ""
	hover_timer = 0.0
	queue_redraw()

# Only the player's own grid supports right-click Use/Drop — a ground pile
# you haven't claimed yet doesn't offer either (player_ref is only ever set
# on the player's own grid; see inventory_ui.gd's show_loot_panel()). The
# hover tooltip works on any grid though, so it's handled before that gate.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hover_position = event.position
		var entry = _find_placement_at(_pixel_to_cell(event.position))
		var new_id: String = entry["item"].instance_id if entry != null else ""
		if new_id != hovered_instance_id:
			# Onto a different item (or off items) — restart the dwell and drop the
			# stale tooltip. Motion within the same item is left untouched, so a shown
			# tooltip stays put instead of flickering.
			hovered_instance_id = new_id
			hover_timer = 0.0
			tooltip.visible = false
		# While holding, redraw so the placement highlight follows the cursor.
		var iui_m = _iui()
		if iui_m != null and iui_m.is_holding():
			queue_redraw()
	if player_ref == null:
		return
	if event is InputEventMouseButton:
		# Left RELEASE: resolve a click (grab / drop) if no drag intervened.
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if _click_candidate:
				_click_candidate = false
				_handle_left_click(_pixel_to_cell(event.position))
				accept_event()
			return
		if not event.pressed:
			return
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
			# (Right-click while HOLDING is consumed by inventory_ui to cancel, so
			# this only ever runs empty-handed.)
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
		elif event.button_index == MOUSE_BUTTON_LEFT:
			# A left press that dismisses an open context menu doesn't also arm a grab;
			# otherwise arm a click-candidate (own storage only — loot piles keep
			# native drag + shift-click). A drag starting clears it in _get_drag_data.
			if context_menu.visible:
				context_menu.visible = false
			elif _is_own_storage(container_id):
				_click_candidate = true

# Resolve a left click (no drag happened): drop the held item here, or grab the item
# under the cursor. Own storage only.
func _handle_left_click(cell: Vector2i) -> void:
	if !_is_own_storage(container_id):
		return
	var iui = _iui()
	if iui == null:
		return
	if iui.is_holding():
		iui.try_place_grid(container_id, cell)
	else:
		var entry = _find_placement_at(cell)
		if entry != null:
			iui.grab(entry["item"], container_id, Vector2i(entry["x"], entry["y"]))

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
		var footprint: Vector2i = entry["item"].footprint()
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
		var footprint := item.footprint()
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
	# Placement highlight for the held-item system: while an item is held and the
	# cursor is over THIS (own-storage) grid, tint the target footprint green
	# (fits / 1-item swap) or red (out of bounds / multiple blockers).
	if hover_position != Vector2(-1, -1):
		var iui = _iui()
		if iui != null and iui.is_holding() and _is_own_storage(container_id):
			var held: Item = iui.held_item
			var cell := _pixel_to_cell(hover_position)
			var fp := held.footprint()
			var tint := Color(0.3, 1.0, 0.3, 0.28) if _held_fits(cell, fp) else Color(1.0, 0.3, 0.3, 0.28)
			draw_rect(Rect2(cell.x * CELL_SIZE, cell.y * CELL_SIZE, fp.x * CELL_SIZE, fp.y * CELL_SIZE), tint, true)

# Whether the held item's footprint could drop at `cell` here (in bounds, at most one
# item in the way so a swap is possible). Drives the green/red placement tint.
func _held_fits(cell: Vector2i, fp: Vector2i) -> bool:
	if container_id == "overflow":
		return false
	if cell.x < 0 or cell.y < 0 or cell.x + fp.x > inventory.width or cell.y + fp.y > inventory.height:
		return false
	return inventory.overlapping_items(cell.x, cell.y, fp.x, fp.y).size() <= 1

func _get_drag_data(at_position: Vector2) -> Variant:
	_click_candidate = false  # a real drag is starting — this is not a click
	var iui = _iui()
	if iui != null and iui.is_holding():
		return null  # no native drag while an item is held on the cursor
	var entry = _find_placement_at(_pixel_to_cell(at_position))
	if entry == null:
		return null
	var item: Item = entry["item"]
	dragging_instance_id = item.instance_id
	tooltip.visible = false
	hovered_instance_id = ""
	hover_timer = 0.0
	queue_redraw()
	var def := ItemData.get_def(item.type)
	var footprint := item.footprint()
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
	elif origin_container == "materials" and player_ref != null and _is_own_storage(container_id):
		# Dragged out of the Materials bank (crystals/gems tab) — withdraw one unit
		# into this grid. The bank holds counts, not placed Items, so cell.x/y aren't
		# used; it lands in the first free cell (see withdraw_material_to_grid).
		player_ref.withdraw_material_to_grid(item.type, container_id)
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
	if what != NOTIFICATION_DRAG_END:
		return
	# Capture BEFORE clearing: a non-empty id means THIS grid is the one the drag
	# started from (DRAG_END fires on every grid).
	var dragged_id := dragging_instance_id
	dragging_instance_id = ""
	queue_redraw()
	# Diablo-style ground drop: a drag from the player's OWN bag that no control
	# accepted (gui_is_drag_successful() == false) AND was released OUTSIDE the
	# inventory window drops the item on the ground where the player stands. Released
	# inside the window on an invalid spot just snaps back (no drop). Only the bag
	# ("player") does this — dragging out of a stash tab/loot pile shouldn't litter.
	if dragged_id == "" or player_ref == null or container_id != "player":
		return
	if get_viewport().gui_is_drag_successful():
		return
	var iui = player_ref.inventory_ui
	if iui != null and iui.has_method("mouse_over_window") and iui.mouse_over_window():
		return
	for entry in inventory.placements:
		if entry["item"].instance_id == dragged_id:
			player_ref.drop_item(entry["item"], container_id)
			return
