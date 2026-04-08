@tool
extends Area2D

const TILE_SIZE: int = 64
const HITS_TO_BREAK: int = 4
const DEFAULT_MATERIAL: MaterialData = preload("res://materials/wood.tres")

var hits: float = 0.0
@export var z_level: int = 3
@export var material_data: MaterialData = DEFAULT_MATERIAL

func get_description() -> String:
	return "a normal bed, looks somewhat comfortable"

func _ready() -> void:
	# Standardized to floor base + 2 (below players at +10)
	z_index = (z_level - 1) * 200 + 2
	add_to_group("z_entity")
	if Engine.is_editor_hint():
		return
	
	var tile_pos := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
	global_position = Vector2((tile_pos.x + 0.5) * TILE_SIZE, (tile_pos.y + 0.5) * TILE_SIZE)
	
	add_to_group("breakable_object")
	add_to_group("bed")

func set_hits(val: float) -> void:
	hits = val

func perform_hit(main_node: Node) -> void:
	if main_node != null and main_node.has_method("shake_tile"):
		var t := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
		main_node.shake_tile(t, z_level)

func perform_break() -> void:
	queue_free()
