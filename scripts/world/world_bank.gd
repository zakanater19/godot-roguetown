extends RefCounted

const DEFAULT_STARTING_BALANCE: int = 100

var world: Node
var accounts: Dictionary = {}

func _init(p_world: Node) -> void:
	world = p_world

func clear_accounts() -> void:
	accounts.clear()

func get_balance_for_player(player: Node) -> int:
	return int(_ensure_account(player).get("balance", DEFAULT_STARTING_BALANCE))

func handle_rpc_request_atm_open(sender_id: int, atm_id: String) -> void:
	if not world.multiplayer.is_server():
		return

	var player := world.utils.find_player_by_peer(sender_id) as Node2D
	var atm := _get_atm_node(atm_id)
	if not _can_player_use_atm(player, atm):
		return
	if not _can_use_open_hand(player):
		_send_error(sender_id, "You need an open hand to use the ATM.")
		return

	world.rpc_show_atm_menu.rpc_id(sender_id, atm_id, get_balance_for_player(player))

func handle_rpc_show_atm_menu(atm_id: String, balance: int) -> void:
	var atm := _get_atm_node(atm_id)
	if atm != null and atm.has_method("_show_atm_menu"):
		atm._show_atm_menu(balance)

func handle_rpc_request_atm_deposit(sender_id: int, atm_id: String, metal_type: int, coin_amount: int) -> void:
	if not world.multiplayer.is_server():
		return

	var player := world.utils.find_player_by_peer(sender_id) as Node2D
	var atm := _get_atm_node(atm_id)
	if not _can_player_use_atm(player, atm):
		return
	if not _can_use_open_hand(player):
		_send_error(sender_id, "You need an open hand to use the ATM.")
		return
	if not _is_valid_metal_type(metal_type) or coin_amount <= 0:
		return

	var available := _count_held_coins(player, metal_type)
	if available < coin_amount:
		_send_error(sender_id, "You do not have enough %s coins to deposit." % _get_metal_name(metal_type))
		return

	var value := coin_amount * Defs.get_coin_value(metal_type)
	var new_balance := get_balance_for_player(player) + value
	_set_balance_for_player(player, new_balance)

	world.rpc_confirm_atm_deposit.rpc(sender_id, metal_type, coin_amount)
	world.rpc_update_atm_balance.rpc_id(sender_id, atm_id, new_balance)
	world.rpc_send_direct_message.rpc_id(
		sender_id,
		"[color=#aaffaa]Deposited %d %s coin(s). New balance: %d.[/color]" % [coin_amount, _get_metal_name(metal_type), new_balance]
	)

func handle_rpc_request_atm_hand_deposit(sender_id: int, atm_id: String, hand_idx: int) -> void:
	if not world.multiplayer.is_server():
		return

	var player := world.utils.find_player_by_peer(sender_id) as Node2D
	var atm := _get_atm_node(atm_id)
	if not _can_player_use_atm(player, atm):
		return
	if not Defs.is_valid_hand_index(hand_idx):
		return
	if player.body != null and player.body.is_arm_broken(hand_idx):
		_send_error(sender_id, "That arm is useless.")
		return

	var hand_item = player.hands[hand_idx]
	if hand_item == null or not is_instance_valid(hand_item):
		return
	if hand_item.get("is_coin_stack") != true:
		_send_error(sender_id, "That cannot be deposited in the ATM.")
		return

	var metal_type := int(hand_item.get("metal_type"))
	var coin_amount := int(hand_item.get("amount"))
	if not _is_valid_metal_type(metal_type) or coin_amount <= 0:
		return

	var value := coin_amount * Defs.get_coin_value(metal_type)
	var new_balance := get_balance_for_player(player) + value
	_set_balance_for_player(player, new_balance)

	world.rpc_confirm_atm_hand_deposit.rpc(sender_id, hand_idx, coin_amount)
	world.rpc_update_atm_balance.rpc_id(sender_id, atm_id, new_balance)
	world.rpc_send_direct_message.rpc_id(
		sender_id,
		"[color=#aaffaa]Deposited %d %s coin(s). New balance: %d.[/color]" % [coin_amount, _get_metal_name(metal_type), new_balance]
	)

