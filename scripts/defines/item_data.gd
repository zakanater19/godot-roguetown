# res://scripts/defines/item_data.gd
# Base resource for all items and clothing.
# Create instances via: right-click FileSystem -> New Resource -> ItemData

class_name ItemData
extends Resource

## The canonical string key used throughout the codebase (e.g. "Sword", "IronChestplate").
@export var item_type: String = ""

## Path to the packed scene that gets instantiated when this item is spawned.
@export var scene_path: String = ""

## Drag the item's texture here in the Inspector.
@export var sprite: Texture2D = null

## Column index in res://objects/objects.png (set -1 if the item has its own PNG).
@export var sprite_col: int = -1

## Shown when the player inspects this item.
@export var description: String = ""

## Equipment slot: "head", "cloak", "armor", "backpack", "waist",
## "clothing", "trousers", "feet", or "" for non-wearable items.
@export var slot: String = ""

## Damage dealt when used as a weapon (0 for non-weapons).
@export var base_damage: int = 0

## Seconds of cooldown applied after using this item.
@export var use_delay: float = 0.5

## If true, this item counts as a weapon in combat checks.
@export var weaponizable: bool = false

## Tool category for action dispatch. Use Defs.TOOL_* constants.
## "" = generic item, "sword" = blade weapon, "pickaxe" = mining tool.
## Add new tool types in Defs.gd before referencing them here.
@export var tool_type: String = ""

## If true, this item cannot be placed inside a satchel.
@export var too_large_for_satchel: bool = false

## If true, the item can be picked up from the ground by a player.
@export var pickable: bool = false

## If true, this item acts as an inventory container (e.g. satchel).
@export var has_inventory: bool = false

## Number of slots available when has_inventory is true.
@export var inventory_slots: int = 0

## If true, this item can be used as furnace fuel (e.g. coal, log).
@export var is_fuel: bool = false

## If true, this item can be smelted in a furnace (e.g. iron ore).
@export var is_smeltable_ore: bool = false

## Texture shown in the HUD inventory/equipment panel.
@export var hud_texture_path: String = ""

## Texture rendered on the player's body when this item is worn/held.
## Leave empty for items that are never visually worn (e.g. raw materials).
@export var mob_texture_path: String = ""

## Rotation (degrees) applied to this item's waist sprite on the player body.
## e.g. 45.0 for a sword worn diagonally at the hip.
@export var waist_rotation: float = 0.0

## Scale multiplier for this item's waist sprite on the player body.
## Use values < 1.0 for oversized sprites (e.g. pickaxe at 0.75).
@export var waist_sprite_scale: float = 1.0

## Vertical pixel offset applied when this item is held in a hand.
## Used as a fallback when no entry exists in hand_offsets.json.
## Positive = down, negative = up. Typical blade weapons use -10.0.
@export var hand_offset_y: float = 0.0

## If true, this item can parry incoming attacks when in parry stance.
## Set on sword-class weapons; allows the combat system to avoid hardcoding item types.
@export var can_parry: bool = false
