@tool
extends Area2D

const TILE_SIZE: int = 64
var item_type: String = "Sword"

var weaponizable: bool = true
var force: int = 50
var too_large_for_satchel: bool = true
var slot: String = "waist"

@export var z_level: int = 3

func get_description() -> String:
	return "a sword, regular steel"

func get_use_delay() -> float:
	return 0.5

func get_hand_offset() -> Vector2:
	return Vector2(0.0, -10.0)

func _ready() -> void:
	# Standardized to floor base + 2 (below players at +10)
	z_index = (z_level - 1) * 200 + 2
	add_to_group("z_entity")
	if Engine.is_editor_hint():
		return
	add_to_group("pickable")

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
		if diff.x <= 1 and diff.y <= 1:
			get_viewport().set_input_as_handled()
			if player.has_method("_on_object_picked_up"):
				player._on_object_picked_up(self)