# res://objects/item_registry.gd
# AutoLoad singleton — register as "ItemRegistry" in project.godot [autoload]
#
# Single source of truth for all item definitions.
# To add a new item: create a new ItemData .tres in res://items/ and drop it in.
# No other files need editing.

extends Node

var _scene_paths_cache: Dictionary = {}
var _item_data_cache: Dictionary = {}
var _icon_cache: Dictionary = {}

func _ready() -> void:
	_load_all_items()

func _load_all_items() -> void:
	var dir := DirAccess.open("res://items/")
	if dir == null:
		push_error("ItemRegistry: could not open res://items/")
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var item := load("res://items/" + fname) as ItemData
			if item != null and item.item_type != "":
				_item_data_cache[item.item_type] = item
				if item.scene_path != "":
					_scene_paths_cache[item.item_type] = item.scene_path
		fname = dir.get_next()

## Re-scan res://items/ after a PCK patch has been mounted.
func reload() -> void:
	_scene_paths_cache.clear()
	_item_data_cache.clear()
	_icon_cache.clear()
	_load_all_items()

## Overwrite (or insert) an item definition received from the server.
## Called by GameVersion.apply_resource_diff on version-mismatched clients.
func patch_item(item: ItemData) -> void:
	_item_data_cache[item.item_type] = item
	_icon_cache.erase(item.item_type)   # invalidate cached icon for this type
	if item.scene_path != "":
		_scene_paths_cache[item.item_type] = item.scene_path

func get_by_type(item_type: String) -> ItemData:
	return _item_data_cache.get(item_type, null)

func get_scene_path(item_type: String) -> String:
	return _scene_paths_cache.get(item_type, "")

func get_item_icon(item_type: String) -> Texture2D:
	if _icon_cache.has(item_type):
		return _icon_cache[item_type]

	var item_data := get_by_type(item_type)
	if item_data == null or item_data.hud_texture_path == "":
		return null

	var tex := load(item_data.hud_texture_path) as Texture2D
	if tex == null:
		return null

	var region_rect := Rect2(0, 0, tex.get_width(), tex.get_height())
	var scene_path := get_scene_path(item_type)
	if scene_path != "":
		var scene := load(scene_path) as PackedScene
		if scene != null:
			var state := scene.get_state()
			for i in range(state.get_node_count()):
				if state.get_node_name(i) == "Sprite2D":
					for j in range(state.get_node_property_count(i)):
						if state.get_node_property_name(i, j) == "region_rect":
							region_rect = state.get_node_property_value(i, j)
							break
					break

	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = region_rect
	_icon_cache[item_type] = atlas
	return atlas
