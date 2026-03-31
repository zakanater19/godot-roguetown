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
	preload("res://items/chaingloves.tres"),
	preload("res://items/hood.tres"),
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
	"ChainGloves":    "res://clothing/chaingloves.png",
	"Hood":           "res://clothing/hooddown.png",
	"Pickaxe":        "res://objects/objects.png",
	"Sword":          "res://objects/objects.png",
	"Dirk":           "res://objects/dirk.png",
	"Lamp":           "res://objects/lampoff.png",
	"Pebble":         "res://objects/objects.png",
	"Coal":           "res://objects/objects.png",
	"IronOre":        "res://objects/objects.png",
	"IronIngot":      "res://objects/objects.png",
	"Log":            "res://objects/objects.png",
	"CopperCoin":     "res://objects/coins/1copper.png",
	"SilverCoin":     "res://objects/coins/1silver.png",
	"GoldCoin":       "res://objects/coins/1gold.png"
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
	"ChainGloves":    "res://clothing/chainglovesonmob.png",
	"Hood":           "res://clothing/hoodonmob.png",
	"Pickaxe":        "res://objects/objects.png",
	"Sword":          "res://objects/objects.png",
	"Dirk":           "res://objects/dirk.png",
	"Lamp":           "res://objects/lampoff.png"
}

var _scene_paths_cache: Dictionary = {}
var _item_data_cache: Dictionary = {}
var _icon_cache: Dictionary = {}

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

func get_item_icon(item_type: String) -> Texture2D:
	if _icon_cache.has(item_type):
		return _icon_cache[item_type]

	if not HUD_TEXTURES.has(item_type):
		return null
		
	var tex = load(HUD_TEXTURES[item_type]) as Texture2D
	if tex == null: 
		return null

	var region_rect = Rect2(0, 0, 32, 32)
	var region_set = false
	var scene_path = get_scene_path(item_type)
	if scene_path != "":
		var scene = load(scene_path) as PackedScene
		if scene != null:
			var state = scene.get_state()
			for i in range(state.get_node_count()):
				if state.get_node_name(i) == "Sprite2D":
					for j in range(state.get_node_property_count(i)):
						if state.get_node_property_name(i, j) == "region_rect":
							region_rect = state.get_node_property_value(i, j)
							region_set = true
							break
					if region_set:
						break

	if not region_set:
		region_rect = Rect2(0, 0, tex.get_width(), tex.get_height())

	var atlas = AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = region_rect
	
	_icon_cache[item_type] = atlas
	return atlas
