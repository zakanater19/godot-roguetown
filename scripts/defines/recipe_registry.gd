# res://scripts/defines/recipe_registry.gd
# Autoload singleton. Scans res://recipes/ on startup and caches every RecipeData
# resource by its recipe_id. Both the crafting UI and the server validation read
# from here — so adding a new recipe only ever requires one .tres file.
extends Node

## All loaded recipes keyed by recipe_id.
var _recipes: Dictionary = {}

func _ready() -> void:
	_load_all_recipes()

func _load_all_recipes(force_replace: bool = false) -> void:
	var cache_mode := ResourceLoader.CACHE_MODE_REPLACE if force_replace else ResourceLoader.CACHE_MODE_REUSE
	_recipes.clear()
	var dir := DirAccess.open("res://recipes/")
	if dir == null:
		push_error("RecipeRegistry: res://recipes/ directory not found.")
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		# Strip .remap suffix if running in an exported build
		var clean_name: String = file_name.replace(".remap", "")
		
		if not dir.current_is_dir() and clean_name.ends_with(".tres"):
			var path: String = "res://recipes/" + clean_name
			var res := ResourceLoader.load(path, "", cache_mode)
			if res is RecipeData:
				if res.recipe_id == "":
					push_warning("RecipeRegistry: recipe at '%s' has no recipe_id, skipping." % path)
				elif _recipes.has(res.recipe_id):
					push_warning("RecipeRegistry: duplicate recipe_id '%s' in '%s', skipping." % [res.recipe_id, path])
				else:
					_recipes[res.recipe_id] = res
		file_name = dir.get_next()
	dir.list_dir_end()

## Re-scan res://recipes/ after a PCK patch has been mounted.
## Uses CACHE_MODE_REPLACE so the ResourceLoader discards pre-patch cached
## objects and reads fresh data from the now-updated virtual filesystem.
func reload() -> void:
	_load_all_recipes(true)

## Overwrite (or insert) a recipe definition received from the server.
## Called by GameVersion.apply_resource_diff on version-mismatched clients.
func patch_recipe(recipe: RecipeData) -> void:
	_recipes[recipe.recipe_id] = recipe

## Returns the RecipeData for recipe_id, or null if not found.
func get_recipe(recipe_id: String) -> RecipeData:
	return _recipes.get(recipe_id, null)

## Returns all loaded RecipeData resources as an Array.
func get_all_recipes() -> Array:
	return _recipes.values()

## Returns all recipes where the player meets the skill requirements.
## skills_dict: the player's { skill_name: level } dictionary.
func get_available_recipes(skills_dict: Dictionary) -> Array:
	var result: Array =[]
	for recipe in _recipes.values():
		var ok := true
		for skill_name in recipe.skill_requirements:
			if skills_dict.get(skill_name, 0) < recipe.skill_requirements[skill_name]:
				ok = false
				break
		if ok:
			result.append(recipe)
	return result