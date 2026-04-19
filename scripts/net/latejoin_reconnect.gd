# res://scripts/net/latejoin_reconnect.gd
# Handles player disconnection capture and reconnection restoration.
extends RefCounted

var lj: Node  # reference to the LateJoin autoload node

func _init(latejoin_node: Node) -> void:
	lj = latejoin_node

# ---------------------------------------------------------------------------
# Disconnection
# ---------------------------------------------------------------------------

func handle_player_disconnection(peer_id: int, player_node: Node) -> void:
	if not is_instance_valid(player_node):
		return

	var node = player_node as Node2D
	if not node.get("dead") and node.get("is_lying_down") == false:
		node.set("is_lying_down", true)
		if node.has_method("_cancel_stand_up"):        node.call("_cancel_stand_up")
		if node.has_method("_update_sprite"):          node.call("_update_sprite")
		if node.has_method("_update_water_submerge"):  node.call("_update_water_submerge")
		if node.has_method("_rpc_sync_lying_down"):    node.call("_rpc_sync_lying_down", true)

	var player_state = capture_player_state(node)
	lj._disconnected_players[peer_id] = {
		"node_path": node.get_path(),
		"state":     player_state,
		"timestamp": Time.get_ticks_msec(),
		"ip":        Host._get_peer_ip(peer_id)
	}

	lj.rpc_set_disconnect_indicator.rpc(node.get_path(), true)

	var hand_ids = []
	for h in node.get("hands"):
		hand_ids.append(World.get_entity_id(h) if h != null else "")

	lj.update_player_state(peer_id, {
		"position":     node.position,
		"disconnected": true,
		"health":       node.get("health"),
		"hands":        hand_ids
	})

# ---------------------------------------------------------------------------
# Reconnection
# ---------------------------------------------------------------------------

func handle_reconnection(peer_id: int) -> bool:
	if lj._disconnected_players.is_empty(): return false
	var best_peer_id = _find_reconnection_candidate_for_peer(peer_id)
	if best_peer_id == -1: return false

	var disconnected_data: Dictionary = lj._disconnected_players[best_peer_id]
	var player_node = _resolve_reconnection_node(best_peer_id, disconnected_data)
	if player_node == null or not is_instance_valid(player_node):
		lj._disconnected_players.erase(best_peer_id)
		return false

	if Host.peers.has(peer_id):
		var ghost = Host.peers[peer_id]
		if is_instance_valid(ghost) and ghost != player_node: ghost.queue_free()

	var success = _perform_reconnection(peer_id, best_peer_id, player_node, {})
	if success: lj._disconnected_players.erase(best_peer_id)
	else:        Host.peers.erase(peer_id)
	return success

func _resolve_reconnection_node(old_peer_id: int, disconnected_data: Dictionary) -> Node:
	var current_node: Node = Host.peers.get(old_peer_id, null)
	if current_node == null or not is_instance_valid(current_node) or current_node.is_queued_for_deletion():
		current_node = lj._find_player_by_peer(old_peer_id)
	if current_node != null and is_instance_valid(current_node) and not current_node.is_queued_for_deletion():
		return current_node

	var player_node_path: NodePath = disconnected_data.get("node_path", NodePath())
	if player_node_path.is_empty():
		return null
	var player_node = lj.get_node_or_null(player_node_path)
	if player_node == null or not is_instance_valid(player_node) or player_node.is_queued_for_deletion():
		return null
	return player_node

func _find_reconnection_candidate_for_peer(new_peer_id: int) -> int:
	var new_ip: String = Host._get_peer_ip(new_peer_id)
	var is_local: bool = new_ip == "" or Host._is_local_ip(new_ip)

	if not is_local:
		# Non-local: match exactly by stored IP — one client per IP, no ambiguity.
		for dc_peer_id in lj._disconnected_players.keys():
			if lj._disconnected_players[dc_peer_id].get("ip", "") == new_ip:
				return dc_peer_id

	# Localhost / fallback: use the most-recently disconnected player.
	# Localhost testing typically has one client at a time, so this is unambiguous.
	var best_peer_id := -1
	var latest_time  := 0
	for dc_peer_id in lj._disconnected_players.keys():
		if lj._disconnected_players[dc_peer_id]["timestamp"] > latest_time:
			latest_time  = lj._disconnected_players[dc_peer_id]["timestamp"]
			best_peer_id = dc_peer_id
	return best_peer_id

