extends Node
class_name SpellRecipes

func get_spell_recipe_from_sequence(sequence: Array[int]) -> Dictionary:
	match sequence:
		[2, 1, 1, 3, 4]:
			return {
				"element": "fire",
				"form": "ball",
			}
		[2, 1, 4]:
			return {
				"element": "fire",
				"form": "bolt",
			}
		[1, 3, 1]:
			return {
				"element": "air",
				"form": "bolt",
			}
		_:
			return {}
