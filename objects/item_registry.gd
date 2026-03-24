# res://objects/item_registry.gd
# AutoLoad singleton — register as "ItemRegistry" in project.godot [autoload]
#
# Single source of truth for all item definitions.
# To add a new item: create a new ItemData .tres in res://items/, then
# add a preload() entry to ALL_ITEMS below.

extends Node

const ALL_ITEMS: Array =[
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
	preload("res://items/merchantvendor.tres"),
	preload("res://items/tree1.tres"),
	preload("res://items/tree2.tres"),
	preload("res://items/dirk.tres"),
	preload("res://items/lamp.tres"),
	preload("res://items/copper_coin.tres"),
	preload("res://items/silver_coin.tres"),
	preload("res://items/gold_coin.tres"),
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

# Centralized texture lists for UI rendering
const HUD_TEXTURES: Dictionary = {
	"IronHelmet":     "res://clothing/ironhelmet.png",
	"IronChestplate": "res://clothing/ironchestplate.png",
	"LeatherBoots":   "res://clothing/leatherboots.png",
	"LeatherTrousers": "res://clothing/leathertrousers.png",
	"Apothshirt":     "res://clothing/apothshirt.png",
	"Blackshirt":     "res://clothing/blackshirt.png",
	"Undershirt":     "res://clothing/undershirt.png",
	"Merchantrobe":   "res://clothing/merchantrobe.png",
	"Plate":          "res://clothing/plate.png",
	"Satchel":        "res://clothing/satchel.png",
	"KingCloak":      "res://clothing/king_cloak.png",
	"Crown":          "res://clothing/crownonmob.png",
	"Pickaxe":        "res://objects/objects.png",
	"Sword":          "res://objects/objects.png",
	"Dirk":           "res://objects/dirk.png",
	"Lamp":           "res://objects/lampoff.png"
}

# Centralized texture lists for on-mob sprite rendering
const MOB_TEXTURES: Dictionary = {
	"IronHelmet":     "res://clothing/ironhelmet.png",
	"IronChestplate": "res://clothing/ironchestplate.png",
	"LeatherBoots":   "res://clothing/leatherboots.png",
	"LeatherTrousers": "res://clothing/leathertrousers.png",
	"Apothshirt":     "res://clothing/apothshirt.png",
	"Blackshirt":     "res://clothing/blackshirt.png",
	"Undershirt":     "res://clothing/undershirt.png",
	"Merchantrobe":   "res://clothing/merchantrobe.png",
	"Plate":          "res://clothing/plate.png",
	"Satchel":        "res://clothing/satchelonmob.png",
	"KingCloak":      "res://clothing/king_cloak_onmob.png",
	"Crown":          "res://clothing/crownonmob.png",
	"Pickaxe":        "res://objects/objects.png",
	"Sword":          "res://objects/objects.png",
	"Dirk":           "res://objects/dirk.png",
	"Lamp":           "res://objects/lampoff.png"
}

var _scene_paths_cache: Dictionary = {}
var _item_data_cache: Dictionary = {}

func _ready() -> void:
	# Build fast lookup caches for O(1) retrieval
	for entry in ALL_ITEMS:
		if entry != null:
			_item_data_cache[entry.item_type] = entry
			if entry.scene_path != "":
				_scene_paths_cache[entry.item_type] = entry.scene_path

func get_by_type(item_type: String) -> ItemData:
	return _item_data_cache.get(item_type, null)

func get_scene_path(item_type: String) -> String:
	return _scene_paths_cache.get(item_type, "")
