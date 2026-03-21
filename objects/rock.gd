# res://objects/rock.gd
@tool
extends Area2D

const TILE_SIZE:     int = 64
const HITS_TO_BREAK: int = 2

const PEBBLE_SCENE: PackedScene = preload("res://objects/pebble.tscn")

# Maximum pixel offset from tile center for dropped items
const DROP_SPREAD: float = 14.0

var hits: int = 0


func get_description() -> String:
	return "a rock, solid and heavy"


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group("minable_object")


func perform_hit(main_node: Node) -> void:
	if main_node != null and main_node.has_method("shake_tile"):
		var t := Vector2i(
			int(global_position.x / TILE_SIZE),
			int(global_position.y / TILE_SIZE)
		)
		main_node.shake_tile(t)


func perform_break(drops_data: Array) -> void:
	var center: Vector2 = position
	for data in drops_data:
		var scene: PackedScene = null
		if data.type == "pebble":
			scene = PEBBLE_SCENE
		elif data.type == "coal":
			scene = load("res://objects/coal.tscn") as PackedScene
		elif data.type == "ironore":
			scene = load("res://objects/ironore.tscn") as PackedScene
		
		if scene != null:
			_spawn_drop(scene, center, data.name)
	queue_free()


func _spawn_drop(scene: PackedScene, center: Vector2, node_name: String) -> void:
	var obj: Node2D = scene.instantiate()
	obj.name = node_name
	
	var rng = RandomNumberGenerator.new()
	rng.seed = node_name.hash()
	obj.position = center + Vector2(
		rng.randf_range(-DROP_SPREAD, DROP_SPREAD),
		rng.randf_range(-DROP_SPREAD, DROP_SPREAD)
	)
	get_parent().add_child(obj)
