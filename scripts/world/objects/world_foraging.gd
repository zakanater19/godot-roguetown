extends RefCounted

var world: Node

func _init(p_world: Node) -> void:
	world = p_world

func handle_rpc_request_search_bush(sender_id: int, bush_id: String, hand_idx: int) -> void:
	if not world.multiplayer.is_server() or not Defs.is_valid_hand_index(hand_idx):
		return

	var player := world.utils.find_player_by_peer(sender_id) as Node2D
	var bush := world.get_entity(bush_id) as Node2D
	if not world.utils.can_player_interact(player):
		return
	if bush == null or bush.get("is_bush") != true:
		return
	if player.active_hand != hand_idx or player.hands[hand_idx] != null:
		return
	if player.body != null and player.body.is_arm_broken(hand_idx):
		return
	if player.z_level != bush.z_level:
		return
	if not world.utils.is_within_interaction_range(player, bush.global_position):
		return
	if not world.utils.server_check_action_cooldown(player):
		return

	if not bush.has_method("has_items_remaining") or not bush.has_items_remaining():
		world.rpc_send_direct_message.rpc_id(sender_id, "[color=#ffaaaa]the bush is picked clean[/color]")
		return

	var item_type := str(bush.choose_loot_item_type()) if bush.has_method("choose_loot_item_type") else ""
	if item_type.is_empty() or ItemRegistry.get_scene_path(item_type).is_empty():
		return

	var new_picked_count: int = int(bush.get("items_picked")) + 1
	var entity_id: String = str(world._make_entity_id("bush_item"))
	var node_name: String = Defs.make_runtime_name(item_type)
	world.rpc_confirm_search_bush.rpc(
		bush_id,
		sender_id,
		hand_idx,
		item_type,
		node_name,
		entity_id,
		new_picked_count
	)
	world.rpc_send_direct_message.rpc_id(
		sender_id,
		"[color=#aaffaa]you find %s in the bush[/color]" % item_type.to_lower()
	)

func handle_rpc_confirm_search_bush(
	bush_id: String,
	peer_id: int,
	hand_idx: int,
	item_type: String,
	node_name: String,
	entity_id: String,
	picked_count: int
) -> void:
	var bush: Node = world.get_entity(bush_id)
	if bush != null:
		if bush.has_method("set_items_picked"):
			bush.set_items_picked(picked_count)
		elif "items_picked" in bush:
			bush.set("items_picked", picked_count)

	var player := world.utils.find_player_by_peer(peer_id) as Node2D
	if player == null or not Defs.is_valid_hand_index(hand_idx):
		return

	var item := world.get_entity(entity_id) as Node2D
	if item == null:
		item = ObjectSpawnUtils.spawn_item_type(
			World.main_scene,
			item_type,
			node_name,
			player.z_level,
			player.global_position,
			entity_id
		)
	if item == null:
		return

	player.hands[hand_idx] = item
	for child in item.get_children():
		if child is CollisionShape2D:
			child.disabled = true
	if player._is_local_authority():
		player._update_hands_ui()