func _perform_reconnection(new_peer_id: int, old_peer_id: int, player_node: Node, _player_state: Dictionary) -> bool:
	var node          = player_node as Node2D
	var current_state = capture_player_state(node)

	for grabber_peer_id in World.grab_map:
		var entry = World.grab_map[grabber_peer_id]
		if entry.get("is_player", false) and entry.get("target_peer_id", -1) == old_peer_id:
			entry["target_peer_id"] = new_peer_id
			entry["target"]         = node

	restore_player_state(node, current_state)
	_reassign_player_node(node, new_peer_id, old_peer_id)

	lj.rpc_set_disconnect_indicator.rpc(node.get_path(), false)

	var hand_ids = []
	for h in node.get("hands"):
		hand_ids.append(World.get_entity_id(h) if h != null else "")

	lj.update_player_state(new_peer_id, {"position": node.position, "disconnected": false, "health": node.get("health"), "hands": hand_ids})
	if node.has_method("_on_reconnection_confirmed"): node.call("_on_reconnection_confirmed")
	Lobby.rpc_hide_lobby.rpc_id(new_peer_id)

	lj.receive_reconnect_state.rpc_id(new_peer_id, node.get_path(), current_state)
	return true

func _update_peer_registry(player_node: Node, old_peer_id: int, new_peer_id: int) -> void:
	if old_peer_id != new_peer_id and Host.peers.get(old_peer_id, null) == player_node:
		Host.peers.erase(old_peer_id)
	Host.peers[new_peer_id] = player_node

func _reassign_player_node(player_node: Node, new_peer_id: int, old_peer_id: int = -1) -> void:
	_update_peer_registry(player_node, old_peer_id, new_peer_id)
	lj.rpc_update_player_authority.rpc(player_node.get_path(), new_peer_id)
	lj.reconnection_confirmed.rpc_id(new_peer_id, player_node.get_path())

# ---------------------------------------------------------------------------
# State capture
# ---------------------------------------------------------------------------

func capture_player_state(player_node: Node2D) -> Dictionary:
	return {
		"character_name":  player_node.get("character_name"),
		"character_class": player_node.get("character_class"),
		"position":        player_node.position,
		"z_level":         player_node.get("z_level"),
		"tile_pos":        player_node.get("tile_pos"),
		"facing":          player_node.get("facing"),
		"health":          player_node.get("health"),
		"limb_hp":         player_node.get("body").limb_hp.duplicate() if player_node.get("body") != null else {},
		"limb_broken":     player_node.get("body").limb_broken.duplicate() if player_node.get("body") != null else {},
		"stamina":         player_node.get("stamina"),
		"dead":            player_node.get("dead"),
		"combat_mode":     player_node.get("combat_mode"),
		"exhausted":       player_node.get("exhausted"),
		"active_hand":     player_node.get("active_hand"),
		"hands":           capture_hands_state(player_node),
		"equipped":        capture_equipped_state(player_node),
		"equipped_data":   player_node.get("equipped_data").duplicate(true) if "equipped_data" in player_node else {},
		"pixel_pos":       player_node.get("pixel_pos"),
		"moving":          player_node.get("moving"),
		"move_elapsed":    player_node.get("move_elapsed"),
		"move_from":       player_node.get("move_from"),
		"move_to":         player_node.get("move_to"),
		"current_move_duration": player_node.get("current_move_duration"),
		"action_cooldown": player_node.get("action_cooldown"),
		"buffered_dir":    player_node.get("buffered_dir"),
		"throwing_mode":   player_node.get("throwing_mode"),
		"intent":          player_node.get("intent"),
		"sleep_state":     player_node.get("sleep_state") if player_node.has_method("toggle_sleep") else 0,
		"is_lying_down":   player_node.get("is_lying_down") == true,
		"skills":          player_node.get("skills").duplicate() if player_node.get("skills") else {},
		"grabbed_by_peer": player_node.get("grabbed_by").get_multiplayer_authority() if (player_node.get("grabbed_by") != null and is_instance_valid(player_node.get("grabbed_by"))) else -1
	}

