extends CanvasLayer

# Diablo-style layout: left column = the "other" panel (ground loot / stash /
# materials), middle column = the player's backpack + quick slots, right column =
# the equipment paper-doll. See inventory_ui.tscn.
@onready var player_grid: InventoryGrid = $panel_container/margin_container/root_vbox/columns_row/middle_column/player_grid
@onready var quick_slot_row: HBoxContainer = $panel_container/margin_container/root_vbox/columns_row/middle_column/quick_slot_row
@onready var loot_grid: InventoryGrid = $panel_container/margin_container/root_vbox/columns_row/left_column/loot_grid
@onready var loot_actions_row: HBoxContainer = $panel_container/margin_container/root_vbox/columns_row/left_column/loot_actions_row
@onready var take_all_button: Button = $panel_container/margin_container/root_vbox/columns_row/left_column/loot_actions_row/take_all_button
@onready var stash_column: VBoxContainer = $panel_container/margin_container/root_vbox/columns_row/left_column/stash_column
@onready var stash_grid: InventoryGrid = $panel_container/margin_container/root_vbox/columns_row/left_column/stash_column/stash_grid
@onready var materials_grid: MaterialsGrid = $panel_container/margin_container/root_vbox/columns_row/left_column/stash_column/materials_grid
@onready var materials_tab_button: Button = $panel_container/margin_container/root_vbox/columns_row/left_column/stash_column/stash_tab_row/materials_tab_button
@onready var gems_tab_button: Button = $panel_container/margin_container/root_vbox/columns_row/left_column/stash_column/stash_tab_row/gems_tab_button
@onready var move_all_button: Button = $panel_container/margin_container/root_vbox/columns_row/left_column/stash_column/move_all_button
@onready var stash_tab_1: StashTabButton = $panel_container/margin_container/root_vbox/columns_row/left_column/stash_column/stash_tab_row/stash_tab_1
@onready var stash_tab_2: StashTabButton = $panel_container/margin_container/root_vbox/columns_row/left_column/stash_column/stash_tab_row/stash_tab_2
@onready var stash_tab_3: StashTabButton = $panel_container/margin_container/root_vbox/columns_row/left_column/stash_column/stash_tab_row/stash_tab_3
@onready var stash_tab_4: StashTabButton = $panel_container/margin_container/root_vbox/columns_row/left_column/stash_column/stash_tab_row/stash_tab_4
@onready var weapon_hand_slot: WeaponSlotButton = $panel_container/margin_container/root_vbox/columns_row/right_column/doll_panel/doll_margin/equipment_doll/weapon_hand_slot
@onready var weapon_holster_slot: WeaponSlotButton = $panel_container/margin_container/root_vbox/columns_row/right_column/doll_panel/doll_margin/equipment_doll/weapon_holster_slot
@onready var backpack_slot: EquipmentSlot = $panel_container/margin_container/root_vbox/columns_row/right_column/doll_panel/doll_margin/equipment_doll/backpack_slot
@onready var belt_slot: EquipmentSlot = $panel_container/margin_container/root_vbox/columns_row/right_column/doll_panel/doll_margin/equipment_doll/belt_slot
@onready var body_slot: EquipmentSlot = $panel_container/margin_container/root_vbox/columns_row/right_column/doll_panel/doll_margin/equipment_doll/body_slot
@onready var hat_slot: EquipmentSlot = $panel_container/margin_container/root_vbox/columns_row/right_column/doll_panel/doll_margin/equipment_doll/hat_slot
@onready var necklace_slot: EquipmentSlot = $panel_container/margin_container/root_vbox/columns_row/right_column/doll_panel/doll_margin/equipment_doll/necklace_slot
@onready var pants_slot: EquipmentSlot = $panel_container/margin_container/root_vbox/columns_row/right_column/doll_panel/doll_margin/equipment_doll/pants_slot
@onready var boots_slot: EquipmentSlot = $panel_container/margin_container/root_vbox/columns_row/right_column/doll_panel/doll_margin/equipment_doll/boots_slot
@onready var ring_1_slot: EquipmentSlot = $panel_container/margin_container/root_vbox/columns_row/right_column/doll_panel/doll_margin/equipment_doll/ring_1_slot
@onready var ring_2_slot: EquipmentSlot = $panel_container/margin_container/root_vbox/columns_row/right_column/doll_panel/doll_margin/equipment_doll/ring_2_slot
@onready var trash_can: TrashCanButton = $panel_container/margin_container/root_vbox/columns_row/right_column/trash_can

