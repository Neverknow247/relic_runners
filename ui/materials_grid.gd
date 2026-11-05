extends Control
class_name MaterialsGrid

# The stash's Materials tab: a fixed grid of per-type slots (element crystals +
# form stones) showing a running, infinitely-stacking count. Deposit-only — drag
# a crystal/stone here from any own-storage grid to bank it (player.bank_material).
# Same placeholder color+label draw style as inventory_grid.gd; no footprints or
# placement since materials are just per-type counts.

const CELL := 160.0
const PAD := 6.0
const COLS := 3
const GRID_LINE_COLOR := Color(1, 1, 1, 0.25)

var player = null
# Which slice of the materials bank this tab shows: "crystals" (element crystals)
# or "gems" (form stones). Set by inventory_ui when its Crystals/Gems tab is picked.
var category := "crystals"

# The material types this tab shows/handles (filtered by category).
func _types() -> Array:
	return ItemData.material_types_in(category)

# Switch which slice is shown (Crystals vs Gems) and resize the grid to fit it.
func set_category(new_category: String) -> void:
	category = new_category
	_resize_to_types()
	refresh()

func _resize_to_types() -> void:
	var rows: int = ceil(_types().size() / float(COLS))
	custom_minimum_size = Vector2(COLS * CELL, rows * CELL)
	size = custom_minimum_size

# Hover tooltip — same name+description popup the item grids use, so a slot's
# material can be identified without memorizing the color/label. Mirrors
# inventory_grid.gd's hover handling: the dwell only restarts when the cursor moves
# to a DIFFERENT slot (tracked by hovered_type), so it doesn't flicker/feel twitchy.
const HOVER_DELAY := 0.05
var tooltip: PanelContainer
var tooltip_label: RichTextLabel
var tooltip_style: StyleBoxFlat
var hover_timer := 0.0
var hover_position := Vector2(-1, -1)
# The material-slot type the cursor is currently over ("" = none). Same role as
# inventory_grid's hovered_instance_id.
var hovered_type := ""

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
	mouse_exited.connect(_on_mouse_exited)

func setup(target_player) -> void:
	player = target_player
	_resize_to_types()
	queue_redraw()

func refresh() -> void:
	if tooltip != null:
		tooltip.visible = false
	hovered_type = ""
	hover_timer = 0.0
	queue_redraw()

# The material type under a pixel, or "" if it's not over a filled slot.
func _type_at(pos: Vector2) -> String:
	var col := int(pos.x / CELL)
	var row := int(pos.y / CELL)
	if col < 0 or col >= COLS:
		return ""
	var idx := row * COLS + col
	var types := _types()
	if idx < 0 or idx >= types.size():
		return ""
	return types[idx]

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hover_position = event.position
		var new_type := _type_at(event.position)
		if new_type != hovered_type:
			# Onto a different slot (or off the slots) — restart the dwell; same-slot
			# motion is left alone so a shown tooltip stays put.
			hovered_type = new_type
			hover_timer = 0.0
			if tooltip != null:
				tooltip.visible = false

func _on_mouse_exited() -> void:
	hover_position = Vector2(-1, -1)
	hovered_type = ""
	hover_timer = 0.0
	if tooltip != null:
		tooltip.visible = false

func _process(delta: float) -> void:
	if player == null or tooltip == null:
		return
	# Shares space with the numbered stash grid — don't dwell/pop a tooltip while
	# this tab is the hidden one.
	if not is_visible_in_tree():
		return
	if hovered_type == "" or tooltip.visible:
		return
	hover_timer += delta
	if hover_timer >= HOVER_DELAY:
		_try_show_tooltip()

# Map the hovered pixel back to a material slot and show its name/description.
func _try_show_tooltip() -> void:
	var col := int(hover_position.x / CELL)
	var row := int(hover_position.y / CELL)
	if col < 0 or col >= COLS:
		return
	var idx := row * COLS + col
	var types := _types()
	if idx < 0 or idx >= types.size():
		return
	var type: String = types[idx]
	var item := Item.create(type, max(1, player.materials.get(type, 0)))
	tooltip_label.text = ItemData.tooltip_text(item)
	tooltip_style.border_color = ItemData.tooltip_accent_color(item)
	tooltip.position = hover_position + Vector2(20, 20)
	tooltip.visible = true

func _draw() -> void:
	if player == null:
		return
	var font := ThemeDB.fallback_font
	var types := _types()
	for i in types.size():
		var type: String = types[i]
		var col := i % COLS
		@warning_ignore("integer_division")  # intentional: grid row index
		var row := i / COLS
		var def := ItemData.get_def(type)
		var origin := Vector2(col * CELL, row * CELL)
		draw_rect(Rect2(origin, Vector2(CELL, CELL)), GRID_LINE_COLOR, false, 2.0)
		var rect := Rect2(origin + Vector2(PAD, PAD), Vector2(CELL - PAD * 2, CELL - PAD * 2))
		draw_rect(rect, def["color"])
		draw_string(font, rect.position + Vector2(12, 48), def["icon_label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 48)
		draw_string(font, rect.position + Vector2(12, rect.size.y - 12), "x%d" % player.materials.get(type, 0), HORIZONTAL_ALIGNMENT_LEFT, -1, 36)

# Drag a material OUT of the bank. The bank stores per-type COUNTS, not placed
# Items, so this hands over a freshly-made stack of the whole count; the actual
# decrement happens only if the drop lands somewhere valid (player.withdraw_
# material_to_grid), so a cancelled/failed drag costs nothing.
func _get_drag_data(at_position: Vector2) -> Variant:
	if player == null:
		return null
	var col := int(at_position.x / CELL)
	var row := int(at_position.y / CELL)
	if col < 0 or col >= COLS:
		return null
	var idx := row * COLS + col
	var types := _types()
	if idx < 0 or idx >= types.size():
		return null
	var type: String = types[idx]
	var count: int = player.materials.get(type, 0)
	if count <= 0:
		return null
	if tooltip != null:
		tooltip.visible = false
	hovered_type = ""
	hover_timer = 0.0
	var def := ItemData.get_def(type)
	var footprint := ItemData.get_footprint(type)
	var preview := ColorRect.new()
	preview.color = def["color"]
	preview.custom_minimum_size = Vector2(footprint.x * CELL, footprint.y * CELL)
	preview.modulate.a = 0.85
	set_drag_preview(preview)
	return {"item": Item.create(type, count), "origin_container": "materials"}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("item") and data.has("origin_container") \
		and ItemData.is_material(data["item"].type)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if player != null:
		player.bank_material(data["item"], data["origin_container"])
		queue_redraw()
