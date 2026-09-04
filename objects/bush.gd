@tool
extends WorldObject

@export_range(1, 99) var max_items: int = 3
@export var loot_item_types: Array[String] = ["Thorn", "Fibers"]

var is_bush: bool = true
var items_picked: int = 0

func get_description() -> String:
	return "a dense bush that might conceal something useful"

func get_z_offset() -> int:
	return 5

func should_snap_to_tile() -> bool:
	return true

func should_register_entity() -> bool:
	return true

func get_runtime_groups() -> Array[String]:
	return [Defs.GROUP_INSPECTABLE]

func has_items_remaining() -> bool:
	return items_picked < max_items

func choose_loot_item_type() -> String:
	if loot_item_types.is_empty():
		return ""
	return loot_item_types.pick_random()

func set_items_picked(value: int) -> void:
	items_picked = clampi(value, 0, max_items)

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if Engine.is_editor_hint():
		return
	if event is not InputEventMouseButton:
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	if Input.is_key_pressed(KEY_SHIFT):
		return

	var player: Node = World.get_local_player()
	if player == null or player.z_level != z_level:
		return
	if not Defs.is_within_tile_reach(player.tile_pos, get_anchor_tile()):
		return

	get_viewport().set_input_as_handled()
	if not Defs.is_valid_hand_index(player.active_hand):
		return
	if player.hands[player.active_hand] != null:
		player._show_inspect_text("you need an open hand to search the bush", "")
		return
	if player.body != null and player.body.is_arm_broken(player.active_hand):
		player._show_inspect_text("that arm is useless", "")
		return
	if player.action_cooldown > 0.0:
		return

	player._face_toward(global_position)
	player._apply_action_cooldown(null)
	var bush_id := World.get_entity_id(self)
	World.rpc_request_search_bush.rpc_id(1, bush_id, player.active_hand)
