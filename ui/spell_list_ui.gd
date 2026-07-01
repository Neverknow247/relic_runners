extends CanvasLayer

@onready var spell_list: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/SpellList
@onready var title_label: Label = $PanelContainer/MarginContainer/VBoxContainer/TitleLabel

const INPUT_NAMES := {
	1: "↑",
	2: "→",
	3: "↓",
	4: "←"
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
	title_label.text = "%s / %s" % [weapon_id.capitalize(), element.capitalize()]
	var recipes: Array = player.all_spell_recipes.get_available_recipes(element, forms)
	for recipe in recipes:
		var label := Label.new()
		label.text = "%s  -  %s" % [
			sequence_to_text(recipe["sequence"]),
			recipe["form"].capitalize()
		]
		spell_list.add_child(label)

func sequence_to_text(sequence: Array) -> String:
	var parts: Array[String] = []
	for input_num in sequence:
		parts.append(INPUT_NAMES.get(input_num, "?"))
	return " ".join(parts)
