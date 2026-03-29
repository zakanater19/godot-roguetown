# res://objects/woodentable.gd
@tool
extends Area2D

const TILE_SIZE: int = 64

@export var z_level: int = 3
var blocks_fov: bool = false

func get_description() -> String:
	return "a wooden table"

func _ready() -> void:
	z_index = (z_level - 1) * 200 + 2
	add_to_group("z_entity")
	if Engine.is_editor_hint():
		return
	var tile_pos := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
	global_position = Vector2((tile_pos.x + 0.5) * TILE_SIZE, (tile_pos.y + 0.5) * TILE_SIZE)
	World.register_solid(tile_pos, z_level, self)
	add_to_group("inspectable")

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	var tile_pos := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
	World.unregister_solid(tile_pos, z_level, self)

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.is_key_pressed(KEY_SHIFT):
			return
		var player: Node = World.get_local_player()
		if player == null or player.z_level != z_level:
			return
		var my_tile := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
		var diff: Vector2i = (my_tile - player.tile_pos).abs()
		if diff.x > 1 or diff.y > 1:
			return
		var held: Node = player.hands[player.active_hand]
		if held == null:
			return # Let the click pass through to the item on the table
		get_viewport().set_input_as_handled()
		var place_pos: Vector2 = get_global_mouse_position()
		if multiplayer.is_server():
			World.rpc_request_table_place(get_path(), player.active_hand, place_pos)
		else:
			World.rpc_request_table_place.rpc_id(1, get_path(), player.active_hand, place_pos)