var player = null
var active_stash_tab := 0
# The stash column shows either a numbered tab's grid or one of the two Materials
# tabs (Crystals / Gems). materials_category tracks which one when showing_materials.
var showing_materials := false
var materials_category := "crystals"

# --- Held-item (click-grab) system ---------------------------------------
# One item at a time can be "held" on the cursor, picked up by a left-CLICK (vs a
# drag). The mouse WHEEL rotates it, a click drops it, right-click cancels it back to
# origin. The
# grids/slot widgets detect the click and call into here; native drag is suppressed
# while holding (is_holding()). held_origin is a container id ("player"/"stash_N"/
# "overflow") for a grid, or "slot:<destination>" (e.g. "slot:backpack"/"slot:hand"/
# "slot:quick_0") when the item was lifted out of an equipment/weapon/belt slot.
var held_item: Item = null
var held_origin := ""
var held_origin_cell := Vector2i.ZERO
var held_origin_rotated := false
var held_preview: ColorRect = null
var held_preview_label: Label = null

func setup(target_player) -> void:
	player = target_player
	player_grid.setup(player.inventory, "player", player)
	loot_grid.visible = false
	stash_column.visible = false
	weapon_hand_slot.setup(player)
	weapon_holster_slot.setup(player)
	for slot in _gear_slots():
		slot.setup(player)
	stash_tab_1.setup(player)
	stash_tab_2.setup(player)
	stash_tab_3.setup(player)
	stash_tab_4.setup(player)
	materials_grid.setup(player)
	trash_can.setup(player)
	stash_tab_1.pressed.connect(func(): _select_stash_tab(0))
	stash_tab_2.pressed.connect(func(): _select_stash_tab(1))
	stash_tab_3.pressed.connect(func(): _select_stash_tab(2))
	stash_tab_4.pressed.connect(func(): _select_stash_tab(3))
	materials_tab_button.pressed.connect(func(): _select_materials_tab("crystals"))
	gems_tab_button.pressed.connect(func(): _select_materials_tab("gems"))
	take_all_button.pressed.connect(func(): if player: player.take_all_from_loot())
	move_all_button.pressed.connect(_on_move_all_pressed)
	refresh()

func refresh() -> void:
	# player.inventory can be swapped out entirely (backpack resize), so
	# player_grid needs to stay pointed at whatever's current, not just
	# redraw whatever it already has.
	if player != null:
		player_grid.setup(player.inventory, "player", player)
	if loot_grid.visible:
		loot_grid.refresh()
	if stash_column.visible:
		if showing_materials:
			materials_grid.refresh()
		else:
			stash_grid.setup(player.stash_tabs[active_stash_tab], "stash_%d" % active_stash_tab, player)
	_refresh_weapon_row()
	for slot in _gear_slots():
		slot.refresh()
	_refresh_quick_slot_row()

# All the EquipmentSlot buttons on the paper-doll (weapons are handled
# separately by _refresh_weapon_row since they're a different widget).
func _gear_slots() -> Array:
	return [
		backpack_slot, belt_slot, body_slot, hat_slot, necklace_slot,
		pants_slot, boots_slot, ring_1_slot, ring_2_slot,
	]

func _refresh_weapon_row() -> void:
	if player == null:
		return
	# Hand always shows whichever weapon is actually active (not a fixed
	# array index) — pressing the swap_weapon key or drag-swapping the two
	# slots here both just flip active_slot, and this display follows it.
	var hand: Weapon = player.weapon_slots[player.active_slot]
	var holster: Weapon = player.weapon_slots[1 - player.active_slot]
	weapon_hand_slot.text = "Hand\n%s" % hand.type.capitalize() if hand != null else "Hand\n(empty)"
	weapon_holster_slot.text = "Holster\n%s" % holster.type.capitalize() if holster != null else "Holster\n(empty)"
	weapon_hand_slot.modulate = Color(1, 1, 0.6)
	weapon_holster_slot.modulate = Color(1, 1, 1)

