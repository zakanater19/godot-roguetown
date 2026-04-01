# res://scripts/world/objects/world_coins.gd
extends RefCounted

var world: Node

func _init(p_world: Node) -> void:
	world = p_world

func handle_rpc_request_split_coins(sender_id: int, from_hand: int, to_hand: int, split_amount: int) -> void:
	if not world.multiplayer.is_server(): return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if player == null or player.dead: return
	if player.hands[to_hand] != null: return
	var from_item = player.hands[from_hand]
	if from_item == null or from_item.get("is_coin_stack") != true: return
	if from_item.get("amount") <= split_amount or split_amount <= 0: return
	var new_name = "Coin_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000)
	var m_type = from_item.get("metal_type")
	world.rpc_confirm_split_coins.rpc(sender_id, from_hand, to_hand, new_name, split_amount, m_type)

func handle_rpc_confirm_split_coins(peer_id: int, from_hand: int, to_hand: int, new_name: String, split_amount: int, metal_type: int) -> void:
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	if player == null: return
	var from_item = player.hands[from_hand]
	if from_item == null: return
	from_item.amount -= split_amount
	var scene_path = world.get_node("/root/ItemRegistry").get_scene_path(from_item.item_type) if world.has_node("/root/ItemRegistry") else ""
	if scene_path == "": return
	var scene = load(scene_path) as PackedScene
	if scene == null: return
	var new_coin = scene.instantiate()
	new_coin.name = new_name
	new_coin.metal_type = metal_type
	new_coin.amount = split_amount
	player.get_parent().add_child(new_coin)
	for child in new_coin.get_children():
		if child is CollisionShape2D: child.disabled = true
	player.hands[to_hand] = new_coin
	if player._is_local_authority():
		player._update_hands_ui()

func handle_rpc_request_combine_hand_coins(sender_id: int, from_hand: int, to_hand: int) -> void:
	if not world.multiplayer.is_server(): return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if player == null or player.dead: return
	var from_item = player.hands[from_hand]
	var to_item = player.hands[to_hand]
	if from_item == null or to_item == null: return
	if from_item.get("is_coin_stack") != true or to_item.get("is_coin_stack") != true: return
	if from_item.get("item_type") != to_item.get("item_type"): return
	var available_space = 20 - to_item.get("amount")
	if available_space <= 0: return
	var transfer_amt = min(from_item.get("amount"), available_space)
	world.rpc_confirm_combine_hand_coins.rpc(sender_id, from_hand, to_hand, transfer_amt)

func handle_rpc_confirm_combine_hand_coins(peer_id: int, from_hand: int, to_hand: int, amount: int) -> void:
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	if player == null: return
	var from_item = player.hands[from_hand]
	var to_item = player.hands[to_hand]
	if from_item == null or to_item == null: return
	to_item.amount += amount
	from_item.amount -= amount
	if from_item.amount <= 0:
		player.hands[from_hand] = null
		if is_instance_valid(from_item): from_item.queue_free()
	if player._is_local_authority():
		player._update_hands_ui()

func handle_rpc_request_combine_ground_coin(sender_id: int, coin_path: NodePath, hand_idx: int) -> void:
	if not world.multiplayer.is_server(): return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if player == null or player.dead: return
	if not world.utils.server_check_action_cooldown(player): return
	var hand_item = player.hands[hand_idx]
	var ground_coin = world.get_node_or_null(coin_path)
	if hand_item == null or ground_coin == null: return
	if not world.utils.is_within_interaction_range(player, ground_coin.global_position): return
	if hand_item.get("is_coin_stack") != true or ground_coin.get("is_coin_stack") != true: return
	if hand_item.get("item_type") != ground_coin.get("item_type"): return
	var available_space = 20 - hand_item.get("amount")
	if available_space <= 0: return
	var transfer_amt = min(ground_coin.get("amount"), available_space)
	world.rpc_confirm_combine_ground_coin.rpc(sender_id, coin_path, hand_idx, transfer_amt)

func handle_rpc_confirm_combine_ground_coin(peer_id: int, coin_path: NodePath, hand_idx: int, amount: int) -> void:
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	var hand_item = player.hands[hand_idx] if player else null
	if hand_item != null: hand_item.amount += amount
	var ground_coin = world.get_node_or_null(coin_path)
	if ground_coin != null and is_instance_valid(ground_coin):
		ground_coin.amount -= amount
		if ground_coin.amount <= 0:
			if world.has_node("/root/LateJoin"):
				world.get_node("/root/LateJoin").unregister_object(coin_path)
			if is_instance_valid(ground_coin): ground_coin.queue_free()
		else:
			if world.has_node("/root/LateJoin"):
				world.get_node("/root/LateJoin").register_object_state(coin_path, {"amount": ground_coin.amount, "metal_type": ground_coin.metal_type, "type": "coin"})
	if player and player._is_local_authority():
		player._update_hands_ui()
