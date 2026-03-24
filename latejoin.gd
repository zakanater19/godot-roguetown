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
	# Guard: if there is no multiplayer peer (e.g. after a disconnect/before hosting),
	# skip all multiplayer calls to prevent "No multiplayer peer is assigned" spam.
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
		var pid = p.get_multiplayer_authority()
		if pid == peer_id:
			continue
		var hand_names =[]
		for h in p.hands:
			hand_names.append(h.name if (h != null and is_instance_valid(h)) else "")
		var equipped_data = _capture_equipped_state(p)
		var eq_data_state = p.equipped_data.duplicate(true) if "equipped_data" in p else {}
		player_states[pid] = {
			"position": p.position,
			"disconnected": false,
			"health": p.health,
			"limb_hp": p.body.limb_hp.duplicate() if p.body != null else {},
			"limb_broken": p.body.limb_broken.duplicate() if p.body != null else {},
			"hands": hand_names,
			"equipped": equipped_data,
			"equipped_data": eq_data_state,
			"is_lying_down": p.get("is_lying_down") == true
		}
	
	if not player_states.is_empty():
		rpc_id(peer_id, "receive_player_states", player_states)
		
	# Send Laws
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
		
	# General property fetching for universal application
	if "hits" in obj:
		data["hits"] = obj.get("hits")
	if "state" in obj:
		data["state"] = obj.get("state")
	if "is_on" in obj:
		data["is_on"] = obj.get("is_on")
	if "_coal_count" in obj:
		data["_coal_count"] = obj.get("_coal_count")
	if "_ironore_count" in obj:
		data["_ironore_count"] = obj.get("_ironore_count")
	if "_fuel_type" in obj:
		data["_fuel_type"] = obj.get("_fuel_type")
	if "_smelting" in obj:
		data["_smelting"] = obj.get("_smelting")
	if "contents" in obj:
		data["contents"] = obj.get("contents").duplicate(true)
	
	if obj is Area2D:
		if "rock.gd" in str(obj.get_script()):
			data["type"] = "rock"
		elif "tree.gd" in str(obj.get_script()):
			data["type"] = "tree"
			
	return data

func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	
	print("LateJoin: Peer disconnected - ", id)
	var player_node = _find_player_by_peer(id)
	if player_node == null:
		print("LateJoin: Player node not found for disconnected peer ", id)
		return
	
	_handle_player_disconnection(id, player_node)

func _handle_player_disconnection(peer_id: int, player_node: Node) -> void:
	if not is_instance_valid(player_node):
		print("LateJoin: Player node invalid for peer ", peer_id)
		return
	
	print("LateJoin: Storing disconnected player data for peer ", peer_id)

	# --- Force the player to lie down before capturing state so the snapshot
	#     records is_lying_down = true, which will be restored on reconnect. ---
	if not player_node.dead and player_node.get("is_lying_down") == false:
		player_node.set("is_lying_down", true)
		if player_node.has_method("_cancel_stand_up"):
			player_node._cancel_stand_up()
		if player_node.has_method("_update_sprite"):
			player_node._update_sprite()
		if player_node.has_method("_update_water_submerge"):
			player_node._update_water_submerge()
		# Sync the lie-down to all still-connected clients
		if player_node.has_method("_rpc_sync_lying_down"):
			player_node._rpc_sync_lying_down.rpc(true)

	var player_state = _capture_player_state(player_node)
	
	_disconnected_players[peer_id] = {
		"node_path": player_node.get_path(),
		"state": player_state,
		"timestamp": Time.get_ticks_msec()
	}
	
	if multiplayer.is_server():
		rpc_set_disconnect_indicator.rpc(player_node.get_path(), true)
	
	var hand_names =[]
	for h in player_node.hands:
		hand_names.append(h.name if h != null else "")
	
	update_player_state(peer_id, {
		"position": player_node.position,
		"disconnected": true,
		"health": player_node.health,
		"hands": hand_names
	})
	
	print("LateJoin: Disconnected player stored with state keys: ", player_state.keys())

