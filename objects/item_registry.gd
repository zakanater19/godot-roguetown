# res://objects/item_registry.gd
# AutoLoad singleton — register as "ItemRegistry" in project.godot [autoload]
#
# Single source of truth for all item definitions.
# To add a new item: create a new ItemData .tres in res://items/, then
# add a preload() entry to ALL_ITEMS below.

extends Node

const ALL_ITEMS: Array = [
	# --- Objects ---
	preload("res://items/sword.tres"),
	preload("res://items/pickaxe.tres"),
	preload("res://items/pebble.tres"),
	preload("res://items/coal.tres"),
	preload("res://items/ironore.tres"),
	preload("res://items/ironingot.tres"),
	preload("res://items/log.tres"),
	preload("res://items/rock.tres"),
	preload("res://items/furnace.tres"),
	preload("res://items/tree1.tres"),
	preload("res://items/tree2.tres"),
	# --- Clothing ---
	preload("res://items/ironhelmet.tres"),
	preload("res://items/ironchestplate.tres"),
	preload("res://items/leatherboots.tres"),
	preload("res://items/leathertrousers.tres"),
	preload("res://items/apothshirt.tres"),
	preload("res://items/blackshirt.tres"),
	preload("res://items/undershirt.tres"),
	preload("res://items/merchantrobe.tres"),
	preload("res://items/plate.tres"),
	preload("res://items/satchel.tres"),
	preload("res://items/king_cloak.tres"),
	preload("res://items/crown.tres"),
]

# Returns the ItemData resource for a given item_type string, or null if not found.
func get_by_type(item_type: String) -> ItemData:
	for entry: ItemData in ALL_ITEMS:
		if entry.item_type == item_type:
			return entry
	return null

# Convenience: returns the scene_path string directly, or "" if not found.
func get_scene_path(item_type: String) -> String:
	var entry := get_by_type(item_type)
	return entry.scene_path if entry != null else ""