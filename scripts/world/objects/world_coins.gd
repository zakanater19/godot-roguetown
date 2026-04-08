# res://scripts/world/objects/world_coins.gd
extends RefCounted

var world: Node

func _init(p_world: Node) -> void:
	world = p_world

func handle_rpc_request_split_coins(sender_id: int, from_hand: int, to_hand: int, split_amount: int) -> void:
	if not world.multiplayer.is_server(): return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if player == null or player.dead: return
	if not Defs.is_valid_hand_index(from_hand) or not Defs.is_valid_hand_index(to_hand): return
	if player.hands[to_hand] != null: return
	var from_item = player.hands[from_hand]
	if from_item == null or from_item.get("is_coin_stack") != true: return
	if from_item.get("amount") <= split_amount or split_amount <= 0: return
	var new_name = Defs.make_runtime_name("Coin")
	var m_type = from_item.get("metal_type")
	world.rpc_confirm_split_coins.rpc(sender_id, from_hand, to_hand, new_name, split_amount, m_type)

func handle_rpc_confirm_split_coins(peer_id: int, from_hand: int, to_hand: int, new_name: String, split_amount: int, metal_type: int) -> void:
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	if player == null: return
	var from_item = player.hands[from_hand]
	if from_item == null: return
	from_item.amount -= split_amount
	var scene_path = ItemRegistry.get_scene_path(from_item.item_type)
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
	if not Defs.is_valid_hand_index(from_hand) or not Defs.is_valid_hand_index(to_hand): return
	var from_item = player.hands[from_hand]
	var to_item = player.hands[to_hand]
	if from_item == null or to_item == null: return
	if from_item.get("is_coin_stack") != true or to_item.get("is_coin_stack") != true: return
	if from_item.get("item_type") != to_item.get("item_type"): return
	var available_space = Defs.MAX_COIN_STACK - to_item.get("amount")
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

func handle_rpc_request_combine_ground_coin(sender_id: int, coin_id: String, hand_idx: int) -> void:
	if not world.multiplayer.is_server(): return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if player == null or player.dead: return
	if not Defs.is_valid_hand_index(hand_idx): return
	if not world.utils.server_check_action_cooldown(player): return
	var hand_item = player.hands[hand_idx]
	var ground_coin = world.get_entity(coin_id)
	if hand_item == null or ground_coin == null: return
	if not world.utils.is_within_interaction_range(player, ground_coin.global_position): return
	if hand_item.get("is_coin_stack") != true or ground_coin.get("is_coin_stack") != true: return
	if hand_item.get("item_type") != ground_coin.get("item_type"): return
	var available_space = Defs.MAX_COIN_STACK - hand_item.get("amount")
	if available_space <= 0: return
	var transfer_amt = min(ground_coin.get("amount"), available_space)
	world.rpc_confirm_combine_ground_coin.rpc(sender_id, coin_id, hand_idx, transfer_amt)

func handle_rpc_confirm_combine_ground_coin(peer_id: int, coin_id: String, hand_idx: int, amount: int) -> void:
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	var hand_item = player.hands[hand_idx] if player else null
	if hand_item != null: hand_item.amount += amount
	var ground_coin = world.get_entity(coin_id)
	if ground_coin != null and is_instance_valid(ground_coin):
		ground_coin.amount -= amount
		if ground_coin.amount <= 0:
			LateJoin.unregister_object(NodePath(coin_id))
			world.unregister_entity(ground_coin)
			if is_instance_valid(ground_coin): ground_coin.queue_free()
		else:
			LateJoin.register_object_state(NodePath(coin_id), {"amount": ground_coin.amount, "metal_type": ground_coin.metal_type, "type": "coin"})
	if player and player._is_local_authority():
		player._update_hands_ui()
