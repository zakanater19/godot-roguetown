extends RefCounted

const VENDOR_DROP_TILE_OFFSET := Vector2i(0, 1)
const VENDOR_DROP_SPREAD: float = 10.0

var world: Node

func _init(p_world: Node) -> void:
	world = p_world

func handle_rpc_request_merchant_open(sender_id: int, vendor_id: String) -> void:
	if not world.multiplayer.is_server():
		return

	var player := world.utils.find_player_by_peer(sender_id) as Node2D
	var vendor := _get_vendor_node(vendor_id)
	if not _can_player_use_vendor(player, vendor):
		return
	if not _can_use_open_hand(player):
		_send_error(sender_id, "You need an open hand to use the merchant vendor.")
		return

	world.rpc_show_merchant_menu.rpc_id(sender_id, vendor_id, _get_vendor_balance(vendor))

func handle_rpc_show_merchant_menu(vendor_id: String, balance: int) -> void:
	var vendor := _get_vendor_node(vendor_id)
	if vendor != null and vendor.has_method("_show_merchant_menu"):
		vendor._show_merchant_menu(balance)

func handle_rpc_request_merchant_hand_interaction(sender_id: int, vendor_id: String, hand_idx: int) -> void:
	if not world.multiplayer.is_server():
		return

	var player := world.utils.find_player_by_peer(sender_id) as Node2D
	var vendor := _get_vendor_node(vendor_id)
	if not _can_player_use_vendor(player, vendor):
		return
	if not Defs.is_valid_hand_index(hand_idx):
		return
	if player.body != null and player.body.is_arm_broken(hand_idx):
		_send_error(sender_id, "That arm is useless.")
		return

	var held_item: Node = player.hands[hand_idx]
	if held_item == null or not is_instance_valid(held_item):
		return

	if held_item.get("is_coin_stack") == true:
		_handle_coin_deposit(sender_id, vendor, hand_idx, held_item)
		return

	if _has_unsellable_contents(held_item):
		_send_error(sender_id, "Empty that container before selling it.")
		return

	var item_type := Trade.get_item_type_from_node(held_item)
	var sale_value := Trade.get_price(item_type)
	if sale_value <= 0:
		_send_error(sender_id, "The vendor is not interested in that.")
		return

	var payout_payload := _build_ground_coin_payload(vendor, sale_value)
	world.rpc_confirm_merchant_sale.rpc(sender_id, hand_idx, payout_payload)
	world.rpc_send_direct_message.rpc_id(
		sender_id,
		"[color=#aaffaa]Sold %s for %d coin value.[/color]" % [item_type, sale_value]
	)

func handle_rpc_confirm_merchant_coin_deposit(peer_id: int, hand_idx: int, removed_amount: int) -> void:
	var player := world.utils.find_player_by_peer(peer_id) as Node2D
	if player == null or not Defs.is_valid_hand_index(hand_idx):
		return

	var held_item: Node = player.hands[hand_idx]
	if held_item == null or not is_instance_valid(held_item):
		return
	if held_item.get("is_coin_stack") != true:
		return

	held_item.amount = _get_node_int(held_item, "amount", 0) - removed_amount
	if _get_node_int(held_item, "amount", 0) <= 0:
		player.hands[hand_idx] = null
		world.unregister_entity(held_item)
		held_item.queue_free()
	if player._is_local_authority():
		player._update_hands_ui()

func handle_rpc_confirm_merchant_sale(peer_id: int, hand_idx: int, payout_payload: Array) -> void:
	var player := world.utils.find_player_by_peer(peer_id) as Node2D
	if player != null and Defs.is_valid_hand_index(hand_idx):
		var held_item: Node = player.hands[hand_idx]
		if held_item != null and is_instance_valid(held_item):
			player.hands[hand_idx] = null
			world.unregister_entity(held_item)
			held_item.queue_free()
		if player._is_local_authority():
			player._update_hands_ui()

	_spawn_coin_payload(payout_payload)