func handle_rpc_confirm_atm_deposit(peer_id: int, metal_type: int, coin_amount: int) -> void:
	var player := world.utils.find_player_by_peer(peer_id) as Node2D
	if player == null:
		return

	_remove_held_coins(player, metal_type, coin_amount)
	if player._is_local_authority():
		player._update_hands_ui()

func handle_rpc_confirm_atm_hand_deposit(peer_id: int, hand_idx: int, coin_amount: int) -> void:
	var player := world.utils.find_player_by_peer(peer_id) as Node2D
	if player == null:
		return
	if not Defs.is_valid_hand_index(hand_idx):
		return

	var hand_item = player.hands[hand_idx]
	if hand_item == null or not is_instance_valid(hand_item):
		return
	if hand_item.get("is_coin_stack") != true:
		return

	hand_item.amount = int(hand_item.get("amount")) - coin_amount
	if int(hand_item.get("amount")) <= 0:
		player.hands[hand_idx] = null
		hand_item.queue_free()
	if player._is_local_authority():
		player._update_hands_ui()

func handle_rpc_request_atm_withdraw(sender_id: int, atm_id: String, metal_type: int, coin_amount: int, preferred_hand: int) -> void:
	if not world.multiplayer.is_server():
		return

	var player := world.utils.find_player_by_peer(sender_id) as Node2D
	var atm := _get_atm_node(atm_id)
	if not _can_player_use_atm(player, atm):
		return
	if not _can_use_open_hand(player):
		_send_error(sender_id, "You need an open hand to use the ATM.")
		return
	if not _is_valid_metal_type(metal_type) or coin_amount <= 0:
		return

	var cost := coin_amount * Defs.get_coin_value(metal_type)
	var current_balance := get_balance_for_player(player)
	if cost > current_balance:
		_send_error(sender_id, "You cannot withdraw more than your balance.")
		return

	var safe_hand: int = preferred_hand if Defs.is_valid_hand_index(preferred_hand) else player.active_hand
	var payload := _build_withdraw_payload(player, metal_type, coin_amount, safe_hand, atm.global_position, atm.z_level)
	var new_balance := current_balance - cost
	_set_balance_for_player(player, new_balance)

	world.rpc_confirm_atm_withdraw.rpc(sender_id, metal_type, payload)
	world.rpc_update_atm_balance.rpc_id(sender_id, atm_id, new_balance)
	world.rpc_send_direct_message.rpc_id(
		sender_id,
		"[color=#aaffaa]Withdrew %d %s coin(s). New balance: %d.[/color]" % [coin_amount, _get_metal_name(metal_type), new_balance]
	)

func handle_rpc_confirm_atm_withdraw(peer_id: int, metal_type: int, payload: Array) -> void:
	var player := world.utils.find_player_by_peer(peer_id) as Node2D
	if player == null:
		return

	_apply_withdraw_payload(player, metal_type, payload)
	if player._is_local_authority():
		player._update_hands_ui()

func handle_rpc_update_atm_balance(atm_id: String, balance: int) -> void:
	var atm := _get_atm_node(atm_id)
	if atm != null and atm.has_method("_update_atm_balance"):
		atm._update_atm_balance(balance)

func _ensure_account(player: Node) -> Dictionary:
	if player == null:
		return {}

	var key := _get_account_key_for_player(player)
	if key == "":
		return {}

	var current_name := str(player.get("character_name") if player.get("character_name") != null else "")
	var current_class := str(player.get("character_class") if player.get("character_class") != null else "peasant")
	var account: Dictionary = accounts.get(key, {})
	if account.is_empty():
		account = {
			"display_name": current_name,
			"class": current_class,
			"balance": _get_starting_balance_for_player(player),
		}
	else:
		account["display_name"] = current_name
		account["class"] = current_class

	accounts[key] = account
	return account

func _set_balance_for_player(player: Node, new_balance: int) -> void:
	var key := _get_account_key_for_player(player)
	if key == "":
		return

	var account := _ensure_account(player)
	account["balance"] = maxi(0, new_balance)
	accounts[key] = account

