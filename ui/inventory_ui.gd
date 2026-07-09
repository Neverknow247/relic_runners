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
# The stash column shows either a numbered tab's grid or the Materials tab.
var showing_materials := false

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
	materials_tab_button.pressed.connect(_select_materials_tab)
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

# The Materials tab replaces the numbered grid + move-all with the fixed
# per-type materials slots (deposit-only). See materials_grid.gd.
func _select_materials_tab() -> void:
	showing_materials = true
	stash_grid.visible = false
	# Move All still applies here (crystals/stones bank to Materials, other items
	# to the tabs) — see _on_move_all_pressed.
	move_all_button.visible = true
	materials_grid.visible = true
	materials_grid.refresh()
	stash_tab_1.modulate = Color(1, 1, 1)
	stash_tab_2.modulate = Color(1, 1, 1)
	stash_tab_3.modulate = Color(1, 1, 1)
	stash_tab_4.modulate = Color(1, 1, 1)
	materials_tab_button.modulate = Color(1, 1, 0.6)
