# res://objects/object_item.gd
# Base class for all pickable world items. Assign an ItemData .tres to item_data
# in the Inspector - no per-item .gd script needed for standard items.
@tool
class_name ObjectItem
extends PickableWorldObject

@export var item_data: ItemData = null

var item_type: String = ""
var tool_type: String = ""
var material_data: MaterialData = null
var slot: String = ""
var weaponizable: bool = false
var too_large_for_satchel: bool = false
var force: int = 0
var is_fuel: bool = false
var is_smeltable_ore: bool = false

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	if item_data == null:
		push_error(name + ": item_data is not set - assign a .tres in the Inspector.")
		return
	item_type             = item_data.item_type
	tool_type             = item_data.tool_type
	material_data         = item_data.material_data
	slot                  = item_data.slot
	weaponizable          = item_data.weaponizable
	too_large_for_satchel = item_data.too_large_for_satchel
	force                 = item_data.base_damage
	is_fuel               = item_data.is_fuel
	is_smeltable_ore      = item_data.is_smeltable_ore

func is_pickup_enabled() -> bool:
	return item_data != null and item_data.pickable

func get_description() -> String:
	return item_data.description if item_data != null else ""

func get_use_delay() -> float:
	return item_data.use_delay if item_data != null else CombatDefs.DEFAULT_ACTION_DELAY

## Returns the vertical hand offset for this item when held by a player.
## Falls back to item_data.hand_offset_y when no hand_offsets.json entry exists.
func get_hand_offset() -> Vector2:
	return Vector2(0.0, item_data.hand_offset_y) if item_data != null else Vector2.ZERO
