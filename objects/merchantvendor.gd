# res://objects/merchantvendor.gd
@tool
extends Area2D

const TILE_SIZE: int = 64

func get_description() -> String:
	return "a merchant vendor, ready to trade"

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var tile_pos := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
	global_position = Vector2((tile_pos.x + 0.5) * TILE_SIZE, (tile_pos.y + 0.5) * TILE_SIZE)
	World.register_solid(tile_pos, self)
	add_to_group("inspectable")

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	var tile_pos := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
	World.unregister_solid(tile_pos, self)