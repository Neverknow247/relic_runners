extends CanvasLayer

# The weapon workbench panel. Rides alongside the inventory (opened together
# by player.gd's open_workbench_panel) so the player can see their crystals /
# Form Stones while modifying a weapon. Two operations, both routed through
# player.gd helpers that own persistence + refresh:
#   - swap the selected weapon's element by consuming an element crystal
#   - attach/detach Form Stones (limited to what the weapon type can hold)
# Content is rebuilt dynamically each refresh(), same approach as
# spell_list_ui.gd, since it depends entirely on the selected weapon's live
# element/forms and what's currently in the backpack.

@onready var title_label: Label = $panel_container/margin_container/v_box_container/title_label
@onready var weapon_row: HBoxContainer = $panel_container/margin_container/v_box_container/weapon_row
@onready var status_label: Label = $panel_container/margin_container/v_box_container/status_label
@onready var element_section: VBoxContainer = $panel_container/margin_container/v_box_container/element_section
@onready var forms_section: VBoxContainer = $panel_container/margin_container/v_box_container/forms_section

const ELEMENT_CHOICES := ["fire", "holy", "air"]

var player: Node = null
# Which weapon_slots index is being edited (0/1). Follows the player's active
# slot on open, but the player can click the Hand/Holster buttons to retarget.
var selected_slot: int = 0

func setup(target_player: Node) -> void:
	player = target_player
	selected_slot = _default_slot()
	status_label.text = ""
	refresh()

# Prefer the active (hand) slot if it holds a weapon, else whichever slot does.
func _default_slot() -> int:
	if player == null:
		return 0
	if player.weapon_slots[player.active_slot] != null:
		return player.active_slot
	var other: int = 1 - player.active_slot
	if player.weapon_slots[other] != null:
		return other
	return player.active_slot

func refresh() -> void:
	if player == null:
		return
	# A weapon in the selected slot could have been dropped/swapped while the
	# panel was open — fall back to a slot that still has one.
	if player.weapon_slots[selected_slot] == null:
		selected_slot = _default_slot()

	_rebuild_weapon_row()

	var weapon: Weapon = player.weapon_slots[selected_slot]
	_clear(element_section)
	_clear(forms_section)
	if weapon == null:
		title_label.text = "Weapon Workbench"
		_add_header(element_section, "No weapon in either slot")
		return
	title_label.text = "Weapon Workbench — %s" % weapon.type.capitalize()
	_build_element_section(weapon)
	_build_forms_section(weapon)

func _rebuild_weapon_row() -> void:
	_clear(weapon_row)
	# Hand first, then Holster — labels reflect which is active, indices are
	# the real weapon_slots positions so selection maps straight through.
	var hand_slot: int = player.active_slot
	var holster_slot: int = 1 - player.active_slot
	_add_weapon_button("Hand", hand_slot)
	_add_weapon_button("Holster", holster_slot)

func _add_weapon_button(label: String, slot: int) -> void:
	var weapon: Weapon = player.weapon_slots[slot]
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(360, 110)
	btn.add_theme_font_size_override("font_size", 32)
	if weapon != null:
		btn.text = "%s\n%s / %s" % [label, weapon.type.capitalize(), weapon.element.capitalize()]
		btn.disabled = false
		btn.pressed.connect(_on_slot_pressed.bind(slot))
	else:
		btn.text = "%s\n(empty)" % label
		btn.disabled = true
	# Highlight the slot currently being edited.
	btn.modulate = Color(1, 1, 0.6) if slot == selected_slot else Color(1, 1, 1)
	weapon_row.add_child(btn)

func _build_element_section(weapon: Weapon) -> void:
	_add_header(element_section, "Element: %s" % weapon.element.capitalize())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	for element: String in ELEMENT_CHOICES:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(300, 110)
		btn.add_theme_font_size_override("font_size", 32)
		var crystal: String = "crystal_" + element
		var crystal_count: int = _count_of(crystal)
		var has_crystal: bool = crystal_count > 0
		var is_current: bool = weapon.element == element
		btn.text = "%s\n%s" % [element.capitalize(), "current" if is_current else ("have x%d" % crystal_count if has_crystal else "need crystal")]
		btn.disabled = is_current or !has_crystal
		# Tint toward the element's own color so the choice reads like the
		# fire/holy/air it'll become (same colors used on projectiles/enemies).
		var col: Color = SpellData.ELEMENTS.get(element, SpellData.ELEMENTS["default"])["color"]
		btn.modulate = col if !btn.disabled else col.darkened(0.5)
		if !btn.disabled:
			btn.pressed.connect(_on_element_pressed.bind(element))
		row.add_child(btn)
	element_section.add_child(row)

func _build_forms_section(weapon: Weapon) -> void:
	_add_header(forms_section, "Forms (attach a stone to add its spell)")
	for form: String in weapon.capable_forms():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)

		var name_label := Label.new()
		name_label.custom_minimum_size = Vector2(320, 0)
		name_label.add_theme_font_size_override("font_size", 32)
		name_label.text = form.capitalize()
		row.add_child(name_label)

		var attached: bool = weapon.forms.has(form)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(320, 90)
		btn.add_theme_font_size_override("font_size", 30)
		if attached:
			btn.text = "Detach"
			btn.pressed.connect(_on_detach_pressed.bind(form))
		else:
			var stone_count := _count_of(ItemData.stone_for_form(form))
			var has_stone: bool = stone_count > 0
			btn.text = ("Attach (x%d)" % stone_count) if has_stone else "Attach (no stone)"
			btn.disabled = !has_stone
			if has_stone:
				btn.pressed.connect(_on_attach_pressed.bind(form))
		row.add_child(btn)
		forms_section.add_child(row)

func _on_slot_pressed(slot: int) -> void:
	selected_slot = slot
	status_label.text = ""
	refresh()

func _on_element_pressed(element: String) -> void:
	if player.workbench_set_element(selected_slot, element):
		status_label.text = "Element changed to %s." % element.capitalize()
	else:
		status_label.text = "Couldn't change element."
	# player.workbench_* already calls refresh() on success; refresh here too
	# so a no-op still redraws (and clears any stale disabled states).
	refresh()

func _on_attach_pressed(form: String) -> void:
	if player.workbench_attach_form(selected_slot, form):
		status_label.text = "%s form attached." % form.capitalize()
	else:
		status_label.text = "Couldn't attach %s." % form.capitalize()
	refresh()

func _on_detach_pressed(form: String) -> void:
	if player.workbench_detach_form(selected_slot, form):
		status_label.text = "%s form detached — stone banked to Materials." % form.capitalize()
	else:
		status_label.text = "Couldn't detach %s." % form.capitalize()
	refresh()

# Total available of a material: banked in the Materials tab (consumed first)
# plus any loose stacks still in the backpack.
func _count_of(type: String) -> int:
	var total: int = player.material_count(type)
	for entry in player.inventory.placements:
		var item: Item = entry["item"]
		if item.type == type:
			total += item.quantity
	return total

func _has_item(type: String) -> bool:
	# Banked materials count too (workbench consumes those first).
	if player.material_count(type) > 0:
		return true
	for entry in player.inventory.placements:
		var item: Item = entry["item"]
		if item.type == type and item.quantity > 0:
			return true
	return false

func _add_header(section: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 40)
	label.text = text
	section.add_child(label)

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
