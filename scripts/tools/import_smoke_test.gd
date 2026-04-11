class_name ImportSmokeTest
extends RefCounted

const PROJECT_ROOT := "res://"
const ITEMS_DIR := "res://items"
const RECIPES_DIR := "res://recipes"
const MATERIALS_DIR := "res://materials"

# Scenes registered with MultiplayerSpawner.add_spawnable_scene() in Host.gd.
const NET_SPAWNABLE_SCENES: Array[String] = [
	"res://scenes/player.tscn",
	"res://core/ghost.tscn",
]

# Scenes that must contain a MultiplayerSynchronizer with a valid replication_config.
# Each configured property NodePath must resolve to a real property on the target node.
const NET_SYNCED_SCENES: Array[String] = [
	"res://scenes/player.tscn",
	"res://npcs/spider.tscn",
]

var _errors: Array[String] = []
var _warnings: Array[String] = []
var _validated_script_paths: Dictionary = {}
var _validated_scene_paths: Dictionary = {}
var _validated_texture_paths: Dictionary = {}

var _section_results: Array[Dictionary] = []
var _section_name: String = ""
var _section_error_start: int = 0

func run() -> Dictionary:
	var item_types := {}
	var material_ids := {}

	_begin_section("autoloads")
	_validate_autoloads()
	_end_section()

	_begin_section("scripts")
	_validate_project_scripts()
	_end_section()

	_begin_section("scenes")
	_validate_project_scenes()
	_end_section()

	_begin_section("items")
	_validate_items(item_types)
	_end_section()

	_begin_section("materials")
	_validate_materials(material_ids)
	_end_section()

	_begin_section("recipes")
	_validate_recipes(item_types)
	_end_section()

	_begin_section("classes")
	_validate_classes(item_types)
	_end_section()

	_begin_section("clothing offsets")
	_validate_clothing_offsets()
	_end_section()

	_begin_section("coin icons")
	_validate_coin_icons()
	_end_section()

	_begin_section("keyring icons")
	_validate_keyring_icons()
	_end_section()

	_begin_section("net: spawnable scenes")
	_validate_spawnable_scenes()
	_end_section()

	_begin_section("net: replication configs")
	_validate_replication_configs()
	_end_section()

	_begin_section("net: resource diff dirs")
	_validate_resource_diff_dirs()
	_end_section()

	return {
		"errors": _errors.duplicate(),
		"warnings": _warnings.duplicate(),
		"sections": _section_results.duplicate(),
	}

func _begin_section(name: String) -> void:
	_section_name = name
	_section_error_start = _errors.size()

func _end_section() -> void:
	_section_results.append({
		"name": _section_name,
		"errors": _errors.size() - _section_error_start,
	})
	_section_name = ""

func _validate_items(item_types: Dictionary) -> void:
	const VALID_SLOTS: Array[String] = [
		"head", "face", "cloak", "armor", "backpack",
		"gloves", "waist", "clothing", "trousers", "feet",
		"pocket_l", "pocket_r",
	]
	const VALID_TOOL_TYPES: Array[String] = ["slashing", "stabbing", "pickaxe"]

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

		if not item.slot.is_empty() and item.slot not in VALID_SLOTS:
			_fail("%s: slot '%s' is not a valid Defs slot." % [path, item.slot])
		if not item.tool_type.is_empty() and item.tool_type not in VALID_TOOL_TYPES:
			_fail("%s: tool_type '%s' is not a valid Defs tool type." % [path, item.tool_type])
		if item.has_inventory and item.inventory_slots <= 0:
			_fail("%s: has_inventory is true but inventory_slots is %d." % [path, item.inventory_slots])

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

# GAMEPLAY: every item_type referenced in Classes.DATA equipment must exist.
func _validate_classes(item_types: Dictionary) -> void:
	for class_key: String in Classes.DATA:
		var equipment: Dictionary = Classes.DATA[class_key].get("equipment", {})
		for slot_key: String in equipment:
			var item_type: String = str(equipment[slot_key])
			if not item_types.has(item_type):
				_fail("Classes['%s'].equipment['%s']: item_type '%s' not found in %s." % [class_key, slot_key, item_type, ITEMS_DIR])

