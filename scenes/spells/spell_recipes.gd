extends Node
class_name SpellRecipes

const RECIPES := [
	# Fire
	{
		"sequence": [2, 1, 1, 3, 0],
		"element": "fire",
		"form": "ball",
	},
	{
		"sequence": [2, 1, 0],
		"element": "fire",
		"form": "bolt",
	},
	{
		"sequence": [2, 1, 3, 1],
		"element": "fire",
		"form": "rain",
	},
	{
		"sequence": [2, 0, 1, 2],
		"element": "fire",
		"form": "beam",
	},
	{
		"sequence": [2, 3, 3, 1],
		"element": "fire",
		"form": "burst",
	},
	{
		"sequence": [2, 0, 3, 2],
		"element": "fire",
		"form": "cone",
	},

	# Holy
	{
		"sequence": [0, 1, 1, 3, 2],
		"element": "holy",
		"form": "ball",
	},
	{
		"sequence": [0, 1, 2],
		"element": "holy",
		"form": "bolt",
	},
	{
		"sequence": [0, 1, 3, 1],
		"element": "holy",
		"form": "rain",
	},
	{
		"sequence": [0, 2, 1, 0],
		"element": "holy",
		"form": "beam",
	},
	{
		"sequence": [0, 3, 3, 1],
		"element": "holy",
		"form": "burst",
	},
	{
		"sequence": [0, 2, 3, 0],
		"element": "holy",
		"form": "cone",
	},

	# Air
	{
		"sequence": [1, 3, 0, 1, 2],
		"element": "air",
		"form": "ball",
	},
	{
		"sequence": [1, 3, 1],
		"element": "air",
		"form": "bolt",
	},
	{
		"sequence": [1, 3, 2, 1],
		"element": "air",
		"form": "rain",
	},
	{
		"sequence": [1, 2, 3, 1],
		"element": "air",
		"form": "beam",
	},
	{
		"sequence": [1, 0, 0, 3],
		"element": "air",
		"form": "burst",
	},
	{
		"sequence": [1, 2, 3, 2],
		"element": "air",
		"form": "cone",
	},
]

func get_spell_recipe_from_sequence(sequence: Array) -> Dictionary:
	for recipe in RECIPES:
		if recipe["sequence"] == sequence:
			return recipe
	return {}

func get_available_recipes(element: String, forms: Array) -> Array:
	var available: Array = []
	for recipe in RECIPES:
		if recipe["element"] != element:
			continue
		if !forms.has(recipe["form"]):
			continue
		available.append(recipe)
	return available
