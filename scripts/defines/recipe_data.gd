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

## item_type of the required ingredient (must match an ItemData.item_type).
@export var req_item: String = ""

## How many of req_item are consumed per craft.
@export var req_amount: int = 1

## Minimum skill levels required: { "skill_name": level }.
## Leave empty for recipes with no skill gate.
@export var skill_requirements: Dictionary = {}

## "item" → spawns a scene; "tile" → places a tilemap cell.
## Use Defs.RECIPE_RESULT_ITEM / Defs.RECIPE_RESULT_TILE.
@export var result_type: String = "item"

# --- item result fields ---
## Path to the PackedScene instantiated when result_type == "item".
@export var result_scene_path: String = ""

# --- tile result fields ---
## TileMapLayer source_id when result_type == "tile".
@export var result_tile_source: int = 0
## Atlas coordinates in the tileset when result_type == "tile".
@export var result_tile_coords: Vector2i = Vector2i.ZERO
