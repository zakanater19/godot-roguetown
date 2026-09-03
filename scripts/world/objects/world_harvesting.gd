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

func _add_authoritative_tree_drop_results(payload: Dictionary) -> void:
	var broken_paths: Array = payload.get("broken_paths", [])
	var drop_names_by_path: Dictionary = payload.get("drop_names", {})
	var was_solid_by_path: Dictionary = {}

	# Remove every piece from the server's collision map before resolving any
	# fall.  This preserves the intended two-phase tree collapse without asking
	# each client to independently query its local map.
	for raw_path in broken_paths:
		var path := NodePath(String(raw_path))
		var piece := world.get_node_or_null(path)
		if piece == null or not piece.has_method("set_solid_enabled"):
			continue
		var was_solid := piece.has_method("starts_solid") and bool(piece.call("starts_solid"))
		was_solid_by_path[String(raw_path)] = was_solid
		if was_solid:
			piece.call("set_solid_enabled", false)

	var land_z_by_path: Dictionary = {}
	var drop_positions_by_path: Dictionary = {}
	for raw_path in broken_paths:
		var path_key := String(raw_path)
		var piece := world.get_node_or_null(NodePath(path_key))
		if piece == null:
			continue
		var drop_tile: Vector2i = piece.call("get_anchor_tile") if piece.has_method("get_anchor_tile") else Defs.world_to_tile(piece.global_position)
		land_z_by_path[path_key] = world.calculate_gravity_z(drop_tile, int(piece.get("z_level")))
		var positions: Array[Vector2] = []
		var names: Array = drop_names_by_path.get(path_key, [])
		var drop_spread := float(piece.call("get_drop_spread")) if piece.has_method("get_drop_spread") else Defs.DROP_SPREAD
		for _drop_name in names:
			positions.append(world.objects.make_authoritative_drop_position(drop_tile, drop_spread))
		drop_positions_by_path[path_key] = positions

	for raw_path in broken_paths:
		var path_key := String(raw_path)
		if not bool(was_solid_by_path.get(path_key, false)):
			continue
		var piece := world.get_node_or_null(NodePath(path_key))
		if piece != null and piece.has_method("set_solid_enabled"):
			piece.call("set_solid_enabled", true)

	payload["land_z"] = land_z_by_path
	payload["drop_positions"] = drop_positions_by_path

func handle_rpc_request_hit_rock(sender_id: int, rock_path: NodePath) -> void:
	if not world.multiplayer.is_server(): return
	var rock = world.get_node_or_null(rock_path)
	if rock == null: return

	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player): return
	if player.body != null and player.body.is_arm_broken(player.active_hand): return

	if not world.utils.is_within_interaction_range(player, rock.global_position): return
	var hit_strength := _get_material_hit_strength(rock, player.hands[player.active_hand])
	if hit_strength <= 0.0: return
	if not world.utils.server_check_action_cooldown(player, false, 5.0): return

	rock.hits += hit_strength
	LateJoin.register_object_state(rock_path, {"hits": rock.hits, "type": "rock"})

	if rock.hits >= rock.HITS_TO_BREAK:
		var drops = ["pebble", "pebble"]
		if randf() < 0.20: drops.append("coal")
		if randf() < 0.10: drops.append("ironore")
		var drop_data = []
		for d in drops:
			drop_data.append({
				"type": d,
				"name": Defs.make_runtime_name("Drop"),
				"position": world.objects.make_authoritative_drop_position(rock.get_anchor_tile(), Defs.DROP_SPREAD),
			})
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
	var hit_strength := _get_material_hit_strength(tree, player.hands[player.active_hand])
	if hit_strength <= 0.0: return
	if not world.utils.server_check_action_cooldown(player, false, 5.0): return

	tree.hits += hit_strength
	LateJoin.register_object_state(tree_path, {"hits": tree.hits, "type": "tree"})

	if tree.hits >= _get_break_threshold(tree):
		var break_payload := _build_tree_break_payload(tree)
		_add_authoritative_tree_drop_results(break_payload)
		world.rpc_confirm_break_tree.rpc(tree_path, break_payload)
	else:
		world.rpc_confirm_hit_tree.rpc(tree_path)

func handle_rpc_confirm_hit_tree(tree_path: NodePath) -> void:
	var tree = world.get_node_or_null(tree_path)
	if tree != null:
		tree.perform_hit(World.main_scene)

func handle_rpc_confirm_break_tree(tree_path: NodePath, break_payload: Dictionary) -> void:
	var broken_paths: Array = break_payload.get("broken_paths", [str(tree_path)])
	var drop_names_by_path: Dictionary = break_payload.get("drop_names", {})
	var drop_positions_by_path: Dictionary = break_payload.get("drop_positions", {})
	var land_z_by_path: Dictionary = break_payload.get("land_z", {})

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
			var drop_positions: Array = drop_positions_by_path.get(String(raw_path), [])
			var land_z := int(land_z_by_path.get(String(raw_path), int(tree.get("z_level"))))
			tree.perform_break(log_names, drop_positions, land_z)
		LateJoin.unregister_object(piece_path)

	# Tree drops from upper z-levels must finish their gravity calculation while
	# every broken segment is non-solid. Re-enable a surviving stump only after
	# all pieces have produced their drops, otherwise the stump catches later
	# logs one floor above the player and they disappear on the next FOV refresh.
	for raw_path in broken_paths:
		var survivor_path := NodePath(String(raw_path))
		var survivor = world.get_node_or_null(survivor_path)
		if (
			survivor != null
			and not survivor.is_queued_for_deletion()
			and survivor.has_method("set_solid_enabled")
		):
			survivor.call("set_solid_enabled", true)

func handle_rpc_request_hit_breakable(sender_id: int, obj_path: NodePath) -> void:
	if not world.multiplayer.is_server(): return
	var obj = world.get_node_or_null(obj_path)
	if obj == null: return

	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player): return
	if player.body != null and player.body.is_arm_broken(player.active_hand): return
	if not world.utils.is_within_interaction_range(player, obj.global_position): return
	var hit_strength := _get_material_hit_strength(obj, player.hands[player.active_hand])
	if hit_strength <= 0.0: return
	if not world.utils.server_check_action_cooldown(player, false, 5.0): return

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
