extends Node
class_name SpellRecipes

# Cast recipes are GENERATED, not hand-authored: each element gets a unique 2-input
# prefix, each form a prefix-free suffix, and a recipe's sequence is
# ELEMENT_PREFIX[element] + FORM_SUFFIX[form] for every element x form. That keeps
# every sequence globally unique AND prefix-free within an element (all of an
# element's recipes share its 2-input prefix, then diverge by a prefix-free suffix —
# compatible with player.gd's has_relevant_spell_prefix, and get_available_recipes
# already filters to the equipped weapon's element + attached forms). The spell list
# UI displays the sequences, so there's nothing to memorize; adding forms or elements
# is just extending these two tables. Directional inputs are 0-3.
const ELEMENT_PREFIX := {
	"fire": [0, 0],
	"lightning": [0, 1],
	"ice": [0, 2],
	"wind": [0, 3],
	"nature": [1, 0],
	"water": [1, 1],
	"earth": [1, 2],
}
const FORM_SUFFIX := {
	"bolt": [0],
	"ball": [1, 0],
	"rain": [1, 1],
	"beam": [2],
	"burst": [3, 0],
	"cone": [3, 1],
	"wave": [1, 2],
}
# Reserved for the next 7 forms (keep the suffix set prefix-free; [0] and [2] are
# leaves, so everything new starts with 1 or 3): [1,3] as a leaf, and [3,2] / [3,3]
# as branches ([3,2,0..3], [3,3,0..3]) — 9 slots, longest full code 5 taps
# (player.gd's record_attack_direction clears past 6).

static var RECIPES: Array = []

static func _static_init() -> void:
	if OS.is_debug_build():
		var suffixes: Array = FORM_SUFFIX.values()
		for a in suffixes:
			for b in suffixes:
				if a != b and (b as Array).size() >= (a as Array).size() and (b as Array).slice(0, (a as Array).size()) == a:
					push_error("SpellRecipes: FORM_SUFFIX %s is a prefix of %s" % [a, b])
	for element in ELEMENT_PREFIX:
		for form in FORM_SUFFIX:
			RECIPES.append({
				"sequence": (ELEMENT_PREFIX[element] as Array) + (FORM_SUFFIX[form] as Array),
				"element": element,
				"form": form,
			})

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
