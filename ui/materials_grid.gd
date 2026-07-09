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

# Hover tooltip — same name+description popup the item grids use, so a slot's
# material can be identified without memorizing the color/label. Mirrors
# inventory_grid.gd's hover handling (0.5s dwell before it appears).
const HOVER_DELAY := 0.5
var tooltip: PanelContainer
var tooltip_label: RichTextLabel
var tooltip_style: StyleBoxFlat
var hover_timer := 0.0
var hover_position := Vector2(-1, -1)

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
	var rows: int = ceil(ItemData.MATERIAL_TYPES.size() / float(COLS))
	custom_minimum_size = Vector2(COLS * CELL, rows * CELL)
	size = custom_minimum_size
	queue_redraw()

func refresh() -> void:
	if tooltip != null:
		tooltip.visible = false
	hover_timer = 0.0
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.position != hover_position:
		hover_position = event.position
		hover_timer = 0.0
		if tooltip != null:
			tooltip.visible = false

func _on_mouse_exited() -> void:
	hover_position = Vector2(-1, -1)
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
	if hover_position == Vector2(-1, -1) or tooltip.visible:
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
	if idx < 0 or idx >= ItemData.MATERIAL_TYPES.size():
		return
	var type: String = ItemData.MATERIAL_TYPES[idx]
	var item := Item.create(type, max(1, player.materials.get(type, 0)))
	tooltip_label.text = ItemData.tooltip_text(item)
	tooltip_style.border_color = ItemData.tooltip_accent_color(item)
	tooltip.position = hover_position + Vector2(20, 20)
	tooltip.visible = true

func _draw() -> void:
	if player == null:
		return
	var font := ThemeDB.fallback_font
	for i in ItemData.MATERIAL_TYPES.size():
		var type: String = ItemData.MATERIAL_TYPES[i]
		var col := i % COLS
		var row := i / COLS
		var def := ItemData.get_def(type)
		var origin := Vector2(col * CELL, row * CELL)
		draw_rect(Rect2(origin, Vector2(CELL, CELL)), GRID_LINE_COLOR, false, 2.0)
		var rect := Rect2(origin + Vector2(PAD, PAD), Vector2(CELL - PAD * 2, CELL - PAD * 2))
		draw_rect(rect, def["color"])
		draw_string(font, rect.position + Vector2(12, 48), def["icon_label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 48)
		draw_string(font, rect.position + Vector2(12, rect.size.y - 12), "x%d" % player.materials.get(type, 0), HORIZONTAL_ALIGNMENT_LEFT, -1, 36)

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("item") and data.has("origin_container") \
		and ItemData.is_material(data["item"].type)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if player != null:
		player.bank_material(data["item"], data["origin_container"])
		queue_redraw()
