# res://objects/woodentable.gd
@tool
extends WorldObject

var blocks_fov: bool = false

func get_description() -> String:
	return "a wooden table"

func should_snap_to_tile() -> bool:
	return true

func should_register_entity() -> bool:
	return true

func get_runtime_groups() -> Array[String]:
	return [Defs.GROUP_INSPECTABLE]

func get_solid_tile_offsets() -> Array[Vector2i]:
	return [Vector2i.ZERO]

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.is_key_pressed(KEY_SHIFT):
			return
		var player: Node = World.get_local_player()
		if player == null or player.z_level != z_level:
			return
		if not Defs.is_within_tile_reach(player.tile_pos, get_anchor_tile()):
			return
		var held: Node = player.hands[player.active_hand]
		if held == null:
			return # Let the click pass through to the item on the table
		get_viewport().set_input_as_handled()
		var place_pos: Vector2 = get_global_mouse_position()
		var table_id := World.get_entity_id(self)
		if multiplayer.is_server():
			World.rpc_request_table_place(table_id, player.active_hand, place_pos)
		else:
			World.rpc_request_table_place.rpc_id(1, table_id, player.active_hand, place_pos)