func _capture_player_state(player_node: Node) -> Dictionary:
	var state = {
		"character_name": player_node.character_name,
		"character_class": player_node.character_class,
		"position": player_node.position,
		"tile_pos": player_node.tile_pos,
		"facing": player_node.facing,
		"health": player_node.health,
		"limb_hp": player_node.body.limb_hp.duplicate() if player_node.body != null else {},
		"limb_broken": player_node.body.limb_broken.duplicate() if player_node.body != null else {},
		"stamina": player_node.stamina,
		"dead": player_node.dead,
		"combat_mode": player_node.combat_mode,
		"exhausted": player_node.exhausted,
		"active_hand": player_node.active_hand,
		"hands": _capture_hands_state(player_node),
		"equipped": _capture_equipped_state(player_node),
		"equipped_data": player_node.equipped_data.duplicate(true) if "equipped_data" in player_node else {},
		"pixel_pos": player_node.pixel_pos,
		"moving": player_node.moving,
		"move_elapsed": player_node.move_elapsed,
		"move_from": player_node.move_from,
		"move_to": player_node.move_to,
		"current_move_duration": player_node.current_move_duration,
		"action_cooldown": player_node.action_cooldown,
		"buffered_dir": player_node.buffered_dir,
		"throwing_mode": player_node.throwing_mode,
		"intent": player_node.intent,
		"sleep_state": player_node.get("sleep_state") if player_node.has_method("toggle_sleep") else 0,
		"is_lying_down": player_node.get("is_lying_down") == true,
		"skills": player_node.skills.duplicate() if player_node.skills else {},
		"grabbed_by_peer": player_node.grabbed_by.get_multiplayer_authority() if (player_node.grabbed_by != null and is_instance_valid(player_node.grabbed_by)) else -1
	}
	return state

func _capture_equipped_state(player_node: Node) -> Dictionary:
	var CLOTHING_SCENE_PATHS = {
		"IronHelmet":      "res://clothing/ironhelmet.tscn",
		"IronChestplate":  "res://clothing/ironchestplate.tscn",
		"LeatherBoots":    "res://clothing/leatherboots.tscn",
		"LeatherTrousers": "res://clothing/leathertrousers.tscn",
		"Apothshirt":      "res://clothing/apothshirt.tscn",
		"Blackshirt":      "res://clothing/blackshirt.tscn",
		"Undershirt":      "res://clothing/undershirt.tscn",
		"Pickaxe":         "res://objects/pickaxe.tscn",
		"Sword":           "res://objects/sword.tscn",
		"Dirk":            "res://objects/dirk.tscn",
		"KingCloak":       "res://clothing/king_cloak.tscn",
	}
	var equipped_state = {}
	for slot in player_node.equipped:
		var item = player_node.equipped[slot]
		if item != null and not (item is String):
			equipped_state[slot] = {
				"item_type": item.get("item_type") if item.get("item_type") != null else "",
				"scene_file_path": item.scene_file_path if item.scene_file_path != "" else "",
				"node_name": item.name
			}
		elif item is String and item != "":
			var scene_path = CLOTHING_SCENE_PATHS.get(item, "")
			equipped_state[slot] = {
				"item_type": item,
				"scene_file_path": scene_path,
				"node_name": ""
			}
		else:
			equipped_state[slot] = null
	return equipped_state

func _capture_hands_state(player_node: Node) -> Array:
	var hands_state =[]
	for i in range(2):
		var hand_item = player_node.hands[i]
		if hand_item != null and is_instance_valid(hand_item):
			var item_data = {
				"name": hand_item.name,
				"scene_file_path": hand_item.scene_file_path,
				"item_type": hand_item.get("item_type") if hand_item.has_method("get") else "",
				"position": hand_item.position,
				"slot": hand_item.get("slot") if hand_item.has_method("get") else "",
				"weaponizable": hand_item.get("weaponizable") if hand_item.has_method("get") else false,
				"force": hand_item.get("force") if hand_item.has_method("get") else 0
			}
			if hand_item.get_script() != null:
				item_data["script_path"] = hand_item.get_script().resource_path
			else:
				item_data["script_path"] = ""
				
			if "contents" in hand_item:
				item_data["contents"] = hand_item.get("contents").duplicate(true)
				
			hands_state.append(item_data)
		else:
			hands_state.append(null)
	return hands_state

