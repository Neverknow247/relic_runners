extends CanvasLayer

# Hub vendor panel: SELL (left) lists every bag stack the vendor will buy with its
# price; BUY (right) is the fixed ItemData.VENDOR_STOCK. Gold is paid/received
# through player.vendor_sell / vendor_buy (bank -> bag -> stash, like crafting).
# Built in code; the local player owns one, the vendor station opens it.

var _panel: PanelContainer
var _gold_label: Label
var _sell_list: VBoxContainer
var _buy_list: VBoxContainer
var _player = null

func _ready() -> void:
	layer = 40
	_player = get_parent()
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -1500
	_panel.offset_right = 1500
	_panel.offset_top = -900
	_panel.offset_bottom = 900
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.05, 0.95)
	style.border_color = Color(0.95, 0.8, 0.35)
	style.set_border_width_all(6)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(50)
	_panel.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 24)
	_panel.add_child(col)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "Vendor"
	title.add_theme_font_size_override("font_size", 84)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 64)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	head.add_child(_gold_label)
	col.add_child(head)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 60)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(columns)
	_sell_list = _make_column(columns, "Sell (from your bag)")
	_buy_list = _make_column(columns, "Buy")
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 110)
	close.add_theme_font_size_override("font_size", 52)
	close.pressed.connect(close_panel)
	col.add_child(close)
	add_child(_panel)
	_panel.visible = false

func _make_column(parent: Control, heading: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := Label.new()
	h.text = heading
	h.add_theme_font_size_override("font_size", 60)
	box.add_child(h)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 1100)
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	parent.add_child(box)
	return list

func is_open() -> bool:
	return _panel.visible

func open_panel() -> void:
	_refresh()
	_panel.visible = true

func close_panel() -> void:
	_panel.visible = false

func _row(list: VBoxContainer, text: String, button_text: String, enabled: bool, on_press: Callable) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 48)
	row.add_child(l)
	var b := Button.new()
	b.text = button_text
	b.custom_minimum_size = Vector2(300, 90)
	b.add_theme_font_size_override("font_size", 44)
	b.disabled = !enabled
	b.pressed.connect(on_press)
	row.add_child(b)
	list.add_child(row)

func _refresh() -> void:
	if _player == null:
		return
	_gold_label.text = "Gold: %d" % _player.gold_available()
	for c in _sell_list.get_children():
		c.queue_free()
	for c in _buy_list.get_children():
		c.queue_free()
	var any_sellable := false
	for entry in _player.inventory.placements:
		var item: Item = entry["item"]
		var price := ItemData.vendor_sell_price(item)
		if price <= 0:
			continue
		any_sellable = true
		var label := "%s x%d" % [ItemData.get_def(item.type).get("display_name", item.type), item.quantity]
		_row(_sell_list, label, "Sell %dg" % price, true, _on_sell.bind(item.instance_id))
	if !any_sellable:
		var none := Label.new()
		none.text = "(nothing in your bag the vendor wants)"
		none.add_theme_font_size_override("font_size", 40)
		_sell_list.add_child(none)
	var gold: int = _player.gold_available()
	for i in ItemData.VENDOR_STOCK.size():
		var stock: Array = ItemData.VENDOR_STOCK[i]
		var label := "%s x%d" % [ItemData.get_def(stock[0]).get("display_name", stock[0]), stock[1]]
		_row(_buy_list, label, "Buy %dg" % stock[2], gold >= stock[2], _on_buy.bind(i))

func _on_sell(instance_id: String) -> void:
	if _player.vendor_sell(instance_id) > 0:
		Sounds.play_sfx("loot", null, -2.0)
	_refresh()

func _on_buy(index: int) -> void:
	if _player.vendor_buy(index):
		Sounds.play_sfx("armed", null, -4.0)
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if _panel.visible and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()