func handle_rpc_request_merchant_purchase(sender_id: int, vendor_id: String, item_type: String) -> void:
	if not world.multiplayer.is_server():
		return

	var player := world.utils.find_player_by_peer(sender_id) as Node2D
	var vendor := _get_vendor_node(vendor_id)
	if not _can_player_use_vendor(player, vendor):
		return
	if not Trade.is_buyable(item_type):
		_send_error(sender_id, "That item is not available here.")
		return

	var price := Trade.get_price(item_type)
	var current_balance := _get_vendor_balance(vendor)
	if price <= 0 or current_balance < price:
		_send_error(sender_id, "You do not have enough inserted coins.")
		return

	var item_data := ItemRegistry.get_by_type(item_type)
	if item_data == null or item_data.scene_path.is_empty():
		return

	var new_balance := current_balance - price
	_set_vendor_balance(vendor, new_balance)

	var entity_id: String = world._make_entity_id("merchant_item")
	var node_name: String = Defs.make_runtime_name(item_type)
	var spawn_position: Vector2 = _make_drop_position(vendor, entity_id, 0)
	world.rpc_confirm_merchant_purchase.rpc(item_type, node_name, entity_id, vendor.z_level, spawn_position)
	world.rpc_update_merchant_balance.rpc(vendor_id, new_balance)
	world.rpc_send_direct_message.rpc_id(
		sender_id,
		"[color=#aaffaa]Purchased %s for %d coin value.[/color]" % [item_type, price]
	)

func handle_rpc_confirm_merchant_purchase(item_type: String, node_name: String, entity_id: String, z_level: int, spawn_position: Vector2) -> void:
	var main_scene := World.main_scene
	if main_scene == null:
		return
	var item := ObjectSpawnUtils.spawn_item_type(main_scene, item_type, node_name, z_level, spawn_position, entity_id)
	_apply_spawn_input_grace(item)

func handle_rpc_request_merchant_withdraw(sender_id: int, vendor_id: String) -> void:
	if not world.multiplayer.is_server():
		return

	var player := world.utils.find_player_by_peer(sender_id) as Node2D
	var vendor := _get_vendor_node(vendor_id)
	if not _can_player_use_vendor(player, vendor):
		return

	var current_balance := _get_vendor_balance(vendor)
	if current_balance <= 0:
		_send_error(sender_id, "The vendor is empty.")
		return

	var payout_payload := _build_ground_coin_payload(vendor, current_balance)
	_set_vendor_balance(vendor, 0)
	world.rpc_confirm_merchant_withdraw.rpc(payout_payload)
	world.rpc_update_merchant_balance.rpc(vendor_id, 0)
	world.rpc_send_direct_message.rpc_id(sender_id, "[color=#aaffaa]The vendor spits your coins back out.[/color]")

func handle_rpc_confirm_merchant_withdraw(payout_payload: Array) -> void:
	_spawn_coin_payload(payout_payload)

func handle_rpc_update_merchant_balance(vendor_id: String, balance: int) -> void:
	var vendor := _get_vendor_node(vendor_id)
	if vendor != null and vendor.has_method("_update_merchant_balance"):
		vendor._update_merchant_balance(balance)

func _handle_coin_deposit(sender_id: int, vendor: Node2D, hand_idx: int, held_item: Node) -> void:
	var metal_type := _get_node_int(held_item, "metal_type", -1)
	var amount := _get_node_int(held_item, "amount", 0)
	var deposit_value := amount * Defs.get_coin_value(metal_type)
	if amount <= 0 or deposit_value <= 0:
		return

	var new_balance := _get_vendor_balance(vendor) + deposit_value
	_set_vendor_balance(vendor, new_balance)
	world.rpc_confirm_merchant_coin_deposit.rpc(sender_id, hand_idx, amount)
	world.rpc_update_merchant_balance.rpc(World.get_entity_id(vendor), new_balance)
	world.rpc_send_direct_message.rpc_id(
		sender_id,
		"[color=#aaffaa]Inserted %d coin value into the vendor.[/color]" % deposit_value
	)

func _get_vendor_node(vendor_id: String) -> Node2D:
	var vendor := world.get_entity(vendor_id) as Node2D
	if vendor == null or not is_instance_valid(vendor):
		return null
	if vendor.get("is_merchant_vendor") != true:
		return null
	return vendor

func _can_player_use_vendor(player: Node2D, vendor: Node2D) -> bool:
	return (
		player != null
		and vendor != null
		and world.utils.can_player_interact(player)
		and player.z_level == vendor.z_level
		and world.utils.is_within_interaction_range(player, vendor.global_position)
	)

