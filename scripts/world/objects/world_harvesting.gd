# res://scripts/world/objects/world_harvesting.gd
extends RefCounted

var world: Node

func _init(p_world: Node) -> void:
	world = p_world

func _get_material_hit_strength(target: Node, held_item: Node) -> float:
	return MaterialRegistry.get_tool_efficiency(target, held_item)

func _get_break_threshold(target: Node) -> float:
	if target != null and target.has_method("get_hits_to_break"):
		return float(target.call("get_hits_to_break"))
	if target != null and "HITS_TO_BREAK" in target:
		return float(target.get("HITS_TO_BREAK"))
	return 1.0

func _build_tree_break_payload(tree: Node) -> Dictionary:
	if tree != null and tree.has_method("build_break_payload"):
		var payload = tree.call("build_break_payload")
		if payload is Dictionary and not payload.is_empty():
			return payload

	var tree_path := str(tree.get_path())
	var drop_names: Array[String] = []
	for _i in range(2):
		drop_names.append(Defs.make_runtime_name("Log"))

	return {
		"broken_paths": [tree_path],
		"drop_names": {
			tree_path: drop_names,
		},
	}

func handle_rpc_request_hit_rock(sender_id: int, rock_path: NodePath) -> void:
	if not world.multiplayer.is_server(): return
	var rock = world.get_node_or_null(rock_path)
	if rock == null: return

	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player): return
	if player.body != null and player.body.is_arm_broken(player.active_hand): return

	if not world.utils.is_within_interaction_range(player, rock.global_position): return
	if not world.utils.server_check_action_cooldown(player): return
	var hit_strength := _get_material_hit_strength(rock, player.hands[player.active_hand])
	if hit_strength <= 0.0: return

	rock.hits += hit_strength
	LateJoin.register_object_state(rock_path, {"hits": rock.hits, "type": "rock"})

	if rock.hits >= rock.HITS_TO_BREAK:
		var drops = ["pebble", "pebble"]
		if randf() < 0.20: drops.append("coal")
		if randf() < 0.10: drops.append("ironore")
		var drop_data = []
		for d in drops:
			drop_data.append({"type": d, "name": Defs.make_runtime_name("Drop")})
		world.rpc_confirm_break_rock.rpc(rock_path, drop_data)
	else:
		world.rpc_confirm_hit_rock.rpc(rock_path)

func handle_rpc_confirm_hit_rock(rock_path: NodePath) -> void:
	var rock = world.get_node_or_null(rock_path)
	if rock != null:
		rock.perform_hit(World.main_scene)

func handle_rpc_confirm_break_rock(rock_path: NodePath, drops_data: Array) -> void:
	var rock = world.get_node_or_null(rock_path)
	if rock != null:
		rock.perform_break(drops_data)
		LateJoin.unregister_object(rock_path)

func handle_rpc_request_hit_tree(sender_id: int, tree_path: NodePath) -> void:
	if not world.multiplayer.is_server(): return
	var tree = world.get_node_or_null(tree_path)
	if tree == null: return

	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player): return
	if player.body != null and player.body.is_arm_broken(player.active_hand): return

	if not world.utils.is_within_interaction_range(player, tree.global_position): return
	if not world.utils.server_check_action_cooldown(player): return
	var hit_strength := _get_material_hit_strength(tree, player.hands[player.active_hand])
	if hit_strength <= 0.0: return

	tree.hits += hit_strength
	LateJoin.register_object_state(tree_path, {"hits": tree.hits, "type": "tree"})

	if tree.hits >= _get_break_threshold(tree):
		world.rpc_confirm_break_tree.rpc(tree_path, _build_tree_break_payload(tree))
	else:
		world.rpc_confirm_hit_tree.rpc(tree_path)

func handle_rpc_confirm_hit_tree(tree_path: NodePath) -> void:
	var tree = world.get_node_or_null(tree_path)
	if tree != null:
		tree.perform_hit(World.main_scene)

func handle_rpc_confirm_break_tree(tree_path: NodePath, break_payload: Dictionary) -> void:
	var broken_paths: Array = break_payload.get("broken_paths", [str(tree_path)])
	var drop_names_by_path: Dictionary = break_payload.get("drop_names", {})

	for raw_path in broken_paths:
		var disable_path := NodePath(String(raw_path))
		var blocking_piece = world.get_node_or_null(disable_path)
		if blocking_piece != null and blocking_piece.has_method("set_solid_enabled"):
			blocking_piece.call("set_solid_enabled", false)

	for raw_path in broken_paths:
		var piece_path := NodePath(String(raw_path))
		var tree = world.get_node_or_null(piece_path)
		if tree != null and tree.has_method("perform_break"):
			var log_names: Array = []
			var payload_names = drop_names_by_path.get(String(raw_path), [])
			if payload_names is Array:
				log_names = payload_names
			tree.perform_break(log_names)
		LateJoin.unregister_object(piece_path)

func handle_rpc_request_hit_breakable(sender_id: int, obj_path: NodePath) -> void:
	if not world.multiplayer.is_server(): return
	var obj = world.get_node_or_null(obj_path)
	if obj == null: return

	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player): return
	if player.body != null and player.body.is_arm_broken(player.active_hand): return
	if not world.utils.is_within_interaction_range(player, obj.global_position): return
	if not world.utils.server_check_action_cooldown(player): return
	var hit_strength := _get_material_hit_strength(obj, player.hands[player.active_hand])
	if hit_strength <= 0.0: return

	obj.hits += hit_strength
	LateJoin.register_object_state(obj_path, {"hits": obj.hits, "type": "breakable"})

	if obj.hits >= obj.HITS_TO_BREAK:
		world.rpc_confirm_break_breakable.rpc(obj_path)
	else:
		world.rpc_confirm_hit_breakable.rpc(obj_path)

func handle_rpc_confirm_hit_breakable(obj_path: NodePath) -> void:
	var obj = world.get_node_or_null(obj_path)
	if obj != null and obj.has_method("perform_hit"):
		obj.perform_hit(World.main_scene)

func handle_rpc_confirm_break_breakable(obj_path: NodePath) -> void:
	var obj = world.get_node_or_null(obj_path)
	if obj != null and obj.has_method("perform_break"):
		obj.perform_break()
		LateJoin.unregister_object(obj_path)