func _handle_reconnection(peer_id: int) -> bool:
	print("LateJoin: Checking for reconnection for peer ", peer_id)
	
	if _disconnected_players.is_empty():
		print("LateJoin: No disconnected players available for reconnection")
		return false
	
	var best_peer_id = _find_best_reconnection_candidate()
	if best_peer_id == -1:
		print("LateJoin: No valid reconnection candidate found")
		return false
	
	var disconnected_data = _disconnected_players[best_peer_id]
	var player_node_path = disconnected_data["node_path"]
	
	var player_node = get_node_or_null(player_node_path)
	if player_node == null or not is_instance_valid(player_node):
		print("LateJoin: Player node not found or invalid at path: ", player_node_path)
		_disconnected_players.erase(best_peer_id)
		return false
	
	print("LateJoin: Reconnecting peer ", peer_id, " to player ", best_peer_id)
	
	if Host.peers.has(peer_id):
		var ghost_player = Host.peers[peer_id]
		if is_instance_valid(ghost_player) and ghost_player != player_node:
			print("LateJoin: Cleaning up ghost player spawned for ", peer_id)
			ghost_player.queue_free()
	
	Host.peers[peer_id] = player_node
	var success = _perform_reconnection(peer_id, best_peer_id, player_node, {}) 
	
	if success:
		_disconnected_players.erase(best_peer_id)
		print("LateJoin: Reconnection successful!")
	else:
		if Host.peers.has(peer_id):
			Host.peers.erase(peer_id)
		print("LateJoin: Reconnection failed!")
	
	return success

func _find_best_reconnection_candidate() -> int:
	var best_peer_id = -1
	var latest_time = 0
	
	for peer_id in _disconnected_players.keys():
		var data = _disconnected_players[peer_id]
		if data["timestamp"] > latest_time:
			latest_time = data["timestamp"]
			best_peer_id = peer_id
	
	return best_peer_id

func _perform_reconnection(new_peer_id: int, old_peer_id: int, player_node: Node, _player_state: Dictionary) -> bool:
	# Capture the player's live current state, since their body remained in the world
	# and may have been shoved, attacked, or looted while disconnected.
	var current_state = _capture_player_state(player_node)
	
	# FIX: Re-link grab targets if the player was being dragged
	for grabber_peer_id in World._grab_map:
		var entry = World._grab_map[grabber_peer_id]
		if entry.get("is_player", false) and entry.get("target_peer_id", -1) == old_peer_id:
			entry["target_peer_id"] = new_peer_id
			entry["target"] = player_node
	
	_restore_player_state(player_node, current_state)
	_reassign_player_node(player_node, new_peer_id)
	
	if multiplayer.is_server():
		rpc_set_disconnect_indicator.rpc(player_node.get_path(), false)
	
	var hand_names =[]
	for h in player_node.hands:
		hand_names.append(h.name if h != null else "")
		
	update_player_state(new_peer_id, {
		"position": player_node.position,
		"disconnected": false,
		"health": player_node.health,
		"hands": hand_names
	})
	
	if player_node.has_method("_on_reconnection_confirmed"):
		player_node._on_reconnection_confirmed()
		
	if has_node("/root/Lobby"):
		get_node("/root/Lobby").rpc_hide_lobby.rpc_id(new_peer_id)
		
	receive_reconnect_state.rpc_id(new_peer_id, player_node.get_path(), current_state)
	
	return true

