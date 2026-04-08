# res://scripts/world/objects/world_harvesting.gd
extends RefCounted

var world: Node

func _init(p_world: Node) -> void:
	world = p_world

func handle_rpc_request_hit_rock(sender_id: int, rock_path: NodePath) -> void:
	if not world.multiplayer.is_server(): return
	var rock = world.get_node_or_null(rock_path)
	if rock == null: return

	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player): return
	if player.body != null and player.body.is_arm_broken(player.active_hand): return

	if not world.utils.is_within_interaction_range(player, rock.global_position): return
	if not world.utils.server_check_action_cooldown(player): return

	rock.hits += 1
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

	tree.hits += 1
	LateJoin.register_object_state(tree_path, {"hits": tree.hits, "type": "tree"})

	if tree.hits >= tree.HITS_TO_BREAK:
		var log_names = []
		for i in range(3):
			log_names.append(Defs.make_runtime_name("Log"))
		world.rpc_confirm_break_tree.rpc(tree_path, log_names)
	else:
		world.rpc_confirm_hit_tree.rpc(tree_path)

func handle_rpc_confirm_hit_tree(tree_path: NodePath) -> void:
	var tree = world.get_node_or_null(tree_path)
	if tree != null:
		tree.perform_hit(World.main_scene)

func handle_rpc_confirm_break_tree(tree_path: NodePath, log_names: Array) -> void:
	var tree = world.get_node_or_null(tree_path)
	if tree != null:
		tree.perform_break(log_names)
		LateJoin.unregister_object(tree_path)

func handle_rpc_request_hit_breakable(sender_id: int, obj_path: NodePath) -> void:
	if not world.multiplayer.is_server(): return
	var obj = world.get_node_or_null(obj_path)
	if obj == null: return

	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player): return
	if player.body != null and player.body.is_arm_broken(player.active_hand): return
	if not world.utils.is_within_interaction_range(player, obj.global_position): return
	if not world.utils.server_check_action_cooldown(player): return

	obj.hits += 1
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