func _get_starting_balance_for_player(player: Node) -> int:
	var class_id := str(player.get("character_class") if player.get("character_class") != null else "peasant")
	var class_data: Dictionary = Classes.DATA.get(class_id, Classes.DATA.get("peasant", {}))
	return maxi(0, int(class_data.get("starting_money", DEFAULT_STARTING_BALANCE)))

func _get_account_key_for_player(player: Node) -> String:
	if player == null:
		return ""

	var raw_name := str(player.get("character_name") if player.get("character_name") != null else "")
	return raw_name.strip_edges().to_lower()

func _get_atm_node(atm_id: String) -> Node2D:
	var atm := world.get_entity(atm_id) as Node2D
	if atm == null or not is_instance_valid(atm):
		return null
	if atm.get("is_atm_machine") != true:
		return null
	return atm

func _can_player_use_atm(player: Node2D, atm: Node2D) -> bool:
	return (
		player != null
		and atm != null
		and world.utils.can_player_interact(player)
		and player.z_level == atm.z_level
		and world.utils.is_within_interaction_range(player, atm.global_position)
	)

func _can_use_open_hand(player: Node2D) -> bool:
	if player == null:
		return false
	if not Defs.is_valid_hand_index(player.active_hand):
		return false
	if player.hands[player.active_hand] != null:
		return false
	return player.body == null or not player.body.is_arm_broken(player.active_hand)

func _is_valid_metal_type(metal_type: int) -> bool:
	return Defs.get_coin_value(metal_type) > 0 and Defs.get_coin_item_type(metal_type) != ""

func _get_metal_name(metal_type: int) -> String:
	if metal_type < 0 or metal_type >= Defs.COIN_METAL_SUFFIXES.size():
		return "unknown"
	return Defs.COIN_METAL_SUFFIXES[metal_type]

func _send_error(peer_id: int, message: String) -> void:
	world.rpc_send_direct_message.rpc_id(peer_id, "[color=#ffaaaa]%s[/color]" % message)

func _count_held_coins(player: Node2D, metal_type: int) -> int:
	var total := 0
	for hand_item in player.hands:
		if hand_item == null or not is_instance_valid(hand_item):
			continue
		if hand_item.get("is_coin_stack") != true:
			continue
		if int(hand_item.get("metal_type")) != metal_type:
			continue
		total += int(hand_item.get("amount"))
	return total

func _remove_held_coins(player: Node2D, metal_type: int, coin_amount: int) -> void:
	var remaining := coin_amount
	for hand_idx in range(player.hands.size()):
		if remaining <= 0:
			break

		var hand_item = player.hands[hand_idx]
		if hand_item == null or not is_instance_valid(hand_item):
			continue
		if hand_item.get("is_coin_stack") != true:
			continue
		if int(hand_item.get("metal_type")) != metal_type:
			continue

		var stack_amount := int(hand_item.get("amount"))
		var to_remove: int = min(stack_amount, remaining)
		hand_item.amount = stack_amount - to_remove
		remaining -= to_remove

		if int(hand_item.get("amount")) <= 0:
			player.hands[hand_idx] = null
			hand_item.queue_free()