func _can_use_open_hand(player: Node2D) -> bool:
	if player == null:
		return false
	if not Defs.is_valid_hand_index(player.active_hand):
		return false
	if player.hands[player.active_hand] != null:
		return false
	return player.body == null or not player.body.is_arm_broken(player.active_hand)

func _get_vendor_balance(vendor: Node) -> int:
	var stored_balance = vendor.get("stored_balance") if vendor != null else null
	return int(stored_balance) if stored_balance != null else 0

func _set_vendor_balance(vendor: Node, amount: int) -> void:
	if vendor != null:
		vendor.set("stored_balance", maxi(0, amount))

func _send_error(peer_id: int, message: String) -> void:
	world.rpc_send_direct_message.rpc_id(peer_id, "[color=#ffaaaa]%s[/color]" % message)

func _build_ground_coin_payload(vendor: Node2D, total_value: int) -> Array:
	var payload: Array = []
	if vendor == null or total_value <= 0:
		return payload

	var remaining := total_value
	var drop_index := 0
	for metal_type in [2, 1, 0]:
		var coin_value := Defs.get_coin_value(metal_type)
		if coin_value <= 0:
			continue

		var coin_count: int = floori(float(remaining) / float(coin_value))
		while coin_count > 0:
			var stack_amount: int = min(coin_count, Defs.MAX_COIN_STACK)
			var entry_id: String = world._make_entity_id("merchant_coin")
			payload.append({
				"node_name": Defs.make_runtime_name("Coin"),
				"entity_id": entry_id,
				"amount": stack_amount,
				"metal_type": metal_type,
				"position": _make_drop_position(vendor, entry_id, drop_index),
				"z_level": vendor.z_level,
			})
			coin_count -= stack_amount
			remaining -= stack_amount * coin_value
			drop_index += 1

	return payload

func _spawn_coin_payload(payload: Array) -> void:
	var main_scene := World.main_scene
	if main_scene == null:
		return

	for entry in payload:
		if not (entry is Dictionary):
			continue
		var data: Dictionary = entry
		if data.is_empty():
			continue
		var metal_type := int(data.get("metal_type", -1))
		var item_type := Defs.get_coin_item_type(metal_type)
		if item_type.is_empty():
			continue
		var spawn_position: Vector2 = data.get("position", Vector2.ZERO)
		var coin := ObjectSpawnUtils.spawn_item_type(
			main_scene,
			item_type,
			str(data.get("node_name", Defs.make_runtime_name("Coin"))),
			int(data.get("z_level", 3)),
			spawn_position,
			str(data.get("entity_id", ""))
		)
		if coin == null:
			continue
		_apply_spawn_input_grace(coin)
		coin.set("metal_type", metal_type)
		coin.set("amount", int(data.get("amount", 1)))

func _make_drop_position(vendor: Node2D, seed_key: String, offset_index: int) -> Vector2:
	var drop_tile: Vector2i = vendor.get_anchor_tile() + VENDOR_DROP_TILE_OFFSET
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s:%d" % [seed_key, offset_index]).hash()
	return Defs.tile_to_pixel(drop_tile) + Vector2(
		rng.randf_range(-VENDOR_DROP_SPREAD, VENDOR_DROP_SPREAD),
		rng.randf_range(-VENDOR_DROP_SPREAD, VENDOR_DROP_SPREAD)
	)

func _apply_spawn_input_grace(item: Node) -> void:
	var collision_object := item as CollisionObject2D
	if collision_object == null:
		return

	var should_restore_pickable := true
	if item.has_method("is_pickup_enabled"):
		should_restore_pickable = item.is_pickup_enabled()

	collision_object.input_pickable = false

	var tree := world.get_tree()
	if tree == null:
		return

	tree.process_frame.connect(func() -> void:
		if collision_object != null and is_instance_valid(collision_object):
			collision_object.input_pickable = should_restore_pickable
	, CONNECT_ONE_SHOT)

func _has_unsellable_contents(item: Node) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if "contents" not in item:
		return false
	var contents: Variant = item.get("contents")
	if not (contents is Array):
		return false
	for entry in contents:
		if entry != null:
			return true
	return false

func _get_node_int(node: Node, property_name: String, default_value: int) -> int:
	if node == null or not is_instance_valid(node):
		return default_value
	var value = node.get(property_name)
	return int(value) if value != null else default_value