func capture_equipped_state(player_node: Node2D) -> Dictionary:
	var equipped_state = {}
	var eq = player_node.get("equipped")
	for slot in eq:
		var item = eq[slot]
		if item != null and not (item is String):
			var itype: String = item.get("item_type") if item.get("item_type") != null else ""
			equipped_state[slot] = {
				"item_type":       itype,
				"scene_file_path": ItemRegistry.get_scene_path(itype) if itype != "" else item.scene_file_path,
				"node_name":       item.name
			}
		elif item is String and item != "":
			equipped_state[slot] = {"item_type": item, "scene_file_path": ItemRegistry.get_scene_path(item), "node_name": ""}
		else:
			equipped_state[slot] = null
	return equipped_state

func capture_hands_state(player_node: Node2D) -> Array:
	var hands_state = []
	var h_arr = player_node.get("hands")
	for i in range(2):
		var hand_item = h_arr[i]
		if hand_item != null and is_instance_valid(hand_item):
			var item_data = {
				"name":            hand_item.name,
				"entity_id":       World.get_entity_id(hand_item),
				"scene_file_path": hand_item.scene_file_path,
				"item_type":       hand_item.get("item_type") if hand_item.has_method("get") else "",
				"position":        hand_item.position,
				"slot":            hand_item.get("slot") if hand_item.has_method("get") else "",
				"weaponizable":    hand_item.get("weaponizable") if hand_item.has_method("get") else false,
				"force":           hand_item.get("force") if hand_item.has_method("get") else 0
			}
			item_data["script_path"] = hand_item.get_script().resource_path if hand_item.get_script() != null else ""
			if "contents"   in hand_item: item_data["contents"]   = hand_item.get("contents").duplicate(true)
			if "amount"     in hand_item: item_data["amount"]     = hand_item.get("amount")
			if "metal_type" in hand_item: item_data["metal_type"] = hand_item.get("metal_type")
			if "key_id"     in hand_item: item_data["key_id"]     = hand_item.get("key_id")
			if "is_on"      in hand_item: item_data["is_on"]      = hand_item.get("is_on")
			hands_state.append(item_data)
		else:
			hands_state.append(null)
	return hands_state

# ---------------------------------------------------------------------------
# State restoration
# ---------------------------------------------------------------------------

