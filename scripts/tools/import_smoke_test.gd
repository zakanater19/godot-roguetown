class_name ImportSmokeTest
extends RefCounted

const PROJECT_ROOT := "res://"
const ITEMS_DIR := "res://items"
const RECIPES_DIR := "res://recipes"
const MATERIALS_DIR := "res://materials"

var _errors: Array[String] = []
var _warnings: Array[String] = []
var _validated_script_paths: Dictionary = {}
var _validated_scene_paths: Dictionary = {}
var _validated_texture_paths: Dictionary = {}

func run() -> Dictionary:
	var item_types := {}
	var material_ids := {}

	_validate_autoloads()
	_validate_project_scripts()
	_validate_project_scenes()
	_validate_items(item_types)
	_validate_materials(material_ids)
	_validate_recipes(item_types)

	return {
		"errors": _errors.duplicate(),
		"warnings": _warnings.duplicate(),
	}

func _validate_items(item_types: Dictionary) -> void:
	for path in _collect_paths(ITEMS_DIR, ".tres"):
		var item := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as ItemData
		if item == null:
			_fail("%s: failed to load as ItemData." % path)
			continue
		if item.item_type.is_empty():
			_fail("%s: item_type is empty." % path)
		elif item_types.has(item.item_type):
			_fail("%s: duplicate item_type '%s' also used by %s." % [path, item.item_type, item_types[item.item_type]["path"]])
		else:
			item_types[item.item_type] = {
				"path": path,
				"scene_path": item.scene_path,
			}

		if item.scene_path.is_empty():
			_fail("%s: scene_path is empty." % path)
		else:
			_validate_packed_scene(item.scene_path, "%s scene_path" % path)

		if not item.hud_texture_path.is_empty():
			_validate_texture(item.hud_texture_path, "%s hud_texture_path" % path)
		if not item.mob_texture_path.is_empty():
			_validate_texture(item.mob_texture_path, "%s mob_texture_path" % path)

func _validate_materials(material_ids: Dictionary) -> void:
	for path in _collect_paths(MATERIALS_DIR, ".tres"):
		var material := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as MaterialData
		if material == null:
			_fail("%s: failed to load as MaterialData." % path)
			continue
		if material.material_id.is_empty():
			_fail("%s: material_id is empty." % path)
		elif material_ids.has(material.material_id):
			_fail("%s: duplicate material_id '%s' also used by %s." % [path, material.material_id, material_ids[material.material_id]])
		else:
			material_ids[material.material_id] = path

		for tool_type in material.tool_efficiencies.keys():
			var value: Variant = material.tool_efficiencies[tool_type]
			if not (value is int or value is float):
				_fail("%s: tool_efficiencies['%s'] must be numeric." % [path, tool_type])

func _validate_autoloads() -> void:
	for property_info in ProjectSettings.get_property_list():
		var property_name := String(property_info.get("name", ""))
		if not property_name.begins_with("autoload/"):
			continue
		var autoload_value := String(ProjectSettings.get_setting(property_name, ""))
		var resource_path := autoload_value.trim_prefix("*")
		if resource_path.is_empty():
			_fail("%s: autoload path is empty." % property_name)
			continue
		if resource_path.ends_with(".gd"):
			_validate_script(resource_path, "%s autoload" % property_name)
		elif resource_path.ends_with(".tscn"):
			_validate_packed_scene(resource_path, "%s autoload" % property_name)
		else:
			_fail("%s: unsupported autoload path %s." % [property_name, resource_path])

func _validate_project_scripts() -> void:
	for path in _collect_paths(PROJECT_ROOT, ".gd"):
		_validate_script(path, "project script")

func _validate_project_scenes() -> void:
	for path in _collect_paths(PROJECT_ROOT, ".tscn"):
		_validate_packed_scene(path, "project scene")

