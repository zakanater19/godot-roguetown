extends RefCounted

var world: Node
var active_attempts: Dictionary = {}

func _init(p_world: Node) -> void:
	world = p_world

func _get_valid_spider_corpse(corpse_id: String) -> Node2D:
	var corpse := world.get_entity(corpse_id) as Node2D
	if corpse == null or not corpse.has_method("can_be_butchered"):
		return null
	if not corpse.can_be_butchered():
		return null
	return corpse

func _get_valid_butcherer(sender_id: int, corpse: Node2D, hand_idx: int, weapon_id: String = "") -> Node2D:
	if not Defs.is_valid_hand_index(hand_idx):
		return null
	var player := world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player) or player.exhausted:
		return null
	if player.active_hand != hand_idx or player.z_level != corpse.z_level:
		return null
	if not world.utils.is_within_interaction_range(player, corpse.global_position):
		return null
	if player.body != null and player.body.is_arm_broken(hand_idx):
		return null
	var weapon: Node = player.hands[hand_idx]
	if not Defs.is_spider_butchering_tool(weapon):
		return null
	if weapon_id != "" and world.get_entity_id(weapon) != weapon_id:
		return null
	return player

func handle_rpc_request_begin_spider_butcher(sender_id: int, corpse_id: String, hand_idx: int) -> void:
	if not world.multiplayer.is_server():
		return
	var corpse := _get_valid_spider_corpse(corpse_id)
	if corpse == null:
		return
	var player := _get_valid_butcherer(sender_id, corpse, hand_idx)
	if player == null:
		return

	var weapon_id: String = world.get_entity_id(player.hands[hand_idx])
	var current: Dictionary = active_attempts.get(sender_id, {})
	if current.get("corpse_id", "") != corpse_id or current.get("weapon_id", "") != weapon_id:
		if not world.utils.server_check_action_cooldown(player):
			return
		active_attempts[sender_id] = {
			"corpse_id": corpse_id,
			"hand_idx": hand_idx,
			"weapon_id": weapon_id,
			"started_at_msec": Time.get_ticks_msec(),
		}

	if sender_id == world.multiplayer.get_unique_id():
		world.rpc_confirm_begin_spider_butcher(corpse_id, hand_idx, weapon_id)
	else:
		world.rpc_confirm_begin_spider_butcher.rpc_id(sender_id, corpse_id, hand_idx, weapon_id)

func handle_rpc_confirm_begin_spider_butcher(corpse_id: String, hand_idx: int, weapon_id: String) -> void:
	var local_player := world.utils.get_local_player() as Node2D
	if local_player != null and local_player.misc != null:
		local_player.misc.begin_spider_butchering(corpse_id, hand_idx, weapon_id)

func handle_rpc_cancel_spider_butcher(sender_id: int, corpse_id: String) -> void:
	if not world.multiplayer.is_server():
		return
	var attempt: Dictionary = active_attempts.get(sender_id, {})
	if attempt.get("corpse_id", "") == corpse_id:
		active_attempts.erase(sender_id)

func handle_rpc_request_finish_spider_butcher(sender_id: int, corpse_id: String, hand_idx: int, weapon_id: String) -> void:
	if not world.multiplayer.is_server():
		return
	var attempt: Dictionary = active_attempts.get(sender_id, {})
	if attempt.is_empty():
		return
	active_attempts.erase(sender_id)
	if (
		attempt.get("corpse_id", "") != corpse_id
		or int(attempt.get("hand_idx", -1)) != hand_idx
		or attempt.get("weapon_id", "") != weapon_id
	):
		return
	var elapsed_msec := Time.get_ticks_msec() - int(attempt.get("started_at_msec", 0))
	# Leave one frame of tolerance between the client progress clock and the
	# server's monotonic clock while still enforcing the five-second action.
	if elapsed_msec < int((Defs.SPIDER_BUTCHER_DURATION - 0.1) * 1000.0):
		return

	var corpse := _get_valid_spider_corpse(corpse_id)
	if corpse == null or _get_valid_butcherer(sender_id, corpse, hand_idx, weapon_id) == null:
		return

	var drop_z: int = world.calculate_gravity_z(corpse.tile_pos, corpse.z_level)
	var drops: Array = []
	for _index in range(randi_range(1, 2)):
		drops.append(_make_drop_payload("Leather", corpse.tile_pos, drop_z))
	drops.append(_make_drop_payload("SpiderMeat", corpse.tile_pos, drop_z))
	world.rpc_confirm_spider_butcher.rpc(corpse_id, drops)

	var message := "[color=#aaffaa]You butcher the spider.[/color]"
	if sender_id == world.multiplayer.get_unique_id():
		world.rpc_send_direct_message(message)
	else:
		world.rpc_send_direct_message.rpc_id(sender_id, message)

func _make_drop_payload(item_type: String, tile_pos: Vector2i, z_level: int) -> Dictionary:
	return {
		"item_type": item_type,
		"node_name": Defs.make_runtime_name(item_type),
		"entity_id": world._make_entity_id("butcher_drop"),
		"position": world.objects.make_authoritative_drop_position(tile_pos, Defs.DROP_SPREAD),
		"z_level": z_level,
	}

func handle_rpc_confirm_spider_butcher(corpse_id: String, drops: Array) -> void:
	var corpse: Node = world.get_entity(corpse_id)
	if corpse != null:
		world.unregister_entity(corpse)
		corpse.queue_free()

	for drop_data in drops:
		ObjectSpawnUtils.spawn_item_type(
			World.main_scene,
			str(drop_data.get("item_type", "")),
			str(drop_data.get("node_name", "")),
			int(drop_data.get("z_level", 3)),
			Vector2(drop_data.get("position", Vector2.ZERO)),
			str(drop_data.get("entity_id", ""))
		)
