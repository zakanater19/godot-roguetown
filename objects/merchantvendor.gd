# res://objects/merchantvendor.gd
@tool
extends Area2D

const TILE_SIZE: int = 64

@export var z_level: int = 3
var blocks_fov: bool = false

func get_description() -> String:
	return "a merchant vendor, ready to trade"

func _ready() -> void:
	z_index = (z_level - 1) * 200 + 5
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