func _restore_player_state(player_node: Node, player_state: Dictionary) -> void:
	player_node.character_name = player_state.get("character_name", "noob")
	player_node.character_class = player_state.get("character_class", "peasant")
	player_node.position = player_state["position"]
	player_node.tile_pos = player_state["tile_pos"]
	player_node.facing = player_state["facing"]
	player_node.health = player_state["health"]
	
	if player_state.has("limb_hp") and player_node.body != null:
		player_node.body.limb_hp = player_state["limb_hp"].duplicate()
	if player_state.has("limb_broken") and player_node.body != null:
		player_node.body.limb_broken = player_state["limb_broken"].duplicate()
		
	player_node.stamina = player_state["stamina"]
	player_node.dead = player_state["dead"]
	player_node.combat_mode = player_state["combat_mode"]
	if player_state.has("exhausted"):
		player_node.exhausted = player_state["exhausted"]
	player_node.active_hand = player_state["active_hand"]
	player_node.pixel_pos = player_state["pixel_pos"]
	player_node.moving = player_state["moving"]
	player_node.move_elapsed = player_state["move_elapsed"]
	player_node.move_from = player_state["move_from"]
	player_node.move_to = player_state["move_to"]
	player_node.current_move_duration = player_state["current_move_duration"]
	player_node.action_cooldown = player_state["action_cooldown"]
	player_node.buffered_dir = player_state["buffered_dir"]
	player_node.throwing_mode = player_state["throwing_mode"]
	player_node.intent = player_state["intent"]
	
	if player_state.has("sleep_state"):
		player_node.sleep_state = player_state["sleep_state"]
		if player_node.sleep_state != 0 and player_node.has_method("_set_lying_down_visuals"):
			player_node._set_lying_down_visuals(true)
	
	if player_state.has("is_lying_down"):
		player_node.set("is_lying_down", player_state["is_lying_down"])
	
	if player_state.has("skills"):
		player_node.skills = player_state["skills"].duplicate()
		
	if player_state.has("equipped_data") and "equipped_data" in player_node:
		player_node.equipped_data = player_state["equipped_data"].duplicate(true)
	
	# Restore grab status
	if multiplayer.is_server() and player_state.has("grabbed_by_peer"):
		var grabber_peer = player_state["grabbed_by_peer"]
		if grabber_peer != -1:
			var grabber = _find_player_by_peer(grabber_peer)
			if grabber != null and is_instance_valid(grabber):
				# Relink references on server
				player_node.grabbed_by = grabber
				grabber.grabbed_target = player_node
				
				# Force refresh on grabber's UI
				_rpc_force_update_grab_ui.rpc_id(grabber_peer)
				
				# Force grabber to update their 'grabbed_target' pointer
				_rpc_set_grabbed_target.rpc_id(grabber_peer, player_node.get_path())
				
				# Sync grabbed_by to the target client
				_rpc_set_grabbed_by.rpc_id(player_node.get_multiplayer_authority(), grabber.get_path())

	var equipped_data = player_state["equipped"]
	for slot in equipped_data:
		var item_data = equipped_data[slot]
		if item_data == null:
			player_node.equipped[slot] = null
		elif item_data is Dictionary:
			player_node.equipped[slot] = item_data.get("item_type", "")
		elif item_data is String:
			player_node.equipped[slot] = item_data if item_data != "" else null
		else:
			player_node.equipped[slot] = null
	
	var hands_state = player_state["hands"]
	for i in range(min(2, hands_state.size())):
		var hand_data = hands_state[i]
		if hand_data != null:
			if player_node.hands[i] == null or not is_instance_valid(player_node.hands[i]):
				var item = _recreate_hand_item(hand_data)
				if item != null:
					player_node.hands[i] = item
					for child in item.get_children():
						if child is CollisionShape2D:
							child.disabled = true
		else:
			player_node.hands[i] = null
	
	if player_node.has_method("_update_sprite"):
		player_node._update_sprite()
	if player_node.has_method("_update_clothing_sprites"):
		player_node._update_clothing_sprites()
	if player_node.has_method("_update_hands_ui"):
		player_node._update_hands_ui()
	if player_node.has_method("_update_water_submerge"):
		player_node._update_water_submerge()

