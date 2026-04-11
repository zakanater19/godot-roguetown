# res://scripts/defines/recipe_data.gd
# Data resource for a single crafting recipe.
# Create new recipes by right-clicking the recipes/ folder -> New Resource -> RecipeData.
# They are auto-discovered by RecipeRegistry at startup — no other files need editing.
class_name RecipeData
extends Resource

## Unique string key used to identify this recipe (e.g. "sword", "wooden_floor").
@export var recipe_id: String = ""

## Name shown in the crafting menu UI.
@export var display_name: String = ""

## ItemData resource required as the ingredient for this recipe.
@export var req_item_data: ItemData = null

## How many of the required ingredient are consumed per craft.
@export var req_amount: int = 1

## Minimum skill levels required: { "skill_name": level }.
## Leave empty for recipes with no skill gate.
@export var skill_requirements: Dictionary = {}

## "item" → spawns a scene; "tile" → places a tilemap cell.
## Use Defs.RECIPE_RESULT_ITEM / Defs.RECIPE_RESULT_TILE.
@export var result_type: String = "item"

# --- item result fields ---
## ItemData resource produced when result_type == "item".
@export var result_item_data: ItemData = null

# --- tile result fields ---
## TileMapLayer source_id when result_type == "tile".
@export var result_tile_source: int = 0
## Atlas coordinates in the tileset when result_type == "tile".
@export var result_tile_coords: Vector2i = Vector2i.ZERO

func get_required_item_type() -> String:
	return req_item_data.item_type if req_item_data != null else ""

func get_result_item_type() -> String:
	return result_item_data.item_type if result_item_data != null else ""