func restore_player_state(player_node: Node2D, player_state: Dictionary) -> void:
	player_node.set("character_name",  player_state.get("character_name", "noob"))
	player_node.set("character_class", player_state.get("character_class", "peasant"))
	player_node.position = player_state["position"]
	if player_state.has("z_level"):
		player_node.set("z_level", player_state["z_level"])
		player_node.z_index = (player_node.get("z_level") - 1) * 200 + 10
	player_node.set("tile_pos",   player_state["tile_pos"])
	player_node.set("facing",     player_state["facing"])
	player_node.set("health",     player_state["health"])

	if player_state.has("limb_hp")    and player_node.get("body") != null:
		player_node.get("body").limb_hp    = player_state["limb_hp"].duplicate()
	if player_state.has("limb_broken") and player_node.get("body") != null:
		player_node.get("body").limb_broken = player_state["limb_broken"].duplicate()

	player_node.set("stamina",              player_state["stamina"])
	player_node.set("dead",                 player_state["dead"])
	player_node.set("combat_mode",          player_state["combat_mode"])
	if player_state.has("exhausted"):       player_node.set("exhausted",       player_state["exhausted"])
	player_node.set("active_hand",          player_state["active_hand"])
	player_node.set("pixel_pos",            player_state["pixel_pos"])
	player_node.set("moving",               player_state["moving"])
	player_node.set("move_elapsed",         player_state["move_elapsed"])
	player_node.set("move_from",            player_state["move_from"])
	player_node.set("move_to",              player_state["move_to"])
	player_node.set("current_move_duration", player_state["current_move_duration"])
	player_node.set("action_cooldown",      player_state["action_cooldown"])
	player_node.set("buffered_dir",         player_state["buffered_dir"])
	player_node.set("throwing_mode",        player_state["throwing_mode"])
	player_node.set("intent",               player_state["intent"])

	if player_state.has("sleep_state"):
		player_node.set("sleep_state", player_state["sleep_state"])
		if player_node.get("sleep_state") != 0 and player_node.has_method("_set_lying_down_visuals"):
			player_node.call("_set_lying_down_visuals", true)

	if player_state.has("is_lying_down"):  player_node.set("is_lying_down", player_state["is_lying_down"])
	if player_state.has("skills"):         player_node.set("skills",        player_state["skills"].duplicate())
	if player_state.has("equipped_data"):  player_node.set("equipped_data", player_state["equipped_data"].duplicate(true))

	if lj.multiplayer.is_server() and player_state.has("grabbed_by_peer"):
		var grabber_peer = player_state["grabbed_by_peer"]
		if grabber_peer != -1:
			var grabber = lj._find_player_by_peer(grabber_peer)
			if grabber != null and is_instance_valid(grabber):
				player_node.set("grabbed_by", grabber)
				grabber.set("grabbed_target", player_node)
				World.rpc_confirm_grab_start.rpc(grabber_peer, true, player_node.get_multiplayer_authority(), World.get_entity_id(player_node), grabber.get("character_name"), player_node.get("character_name"), "chest", grabber.get("active_hand"))

	var eq_data   = player_state["equipped"]
	var eq        = player_node.get("equipped")
	for slot in eq_data:
		var item_data = eq_data[slot]
		if item_data == null:              eq[slot] = null
		elif item_data is Dictionary:      eq[slot] = item_data.get("item_type", "")
		elif item_data is String:          eq[slot] = item_data if item_data != "" else null
		else:                              eq[slot] = null

	var hands_state = player_state["hands"]
	var h_arr       = player_node.get("hands")
	for i in range(min(2, hands_state.size())):
		var h_data = hands_state[i]
		if h_data == null:
			h_arr[i] = null
			continue

		var desired_entity_id := str(h_data.get("entity_id", ""))
		var current_item: Node = h_arr[i]
		if current_item != null:
			if not is_instance_valid(current_item) or current_item.is_queued_for_deletion():
				current_item = null
				h_arr[i] = null
			elif desired_entity_id == "" or World.get_entity_id(current_item) != desired_entity_id:
				current_item = null
				h_arr[i] = null

		if desired_entity_id == "":
			h_arr[i] = null
			continue

		if current_item == null:
			current_item = World.get_entity(desired_entity_id)
			if current_item == null:
				current_item = _recreate_hand_item(h_data)

		if current_item != null and is_instance_valid(current_item):
			h_arr[i] = current_item
			if "z_level" in current_item:
				current_item.set("z_level", player_node.get("z_level"))
			for child in current_item.get_children():
				if child is CollisionShape2D:
					child.disabled = true
		else:
			h_arr[i] = null

	for i in range(hands_state.size(), 2):
		h_arr[i] = null

	if player_node.has_method("_update_sprite"):          player_node.call("_update_sprite")
	if player_node.has_method("_update_clothing_sprites"): player_node.call("_update_clothing_sprites")
	if player_node.has_method("_update_hands_ui"):         player_node.call("_update_hands_ui")
	if player_node.has_method("_update_water_submerge"):   player_node.call("_update_water_submerge")