func _recreate_hand_item(hand_data: Dictionary) -> Node:
	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node == null:
		return null
		
	var existing = main_node.get_node_or_null(NodePath(hand_data["name"]))
	if existing != null:
		return existing
		
	var scene_path = hand_data.get("scene_file_path", "")
	if scene_path.is_empty():
		if hand_data.get("script_path", "").is_empty():
			return null
		var script = load(hand_data["script_path"])
		if script == null:
			return null
		var fallback_item = Area2D.new()
		fallback_item.set_script(script)
		fallback_item.name = hand_data["name"]
		fallback_item.position = hand_data["position"]
		
		if hand_data.has("contents") and "contents" in fallback_item:
			fallback_item.set("contents", hand_data["contents"].duplicate(true))
			
		main_node.add_child(fallback_item)
		return fallback_item
		
	var scene = load(scene_path) as PackedScene
	if scene == null:
		return null
		
	var item = scene.instantiate()
	item.name = hand_data["name"]
	item.position = hand_data["position"]
	
	if hand_data.has("contents") and "contents" in item:
		item.set("contents", hand_data["contents"].duplicate(true))
		
	main_node.add_child(item)
	
	return item

func _reassign_player_node(player_node: Node, new_peer_id: int) -> void:
	Host.peers[new_peer_id] = player_node
	rpc_update_player_authority.rpc(player_node.get_path(), new_peer_id)
	rpc_id(new_peer_id, "reconnection_confirmed", player_node.get_path())

func _attempt_manual_reconnection() -> void:
	if multiplayer.is_server():
		print("LateJoin: Cannot manually reconnect on server")
		return
	
	print("LateJoin: Attempting manual reconnection...")
	var enet = ENetMultiplayerPeer.new()
	var err = enet.create_client("127.0.0.1", Host.PORT)
	
	if err == OK:
		multiplayer.multiplayer_peer = enet
		print("LateJoin: Reconnection attempt sent")
	else:
		print("LateJoin: Reconnection failed - ", err)

@rpc("authority", "call_local", "reliable")
func rpc_update_player_authority(player_path: NodePath, new_peer_id: int) -> void:
	var player = get_node_or_null(player_path)
	if player != null:
		player.set_multiplayer_authority(new_peer_id)
		if player.has_method("_on_authority_changed"):
			player._on_authority_changed()

@rpc("authority", "call_remote", "reliable")
func _rpc_force_update_grab_ui() -> void:
	var local_player = World.get_local_player()
	if local_player and local_player.has_method("_update_grab_ui"):
		local_player._update_grab_ui()

@rpc("authority", "call_remote", "reliable")
func _rpc_set_grabbed_by(grabber_path: NodePath) -> void:
	var local_player = World.get_local_player()
	if local_player:
		local_player.grabbed_by = get_node_or_null(grabber_path)
		local_player._update_grab_ui()

@rpc("authority", "call_remote", "reliable")
func _rpc_set_grabbed_target(target_path: NodePath) -> void:
	var local_player = World.get_local_player()
	if local_player:
		local_player.grabbed_target = get_node_or_null(target_path)
		local_player._update_grab_ui()

@rpc("authority", "call_local", "reliable")
func rpc_set_disconnect_indicator(player_path: NodePath, show: bool) -> void:
	var player = get_node_or_null(player_path)
	if not player: 
		return
	
	var existing = player.get_node_or_null("DisconnectIndicator")
	if existing:
		existing.queue_free()
		
	if show:
		var indicator = Node2D.new()
		indicator.name = "DisconnectIndicator"
		indicator.position = Vector2(0, -50)  # Above player's head
		player.add_child(indicator)
		
		var label = Label.new()
		label.text = " ?! "
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
	if World.tilemap == null:
		return
	
	for tile_pos in tile_changes:
		var change = tile_changes[tile_pos]
		World.tilemap.set_cell(
			Vector2i(tile_pos.x, tile_pos.y),
			change["source_id"],
			change["atlas_coords"]
		)

