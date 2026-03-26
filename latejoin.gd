# res://latejoin.gd
# AutoLoad singleton — register as "LateJoin" in project.godot
# Handles late join synchronization and player disconnection/reconnection

extends Node

# --- CONFIGURATION ---
const SYNC_INTERVAL: float = 1.0  # How often to check for state changes

# --- STATE TRACKING ---
var _world_state: Dictionary = {
	"tiles": {},      # Vector2i -> {source_id, atlas_coords}
	"objects": {},    # NodePath -> {type, position, state, ...}
	"players": {},    # peer_id -> {position, health, equipment, ...}
}

var _pending_joins: Array[int] =[]  # peer_ids waiting for world state
var _state_dirty: bool = false
var _sync_timer: float = 0.0

# Store all disconnected players with their full state
var _disconnected_players: Dictionary = {}  # peer_id -> {node_path, state, timestamp}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	if not multiplayer.is_server():
		print("LateJoin: Client mode - Press F5 to manually attempt reconnection")

func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return

	if not multiplayer.is_server() and Input.is_key_pressed(KEY_F5):
		_attempt_manual_reconnection()
	
	_sync_timer += delta
	if _sync_timer >= SYNC_INTERVAL:
		_sync_timer = 0.0
		if _state_dirty and multiplayer.is_server():
			_broadcast_state_updates()
			_state_dirty = false

func register_tile_change(tile_pos: Vector2i, source_id: int, atlas_coords: Vector2i) -> void:
	_world_state["tiles"][tile_pos] = {
		"source_id": source_id,
		"atlas_coords": atlas_coords
	}
	_state_dirty = true

func register_object_state(object_path: NodePath, object_data: Dictionary) -> void:
	_world_state["objects"][object_path] = object_data
	_state_dirty = true

func unregister_object(object_path: NodePath) -> void:
	_world_state["objects"].erase(object_path)
	_state_dirty = true

func update_player_state(peer_id: int, player_data: Dictionary) -> void:
	_world_state["players"][peer_id] = player_data
	_state_dirty = true

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	
	print("LateJoin: Peer connected - ", id)
	_pending_joins.append(id)
	_send_world_state_to_peer(id)
	
	if _handle_reconnection(id):
		return

func _send_world_state_to_peer(peer_id: int) -> void:
	var tile_changes = _world_state["tiles"]
	if not tile_changes.is_empty():
		rpc_id(peer_id, "receive_tile_changes", tile_changes)
	
	var object_states = _world_state["objects"]
	if not object_states.is_empty():
		rpc_id(peer_id, "receive_object_states", object_states)
	
	_sync_objects_for_late_joiner(peer_id)
	
	var player_states = {}
	for p in get_tree().get_nodes_in_group("player"):
		var node = p as Node2D
		var pid = node.get_multiplayer_authority()
		if pid == peer_id:
			continue
		var hand_names =[]
		for h in node.get("hands"):
			hand_names.append(h.name if (h != null and is_instance_valid(h)) else "")
		var equipped_data = _capture_equipped_state(node)
		var eq_data_state = node.get("equipped_data").duplicate(true) if "equipped_data" in node else {}
		player_states[pid] = {
			"position": node.position,
			"z_level": node.get("z_level"),
			"disconnected": false,
			"health": node.get("health"),
			"limb_hp": node.get("body").limb_hp.duplicate() if node.get("body") != null else {},
			"limb_broken": node.get("body").limb_broken.duplicate() if node.get("body") != null else {},
			"hands": hand_names,
			"equipped": equipped_data,
			"equipped_data": eq_data_state,
			"is_lying_down": node.get("is_lying_down") == true
		}
	
	if not player_states.is_empty():
		rpc_id(peer_id, "receive_player_states", player_states)
		
	rpc_id(peer_id, "receive_laws", World.current_laws)