func _validate_recipes(item_types: Dictionary) -> void:
	var recipe_ids := {}
	for path in _collect_paths(RECIPES_DIR, ".tres"):
		var recipe := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as RecipeData
		if recipe == null:
			_fail("%s: failed to load as RecipeData." % path)
			continue
		if recipe.recipe_id.is_empty():
			_fail("%s: recipe_id is empty." % path)
		elif recipe_ids.has(recipe.recipe_id):
			_fail("%s: duplicate recipe_id '%s' also used by %s." % [path, recipe.recipe_id, recipe_ids[recipe.recipe_id]])
		else:
			recipe_ids[recipe.recipe_id] = path

		var req_item_type := recipe.get_required_item_type()
		if req_item_type.is_empty():
			_fail("%s: req_item_data is missing or has an empty item_type." % path)
		elif not item_types.has(req_item_type):
			_fail("%s: required item '%s' was not found in %s." % [path, req_item_type, ITEMS_DIR])

		match recipe.result_type:
			Defs.RECIPE_RESULT_ITEM:
				var result_item_type := recipe.get_result_item_type()
				if result_item_type.is_empty():
					_fail("%s: result_item_data is missing or has an empty item_type." % path)
				elif not item_types.has(result_item_type):
					_fail("%s: result item '%s' was not found in %s." % [path, result_item_type, ITEMS_DIR])
				else:
					var scene_path := str(item_types[result_item_type].get("scene_path", ""))
					if scene_path.is_empty():
						_fail("%s: could not resolve scene for result item '%s'." % [path, result_item_type])
					else:
						_validate_packed_scene(scene_path, "%s result item" % path)
			Defs.RECIPE_RESULT_TILE:
				pass
			_:
				_fail("%s: unsupported result_type '%s'." % [path, recipe.result_type])

func _validate_packed_scene(scene_path: String, context: String) -> void:
	if _validated_scene_paths.has(scene_path):
		return
	_validated_scene_paths[scene_path] = true
	if not ResourceLoader.exists(scene_path):
		_fail("%s: missing scene %s." % [context, scene_path])
		return
	var scene := ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if scene == null:
		_fail("%s: failed to load scene %s." % [context, scene_path])
		return
	var instance := scene.instantiate()
	if instance == null:
		_fail("%s: failed to instantiate scene %s." % [context, scene_path])
		return
	instance.free()

func _validate_texture(texture_path: String, context: String) -> void:
	if _validated_texture_paths.has(texture_path):
		return
	_validated_texture_paths[texture_path] = true
	if not ResourceLoader.exists(texture_path):
		_fail("%s: missing texture %s." % [context, texture_path])
		return
	var texture := ResourceLoader.load(texture_path, "", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D
	if texture == null:
		_fail("%s: failed to load texture %s." % [context, texture_path])

func _validate_script(script_path: String, context: String) -> void:
	if _validated_script_paths.has(script_path):
		return
	_validated_script_paths[script_path] = true
	if not ResourceLoader.exists(script_path):
		_fail("%s: missing script %s." % [context, script_path])
		return
	var script := ResourceLoader.load(script_path, "", ResourceLoader.CACHE_MODE_REPLACE) as Script
	if script == null:
		_fail("%s: failed to load script %s." % [context, script_path])

func _collect_paths(root_path: String, extension: String) -> Array[String]:
	var paths: Array[String] = []
	_collect_paths_recursive(root_path, extension, paths)
	paths.sort()
	return paths

func _collect_paths_recursive(root_path: String, extension: String, out_paths: Array[String]) -> void:
	var dir := DirAccess.open(root_path)
	if dir == null:
		_fail("Could not open directory %s." % root_path)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name in [".", ".."]:
			name = dir.get_next()
			continue
		var child_path := "%s/%s" % [root_path, name]
		if dir.current_is_dir():
			_collect_paths_recursive(child_path, extension, out_paths)
		elif name.ends_with(extension) or name.ends_with("%s.remap" % extension):
			out_paths.append(child_path.replace(".remap", ""))
		name = dir.get_next()
	dir.list_dir_end()

func _fail(message: String) -> void:
	_errors.append(message)