@rpc("authority", "call_remote", "reliable") 
func receive_object_states(object_states: Dictionary) -> void:
	for obj_path in object_states:
		var obj_data = object_states[obj_path]
		var obj = get_node_or_null(obj_path)
		if obj != null and obj.has_method("set_hits"):
			obj.set_hits(obj_data.get("hits", 0))

@rpc("authority", "call_remote", "reliable")
func receive_player_states(player_states: Dictionary) -> void:
	for peer_id in player_states:
		var player_data = player_states[peer_id]
		var player_node = _find_player_by_peer(peer_id)
		if player_node != null:
			var local_player = World.get_local_player()
			if local_player != null:
				var distance = (player_data["position"] - local_player.position).length()
				if distance > 1000:
					player_node.position = player_data["position"]
			
			if player_data.has("limb_hp") and player_node.body != null:
				player_node.body.limb_hp = player_data["limb_hp"].duplicate()
			if player_data.has("limb_broken") and player_node.body != null:
				player_node.body.limb_broken = player_data["limb_broken"].duplicate()
			
			if player_data.has("hands"):
				if player_node.has_method("sync_hands"):
					player_node.sync_hands(player_data["hands"])
					
			if player_data.has("equipped_data") and "equipped_data" in player_node:
				player_node.equipped_data = player_data["equipped_data"].duplicate(true)
			
			if player_data.has("equipped"):
				for slot in player_data["equipped"]:
					var item_data = player_data["equipped"][slot]
					if item_data == null:
						player_node.equipped[slot] = null
					elif item_data is Dictionary and item_data.has("item_type"):
						var item_type = item_data["item_type"]
						if item_type == "":
							player_node.equipped[slot] = null
						else:
							player_node.equipped[slot] = item_type
					elif item_data is String:
						player_node.equipped[slot] = item_data if item_data != "" else null
					else:
						player_node.equipped[slot] = null
						
				if player_node.has_method("_update_clothing_sprites"):
					player_node._update_clothing_sprites()
			
			if player_data.has("is_lying_down"):
				player_node.set("is_lying_down", player_data["is_lying_down"])
				if player_node.has_method("_update_sprite"):
					player_node._update_sprite()
				if player_node.has_method("_update_water_submerge"):
					player_node._update_water_submerge()
			
			if player_node.has_method("_update_hands_ui"):
				player_node._update_hands_ui()
			if player_node.get("_hud") != null:
				player_node._hud.update_stats(player_node.health, player_node.stamina)

@rpc("authority", "call_remote", "reliable")
func purge_missing_objects(valid_names: Array) -> void:
	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node == null:
		return
		
	var sync_groups =["pickable", "minable_object", "choppable_object", "inspectable", "door", "breakable_object"]
	for group in sync_groups:
		for obj in get_tree().get_nodes_in_group(group):
			if obj is Node2D and obj.get_parent() == main_node:
				if not obj.name in valid_names:
					obj.queue_free()