func _sync_objects_for_late_joiner(peer_id: int) -> void:
	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node == null:
		return
	
	var objects_to_sync =[]
	var valid_object_names =[]
	var sync_groups =["pickable", "minable_object", "choppable_object", "inspectable", "door", "breakable_object"]
	
	for group in sync_groups:
		for obj in get_tree().get_nodes_in_group(group):
			if obj is Node2D and obj.get_parent() == main_node:
				if not objects_to_sync.has(obj):
					objects_to_sync.append(obj)
					valid_object_names.append(obj.name)
	
	rpc_id(peer_id, "purge_missing_objects", valid_object_names)
	
	for obj in objects_to_sync:
		var obj_data = _get_object_sync_data(obj)
		if obj_data != null:
			rpc_id(peer_id, "spawn_object_for_late_join", obj_data)

func _get_object_sync_data(obj: Node) -> Dictionary:
	if not obj is Node2D:
		return {}
	
	var data = {
		"scene_file_path": obj.scene_file_path if obj.scene_file_path != "" else "",
		"position": obj.position,
		"name": obj.name,
		"groups": obj.get_groups()
	}
	
	if obj.get_script() != null:
		data["script_path"] = obj.get_script().resource_path
		
	if "z_level" in obj:
		data["z_level"] = obj.get("z_level")
		
	if "hits" in obj: data["hits"] = obj.get("hits")
	if "state" in obj: data["state"] = obj.get("state")
	if "is_on" in obj: data["is_on"] = obj.get("is_on")
	if "_coal_count" in obj: data["_coal_count"] = obj.get("_coal_count")
	if "_ironore_count" in obj: data["_ironore_count"] = obj.get("_ironore_count")
	if "_fuel_type" in obj: data["_fuel_type"] = obj.get("_fuel_type")
	if "_smelting" in obj: data["_smelting"] = obj.get("_smelting")
	if "contents" in obj: data["contents"] = obj.get("contents").duplicate(true)
	if "amount" in obj: data["amount"] = obj.get("amount")
	
	if obj is Area2D:
		var script_str = str(obj.get_script())
		if "rock.gd" in script_str: data["type"] = "rock"
		elif "tree.gd" in script_str: data["type"] = "tree"
		elif "coin.gd" in script_str: data["type"] = "coin"
			
	return data

func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	
	var player_node = _find_player_by_peer(id)
	if player_node == null:
		return
	
	_handle_player_disconnection(id, player_node)

func _handle_player_disconnection(peer_id: int, player_node: Node) -> void:
	if not is_instance_valid(player_node):
		return
	
	var node = player_node as Node2D
	if not node.get("dead") and node.get("is_lying_down") == false:
		node.set("is_lying_down", true)
		if node.has_method("_cancel_stand_up"): node.call("_cancel_stand_up")
		if node.has_method("_update_sprite"): node.call("_update_sprite")
		if node.has_method("_update_water_submerge"): node.call("_update_water_submerge")
		if node.has_method("_rpc_sync_lying_down"): node.call("_rpc_sync_lying_down", true)

	var player_state = _capture_player_state(node)
	_disconnected_players[peer_id] = {
		"node_path": node.get_path(),
		"state": player_state,
		"timestamp": Time.get_ticks_msec()
	}
	
	rpc_set_disconnect_indicator.rpc(node.get_path(), true)
	
	var hand_names =[]
	for h in node.get("hands"):
		hand_names.append(h.name if h != null else "")
	
	update_player_state(peer_id, {
		"position": node.position,
		"disconnected": true,
		"health": node.get("health"),
		"hands": hand_names
	})

