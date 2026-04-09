extends RefCounted

var world: Node
var _structures = null

func _init(p_world: Node) -> void:
	world = p_world
	_structures = preload("res://scripts/world/objects/world_structure_handler.gd").new(world)

func handle_rpc_request_hit_gate(sender_id: int, gate_path: NodePath) -> void:
	match _structures.resolve_interaction(sender_id, gate_path):
		"toggle":
			world.rpc_confirm_toggle_gate.rpc(gate_path)
		"hit":
			world.rpc_confirm_hit_gate.rpc(gate_path)
		"destroy":
			world.rpc_confirm_destroy_gate.rpc(gate_path)
		"remove":
			world.rpc_confirm_remove_gate.rpc(gate_path)

func handle_rpc_confirm_toggle_gate(gate_path: NodePath) -> void:
	_structures.confirm_toggle(gate_path)

func handle_rpc_confirm_hit_gate(gate_path: NodePath) -> void:
	_structures.confirm_hit(gate_path)

func handle_rpc_confirm_destroy_gate(gate_path: NodePath) -> void:
	_structures.confirm_destroy(gate_path)

func handle_rpc_confirm_remove_gate(gate_path: NodePath) -> void:
	_structures.confirm_remove(gate_path)