@rpc("authority", "call_remote", "reliable")
func spawn_object_for_late_join(obj_data: Dictionary) -> void:
	var main_node = get_tree().root.get_node_or_null("Main")
	if main_node == null:
		return
	
	var obj_name = str(obj_data["name"])
	var obj = main_node.get_node_or_null(NodePath(obj_name))
	
	if obj == null:
		if obj_data.has("scene_file_path") and obj_data["scene_file_path"] != "":
			var scene = load(obj_data["scene_file_path"]) as PackedScene
			if scene != null:
				obj = scene.instantiate()
				
		if obj == null:
			match obj_data.get("type", ""):
				"rock":
					var scene = load("res://objects/rock.tscn") as PackedScene
					if scene: obj = scene.instantiate()
				"tree":
					var scene = load("res://objects/tree.tscn") as PackedScene
					if scene: obj = scene.instantiate()
				_:
					if obj_data.has("script_path"):
						var script = load(obj_data["script_path"])
						if script != null:
							obj = Node2D.new()
							obj.set_script(script)
	
		if obj != null:
			obj.name = obj_name
			main_node.add_child(obj)
			
	if obj != null:
		obj.position = obj_data["position"]
		
		# Apply robust state variables
		if obj_data.has("hits"):
			if obj.has_method("set_hits"):
				obj.set_hits(obj_data["hits"])
			else:
				obj.set("hits", obj_data["hits"])
				
		if obj_data.has("state"):
			obj.set("state", obj_data["state"])
			if obj.has_method("_update_sprite"):
				obj._update_sprite()
			if obj.has_method("_update_solidity"):
				obj._update_solidity()
				
		if obj_data.has("is_on"):
			obj.set("is_on", obj_data["is_on"])
		if obj_data.has("_coal_count"):
			obj.set("_coal_count", obj_data["_coal_count"])
		if obj_data.has("_ironore_count"):
			obj.set("_ironore_count", obj_data["_ironore_count"])
		if obj_data.has("_fuel_type"):
			obj.set("_fuel_type", obj_data["_fuel_type"])
		if obj_data.has("_smelting"):
			obj.set("_smelting", obj_data["_smelting"])
		if obj_data.has("contents"):
			obj.set("contents", obj_data["contents"])
			
		if obj.has_method("_set_sprite") and obj_data.has("is_on"):
			obj._set_sprite(obj_data["is_on"])

@rpc("authority", "call_remote", "reliable")
func receive_laws(laws: Array) -> void:
	World.current_laws = laws
	if Sidebar.has_method("refresh_laws_ui"):
		Sidebar.refresh_laws_ui()

@rpc("authority", "call_remote", "reliable")
func reconnection_confirmed(player_path: NodePath) -> void:
	var player = get_node_or_null(player_path)
	if player != null and player.has_method("_on_reconnection_confirmed"):
		player._on_reconnection_confirmed()

@rpc("authority", "call_remote", "reliable")
func receive_reconnect_state(player_path: NodePath, player_state: Dictionary) -> void:
	await get_tree().create_timer(0.1).timeout
	var player_node = get_node_or_null(player_path)
	if player_node != null:
		_restore_player_state(player_node, player_state)
		# --- Trigger stand-up attempt if the player was laid down on disconnect.
		#     _restore_player_state sets is_lying_down = true from the snapshot,
		#     so toggle_lying_down() here starts the 2-second stand-up timer,
		#     exactly as if the player had pressed V while prone. ---
		if player_node.get("is_lying_down") == true:
			if player_node.has_method("toggle_lying_down"):
				player_node.toggle_lying_down()

func _find_player_by_peer(peer_id: int) -> Node:
	for p in get_tree().get_nodes_in_group("player"):
		if p.get_multiplayer_authority() == peer_id:
			return p
	return null

func _broadcast_state_updates() -> void:
	for peer_id in multiplayer.get_peers():
		if peer_id != 1:
			pass

func get_world_state() -> Dictionary:
	return _world_state.duplicate(true)

func is_player_disconnected(peer_id: int) -> bool:
	return _disconnected_players.has(peer_id)

@rpc("any_peer", "call_remote", "reliable")
func client_reconnection_confirmed() -> void:
	print("LateJoin: Reconnection confirmed on client")
	if has_node("/root/Main"):
		var main = get_node("/root/Main")
		if main.has_method("_on_client_reconnected"):
			main._on_client_reconnected()

# ----- NEW METHOD FOR HEALTH UPDATE -----
func update_disconnected_health(peer_id: int, new_health: int) -> void:
	if _disconnected_players.has(peer_id):
		_disconnected_players[peer_id]["state"]["health"] = new_health
		print("LateJoin: Updated stored health for peer ", peer_id, " to ", new_health)
		