func _recreate_hand_item(hand_data: Dictionary) -> Node:
	var main_node = World.main_scene
	if main_node == null: return null
	var entity_id := str(hand_data.get("entity_id", ""))
	var existing = World.get_entity(entity_id)
	if existing != null: return existing
	var scene_path = hand_data.get("scene_file_path", "")
	if scene_path.is_empty():
		if hand_data.get("script_path", "").is_empty(): return null
		var script = load(hand_data["script_path"])
		if script == null: return null
		var fallback = Area2D.new(); fallback.set_script(script)
		fallback.name = hand_data["name"]; fallback.position = hand_data["position"]
		if hand_data.has("contents") and "contents" in fallback: fallback.set("contents", hand_data["contents"].duplicate(true))
		if hand_data.has("amount")   and "amount"   in fallback: fallback.set("amount",   hand_data["amount"])
		if hand_data.has("metal_type") and "metal_type" in fallback: fallback.set("metal_type", hand_data["metal_type"])
		if hand_data.has("key_id") and "key_id" in fallback: fallback.set("key_id", hand_data["key_id"])
		main_node.add_child(fallback)
		if hand_data.has("is_on") and fallback.has_method("_set_sprite"): fallback._set_sprite(hand_data["is_on"])
		elif fallback.has_method("_update_sprite"): fallback._update_sprite()
		World.register_entity(fallback, entity_id)
		return fallback
	var scene = load(scene_path) as PackedScene
	if scene == null: return null
	var item = scene.instantiate()
	item.name = hand_data["name"]; item.position = hand_data["position"]
	if hand_data.has("contents") and "contents" in item: item.set("contents", hand_data["contents"].duplicate(true))
	if hand_data.has("amount")   and "amount"   in item: item.set("amount",   hand_data["amount"])
	if hand_data.has("metal_type") and "metal_type" in item: item.set("metal_type", hand_data["metal_type"])
	if hand_data.has("key_id") and "key_id" in item: item.set("key_id", hand_data["key_id"])
	main_node.add_child(item)
	if hand_data.has("is_on") and item.has_method("_set_sprite"): item._set_sprite(hand_data["is_on"])
	elif item.has_method("_update_sprite"): item._update_sprite()
	World.register_entity(item, entity_id)
	return item

# ---------------------------------------------------------------------------
# Retry helpers (async — must be called as coroutines via the lj node)
# ---------------------------------------------------------------------------

func retry_update_authority(player_path: NodePath, new_peer_id: int, retries: int) -> void:
	var player = lj.get_node_or_null(player_path)
	if player != null:
		player.set_multiplayer_authority(new_peer_id)
		if player.has_method("_on_authority_changed"): player.call("_on_authority_changed")
	elif retries > 0:
		await lj.get_tree().create_timer(0.1).timeout
		retry_update_authority(player_path, new_peer_id, retries - 1)

func retry_set_disconnect_indicator(player_path: NodePath, show: bool, retries: int) -> void:
	var player = lj.get_node_or_null(player_path)
	if player != null:
		var existing = player.get_node_or_null("DisconnectIndicator")
		if existing: existing.queue_free()
		if show:
			var indicator = Node2D.new(); indicator.name = "DisconnectIndicator"
			indicator.position = Vector2(0, -50); player.add_child(indicator)
			var label = Label.new(); label.text = " ?! "
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_color_override("font_color", Color.YELLOW)
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			label.add_theme_constant_override("outline_size", 3)
			indicator.add_child(label)
			var tween = indicator.create_tween().set_loops(20)
			tween.tween_property(label, "modulate:a", 0.3, 0.5)
			tween.tween_property(label, "modulate:a", 1.0, 0.5)
	elif retries > 0:
		await lj.get_tree().create_timer(0.1).timeout
		retry_set_disconnect_indicator(player_path, show, retries - 1)

func retry_reconnection_confirmed(player_path: NodePath, retries: int) -> void:
	var player = lj.get_node_or_null(player_path)
	if player != null and player.has_method("_on_reconnection_confirmed"):
		player.call("_on_reconnection_confirmed")
	elif retries > 0:
		await lj.get_tree().create_timer(0.1).timeout
		retry_reconnection_confirmed(player_path, retries - 1)

func retry_receive_reconnect_state(player_path: NodePath, player_state: Dictionary, retries: int) -> void:
	var node = lj.get_node_or_null(player_path) as Node2D
	if node != null:
		restore_player_state(node, player_state)
		if node.get("is_lying_down") == true and node.has_method("toggle_lying_down"):
			node.call("toggle_lying_down")
	elif retries > 0:
		await lj.get_tree().create_timer(0.1).timeout
		retry_receive_reconnect_state(player_path, player_state, retries - 1)

func retry_receive_object_states(object_states: Dictionary, _retries: int) -> void:
	lj._sync.handle_receive_object_states(object_states)