func _capture_player_state(player_node: Node2D) -> Dictionary:
	var state = {
		"character_name": player_node.get("character_name"),
		"character_class": player_node.get("character_class"),
		"position": player_node.position,
		"z_level": player_node.get("z_level"),
		"tile_pos": player_node.get("tile_pos"),
		"facing": player_node.get("facing"),
		"health": player_node.get("health"),
		"limb_hp": player_node.get("body").limb_hp.duplicate() if player_node.get("body") != null else {},
		"limb_broken": player_node.get("body").limb_broken.duplicate() if player_node.get("body") != null else {},
		"stamina": player_node.get("stamina"),
		"dead": player_node.get("dead"),
		"combat_mode": player_node.get("combat_mode"),
		"exhausted": player_node.get("exhausted"),
		"active_hand": player_node.get("active_hand"),
		"hands": _capture_hands_state(player_node),
		"equipped": _capture_equipped_state(player_node),
		"equipped_data": player_node.get("equipped_data").duplicate(true) if "equipped_data" in player_node else {},
		"pixel_pos": player_node.get("pixel_pos"),
		"moving": player_node.get("moving"),
		"move_elapsed": player_node.get("move_elapsed"),
		"move_from": player_node.get("move_from"),
		"move_to": player_node.get("move_to"),
		"current_move_duration": player_node.get("current_move_duration"),
		"action_cooldown": player_node.get("action_cooldown"),
		"buffered_dir": player_node.get("buffered_dir"),
		"throwing_mode": player_node.get("throwing_mode"),
		"intent": player_node.get("intent"),
		"sleep_state": player_node.get("sleep_state") if player_node.has_method("toggle_sleep") else 0,
		"is_lying_down": player_node.get("is_lying_down") == true,
		"skills": player_node.get("skills").duplicate() if player_node.get("skills") else {},
		"grabbed_by_peer": player_node.get("grabbed_by").get_multiplayer_authority() if (player_node.get("grabbed_by") != null and is_instance_valid(player_node.get("grabbed_by"))) else -1
	}
	return state

func _capture_equipped_state(player_node: Node2D) -> Dictionary:
	var CLOTHING_SCENE_PATHS = {
		"IronHelmet": "res://clothing/ironhelmet.tscn", "IronChestplate": "res://clothing/ironchestplate.tscn",
		"LeatherBoots": "res://clothing/leatherboots.tscn", "LeatherTrousers": "res://clothing/leathertrousers.tscn",
		"Apothshirt": "res://clothing/apothshirt.tscn", "Blackshirt": "res://clothing/blackshirt.tscn",
		"Undershirt": "res://clothing/undershirt.tscn", "Pickaxe": "res://objects/pickaxe.tscn",
		"Sword": "res://objects/sword.tscn", "Dirk": "res://objects/dirk.tscn", "KingCloak": "res://clothing/king_cloak.tscn",
	}
	var equipped_state = {}
	var eq = player_node.get("equipped")
	for slot in eq:
		var item = eq[slot]
		if item != null and not (item is String):
			equipped_state[slot] = {
				"item_type": item.get("item_type") if item.get("item_type") != null else "",
				"scene_file_path": item.scene_file_path if item.scene_file_path != "" else "",
				"node_name": item.name
			}
		elif item is String and item != "":
			equipped_state[slot] = {"item_type": item, "scene_file_path": CLOTHING_SCENE_PATHS.get(item, ""), "node_name": ""}
		else:
			equipped_state[slot] = null
	return equipped_state

func _capture_hands_state(player_node: Node2D) -> Array:
	var hands_state =[]
	var h_arr = player_node.get("hands")
	for i in range(2):
		var hand_item = h_arr[i]
		if hand_item != null and is_instance_valid(hand_item):
			var item_data = {
				"name": hand_item.name, "scene_file_path": hand_item.scene_file_path,
				"item_type": hand_item.get("item_type") if hand_item.has_method("get") else "",
				"position": hand_item.position, "slot": hand_item.get("slot") if hand_item.has_method("get") else "",
				"weaponizable": hand_item.get("weaponizable") if hand_item.has_method("get") else false,
				"force": hand_item.get("force") if hand_item.has_method("get") else 0
			}
			item_data["script_path"] = hand_item.get_script().resource_path if hand_item.get_script() != null else ""
			if "contents" in hand_item: item_data["contents"] = hand_item.get("contents").duplicate(true)
			if "amount" in hand_item: item_data["amount"] = hand_item.get("amount")
			hands_state.append(item_data)
		else: hands_state.append(null)
	return hands_state

func _handle_reconnection(peer_id: int) -> bool:
	if _disconnected_players.is_empty(): return false
	var best_peer_id = _find_best_reconnection_candidate()
	if best_peer_id == -1: return false
	
	var player_node_path = _disconnected_players[best_peer_id]["node_path"]
	var player_node = get_node_or_null(player_node_path)
	if player_node == null or not is_instance_valid(player_node):
		_disconnected_players.erase(best_peer_id); return false
	
	if Host.peers.has(peer_id):
		var ghost = Host.peers[peer_id]
		if is_instance_valid(ghost) and ghost != player_node: ghost.queue_free()
	
	Host.peers[peer_id] = player_node
	var success = _perform_reconnection(peer_id, best_peer_id, player_node, {}) 
	if success: _disconnected_players.erase(best_peer_id)
	else: Host.peers.erase(peer_id)
	return success

