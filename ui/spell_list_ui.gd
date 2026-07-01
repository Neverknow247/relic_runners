extends CanvasLayer

@onready var title_label: Label = $panel_container/margin_container/v_box_container/title_label
@onready var spell_list: VBoxContainer = $panel_container/margin_container/v_box_container/spell_list

const INPUT_NAMES := {
	0: preload("res://assets/art/ui/keyboard_arrow_left.png"),
	1: preload("res://assets/art/ui/keyboard_arrow_up.png"),
	2: preload("res://assets/art/ui/keyboard_arrow_right.png"),
	3: preload("res://assets/art/ui/keyboard_arrow_down.png"),
}

const PRESSED_INPUT_NAMES := {
	0: preload("res://assets/art/ui/keyboard_arrow_left_outline.png"),
	1: preload("res://assets/art/ui/keyboard_arrow_up_outline.png"),
	2: preload("res://assets/art/ui/keyboard_arrow_right_outline.png"),
	3: preload("res://assets/art/ui/keyboard_arrow_down_outline.png"),
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
	print(weapon_id.capitalize())
	title_label.text = "%s / %s" % [weapon_id.capitalize(), element.capitalize()]
	#title_label.add_theme_font_size_override("font_size", 64)
	var recipes: Array = player.all_spell_recipes.get_available_recipes(element, forms)
	for recipe in recipes:
		var label := Label.new()
		label.text = "%s  :  %s" % [
			recipe["form"].capitalize(),
			sequence_to_text(recipe["sequence"])
		]
		label.add_theme_font_size_override("font_size", 64)
		spell_list.add_child(label)

func sequence_to_text(sequence: Array) -> String:
	var parts: Array[String] = []
	for input_num in sequence:
		parts.append(INPUT_NAMES.get(input_num, "?"))
	return " ".join(parts)
