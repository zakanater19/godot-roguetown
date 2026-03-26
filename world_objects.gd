extends RefCounted

var world: Node

func _init(p_world: Node) -> void:
	world = p_world

func drop_item_at(obj: Node2D, tile: Vector2i, spread: float) -> void:
	var drop_offset := Vector2(
		randf_range(-spread, spread),
		randf_range(-spread, spread)
	)
	obj.global_position = world.utils.tile_to_pixel(tile) + drop_offset

func handle_rpc_request_hit_rock(sender_id: int, rock_path: NodePath) -> void:
	if not world.multiplayer.is_server(): return
	var rock = world.get_node_or_null(rock_path)
	if rock == null: return

	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if player == null or player.dead: return
	if player.body != null and player.body.is_arm_broken(player.active_hand): return
	
	if not world.utils.is_within_interaction_range(player, rock.global_position): return
	if not world.utils.server_check_action_cooldown(player): return

	rock.hits += 1
	if world.has_node("/root/LateJoin"):
		world.get_node("/root/LateJoin").register_object_state(rock_path, {"hits": rock.hits, "type": "rock"})
	
	if rock.hits >= rock.HITS_TO_BREAK:
		var drops =["pebble", "pebble"]
		if randf() < 0.20: drops.append("coal")
		if randf() < 0.10: drops.append("ironore")

		var drop_data =[]
		for d in drops:
			drop_data.append({"type": d, "name": "Drop_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000)})
		world.rpc_confirm_break_rock.rpc(rock_path, drop_data)
	else:
		world.rpc_confirm_hit_rock.rpc(rock_path)

func handle_rpc_confirm_hit_rock(rock_path: NodePath) -> void:
	var rock = world.get_node_or_null(rock_path)
	if rock != null:
		var main = world.get_tree().root.get_node_or_null("Main")
		rock.perform_hit(main)

func handle_rpc_confirm_break_rock(rock_path: NodePath, drops_data: Array) -> void:
	var rock = world.get_node_or_null(rock_path)
	if rock != null:
		rock.perform_break(drops_data)
		if world.has_node("/root/LateJoin"):
			world.get_node("/root/LateJoin").unregister_object(rock_path)

func handle_rpc_request_hit_tree(sender_id: int, tree_path: NodePath) -> void:
	if not world.multiplayer.is_server(): return
	var tree = world.get_node_or_null(tree_path)
	if tree == null: return

	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if player == null or player.dead: return
	if player.body != null and player.body.is_arm_broken(player.active_hand): return
	
	if not world.utils.is_within_interaction_range(player, tree.global_position): return
	if not world.utils.server_check_action_cooldown(player): return

	tree.hits += 1
	if world.has_node("/root/LateJoin"):
		world.get_node("/root/LateJoin").register_object_state(tree_path, {"hits": tree.hits, "type": "tree"})
	
	if tree.hits >= tree.HITS_TO_BREAK:
		var log_names =[]
		for i in range(3):
			log_names.append("Log_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000))
		world.rpc_confirm_break_tree.rpc(tree_path, log_names)
	else:
		world.rpc_confirm_hit_tree.rpc(tree_path)

func handle_rpc_confirm_hit_tree(tree_path: NodePath) -> void:
	var tree = world.get_node_or_null(tree_path)
	if tree != null:
		var main = world.get_tree().root.get_node_or_null("Main")
		tree.perform_hit(main)

func handle_rpc_confirm_break_tree(tree_path: NodePath, log_names: Array) -> void:
	var tree = world.get_node_or_null(tree_path)
	if tree != null:
		tree.perform_break(log_names)
		if world.has_node("/root/LateJoin"):
			world.get_node("/root/LateJoin").unregister_object(tree_path)

func handle_rpc_request_hit_breakable(sender_id: int, obj_path: NodePath) -> void:
	if not world.multiplayer.is_server(): return
	var obj = world.get_node_or_null(obj_path)
	if obj == null: return

	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if player == null or player.dead: return
	if player.body != null and player.body.is_arm_broken(player.active_hand): return
	if not world.utils.is_within_interaction_range(player, obj.global_position): return
	if not world.utils.server_check_action_cooldown(player): return

	obj.hits += 1
	if world.has_node("/root/LateJoin"):
		world.get_node("/root/LateJoin").register_object_state(obj_path, {"hits": obj.hits, "type": "breakable"})
	
	if obj.hits >= obj.HITS_TO_BREAK:
		world.rpc_confirm_break_breakable.rpc(obj_path)
	else:
		world.rpc_confirm_hit_breakable.rpc(obj_path)

func handle_rpc_confirm_hit_breakable(obj_path: NodePath) -> void:
	var obj = world.get_node_or_null(obj_path)
	if obj != null and obj.has_method("perform_hit"):
		var main = world.get_tree().root.get_node_or_null("Main")
		obj.perform_hit(main)

func handle_rpc_confirm_break_breakable(obj_path: NodePath) -> void:
	var obj = world.get_node_or_null(obj_path)
	if obj != null and obj.has_method("perform_break"):
		obj.perform_break()
		if world.has_node("/root/LateJoin"):
			world.get_node("/root/LateJoin").unregister_object(obj_path)

func handle_rpc_request_hit_door(sender_id: int, door_path: NodePath) -> void:
	if not world.multiplayer.is_server(): return
	var door = world.get_node_or_null(door_path)
	if door == null: return

	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if player == null or player.dead: return
	if player.body != null and player.body.is_arm_broken(player.active_hand): return
	if not world.utils.is_within_interaction_range(player, door.global_position): return
	
	var held_item = player.hands[player.active_hand]
	if held_item == null:
		if door.state != door.DoorState.DESTROYED:
			world.rpc_confirm_toggle_door.rpc(door_path)
	else:
		var i_type = held_item.get("item_type")
		var is_sword = (i_type == "Sword") or ("Sword" in held_item.name) or ("sword" in held_item.name.to_lower()) or (i_type == "Dirk") or ("Dirk" in held_item.name) or ("dirk" in held_item.name.to_lower())
		var is_pickaxe = (i_type == "Pickaxe") or ("Pickaxe" in held_item.name) or ("pickaxe" in held_item.name.to_lower())
		
		if is_sword or (is_pickaxe and player.combat_mode):
			if not world.utils.server_check_action_cooldown(player): return
			door.hits += 1
			if door.hits >= door.HITS_TO_BREAK * 2:
				world.rpc_confirm_remove_door.rpc(door_path)
			elif door.hits == door.HITS_TO_BREAK:
				world.rpc_confirm_destroy_door.rpc(door_path)
			else:
				world.rpc_confirm_hit_door.rpc(door_path)

func handle_rpc_confirm_toggle_door(_door_path: NodePath) -> void:
	var door = world.get_node_or_null(_door_path)
	if door != null:
		door.toggle_door()

func handle_rpc_confirm_hit_door(door_path: NodePath) -> void:
	var door = world.get_node_or_null(door_path)
	if door != null:
		var main = world.get_tree().root.get_node_or_null("Main")
		door.perform_hit(main)

func handle_rpc_confirm_destroy_door(door_path: NodePath) -> void:
	var door = world.get_node_or_null(door_path)
	if door != null:
		var main = world.get_tree().root.get_node_or_null("Main")
		door.perform_hit(main)
		door.destroy_door()

func handle_rpc_confirm_remove_door(door_path: NodePath) -> void:
	var door = world.get_node_or_null(door_path)
	if door != null:
		var main = world.get_tree().root.get_node_or_null("Main")
		door.perform_hit(main)
		door.remove_completely()

func handle_rpc_request_interact_hand_item(sender_id: int, hand_idx: int) -> void:
	if not world.multiplayer.is_server() or hand_idx < 0 or hand_idx > 1: return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if player == null or player.dead: return
	if player.body != null and player.body.is_arm_broken(hand_idx): return
	var item = player.hands[hand_idx]
	if item == null or not is_instance_valid(item) or not item.has_method("interact_in_hand"): return
	if not world.utils.server_check_action_cooldown(player): return
	world.rpc_confirm_interact_hand_item.rpc(sender_id, hand_idx)

func handle_rpc_confirm_interact_hand_item(peer_id: int, hand_idx: int) -> void:
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	if player != null:
		var item = player.hands[hand_idx]
		if item != null and is_instance_valid(item) and item.has_method("interact_in_hand"):
			item.interact_in_hand(player)

func handle_rpc_request_equip(sender_id: int, item_path: NodePath, slot_name: String, hand_index: int) -> void:
	if not world.multiplayer.is_server() or hand_index < 0 or hand_index > 1: return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if player == null or player.dead: return
	if player.body != null and player.body.is_arm_broken(hand_index): return
	var item = world.get_node_or_null(item_path)
	if item == null or player.hands[hand_index] != item: return
	world.rpc_confirm_equip.rpc(sender_id, item_path, slot_name, hand_index)

func handle_rpc_confirm_equip(peer_id: int, item_path: NodePath, slot_name: String, hand_index: int) -> void:
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	var obj    = world.get_node_or_null(item_path)
	if player != null and obj != null:
		player._perform_equip(obj, slot_name, hand_index)

func handle_rpc_request_unequip(sender_id: int, slot_name: String, hand_index: int) -> void:
	if not world.multiplayer.is_server() or hand_index < 0 or hand_index > 1: return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if player == null or player.dead: return
	if player.body != null and player.body.is_arm_broken(hand_index): return
	var unique_name = "Unequip_" + slot_name + "_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000)
	world.rpc_confirm_unequip.rpc(sender_id, slot_name, unique_name, hand_index)

func handle_rpc_confirm_unequip(peer_id: int, slot_name: String, new_node_name: String, hand_index: int) -> void:
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	if player != null:
		player._perform_unequip(slot_name, new_node_name, hand_index)

func handle_rpc_request_furnace_action(sender_id: int, furnace_path: NodePath, action: String, hand_idx: int) -> void:
	if not world.multiplayer.is_server() or hand_idx < 0 or hand_idx > 1: return
	var furnace = world.get_node_or_null(furnace_path)
	if furnace == null: return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if player == null or player.dead: return
	if player.body != null and player.body.is_arm_broken(hand_idx): return
	if not world.utils.is_within_interaction_range(player, furnace.global_position): return
	
	if action.begins_with("insert_") and player.hands[hand_idx] == null: return
	if action == "eject":
		var names =[]
		var total = furnace._coal_count + furnace._ironore_count
		for i in total: names.append("Eject_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000))
		world.rpc_confirm_furnace_action.rpc(sender_id, furnace_path, action, hand_idx, names)
	else:
		world.rpc_confirm_furnace_action.rpc(sender_id, furnace_path, action, hand_idx,[])

func handle_rpc_confirm_furnace_action(peer_id: int, furnace_path: NodePath, action: String, hand_idx: int, generated_names: Array) -> void:
	var player: Node2D  = world.utils.find_player_by_peer(peer_id) as Node2D
	var furnace = world.get_node_or_null(furnace_path)
	if furnace != null:
		furnace._perform_action(action, player, hand_idx, generated_names)

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
				world.get_node("/root/LateJoin").register_object_state(coin_path, {"amount": ground_coin.amount, "type": "coin"})
	if player and player._is_local_authority():
		player._update_hands_ui()

func handle_rpc_request_pickup(sender_id: int, item_path: NodePath, hand_index: int) -> void:
	if not world.multiplayer.is_server() or hand_index < 0 or hand_index > 1: return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if player == null or player.dead: return
	if player.body != null and player.body.is_arm_broken(hand_index): return
	var item = world.get_node_or_null(item_path)
	if item == null: return
	if not world.utils.is_within_interaction_range(player, item.global_position): return
	world.rpc_confirm_pickup.rpc(sender_id, item_path, hand_index)

func handle_rpc_confirm_pickup(peer_id: int, item_path: NodePath, hand_index: int) -> void:
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	var obj    = world.get_node_or_null(item_path)
	if player == null or obj == null: return
	player.hands[hand_index] = obj
	for child in obj.get_children():
		if child is CollisionShape2D: child.disabled = true
	if player._is_local_authority():
		player._update_hands_ui()

func handle_rpc_request_drop(sender_id: int, item_path: NodePath, tile: Vector2i, spread: float, hand_index: int) -> void:
	if not world.multiplayer.is_server() or hand_index < 0 or hand_index > 1: return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if player == null or player.dead: return
	var item = world.get_node_or_null(item_path)
	if item == null or player.hands[hand_index] != item: return
	var diff = (tile - player.tile_pos).abs()
	if diff.x > 1 or diff.y > 1: return
	world.rpc_drop_item_at.rpc(sender_id, item_path, tile, spread, hand_index)

func handle_rpc_drop_item_at(peer_id: int, item_path: NodePath, tile: Vector2i, spread: float, hand_index: int) -> void:
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	if player != null:
		player.hands[hand_index] = null
		if player._is_local_authority():
			player._update_hands_ui()
	var obj := world.get_node_or_null(item_path)
	if obj == null: return
	var sprite: Node = obj.get_node_or_null("Sprite2D")
	if sprite != null:
		sprite.rotation_degrees = 0.0
		sprite.scale = Vector2(abs(sprite.scale.x), abs(sprite.scale.y))
	
	var land_z = world.calculate_gravity_z(tile, player.z_level if player else obj.get("z_level"))
	world.rpc_set_object_z_level.rpc(item_path, land_z)
	
	drop_item_at(obj, tile, spread)
	for child in obj.get_children():
		if child is CollisionShape2D: child.disabled = false

func handle_rpc_request_throw(sender_id: int, item_path: NodePath, hand_index: int, dir: Vector2, throw_range: int) -> void:
	if not world.multiplayer.is_server() or hand_index < 0 or hand_index > 1: return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if player == null or player.dead: return
	var item = world.get_node_or_null(item_path)
	if item == null or player.hands[hand_index] != item: return
	if player.body != null and player.body.is_arm_broken(hand_index): return
	if not world.utils.server_check_action_cooldown(player, true): return
	var safe_range = int(clamp(throw_range, 1, player.THROW_TILES))
	var land_tile = world.utils.cast_throw(player.tile_pos, player.pixel_pos, player.z_level, dir, safe_range)
	var land_z = world.calculate_gravity_z(land_tile, player.z_level)
	var land_pixel = world.utils.tile_to_pixel(land_tile)
	world.rpc_confirm_throw.rpc(sender_id, item_path, hand_index, land_pixel, land_z)

func handle_rpc_confirm_throw(peer_id: int, item_path: NodePath, hand_index: int, land_pixel: Vector2, land_z: int) -> void:
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	var obj    = world.get_node_or_null(item_path)
	if player == null or obj == null: return
	player.hands[hand_index] = null
	if player._is_local_authority():
		player._is_throwing = true
		player._update_hands_ui()
	var z_lvl = player.z_level
	obj.z_index = (z_lvl - 1) * 200 + 7
	var sprite: Node = obj.get_node_or_null("Sprite2D")
	if sprite != null:
		sprite.rotation_degrees = 0.0
		sprite.scale = Vector2(abs(sprite.scale.x), abs(sprite.scale.y))
	var spread_offset := Vector2(randf_range(-player.DROP_SPREAD, player.DROP_SPREAD), randf_range(-player.DROP_SPREAD, player.DROP_SPREAD))
	var final_pos := land_pixel + spread_offset
	var tween = world.get_tree().create_tween()
	tween.tween_property(obj, "global_position", final_pos, player.THROW_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		if player and player._is_local_authority(): player._is_throwing = false
		
		obj.set("z_level", land_z)
		obj.z_index = (land_z - 1) * 200 + (obj.z_index % 200)
		
		for child in obj.get_children():
			if child is CollisionShape2D: child.disabled = false
		if world.multiplayer.is_server():
			var land_tile_check = Vector2i(int(land_pixel.x / world.TILE_SIZE), int(land_pixel.y / world.TILE_SIZE))
			var dmg = player._get_weapon_damage(obj) if player else 0
			var attacker_p    := world.utils.find_player_by_peer(peer_id) as Node2D
			var src_tile: Vector2i = attacker_p.tile_pos if attacker_p != null else land_tile_check
			var hit_results = world.combat.deal_damage_at_tile(land_tile_check, land_z, dmg, peer_id, false)
			var throw_targets = world.utils.get_entities_at_tile(land_tile_check, land_z, peer_id)
			for entity in throw_targets:
				var target_name: String = ""
				if entity.is_in_group("player"): target_name = (entity as Node2D).character_name
				elif entity.has_method("receive_damage"): target_name = entity.name.get_slice("@", 0)
				if target_name != "":
					var roll = hit_results.get(entity, {"damage": dmg, "blocked": false})
					world.rpc_broadcast_damage_log.rpc(attacker_p.character_name if attacker_p else "Unknown", target_name, roll.damage, src_tile, land_z, roll.blocked, false, "", roll.get("block_type", ""))
	)

func handle_rpc_notify_loot_warning(target_peer_id: int, looter_peer_id: int, item_desc: String) -> void:
	if not world.multiplayer.is_server(): return
	var looter: Node2D = world.utils.find_player_by_peer(looter_peer_id) as Node2D
	if looter == null or looter.dead: return
	if target_peer_id == 1: world.rpc_deliver_loot_warning(looter_peer_id, item_desc)
	elif target_peer_id in world.multiplayer.get_peers(): world.rpc_deliver_loot_warning.rpc_id(target_peer_id, looter_peer_id, item_desc)

func handle_rpc_deliver_loot_warning(looter_peer_id: int, item_desc: String) -> void:
	var local_player: Node2D = world.utils.get_local_player() as Node2D
	if local_player != null and local_player.has_method("show_loot_warning"):
		local_player.show_loot_warning(looter_peer_id, item_desc)

func handle_rpc_request_loot_item(sender_id: int, target_peer_id: int, looter_peer_id: int, slot_type: String, slot_index: Variant) -> void:
	if not world.multiplayer.is_server() or sender_id != looter_peer_id: return
	var target: Node2D = world.utils.find_player_by_peer(target_peer_id) as Node2D
	var looter: Node2D = world.utils.find_player_by_peer(looter_peer_id) as Node2D
	if target == null or looter == null or looter.dead: return
	var diff: Vector2i = (target.tile_pos - looter.tile_pos).abs()
	if diff.x > 1 or diff.y > 1 or target.z_level != looter.z_level: return

	var drop_tile: Vector2i = target.tile_pos
	const SPREAD: float = 14.0

	if slot_type == "hand":
		var idx: int  = int(slot_index)
		var obj: Node = target.hands[idx]
		if obj == null or not is_instance_valid(obj): return
		world.rpc_drop_item_at.rpc(target_peer_id, obj.get_path(), drop_tile, SPREAD, idx)
	elif slot_type == "equip":
		var equip_slot: String = str(slot_index)
		var item_name: String  = target.equipped.get(equip_slot, "")
		if item_name == "": return
		var new_name := "Loot_" + equip_slot + "_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000)
		world.rpc_confirm_loot_unequip_drop.rpc(target_peer_id, equip_slot, new_name, drop_tile, SPREAD)

func handle_rpc_confirm_loot_unequip_drop(target_peer_id: int, equip_slot: String, new_node_name: String, drop_tile: Vector2i, spread: float) -> void:
	var target: Node2D = world.utils.find_player_by_peer(target_peer_id) as Node2D
	if target == null: return
	var item_name: String = target.equipped.get(equip_slot, "")
	if item_name == "": return
	
	var scene_path = ""
	if world.has_node("/root/ItemRegistry"):
		scene_path = world.get_node("/root/ItemRegistry").get_scene_path(item_name)
	if scene_path == "": return
	var scene := load(scene_path) as PackedScene
	if scene == null: return

	target.equipped[equip_slot] = null
	target._update_clothing_sprites()

	if target._is_local_authority():
		if target._hud != null:
			target._hud.update_clothing_display(target.equipped)

	var item: Node2D = scene.instantiate()
	item.name        = new_node_name
	item.position    = world.utils.tile_to_pixel(drop_tile)
	
	var land_z = world.calculate_gravity_z(drop_tile, target.z_level)
	item.set("z_level", land_z)
	
	if "equipped_data" in target and target.equipped_data.get(equip_slot) != null:
		if "contents" in target.equipped_data[equip_slot] and "contents" in item:
			item.set("contents", target.equipped_data[equip_slot]["contents"].duplicate(true))
		target.equipped_data[equip_slot] = null
		
	target.get_parent().add_child(item)
	drop_item_at(item, drop_tile, spread)
	for child in item.get_children():
		if child is CollisionShape2D: child.disabled = false

func handle_rpc_request_craft(sender_id: int, looter_peer_id: int, recipe_id: String) -> void:
	if not world.multiplayer.is_server() or sender_id != looter_peer_id: return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if player == null or player.dead: return
		
	var recipes = {
		"sword": {"req": "IronIngot", "req_amt": 1, "scene": "res://objects/sword.tscn"},
		"pickaxe": {"req": "IronIngot", "req_amt": 1, "scene": "res://objects/pickaxe.tscn"},
		"wooden_floor": {"req": "Log", "req_amt": 1, "tile": [0, Vector2i(4, 0)]},
		"cobble_floor": {"req": "Pebble", "req_amt": 1, "tile":[0, Vector2i(5, 0)]},
		"stone_wall": {"req": "Pebble", "req_amt": 2, "tile":[1, Vector2i(6, 0)]}
	}
	if not recipes.has(recipe_id): return
	var recipe = recipes[recipe_id]
	
	var avail =[]
	for i in range(2):
		if player.hands[i] != null: avail.append(player.hands[i])
			
	for obj in world.get_tree().get_nodes_in_group("pickable"):
		if obj == player.hands[0] or obj == player.hands[1]: continue
		if obj.get("z_level") != null and obj.z_level != player.z_level: continue
		var obj_tile = Vector2i(int(obj.global_position.x / world.TILE_SIZE), int(obj.global_position.y / world.TILE_SIZE))
		var diff = (obj_tile - player.tile_pos).abs()
		if diff.x <= 1 and diff.y <= 1:
			avail.append(obj)
			
	var matched_nodes =[]
	var req_type = recipe["req"]
	var req_amt  = recipe["req_amt"]
	
	for obj in avail:
		if matched_nodes.size() >= req_amt: break
		var itype = obj.get("item_type") if obj.get("item_type") != null else obj.name.get_slice("@", 0)
		if itype == req_type: matched_nodes.append(obj)
			
	if matched_nodes.size() < req_amt: return
	var result_name = "Craft_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000)
	var consumed_paths =[]
	for n in matched_nodes: consumed_paths.append(n.get_path())
		
	if recipe.has("scene"):
		world.rpc_confirm_craft_item.rpc(sender_id, consumed_paths, recipe["scene"], result_name, player.tile_pos)
	elif recipe.has("tile"):
		var tile_data = recipe["tile"]
		world.rpc_confirm_craft_tile.rpc(sender_id, consumed_paths, player.tile_pos, player.z_level, tile_data[0], tile_data[1])

func handle_rpc_confirm_craft_item(peer_id: int, consumed_paths: Array, scene_path: String, result_name: String, drop_tile: Vector2i) -> void:
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	for p in consumed_paths:
		var n = world.get_node_or_null(p)
		if n != null:
			if player != null:
				for i in range(2):
					if player.hands[i] == n:
						player.hands[i] = null
						if player._is_local_authority(): player._update_hands_ui()
						break
			n.queue_free()
			
	var scene = load(scene_path) as PackedScene
	if scene == null: return
	var item: Node2D = scene.instantiate()
	item.name = result_name
	
	if player != null:
		var land_z = world.calculate_gravity_z(drop_tile, player.z_level)
		item.set("z_level", land_z)
	
	var main = world.get_tree().root.get_node_or_null("Main")
	if main:
		main.add_child(item)
		drop_item_at(item, drop_tile, 14.0)
		for child in item.get_children():
			if child is CollisionShape2D: child.disabled = false

func handle_rpc_confirm_craft_tile(peer_id: int, consumed_paths: Array, tile_pos: Vector2i, z_level: int, source_id: int, atlas_coords: Vector2i) -> void:
	for p in consumed_paths:
		var n = world.get_node_or_null(p)
		if n != null:
			var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
			if player != null:
				for i in range(2):
					if player.hands[i] == n:
						player.hands[i] = null
						if player._is_local_authority(): player._update_hands_ui()
						break
			n.queue_free()
			
	var tm = world.get_tilemap(z_level)
	if tm != null:
		tm.set_cell(tile_pos, source_id, atlas_coords)
		if world.has_node("/root/LateJoin"):
			world.get_node("/root/LateJoin").register_tile_change(tile_pos, source_id, atlas_coords)

func handle_rpc_request_satchel_insert(sender_id: int, satchel_path: NodePath, hand_idx: int) -> void:
	if not world.multiplayer.is_server() or hand_idx < 0 or hand_idx > 1: return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if player == null or player.dead: return
	var satchel := world.get_node_or_null(satchel_path)
	if satchel == null or satchel.get("z_level") != player.z_level: return
	if not world.utils.is_within_interaction_range(player, satchel.global_position): return
	var item: Node = player.hands[hand_idx]
	if item == null or not is_instance_valid(item): return
	var itype: String = item.get("item_type") if item.get("item_type") != null else item.name.get_slice("@", 0)
	
	var scene_path = ""
	if world.has_node("/root/ItemRegistry"):
		scene_path = world.get_node("/root/ItemRegistry").get_scene_path(itype)
	if scene_path == "": return

	var slot_index: int = -1
	for i in satchel.contents.size():
		if satchel.contents[i] == null:
			slot_index = i
			break
	if slot_index == -1: return

	world.rpc_confirm_satchel_insert.rpc(sender_id, satchel_path, item.get_path(), hand_idx, slot_index, scene_path, itype)

func handle_rpc_confirm_satchel_insert(peer_id: int, satchel_path: NodePath, _item_path: NodePath, hand_idx: int, slot_index: int, scene_path: String, itype: String) -> void:
	var satchel: Node = world.get_node_or_null(satchel_path)
	if satchel == null: return
	if slot_index >= 0 and slot_index < satchel.contents.size():
		satchel.contents[slot_index] = {"scene_path": scene_path, "item_type": itype}
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	if player != null:
		if player.hands[hand_idx] != null and is_instance_valid(player.hands[hand_idx]):
			player.hands[hand_idx].queue_free()
		player.hands[hand_idx] = null
		if player._is_local_authority():
			player._update_hands_ui()
	if satchel.has_method("_refresh_ui"): satchel._refresh_ui()

func handle_rpc_request_satchel_extract(sender_id: int, satchel_path: NodePath, slot_index: int, hand_idx: int) -> void:
	if not world.multiplayer.is_server() or hand_idx < 0 or hand_idx > 1: return
	if slot_index < 0 or slot_index >= 10: return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if player == null or player.dead: return
	if player.hands[hand_idx] != null: return
	if player.body != null and player.body.is_arm_broken(hand_idx): return
	var satchel := world.get_node_or_null(satchel_path)
	if satchel == null or satchel.get("z_level") != player.z_level: return
	if not world.utils.is_within_interaction_range(player, satchel.global_position): return
	if slot_index >= satchel.contents.size(): return
	var slot = satchel.contents[slot_index]
	if slot == null: return
	var scene_path: String = slot.get("scene_path", "")
	if scene_path == "": return
	var new_node_name: String = "SatchelExtract_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000)
	world.rpc_confirm_satchel_extract.rpc(sender_id, satchel_path, slot_index, hand_idx, new_node_name, scene_path)

func handle_rpc_confirm_satchel_extract(peer_id: int, satchel_path: NodePath, slot_index: int, hand_idx: int, new_node_name: String, scene_path: String) -> void:
	var satchel: Node = world.get_node_or_null(satchel_path)
	if satchel == null: return
	if slot_index >= 0 and slot_index < satchel.contents.size():
		satchel.contents[slot_index] = null
	var scene := load(scene_path) as PackedScene
	if scene == null: return
	var item: Node2D = scene.instantiate()
	item.name = new_node_name
	item.position = satchel.global_position
	item.set("z_level", satchel.z_level)
	satchel.get_parent().add_child(item)
	for child in item.get_children():
		if child is CollisionShape2D: child.disabled = true
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	if player != null:
		player.hands[hand_idx] = item
		if player._is_local_authority():
			player._update_hands_ui()
	if satchel.has_method("_refresh_ui"): satchel._refresh_ui()
