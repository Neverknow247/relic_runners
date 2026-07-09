extends CanvasLayer

# The crafting bench panel. Rides alongside the inventory (opened by player.gd's
# open_crafting_panel) so you can see your materials. Lists every recipe in
# ItemData.CRAFTING_RECIPES with a Craft button, enabled only when you have the
# ingredients (counted across the bag + Materials tab). Rebuilt each refresh,
# same dynamic approach as workbench_ui.gd.

@onready var status_label: Label = $panel_container/margin_container/v_box_container/status_label
@onready var recipes_section: VBoxContainer = $panel_container/margin_container/v_box_container/recipes_section

var player: Node = null

func setup(target_player: Node) -> void:
	player = target_player
	status_label.text = ""
	refresh()

func refresh() -> void:
	if player == null:
		return
	_clear(recipes_section)
	for i in ItemData.CRAFTING_RECIPES.size():
		_build_recipe_row(i)

func _build_recipe_row(index: int) -> void:
	var recipe: Dictionary = ItemData.CRAFTING_RECIPES[index]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var out: Array = recipe["output"]
	var name_label := Label.new()
	name_label.custom_minimum_size = Vector2(480, 0)
	name_label.add_theme_font_size_override("font_size", 30)
	var out_name: String = ItemData.get_def(out[0]).get("display_name", out[0])
	name_label.text = out_name + ((" x%d" % out[1]) if out[1] > 1 else "")
	row.add_child(name_label)

	var inputs_label := Label.new()
	inputs_label.custom_minimum_size = Vector2(640, 0)
	inputs_label.add_theme_font_size_override("font_size", 24)
	inputs_label.text = _inputs_text(recipe)
	row.add_child(inputs_label)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(200, 80)
	btn.add_theme_font_size_override("font_size", 28)
	btn.text = "Craft"
	btn.disabled = not player.can_craft(recipe)
	if not btn.disabled:
		btn.pressed.connect(_on_craft_pressed.bind(index))
	row.add_child(btn)

	recipes_section.add_child(row)

# "2 Herbs (5) + 1 Water Flask (3)" — the (n) is how many you currently have.
func _inputs_text(recipe: Dictionary) -> String:
	var parts: Array = []
	for pair in recipe["inputs"]:
		parts.append("%d %s (%d)" % [pair[1], _ingredient_name(pair[0]), player.ingredient_available(pair[0])])
	return " + ".join(parts)

func _ingredient_name(ingredient: String) -> String:
	if ingredient == "@element_crystal":
		return "Any Element Crystal"
	return ItemData.get_def(ingredient).get("display_name", ingredient)

func _on_craft_pressed(index: int) -> void:
	if player.craft(index):
		var out: Array = ItemData.CRAFTING_RECIPES[index]["output"]
		status_label.text = "Crafted %s." % ItemData.get_def(out[0]).get("display_name", out[0])
	else:
		status_label.text = "Missing ingredients."
	refresh()

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
