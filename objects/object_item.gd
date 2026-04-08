# res://objects/object_item.gd
# Base class for all pickable world items. Assign an ItemData .tres to item_data
# in the Inspector — no per-item .gd script needed for standard items.
@tool
class_name ObjectItem
extends Area2D

@export var item_data: ItemData = null
@export var z_level: int = 3

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
	z_index = (z_level - 1) * Defs.Z_LAYER_SIZE + Defs.Z_OFFSET_ITEMS
	add_to_group("z_entity")
	if Engine.is_editor_hint():
		return
	World.register_entity(self)
	if item_data == null:
		push_error(name + ": item_data is not set — assign a .tres in the Inspector.")
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
	if item_data.pickable:
		add_to_group("pickable")

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	World.unregister_entity(self)

func get_description() -> String:
	return item_data.description if item_data != null else ""

func get_use_delay() -> float:
	return item_data.use_delay if item_data != null else CombatDefs.DEFAULT_ACTION_DELAY

## Returns the vertical hand offset for this item when held by a player.
## Falls back to item_data.hand_offset_y when no hand_offsets.json entry exists.
func get_hand_offset() -> Vector2:
	return Vector2(0.0, item_data.hand_offset_y) if item_data != null else Vector2.ZERO

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if Engine.is_editor_hint(): return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.is_key_pressed(KEY_SHIFT): return
		var player: Node = World.get_local_player()
		if player == null: return
		if player.z_level != z_level: return
		var my_tile := Vector2i(int(global_position.x / Defs.TILE_SIZE), int(global_position.y / Defs.TILE_SIZE))
		var diff: Vector2i = (my_tile - player.tile_pos).abs()
		if diff.x <= 1 and diff.y <= 1:
			get_viewport().set_input_as_handled()
			if player.has_method("_on_object_picked_up"):
				player._on_object_picked_up(self)
