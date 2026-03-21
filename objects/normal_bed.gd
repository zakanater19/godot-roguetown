@tool
extends Area2D

const TILE_SIZE: int = 64
const HITS_TO_BREAK: int = 4

var hits: int = 0

func get_description() -> String:
	return "a normal bed, looks somewhat comfortable"

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	
	# Snap to tile center
	var tile_pos := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
	global_position = Vector2((tile_pos.x + 0.5) * TILE_SIZE, (tile_pos.y + 0.5) * TILE_SIZE)
	
	add_to_group("breakable_object")
	add_to_group("bed")
	# Deliberately NOT calling World.register_solid() so it has no collision.

func set_hits(val: int) -> void:
	hits = val

func perform_hit(main_node: Node) -> void:
	if main_node != null and main_node.has_method("shake_tile"):
		var t := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
		main_node.shake_tile(t)

func perform_break() -> void:
	queue_free()