# Quick slot COUNT is a property of the equipped belt (see ItemData's
# provides_quick_slots), so the row's buttons are built dynamically to match
# instead of a fixed number in the .tscn — hidden entirely with no belt
# equipped. Only actually rebuilds the child buttons when the count changes
# (a belt swap), not on every refresh() call, so normal item-in-slot changes
# don't cause a flicker of destroyed-and-recreated buttons.
func _refresh_quick_slot_row() -> void:
	if player == null:
		return
	var count: int = player.quick_slots.size()
	quick_slot_row.visible = player.equipped_belt != null and count > 0
	if quick_slot_row.get_child_count() != count:
		for child in quick_slot_row.get_children():
			quick_slot_row.remove_child(child)
			child.queue_free()
		for i in count:
			var btn := QuickSlotButton.new()
			btn.slot_index = i
			btn.custom_minimum_size = Vector2(320, 120)
			btn.add_theme_font_size_override("font_size", 28)
			quick_slot_row.add_child(btn)
			btn.setup(player)
	for child in quick_slot_row.get_children():
		child.refresh()

func show_loot_panel(pile_inventory: Inventory, pickup_id: String) -> void:
	# A ground pile and the personal stash showing at once would be a
	# confusing 3-grid wall — only one "other" panel is ever open alongside
	# the player's own backpack.
	hide_stash_panel()
	loot_grid.visible = true
	loot_actions_row.visible = true
	# Take All is a backpack trait now (pack_takeall) — only offer it while an
	# unbroken backpack granting it is equipped.
	take_all_button.visible = player != null and player.has_gear_attribute("pack_takeall")
	# player_ref is set so shift-click quick-transfer works from the pile; the
	# right-click Use/Drop menu stays gated to own-storage grids only (see
	# inventory_grid.gd's _gui_input), so an unclaimed pile still offers neither.
	loot_grid.setup(pile_inventory, pickup_id, player)

func hide_loot_panel() -> void:
	loot_grid.visible = false
	loot_actions_row.visible = false

# For shift-click quick-transfer: the container id of the OTHER panel currently
# open alongside the player's backpack (a ground pile, the overflow chest, or
# the active stash tab), or "" if none. From the player's own grid the "other"
# is that panel; from any other grid the "other" is always the player's grid.
func other_open_container_id(from_container: String) -> String:
	if from_container != "player":
		return "player"
	if loot_grid.visible:
		return loot_grid.container_id
	if stash_column.visible:
		# The Materials tab is the open "other" panel when it's the one showing —
		# so shift-clicking a crystal/stone banks it (player._quick_transfer only
		# acts on materials for this destination).
		return "materials" if showing_materials else ("stash_%d" % active_stash_tab)
	return ""

# One "Move All to Stash" for both tab modes: crystals/stones always bank to the
# Materials tab, everything else fills the tab you're looking at (spilling into
# the others), and anything that fits nowhere stays in the bag. On the Materials
# tab, active_stash_tab is just the last numbered tab you had open, so it's a
# sensible starting point for the non-material items.
func _on_move_all_pressed() -> void:
	if player != null:
		player.move_all_to_stash(active_stash_tab)

# The overflow chest reuses the same single "other" grid the ground-loot panel
# uses, but as the player's OWN take-only storage: it gets player_ref set (so
# drag-out and right-click Use/Drop work) and no take-all row. Dropping INTO
# it is blocked in inventory_grid.gd's _can_drop_data.
func show_overflow_panel(overflow_inventory: Inventory) -> void:
	hide_stash_panel()
	loot_actions_row.visible = false
	loot_grid.visible = true
	loot_grid.setup(overflow_inventory, "overflow", player)

func hide_overflow_panel() -> void:
	loot_grid.visible = false
	loot_actions_row.visible = false

func show_stash_panel() -> void:
	hide_loot_panel()
	stash_column.visible = true
	_select_stash_tab(active_stash_tab)

func hide_stash_panel() -> void:
	stash_column.visible = false