func _find_best_reconnection_candidate() -> int:
	var best_peer_id = -1
	var latest_time = 0
	for peer_id in _disconnected_players.keys():
		if _disconnected_players[peer_id]["timestamp"] > latest_time:
			latest_time = _disconnected_players[peer_id]["timestamp"]
			best_peer_id = peer_id
	return best_peer_id

func _perform_reconnection(new_peer_id: int, old_peer_id: int, player_node: Node, _player_state: Dictionary) -> bool:
	var node = player_node as Node2D
	var current_state = _capture_player_state(node)
	
	for grabber_peer_id in World.grab_map:
		var entry = World.grab_map[grabber_peer_id]
		if entry.get("is_player", false) and entry.get("target_peer_id", -1) == old_peer_id:
			entry["target_peer_id"] = new_peer_id
			entry["target"] = node
	
	_restore_player_state(node, current_state)
	_reassign_player_node(node, new_peer_id)
	
	rpc_set_disconnect_indicator.rpc(node.get_path(), false)
	
	var hand_names =[]
	for h in node.get("hands"):
		hand_names.append(h.name if h != null else "")
	
	update_player_state(new_peer_id, {"position": node.position, "disconnected": false, "health": node.get("health"), "hands": hand_names})
	if node.has_method("_on_reconnection_confirmed"): node.call("_on_reconnection_confirmed")
	if has_node("/root/Lobby"): get_node("/root/Lobby").rpc_hide_lobby.rpc_id(new_peer_id)
		
	receive_reconnect_state.rpc_id(new_peer_id, node.get_path(), current_state)
	return true

func _restore_player_state(player_node: Node2D, player_state: Dictionary) -> void:
	player_node.set("character_name", player_state.get("character_name", "noob"))
	player_node.set("character_class", player_state.get("character_class", "peasant"))
	player_node.position = player_state["position"]
	if player_state.has("z_level"):
		player_node.set("z_level", player_state["z_level"])
		player_node.z_index = (player_node.get("z_level") - 1) * 200 + 10
	player_node.set("tile_pos", player_state["tile_pos"])
	player_node.set("facing", player_state["facing"])
	player_node.set("health", player_state["health"])
	
	if player_state.has("limb_hp") and player_node.get("body") != null:
		player_node.get("body").limb_hp = player_state["limb_hp"].duplicate()
	if player_state.has("limb_broken") and player_node.get("body") != null:
		player_node.get("body").limb_broken = player_state["limb_broken"].duplicate()
		
	player_node.set("stamina", player_state["stamina"])
	player_node.set("dead", player_state["dead"])
	player_node.set("combat_mode", player_state["combat_mode"])
	if player_state.has("exhausted"): player_node.set("exhausted", player_state["exhausted"])
	player_node.set("active_hand", player_state["active_hand"])
	player_node.set("pixel_pos", player_state["pixel_pos"])
	player_node.set("moving", player_state["moving"])
	player_node.set("move_elapsed", player_state["move_elapsed"])
	player_node.set("move_from", player_state["move_from"])
	player_node.set("move_to", player_state["move_to"])
	player_node.set("current_move_duration", player_state["current_move_duration"])
	player_node.set("action_cooldown", player_state["action_cooldown"])
	player_node.set("buffered_dir", player_state["buffered_dir"])
	player_node.set("throwing_mode", player_state["throwing_mode"])
	player_node.set("intent", player_state["intent"])
	
	if player_state.has("sleep_state"):
		player_node.set("sleep_state", player_state["sleep_state"])
		if player_node.get("sleep_state") != 0 and player_node.has_method("_set_lying_down_visuals"):
			player_node.call("_set_lying_down_visuals", true)
	
	if player_state.has("is_lying_down"): player_node.set("is_lying_down", player_state["is_lying_down"])
	if player_state.has("skills"): player_node.set("skills", player_state["skills"].duplicate())
	if player_state.has("equipped_data"): player_node.set("equipped_data", player_state["equipped_data"].duplicate(true))
	
	if multiplayer.is_server() and player_state.has("grabbed_by_peer"):
		var grabber_peer = player_state["grabbed_by_peer"]
		if grabber_peer != -1:
			var grabber = _find_player_by_peer(grabber_peer)
			if grabber != null and is_instance_valid(grabber):
				player_node.set("grabbed_by", grabber)
				grabber.set("grabbed_target", player_node)
				World.rpc_confirm_grab_start.rpc(grabber_peer, true, player_node.get_multiplayer_authority(), player_node.get_path(), grabber.get("character_name"), player_node.get("character_name"), "chest", grabber.get("active_hand"))

	var eq_data = player_state["equipped"]
	var eq = player_node.get("equipped")
	for slot in eq_data:
		var item_data = eq_data[slot]
		if item_data == null: eq[slot] = null
		elif item_data is Dictionary: eq[slot] = item_data.get("item_type", "")
		elif item_data is String: eq[slot] = item_data if item_data != "" else null
		else: eq[slot] = null
	
	var hands_state = player_state["hands"]
	var h_arr = player_node.get("hands")
	for i in range(min(2, hands_state.size())):
		var h_data = hands_state[i]
		if h_data != null:
			if h_arr[i] == null or not is_instance_valid(h_arr[i]):
				var item = _recreate_hand_item(h_data)
				if item != null:
					h_arr[i] = item
					for child in item.get_children():
						if child is CollisionShape2D: child.disabled = true
		else: h_arr[i] = null
	
	if player_node.has_method("_update_sprite"): player_node.call("_update_sprite")
	if player_node.has_method("_update_clothing_sprites"): player_node.call("_update_clothing_sprites")
	if player_node.has_method("_update_hands_ui"): player_node.call("_update_hands_ui")
	if player_node.has_method("_update_water_submerge"): player_node.call("_update_water_submerge")

