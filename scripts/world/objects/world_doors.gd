extends RefCounted

var world: Node
var _structures = null

func _init(p_world: Node) -> void:
	world = p_world
	_structures = preload("res://scripts/world/objects/world_structure_handler.gd").new(world)

func handle_rpc_request_hit_door(sender_id: int, door_path: NodePath) -> void:
	match _structures.resolve_interaction(sender_id, door_path):
		"toggle":
			world.rpc_confirm_toggle_door.rpc(door_path)
		"hit":
			world.rpc_confirm_hit_door.rpc(door_path)
		"destroy":
			world.rpc_confirm_destroy_door.rpc(door_path)
		"remove":
			world.rpc_confirm_remove_door.rpc(door_path)

func handle_rpc_confirm_toggle_door(door_path: NodePath) -> void:
	_structures.confirm_toggle(door_path)

func handle_rpc_confirm_hit_door(door_path: NodePath) -> void:
	_structures.confirm_hit(door_path)

func handle_rpc_confirm_destroy_door(door_path: NodePath) -> void:
	_structures.confirm_destroy(door_path)

func handle_rpc_confirm_remove_door(door_path: NodePath) -> void:
	_structures.confirm_remove(door_path)
