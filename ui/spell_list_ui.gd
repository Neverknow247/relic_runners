extends CanvasLayer

@onready var title_label: Label = $panel_container/margin_container/v_box_container/title_label
@onready var spell_list: VBoxContainer = $panel_container/margin_container/v_box_container/spell_list

const INPUT_TEXTURES := {
	0: {
		"normal": preload("res://assets/art/ui/keyboard_arrow_left.png"),
		"active": preload("res://assets/art/ui/keyboard_arrow_left_outline.png")
	},
	1: {
		"normal": preload("res://assets/art/ui/keyboard_arrow_up.png"),
		"active": preload("res://assets/art/ui/keyboard_arrow_up_outline.png")
	},
	2: {
		"normal": preload("res://assets/art/ui/keyboard_arrow_right.png"),
		"active": preload("res://assets/art/ui/keyboard_arrow_right_outline.png")
	},
	3: {
		"normal": preload("res://assets/art/ui/keyboard_arrow_down.png"),
		"active": preload("res://assets/art/ui/keyboard_arrow_down_outline.png")
	}
}

var player: Node = null

func setup(target_player: Node) -> void:
	player = target_player
	refresh()

func refresh() -> void:
	if player == null:
		return

	for child in spell_list.get_children():
		child.queue_free()

	var weapon_id: String = player.equipped_weapon_data["id"]
	var element: String = player.equipped_weapon_data["element"]
	var forms: Array = player.equipped_weapon_data["forms"]
	var current_sequence: Array = player.spell_input_sequence

	title_label.text = "%s / %s" % [weapon_id.capitalize(), element.capitalize()]
	title_label.add_theme_font_size_override("font_size", 64)

	var recipes: Array = player.all_spell_recipes.get_available_recipes(element, forms)

	for recipe in recipes:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var recipe_sequence: Array = recipe["sequence"]
		var is_matching_prefix := sequence_starts_with(recipe_sequence, current_sequence)

		for i in range(recipe_sequence.size()):
			var input_num: int = recipe_sequence[i]
			var icon := TextureRect.new()
			icon.custom_minimum_size = Vector2(64, 64)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var should_be_active := is_matching_prefix and i < current_sequence.size()
			var texture_set: Dictionary = INPUT_TEXTURES[input_num]
			if should_be_active:
				icon.texture = texture_set["active"]
			else:
				icon.texture = texture_set["normal"]
			row.add_child(icon)

		var label := Label.new()
		label.text = " - %s" % recipe["form"].capitalize()
		label.add_theme_font_size_override("font_size", 64)
		row.add_child(label)

		spell_list.add_child(row)

func sequence_starts_with(full_sequence: Array, partial_sequence: Array) -> bool:
	if partial_sequence.size() > full_sequence.size():
		return false

	for i in partial_sequence.size():
		if full_sequence[i] != partial_sequence[i]:
			return false

	return true