func _build_withdraw_payload(player: Node2D, metal_type: int, coin_amount: int, preferred_hand: int, atm_position: Vector2, z_level: int) -> Array:
	var payload: Array = []
	var remaining := coin_amount
	var hand_order: Array[int] = []

	if Defs.is_valid_hand_index(preferred_hand):
		hand_order.append(preferred_hand)
	for hand_idx in range(player.hands.size()):
		if not hand_order.has(hand_idx):
			hand_order.append(hand_idx)

	for hand_idx in hand_order:
		if remaining <= 0:
			break
		var hand_item = player.hands[hand_idx]
		if hand_item == null or not is_instance_valid(hand_item):
			continue
		if hand_item.get("is_coin_stack") != true:
			continue
		if int(hand_item.get("metal_type")) != metal_type:
			continue

		var available_space := Defs.MAX_COIN_STACK - int(hand_item.get("amount"))
		if available_space <= 0:
			continue

		var add_amount: int = min(remaining, available_space)
		payload.append({
			"mode": "hand_add",
			"hand_idx": hand_idx,
			"amount": add_amount,
		})
		remaining -= add_amount

	for hand_idx in hand_order:
		if remaining <= 0:
			break
		if player.hands[hand_idx] != null:
			continue

		var new_stack_amount: int = min(remaining, Defs.MAX_COIN_STACK)
		payload.append({
			"mode": "hand_new",
			"hand_idx": hand_idx,
			"amount": new_stack_amount,
			"node_name": Defs.make_runtime_name("Coin"),
			"entity_id": world._make_entity_id("atm_coin"),
		})
		remaining -= new_stack_amount

	var ground_index := 0
	while remaining > 0:
		var ground_amount: int = min(remaining, Defs.MAX_COIN_STACK)
		payload.append({
			"mode": "ground_new",
			"amount": ground_amount,
			"node_name": Defs.make_runtime_name("Coin"),
			"entity_id": world._make_entity_id("atm_coin"),
			"position": _get_ground_stack_position(atm_position, ground_index),
			"z_level": z_level,
		})
		remaining -= ground_amount
		ground_index += 1

	return payload

func _get_ground_stack_position(atm_position: Vector2, index: int) -> Vector2:
	var row: int = int(floor(float(index) / 3.0))
	var column: int = (index % 3) - 1
	return atm_position + Vector2(column * 18.0, 30.0 + row * 18.0)

func _apply_withdraw_payload(player: Node2D, metal_type: int, payload: Array) -> void:
	var parent_node := player.get_parent()
	if parent_node == null:
		return

	for entry in payload:
		var entry_data := entry as Dictionary
		if entry_data == null or entry_data.is_empty():
			continue

		match str(entry_data.get("mode", "")):
			"hand_add":
				var hand_idx := int(entry_data.get("hand_idx", -1))
				if not Defs.is_valid_hand_index(hand_idx):
					continue
				var hand_item = player.hands[hand_idx]
				if hand_item == null or not is_instance_valid(hand_item):
					continue
				if hand_item.get("is_coin_stack") != true or int(hand_item.get("metal_type")) != metal_type:
					continue
				hand_item.amount += int(entry_data.get("amount", 0))
			"hand_new":
				var hand_slot := int(entry_data.get("hand_idx", -1))
				if not Defs.is_valid_hand_index(hand_slot):
					continue
				if player.hands[hand_slot] != null:
					continue
				var hand_coin := _spawn_coin_from_payload(parent_node, entry_data, metal_type, player.z_level, player.pixel_pos)
				if hand_coin == null:
					continue
				for child in hand_coin.get_children():
					if child is CollisionShape2D:
						child.disabled = true
				player.hands[hand_slot] = hand_coin
			"ground_new":
				var coin_pos: Vector2 = entry_data.get("position", player.pixel_pos)
				var coin_z := int(entry_data.get("z_level", player.z_level))
				_spawn_coin_from_payload(parent_node, entry_data, metal_type, coin_z, coin_pos)

func _spawn_coin_from_payload(parent: Node, entry_data: Dictionary, metal_type: int, z_level: int, spawn_position: Vector2) -> Node2D:
	if parent == null:
		return null

	var item_type := Defs.get_coin_item_type(metal_type)
	var scene_path := ItemRegistry.get_scene_path(item_type)
	if scene_path == "":
		return null

	var scene := load(scene_path) as PackedScene
	if scene == null:
		return null

	var coin := scene.instantiate() as Node2D
	if coin == null:
		return null

	coin.name = str(entry_data.get("node_name", Defs.make_runtime_name("Coin")))
	coin.set("metal_type", metal_type)
	coin.set("amount", int(entry_data.get("amount", 1)))
	if "z_level" in coin:
		coin.set("z_level", z_level)

	var entity_id := str(entry_data.get("entity_id", ""))
	if entity_id != "":
		coin.set_meta("entity_id", entity_id)

	parent.add_child(coin)
	coin.global_position = spawn_position
	if entity_id != "":
		world.register_entity(coin, entity_id)
	return coin
