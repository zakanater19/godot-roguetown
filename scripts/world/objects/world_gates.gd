# res://scripts/world/objects/world_gates.gd
extends RefCounted

var world: Node

func _init(p_world: Node) -> void:
	world = p_world

func handle_rpc_request_hit_gate(sender_id: int, gate_path: NodePath) -> void:
	if not world.multiplayer.is_server(): return
	var gate = world.get_node_or_null(gate_path)
	if gate == null: return

	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if player == null or player.dead: return
	if player.body != null and player.body.is_arm_broken(player.active_hand): return
	if not world.utils.is_within_interaction_range(player, gate.global_position): return

	var held_item = player.hands[player.active_hand]
	if held_item == null:
		if gate.state != gate.GateState.DESTROYED:
			world.rpc_confirm_toggle_gate.rpc(gate_path)
	else:
		var is_sword = Defs.is_tool_sword(held_item)
		var is_pickaxe = Defs.is_tool_pickaxe(held_item)

		if is_sword or (is_pickaxe and player.combat_mode):
			if not world.utils.server_check_action_cooldown(player): return
			gate.hits += 1
			if gate.hits >= gate.HITS_TO_BREAK * 2:
				world.rpc_confirm_remove_gate.rpc(gate_path)
			elif gate.hits == gate.HITS_TO_BREAK:
				world.rpc_confirm_destroy_gate.rpc(gate_path)
			else:
				world.rpc_confirm_hit_gate.rpc(gate_path)

func handle_rpc_confirm_toggle_gate(_gate_path: NodePath) -> void:
	var gate = world.get_node_or_null(_gate_path)
	if gate != null:
		gate.toggle_gate()

func handle_rpc_confirm_hit_gate(gate_path: NodePath) -> void:
	var gate = world.get_node_or_null(gate_path)
	if gate != null:
		var main = world.get_tree().root.get_node_or_null("Main")
		gate.perform_hit(main)

func handle_rpc_confirm_destroy_gate(gate_path: NodePath) -> void:
	var gate = world.get_node_or_null(gate_path)
	if gate != null:
		var main = world.get_tree().root.get_node_or_null("Main")
		gate.perform_hit(main)
		gate.destroy_gate()

func handle_rpc_confirm_remove_gate(gate_path: NodePath) -> void:
	var gate = world.get_node_or_null(gate_path)
	if gate != null:
		var main = world.get_tree().root.get_node_or_null("Main")
		gate.perform_hit(main)
		gate.remove_completely()