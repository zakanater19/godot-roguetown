@tool
extends Area2D

const TILE_SIZE: int = 64
const HITS_TO_BREAK: int = 5
const LOG_SCENE: PackedScene = preload("res://objects/log.tscn")

const DROP_SPREAD: float = 14.0

var hits: int = 0

func get_description() -> String:
	return "a dark, bare tree"

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	
	# Snap to tile center
	var tile_pos := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
	global_position = Vector2((tile_pos.x + 0.5) * TILE_SIZE, (tile_pos.y + 0.5) * TILE_SIZE)
	
	add_to_group("choppable_object")
	World.register_solid(tile_pos, self)

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	var tile_pos := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
	World.unregister_solid(tile_pos, self)

func perform_hit(main_node: Node) -> void:
	if main_node != null and main_node.has_method("shake_tile"):
		var t := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
		main_node.shake_tile(t)

func perform_break(log_names: Array) -> void:
	for log_name in log_names:
		_spawn_log(position, log_name)
	queue_free()

func _spawn_log(center: Vector2, node_name: String) -> void:
	var obj: Node2D = LOG_SCENE.instantiate()
	obj.name = node_name
	var rng = RandomNumberGenerator.new()
	rng.seed = node_name.hash()
	obj.position = center + Vector2(
		rng.randf_range(-DROP_SPREAD, DROP_SPREAD),
		rng.randf_range(-DROP_SPREAD, DROP_SPREAD)
	)
	get_parent().add_child(obj)