# True while the mouse is over the inventory window. The grids use this to tell a
# failed drag released in the game world (drop on ground) from one released inside
# the window on an invalid spot (snap back). Uses the panel's own coordinate space
# so it stays correct under the stretched UI canvas.
func mouse_over_window() -> bool:
	var pc := $panel_container
	return pc.get_global_rect().has_point(pc.get_global_mouse_position())

# ======================= Held-item (click-grab) system ===================
func is_holding() -> bool:
	return held_item != null

func _ensure_preview() -> void:
	if held_preview != null:
		return
	held_preview = ColorRect.new()
	held_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	held_preview.z_index = 100
	held_preview.visible = false
	held_preview_label = Label.new()
	held_preview_label.position = Vector2(12, 8)
	held_preview_label.add_theme_font_size_override("font_size", 48)
	held_preview.add_child(held_preview_label)
	add_child(held_preview)

func _refresh_preview() -> void:
	_ensure_preview()
	if held_item == null:
		held_preview.visible = false
		return
	var fp := held_item.footprint()
	var def := ItemData.get_def(held_item.type)
	var col: Color = def["color"]
	held_preview.color = Color(col.r, col.g, col.b, 0.8)
	held_preview.size = Vector2(fp.x * InventoryGrid.CELL_SIZE, fp.y * InventoryGrid.CELL_SIZE)
	held_preview_label.text = def["icon_label"]
	held_preview.visible = true

func _process(_delta: float) -> void:
	if held_item == null:
		return
	# Closing the inventory mid-hold would strand the item — put it back first.
	if not visible:
		cancel_held()
		return
	if held_preview != null:
		# Center the item's top-left cell on the cursor (matches top-left-anchored drop).
		var m: Vector2 = $panel_container.get_global_mouse_position()
		held_preview.position = m - Vector2(InventoryGrid.CELL_SIZE, InventoryGrid.CELL_SIZE) * 0.5

func _input(event: InputEvent) -> void:
	if held_item == null or not visible:
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				# Scroll the wheel (either direction) to rotate the held item.
				rotate_held()
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_RIGHT:
				cancel_held()
				get_viewport().set_input_as_handled()

func rotate_held() -> void:
	if held_item == null:
		return
	held_item.rotated = not held_item.rotated
	_refresh_preview()
	# Redraw whatever grids are showing so the placement highlight tracks the new shape.
	player_grid.queue_redraw()
	if stash_column.visible and not showing_materials:
		stash_grid.queue_redraw()
	if loot_grid.visible:
		loot_grid.queue_redraw()

# Pick up an item from a GRID cell (called by inventory_grid on a click).
func grab(item: Item, origin_container: String, cell: Vector2i) -> void:
	if item == null or is_holding() or player == null:
		return
	var taken: Item = player.take_from_container(origin_container, item.instance_id)
	if taken == null:
		return
	held_item = taken
	held_origin = origin_container
	held_origin_cell = cell
	held_origin_rotated = taken.rotated
	_refresh_preview()

# Drop the held item into an own-storage grid at cell (clean place OR 1-item swap).
func try_place_grid(container_id: String, cell: Vector2i) -> void:
	if held_item == null or player == null:
		return
	if container_id == "overflow":
		return  # overflow is take-only (mirrors _can_drop_data)
	var result = player.place_or_swap_in_container(container_id, held_item, cell)
	if result == false:
		return  # didn't fit — keep holding
	held_item = result if result is Item else null
	if held_item != null:
		# Swapped — now holding the displaced item, with this cell as its origin.
		held_origin = container_id
		held_origin_cell = cell
		held_origin_rotated = held_item.rotated
	_refresh_preview()

func _slot_item_id(destination: String) -> String:
	if destination == "hand" or destination == "holster":
		var idx: int = player.active_slot if destination == "hand" else 1 - player.active_slot
		var w = player.weapon_slots[idx]
		return w.instance_id if w != null else ""
	if destination.begins_with("quick_"):
		var qi := int(destination.trim_prefix("quick_"))
		if qi >= 0 and qi < player.quick_slots.size() and player.quick_slots[qi] != null:
			return player.quick_slots[qi].instance_id
		return ""
	var it: Item = player.get_equipped(destination)
	return it.instance_id if it != null else ""