# GAMEPLAY: clothing_offsets.json must parse and have a complete entry (all 4
# directions, valid offset array and positive scale) for every item_type key.
func _validate_clothing_offsets() -> void:
	const OFFSETS_PATH := "res://clothing/clothing_offsets.json"
	const DIRECTIONS: Array[String] = ["north", "south", "east", "west"]
	if not ResourceLoader.exists(OFFSETS_PATH):
		_fail("%s: file missing." % OFFSETS_PATH)
		return
	var file := FileAccess.open(OFFSETS_PATH, FileAccess.READ)
	if file == null:
		_fail("%s: could not open." % OFFSETS_PATH)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		_fail("%s: JSON parse error at line %d: %s." % [OFFSETS_PATH, json.get_error_line(), json.get_error_message()])
		return
	var data: Variant = json.get_data()
	if not data is Dictionary:
		_fail("%s: root must be a JSON object." % OFFSETS_PATH)
		return
	for item_type: String in (data as Dictionary):
		var entry: Variant = data[item_type]
		if not entry is Dictionary:
			_fail("%s: entry for '%s' must be an object." % [OFFSETS_PATH, item_type])
			continue
		for dir in DIRECTIONS:
			if not (entry as Dictionary).has(dir):
				_fail("%s: '%s' missing direction '%s'." % [OFFSETS_PATH, item_type, dir])
				continue
			var d: Variant = (entry as Dictionary)[dir]
			if not d is Dictionary:
				_fail("%s: '%s.%s' must be an object." % [OFFSETS_PATH, item_type, dir])
				continue
			var offset: Variant = (d as Dictionary).get("offset")
			if not offset is Array or (offset as Array).size() != 2:
				_fail("%s: '%s.%s.offset' must be a 2-element array." % [OFFSETS_PATH, item_type, dir])
			var scale_val: Variant = (d as Dictionary).get("scale")
			if not (scale_val is float or scale_val is int) or float(scale_val) <= 0.0:
				_fail("%s: '%s.%s.scale' must be a positive number." % [OFFSETS_PATH, item_type, dir])

# GAMEPLAY: all coin stack icon images referenced by Defs helpers must exist.
func _validate_coin_icons() -> void:
	for threshold: int in Defs.COIN_STACK_ICON_THRESHOLDS:
		for suffix: String in Defs.COIN_METAL_SUFFIXES:
			var tex_path := "res://objects/coins/%d%s.png" % [threshold, suffix]
			_validate_texture(tex_path, "coin icon")

# GAMEPLAY: keyring icons keyring0.png .. keyringN.png must all exist.
func _validate_keyring_icons() -> void:
	for i in range(Defs.KEYRING_MAX_KEYS + 1):
		var tex_path := "res://objects/keys/keyring%d.png" % i
		_validate_texture(tex_path, "keyring icon")

# Every scene registered with MultiplayerSpawner must exist and instantiate cleanly.
func _validate_spawnable_scenes() -> void:
	for scene_path in NET_SPAWNABLE_SCENES:
		_validate_packed_scene(scene_path, "spawnable scene")

# Every scene in NET_SYNCED_SCENES must have a MultiplayerSynchronizer whose
# replication_config property paths all resolve to real properties on their
# target nodes.  A path like NodePath(".:tile_pos") breaks silently at runtime
# when the property is renamed; this check catches that at import time.
func _validate_replication_configs() -> void:
	for scene_path in NET_SYNCED_SCENES:
		if not ResourceLoader.exists(scene_path):
			continue
		var packed := ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
		if packed == null:
			continue
		var instance := packed.instantiate()
		if instance == null:
			continue

		var sync_node := _find_multiplayer_synchronizer(instance)
		if sync_node == null:
			_fail("%s: expected a MultiplayerSynchronizer but none found." % scene_path)
			instance.free()
			continue

		var config: SceneReplicationConfig = sync_node.get("replication_config")
		if config == null:
			_fail("%s: MultiplayerSynchronizer '%s' has no replication_config." % [scene_path, sync_node.name])
			instance.free()
			continue

		for prop_path: NodePath in config.get_properties():
			_validate_replication_property(scene_path, instance, prop_path)

		instance.free()

# NETCODE/PATCHING: every directory in GameVersion.RESOURCE_DIFF_DIRS must exist.
# If one is missing, build_manifest() silently skips it and clients never receive
# diffs for that content type — a silent desync on every server restart.
func _validate_resource_diff_dirs() -> void:
	for dir_path: String in GameVersion.RESOURCE_DIFF_DIRS:
		if DirAccess.open(dir_path) == null:
			_fail("GameVersion.RESOURCE_DIFF_DIRS: directory missing or inaccessible: %s." % dir_path)

func _validate_replication_property(scene_path: String, root: Node, prop_path: NodePath) -> void:
	var path_str := str(prop_path)
	var colon_idx := path_str.find(":")
	if colon_idx == -1:
		_fail("%s: replication property '%s' has no ':' separator between node path and property name." % [scene_path, path_str])
		return

	var node_path_str := path_str.substr(0, colon_idx)
	var prop_name := path_str.substr(colon_idx + 1)

	var target: Node
	if node_path_str == "." or node_path_str.is_empty():
		target = root
	else:
		target = root.get_node_or_null(NodePath(node_path_str))

	if target == null:
		_fail("%s: replication property '%s' — node '%s' not found in scene." % [scene_path, path_str, node_path_str])
		return

	var found := false
	for pi: Dictionary in target.get_property_list():
		if pi["name"] == prop_name:
			found = true
			break

	if not found:
		_fail("%s: replication property '%s' — '%s' does not exist on node '%s'." % [scene_path, path_str, prop_name, target.name])

# Returns the first MultiplayerSynchronizer descendant of root, or null.
func _find_multiplayer_synchronizer(root: Node) -> MultiplayerSynchronizer:
	if root is MultiplayerSynchronizer:
		return root as MultiplayerSynchronizer
	for child in root.get_children():
		var result := _find_multiplayer_synchronizer(child)
		if result != null:
			return result
	return null

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
