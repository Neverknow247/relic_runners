extends Node
class_name SpellRecipes

const RECIPES := {
	# Fire
	[2, 1, 1, 3, 4]: {
		"element": "fire",
		"form": "ball",
	},
	[2, 1, 4]: {
		"element": "fire",
		"form": "bolt",
	},
	[2, 1, 3, 1]: {
		"element": "fire",
		"form": "rain",
	},
	[2, 4, 1, 2]: {
		"element": "fire",
		"form": "beam",
	},
	[2, 3, 3, 1]: {
		"element": "fire",
		"form": "burst",
	},
	[2, 4, 3, 2]: {
		"element": "fire",
		"form": "cone",
	},

	# Holy
	[4, 1, 1, 3, 2]: {
		"element": "holy",
		"form": "ball",
	},
	[4, 1, 2]: {
		"element": "holy",
		"form": "bolt",
	},
	[4, 1, 3, 1]: {
		"element": "holy",
		"form": "rain",
	},
	[4, 2, 1, 4]: {
		"element": "holy",
		"form": "beam",
	},
	[4, 3, 3, 1]: {
		"element": "holy",
		"form": "burst",
	},
	[4, 2, 3, 4]: {
		"element": "holy",
		"form": "cone",
	},

	# Air
	[1, 3, 4, 1, 2]: {
		"element": "air",
		"form": "ball",
	},
	[1, 3, 1]: {
		"element": "air",
		"form": "bolt",
	},
	[1, 3, 2, 1]: {
		"element": "air",
		"form": "rain",
	},
	[1, 2, 3, 1]: {
		"element": "air",
		"form": "beam",
	},
	[1, 4, 4, 3]: {
		"element": "air",
		"form": "burst",
	},
	[1, 2, 3, 2]: {
		"element": "air",
		"form": "cone",
	},
}

func get_spell_recipe_from_sequence(sequence: Array[int]) -> Dictionary:
	return RECIPES.get(sequence, {})