func _recreate_hand_item(hand_data: Dictionary) -> Node:
	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node == null: return null
	var existing = main_node.get_node_or_null(NodePath(hand_data["name"]))
	if existing != null: return existing
	var scene_path = hand_data.get("scene_file_path", "")
	if scene_path.is_empty():
		if hand_data.get("script_path", "").is_empty(): return null
		var script = load(hand_data["script_path"])
		if script == null: return null
		var fallback = Area2D.new(); fallback.set_script(script)
		fallback.name = hand_data["name"]; fallback.position = hand_data["position"]
		if hand_data.has("contents") and "contents" in fallback: fallback.set("contents", hand_data["contents"].duplicate(true))
		if hand_data.has("amount") and "amount" in fallback: fallback.set("amount", hand_data["amount"])
		main_node.add_child(fallback); return fallback
	var scene = load(scene_path) as PackedScene
	if scene == null: return null
	var item = scene.instantiate()
	item.name = hand_data["name"]; item.position = hand_data["position"]
	if hand_data.has("contents") and "contents" in item: item.set("contents", hand_data["contents"].duplicate(true))
	if hand_data.has("amount") and "amount" in item: item.set("amount", hand_data["amount"])
	main_node.add_child(item); return item

func _reassign_player_node(player_node: Node, new_peer_id: int) -> void:
	Host.peers[new_peer_id] = player_node
	rpc_update_player_authority.rpc(player_node.get_path(), new_peer_id)
	rpc_id(new_peer_id, "reconnection_confirmed", player_node.get_path())

func _attempt_manual_reconnection() -> void:
	if multiplayer.is_server(): return
	var enet = ENetMultiplayerPeer.new()
	var err = enet.create_client("127.0.0.1", Host.PORT)
	if err == OK: multiplayer.multiplayer_peer = enet

@rpc("authority", "call_local", "reliable")
func rpc_update_player_authority(player_path: NodePath, new_peer_id: int) -> void:
	var player = get_node_or_null(player_path)
	if player != null:
		player.set_multiplayer_authority(new_peer_id)
		if player.has_method("_on_authority_changed"): player.call("_on_authority_changed")

