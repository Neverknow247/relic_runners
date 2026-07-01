extends Node
class_name SpellRecipes

const RECIPES := {
	# Fire
	[2, 1, 1, 3, 0]: {
		"element": "fire",
		"form": "ball",
	},
	[2, 1, 0]: {
		"element": "fire",
		"form": "bolt",
	},
	[2, 1, 3, 1]: {
		"element": "fire",
		"form": "rain",
	},
	[2, 0, 1, 2]: {
		"element": "fire",
		"form": "beam",
	},
	[2, 3, 3, 1]: {
		"element": "fire",
		"form": "burst",
	},
	[2, 0, 3, 2]: {
		"element": "fire",
		"form": "cone",
	},

	# Holy
	[0, 1, 1, 3, 2]: {
		"element": "holy",
		"form": "ball",
	},
	[0, 1, 2]: {
		"element": "holy",
		"form": "bolt",
	},
	[0, 1, 3, 1]: {
		"element": "holy",
		"form": "rain",
	},
	[0, 2, 1, 0]: {
		"element": "holy",
		"form": "beam",
	},
	[0, 3, 3, 1]: {
		"element": "holy",
		"form": "burst",
	},
	[0, 2, 3, 0]: {
		"element": "holy",
		"form": "cone",
	},

	# Air
	[1, 3, 0, 1, 2]: {
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
	[1, 0, 0, 3]: {
		"element": "air",
		"form": "burst",
	},
	[1, 2, 3, 2]: {
		"element": "air",
		"form": "cone",
	},
}

func get_spell_recipe_from_sequence(sequence: Array) -> Dictionary:
	if RECIPES.has(sequence):
		var recipe: Dictionary = RECIPES[sequence].duplicate()
		recipe["sequence"] = sequence
		return recipe
	return {}

func get_available_recipes(element: String, forms: Array) -> Array:
	var available: Array = []
	for sequence in RECIPES.keys():
		var recipe: Dictionary = RECIPES[sequence]
		if recipe["element"] != element:
			continue
		if !forms.has(recipe["form"]):
			continue
		var recipe_with_sequence := recipe.duplicate()
		recipe_with_sequence["sequence"] = sequence
		available.append(recipe_with_sequence)
	return available