# Lift an equipped item off a slot into the hand (empty-handed click on a filled
# slot). Reuses the unequip-to-bag path (all its side effects), then takes it into
# hand — so it needs one free bag cell; if there's none it stays equipped.
func grab_from_slot(destination: String) -> void:
	if is_holding() or player == null:
		return
	var id := _slot_item_id(destination)
	if id == "":
		return
	if destination.begins_with("quick_"):
		player.unequip_quick_slot_to_grid(int(destination.trim_prefix("quick_")), "player", 0, 0)
	else:
		player.unequip_to_grid(destination, "player", 0, 0)
	var item: Item = player.take_from_container("player", id)
	if item == null:
		return  # couldn't land in the bag — stays equipped, nothing grabbed
	held_item = item
	held_origin = "slot:" + destination
	held_origin_cell = Vector2i.ZERO
	held_origin_rotated = item.rotated
	_refresh_preview()

# Drop the held item onto an equipment/weapon/belt/quick slot (equip it). The caller
# (the slot widget) has already checked the item is valid for that slot.
func try_place_slot(destination: String) -> void:
	if held_item == null or player == null:
		return
	if player._equip_claimed_to_destination(destination, held_item):
		held_item = null
		_refresh_preview()
		refresh()
	# else: no room to displace the current occupant — keep holding.

func cancel_held() -> void:
	if held_item == null:
		return
	held_item.rotated = held_origin_rotated
	_return_held_to_origin()
	held_item = null
	_refresh_preview()
	refresh()

func _return_held_to_origin() -> void:
	if player == null:
		return
	if held_origin.begins_with("slot:"):
		if not player._equip_claimed_to_destination(held_origin.trim_prefix("slot:"), held_item):
			_drop_held_into_bag()
		return
	if player.place_or_swap_in_container(held_origin, held_item, held_origin_cell) == false:
		_drop_held_into_bag()

# Last-resort so cancel can never destroy an item: stuff it anywhere in the bag.
func _drop_held_into_bag() -> void:
	player.inventory.try_stack_or_place(held_item)
	player.persist_inventory()

func _select_stash_tab(idx: int) -> void:
	active_stash_tab = idx
	showing_materials = false
	stash_grid.visible = true
	move_all_button.visible = true
	move_all_button.text = "Move All to Stash"
	materials_grid.visible = false
	stash_grid.setup(player.stash_tabs[idx], "stash_%d" % idx, player)
	stash_tab_1.modulate = Color(1, 1, 0.6) if idx == 0 else Color(1, 1, 1)
	stash_tab_2.modulate = Color(1, 1, 0.6) if idx == 1 else Color(1, 1, 1)
	stash_tab_3.modulate = Color(1, 1, 0.6) if idx == 2 else Color(1, 1, 1)
	stash_tab_4.modulate = Color(1, 1, 0.6) if idx == 3 else Color(1, 1, 1)
	materials_tab_button.modulate = Color(1, 1, 1)
	gems_tab_button.modulate = Color(1, 1, 1)

# A Materials tab (Crystals or Gems) replaces the numbered grid + move-all with the
# fixed per-type material slots — now drag-OUT capable too. See materials_grid.gd.
func _select_materials_tab(category: String) -> void:
	showing_materials = true
	materials_category = category
	stash_grid.visible = false
	# Move All still applies here (crystals/gems bank to Materials, other items to the
	# tabs) — see _on_move_all_pressed.
	move_all_button.visible = true
	materials_grid.visible = true
	materials_grid.set_category(category)
	stash_tab_1.modulate = Color(1, 1, 1)
	stash_tab_2.modulate = Color(1, 1, 1)
	stash_tab_3.modulate = Color(1, 1, 1)
	stash_tab_4.modulate = Color(1, 1, 1)
	# Highlight whichever material tab is active.
	materials_tab_button.modulate = Color(1, 1, 0.6) if category == "crystals" else Color(1, 1, 1)
	gems_tab_button.modulate = Color(1, 1, 0.6) if category == "gems" else Color(1, 1, 1)