@rpc("authority", "call_local", "reliable")
func rpc_set_disconnect_indicator(player_path: NodePath, show: bool) -> void:
	var player = get_node_or_null(player_path)
	if not player: return
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

@rpc("authority", "call_remote", "reliable")
func receive_tile_changes(tile_changes: Dictionary) -> void:
	if World.tilemap == null: return
	for tile_pos in tile_changes:
		var change = tile_changes[tile_pos]
		World.tilemap.set_cell(Vector2i(tile_pos.x, tile_pos.y), change["source_id"], change["atlas_coords"])

@rpc("authority", "call_remote", "reliable") 
func receive_object_states(object_states: Dictionary) -> void:
	for obj_path in object_states:
		var obj_data = object_states[obj_path]
		var obj = get_node_or_null(obj_path)
		if obj != null:
			if obj.has_method("set_hits"): obj.call("set_hits", obj_data.get("hits", 0))
			if obj_data.has("amount") and "amount" in obj: obj.set("amount", obj_data["amount"])

@rpc("authority", "call_remote", "reliable")
func receive_player_states(player_states: Dictionary) -> void:
	for peer_id in player_states:
		var p_data = player_states[peer_id]
		var node = _find_player_by_peer(peer_id) as Node2D
		if node != null:
			var lp = World.get_local_player() as Node2D
			if lp != null and (p_data["position"] - lp.position).length() > 1000: node.position = p_data["position"]
			if p_data.has("z_level"): node.set("z_level", p_data["z_level"])
			if p_data.has("limb_hp") and node.get("body") != null: node.get("body").limb_hp = p_data["limb_hp"].duplicate()
			if p_data.has("limb_broken") and node.get("body") != null: node.get("body").limb_broken = p_data["limb_broken"].duplicate()
			if p_data.has("hands") and node.has_method("sync_hands"): node.call("sync_hands", p_data["hands"])
			if p_data.has("equipped_data") and "equipped_data" in node: node.set("equipped_data", p_data["equipped_data"].duplicate(true))
			if p_data.has("equipped"):
				var eq = node.get("equipped")
				for slot in p_data["equipped"]:
					var item = p_data["equipped"][slot]
					if item == null: eq[slot] = null
					elif item is Dictionary and item.has("item_type"): eq[slot] = item["item_type"] if item["item_type"] != "" else null
					elif item is String: eq[slot] = item if item != "" else null
					else: eq[slot] = null
				if node.has_method("_update_clothing_sprites"): node.call("_update_clothing_sprites")
			if p_data.has("is_lying_down"):
				node.set("is_lying_down", p_data["is_lying_down"])
				if node.has_method("_update_sprite"): node.call("_update_sprite")
				if node.has_method("_update_water_submerge"): node.call("_update_water_submerge")
			if node.has_method("_update_hands_ui"): node.call("_update_hands_ui")
			if node.get("_hud") != null: node.get("_hud").update_stats(node.get("health"), node.get("stamina"))

@rpc("authority", "call_remote", "reliable")
func purge_missing_objects(valid_names: Array) -> void:
	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node == null: return
	var groups =["pickable", "minable_object", "choppable_object", "inspectable", "door", "breakable_object"]
	for group in groups:
		for obj in get_tree().get_nodes_in_group(group):
			if obj is Node2D and obj.get_parent() == main_node and not obj.name in valid_names: obj.queue_free()

@rpc("authority", "call_remote", "reliable")
func spawn_object_for_late_join(obj_data: Dictionary) -> void:
	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node == null: return
	var obj_name = str(obj_data["name"])
	var obj = main_node.get_node_or_null(NodePath(obj_name))
	
	# If object exists, we might need to fix Z and registry
	if obj != null:
		if obj_data.has("z_level"):
			var new_z = obj_data["z_level"]
			var old_z = obj.get("z_level")
			if old_z != new_z:
				var tile = World._world_to_tile(obj.global_position)
				World.unregister_solid(tile, old_z, obj)
				World.register_solid(tile, new_z, obj)
				obj.set("z_level", new_z)
				obj.z_index = (new_z - 1) * 200 + (obj.z_index % 200)

	# If object doesn't exist, spawn it
	if obj == null:
		if obj_data.has("scene_file_path") and obj_data["scene_file_path"] != "":
			var scene = load(obj_data["scene_file_path"]) as PackedScene
			if scene != null: obj = scene.instantiate()
		if obj == null:
			match obj_data.get("type", ""):
				"rock": obj = (load("res://objects/rock.tscn") as PackedScene).instantiate()
				"tree": obj = (load("res://objects/tree.tscn") as PackedScene).instantiate()
				"coin": obj = (load("res://objects/coin.tscn") as PackedScene).instantiate()
				_:
					if obj_data.has("script_path"):
						var s = load(obj_data["script_path"]); if s: obj = Node2D.new(); obj.set_script(s)
		if obj != null:
			obj.name = obj_name
			if obj_data.has("z_level"):
				obj.set("z_level", obj_data["z_level"])
			main_node.add_child(obj)
			if obj_data.has("z_level"):
				obj.z_index = (obj.z_level - 1) * 200 + (obj.z_index % 200)

	if obj != null:
		obj.position = obj_data["position"]
		if obj_data.has("hits"):
			if obj.has_method("set_hits"): obj.call("set_hits", obj_data["hits"])
			else: obj.set("hits", obj_data["hits"])
		if obj_data.has("amount"): obj.set("amount", obj_data["amount"])
		if obj_data.has("state"):
			obj.set("state", obj_data["state"])
			if obj.has_method("_update_sprite"): obj.call("_update_sprite")
			if obj.has_method("_update_solidity"): obj.call("_update_solidity")
		if obj_data.has("is_on"): obj.set("is_on", obj_data["is_on"])
		if obj_data.has("_coal_count"): obj.set("_coal_count", obj_data["_coal_count"])
		if obj_data.has("_ironore_count"): obj.set("_ironore_count", obj_data["_ironore_count"])
		if obj_data.has("_fuel_type"): obj.set("_fuel_type", obj_data["_fuel_type"])
		if obj_data.has("_smelting"): obj.set("_smelting", obj_data["_smelting"])
		if obj_data.has("contents"): obj.set("contents", obj_data["contents"])
		if obj.has_method("_set_sprite") and obj_data.has("is_on"): obj.call("_set_sprite", obj_data["is_on"])

@rpc("authority", "call_remote", "reliable")
func receive_laws(laws: Array) -> void:
	World.current_laws = laws
	if Sidebar.has_method("refresh_laws_ui"): Sidebar.refresh_laws_ui()

@rpc("authority", "call_remote", "reliable")
func reconnection_confirmed(player_path: NodePath) -> void:
	var player = get_node_or_null(player_path)
	if player != null and player.has_method("_on_reconnection_confirmed"): player.call("_on_reconnection_confirmed")

@rpc("authority", "call_remote", "reliable")
func receive_reconnect_state(player_path: NodePath, player_state: Dictionary) -> void:
	await get_tree().create_timer(0.1).timeout
	var node = get_node_or_null(player_path) as Node2D
	if node != null:
		_restore_player_state(node, player_state)
		if node.get("is_lying_down") == true and node.has_method("toggle_lying_down"): node.call("toggle_lying_down")

func _find_player_by_peer(peer_id: int) -> Node:
	for p in get_tree().get_nodes_in_group("player"):
		if p.get_multiplayer_authority() == peer_id: return p
	return null

func _broadcast_state_updates() -> void:
	pass

func get_world_state() -> Dictionary:
	return _world_state.duplicate(true)

func is_player_disconnected(peer_id: int) -> bool:
	return _disconnected_players.has(peer_id)

@rpc("any_peer", "call_remote", "reliable")
func client_reconnection_confirmed() -> void:
	if has_node("/root/Main"):
		var main = get_node("/root/Main")
		if main.has_method("_on_client_reconnected"): main.call("_on_client_reconnected")

func update_disconnected_health(peer_id: int, new_health: int) -> void:
	if _disconnected_players.has(peer_id): _disconnected_players[peer_id]["state"]["health"] = new_health