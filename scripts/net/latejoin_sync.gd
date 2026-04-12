# res://scripts/net/latejoin_sync.gd
# Handles world-state synchronisation for late-joining clients.
extends RefCounted

var lj: Node  # reference to the LateJoin autoload node

func _init(latejoin_node: Node) -> void:
	lj = latejoin_node

# ---------------------------------------------------------------------------
# Server-side: push world state to a joining peer
# ---------------------------------------------------------------------------

func send_world_state_to_peer(peer_id: int) -> void:
	var tile_changes = lj._world_state["tiles"]
	if not tile_changes.is_empty():
		lj.rpc_id(peer_id, "receive_tile_changes", tile_changes)

	var object_states = lj._world_state["objects"]
	if not object_states.is_empty():
		lj.rpc_id(peer_id, "receive_object_states", object_states)

	sync_objects_for_late_joiner(peer_id)

	var player_states = {
		"by_peer": {},
		"by_entity": {},
	}
	for p in lj.get_tree().get_nodes_in_group("player"):
		var node = p as Node2D
		if node == null:
			continue
		var entity_id = World.get_entity_id(node)
		if node.get("is_possessed") == false:
			# Corpses can share a peer ID with an active ghost, so sync them by stable entity ID.
			if entity_id != "":
				player_states["by_entity"][entity_id] = lj._reconnect.capture_player_state(node)
			continue
		var sync_state = _build_player_sync_state(node)
		var pid  = node.get_multiplayer_authority()
		if pid == peer_id:
			continue
		player_states["by_peer"][pid] = sync_state

	if not player_states["by_peer"].is_empty() or not player_states["by_entity"].is_empty():
		lj.rpc_id(peer_id, "receive_player_states", player_states)

	lj.rpc_id(peer_id, "receive_laws", World.current_laws)

func _build_player_sync_state(node: Node2D) -> Dictionary:
	var hand_ids = []
	var hand_states = lj._reconnect.capture_hands_state(node)
	for h in node.get("hands"):
		hand_ids.append(World.get_entity_id(h) if (h != null and is_instance_valid(h)) else "")
	var equipped_data = lj._reconnect.capture_equipped_state(node)
	var eq_data_state = node.get("equipped_data").duplicate(true) if "equipped_data" in node else {}
	return {
		"position":       node.position,
		"z_level":        node.get("z_level"),
		"disconnected":   false,
		"health":         node.get("health"),
		"dead":           node.get("dead") == true,
		"limb_hp":        node.get("body").limb_hp.duplicate() if node.get("body") != null else {},
		"limb_broken":    node.get("body").limb_broken.duplicate() if node.get("body") != null else {},
		"hands":          hand_ids,
		"hand_states":    hand_states,
		"equipped":       equipped_data,
		"equipped_data":  eq_data_state,
		"is_lying_down":  node.get("is_lying_down") == true,
		"is_sneaking":    node.get("is_sneaking") == true,
		"sneak_alpha":    node.get("sneak_alpha") if "sneak_alpha" in node else 1.0
	}

func sync_objects_for_late_joiner(peer_id: int) -> void:
	var main_node = World.main_scene
	if main_node == null:
		return

	var objects_to_sync   = []
	var valid_object_ids = []
	var held_object_ids := _collect_held_object_ids()
	var sync_groups = ["pickable", "minable_object", "choppable_object", "inspectable", "door", "gate", "breakable_object"]

	for group in sync_groups:
		for obj in lj.get_tree().get_nodes_in_group(group):
			if obj is Node2D and obj.get_parent() == main_node:
				var obj_id := World.register_entity(obj)
				if held_object_ids.has(obj_id):
					continue
				if not objects_to_sync.has(obj):
					objects_to_sync.append(obj)
					valid_object_ids.append(obj_id)

	lj.rpc_id(peer_id, "purge_missing_objects", valid_object_ids)

	for obj in objects_to_sync:
		var obj_data = get_object_sync_data(obj)
		if obj_data != null:
			lj.rpc_id(peer_id, "spawn_object_for_late_join", obj_data)

func _collect_held_object_ids() -> Dictionary:
	var held_object_ids := {}
	for player_node in lj.get_tree().get_nodes_in_group("player"):
		var hands: Variant = player_node.get("hands")
		if not (hands is Array):
			continue
		for hand_item in hands:
			if hand_item == null or not is_instance_valid(hand_item):
				continue
			var entity_id := World.get_entity_id(hand_item)
			if entity_id != "":
				held_object_ids[entity_id] = true
	return held_object_ids

func get_object_sync_data(obj: Node) -> Dictionary:
	if not obj is Node2D:
		return {}

	var data = {
		"scene_file_path": obj.scene_file_path if obj.scene_file_path != "" else "",
		"position":        obj.position,
		"name":            obj.name,
		"entity_id":       World.register_entity(obj),
		"groups":          obj.get_groups(),
		"child_index":     obj.get_index(),
	}

	if obj.get_script() != null:
		data["script_path"] = obj.get_script().resource_path

	if "z_level"       in obj: data["z_level"]       = obj.get("z_level")
	if "z_index"       in obj: data["z_index"]       = obj.get("z_index")
	if "hits"          in obj: data["hits"]           = obj.get("hits")
	if "state"         in obj: data["state"]          = obj.get("state")
	if "is_on"         in obj: data["is_on"]          = obj.get("is_on")
	if "_coal_count"   in obj: data["_coal_count"]    = obj.get("_coal_count")
	if "_ironore_count" in obj: data["_ironore_count"] = obj.get("_ironore_count")
	if "_fuel_type"    in obj: data["_fuel_type"]     = obj.get("_fuel_type")
	if "_smelting"     in obj: data["_smelting"]      = obj.get("_smelting")
	if "contents"      in obj: data["contents"]       = obj.get("contents").duplicate(true)
	if "amount"        in obj: data["amount"]         = obj.get("amount")
	if "metal_type"    in obj: data["metal_type"]     = obj.get("metal_type")
	if "stored_balance" in obj: data["stored_balance"] = obj.get("stored_balance")
	if "key_id"        in obj: data["key_id"]         = obj.get("key_id")
	if "is_locked"     in obj: data["is_locked"]      = obj.get("is_locked")
	if "tree_id"       in obj: data["tree_id"]        = obj.get("tree_id")
	if "piece_kind"    in obj: data["piece_kind"]     = obj.get("piece_kind")
	if "support_segment_name" in obj: data["support_segment_name"] = obj.get("support_segment_name")
	if "hits_to_break" in obj: data["hits_to_break"]  = obj.get("hits_to_break")
	if "drop_count"    in obj: data["drop_count"]     = obj.get("drop_count")
	if "atlas_index"   in obj: data["atlas_index"]    = obj.get("atlas_index")
	if "solid_piece"   in obj: data["solid_piece"]    = obj.get("solid_piece")
	if "blocks_fov"    in obj: data["blocks_fov"]     = obj.get("blocks_fov")
	if "decor_configs" in obj: data["decor_configs"]  = obj.get("decor_configs").duplicate(true)

	if obj is Area2D:
		var script_str = str(obj.get_script())
		if "rock.gd"  in script_str: data["type"] = "rock"
		elif "tree.gd" in script_str: data["type"] = "tree"
		elif "coin.gd" in script_str: data["type"] = "coin"

	return data

func _apply_pre_add_object_state(obj: Node, obj_data: Dictionary) -> void:
	var pre_add_keys := [
		"z_level",
		"tree_id",
		"piece_kind",
		"support_segment_name",
		"hits_to_break",
		"drop_count",
		"atlas_index",
		"solid_piece",
		"blocks_fov",
		"decor_configs",
	]

	for key in pre_add_keys:
		if not obj_data.has(key):
			continue
		if not (key in obj):
			continue
		var value = obj_data[key]
		if value is Array or value is Dictionary:
			obj.set(key, value.duplicate(true))
		else:
			obj.set(key, value)

# ---------------------------------------------------------------------------
# Client-side: receive and apply world state
# ---------------------------------------------------------------------------

func handle_receive_tile_changes(tile_changes: Dictionary) -> void:
	for key in tile_changes:
		var change  = tile_changes[key]
		var z_level = change.get("z_level", 3)
		var tm      = World.get_tilemap(z_level)
		if tm != null:
			tm.set_cell(change["tile_pos"], change["source_id"], change["atlas_coords"])

func handle_receive_object_states(object_states: Dictionary) -> void:
	_retry_receive_object_states(object_states, 20)

func _retry_receive_object_states(object_states: Dictionary, retries: int) -> void:
	var missing = {}
	for obj_ref in object_states:
		var obj_data = object_states[obj_ref]
		var obj = World.get_entity(str(obj_ref))
		if obj == null:
			obj = lj.get_node_or_null(obj_ref)
		if obj != null:
			if obj.has_method("set_hits"): obj.call("set_hits", obj_data.get("hits", 0))
			if obj_data.has("amount")     and "amount"     in obj: obj.set("amount",     obj_data["amount"])
			if obj_data.has("metal_type") and "metal_type" in obj: obj.set("metal_type", obj_data["metal_type"])
			if obj_data.has("stored_balance") and obj.has_method("_update_merchant_balance"): obj.call("_update_merchant_balance", int(obj_data["stored_balance"]))
			if obj_data.has("contents")   and "contents"   in obj: obj.set("contents",   obj_data["contents"].duplicate(true))
			if obj_data.has("key_id")     and "key_id"     in obj: obj.set("key_id",     obj_data["key_id"])
			if obj_data.has("is_locked")  and "is_locked"  in obj: obj.set("is_locked",  obj_data["is_locked"])
			if obj.has_method("_update_sprite"): obj.call("_update_sprite")
		else:
			missing[obj_ref] = obj_data

	if not missing.is_empty() and retries > 0:
		await lj.get_tree().create_timer(0.1).timeout
		_retry_receive_object_states(missing, retries - 1)

func handle_receive_player_states(player_states: Dictionary) -> void:
	_retry_receive_player_states(player_states, 20)

func _retry_receive_player_states(player_states: Dictionary, retries: int) -> void:
	var missing = {}

	var peer_states: Dictionary = {}
	var entity_states: Dictionary = {}
	if player_states.has("by_peer") or player_states.has("by_entity"):
		peer_states = player_states.get("by_peer", {})
		entity_states = player_states.get("by_entity", {})
	else:
		# Backward-compatible fallback for older flat payloads.
		for state_id in player_states:
			if state_id is int or (state_id is String and str(state_id).is_valid_int()):
				peer_states[state_id] = player_states[state_id]
			else:
				entity_states[state_id] = player_states[state_id]

	for state_id in peer_states:
		var p_data = peer_states[state_id]
		var node := _resolve_player_sync_target(state_id)
		if node != null:
			_apply_synced_player_state(node, p_data, true)
		else:
			missing[state_id] = p_data

	for state_id in entity_states:
		var p_data = entity_states[state_id]
		var node := _resolve_player_sync_target(state_id)
		if node != null:
			_apply_synced_player_state(node, p_data, false)
		else:
			missing[state_id] = p_data

	if not missing.is_empty() and retries > 0:
		await lj.get_tree().create_timer(0.1).timeout
		_retry_receive_player_states(missing, retries - 1)

func _resolve_player_sync_target(state_id: Variant) -> Node2D:
	if state_id is int:
		return lj._find_player_by_peer(int(state_id)) as Node2D
	if state_id is String and str(state_id).is_valid_int():
		return lj._find_player_by_peer(int(str(state_id))) as Node2D
	return World.get_entity(str(state_id)) as Node2D

func _apply_synced_player_state(node: Node2D, p_data: Dictionary, limit_far_position_fix: bool) -> void:
	if not limit_far_position_fix:
		lj._reconnect.restore_player_state(node, p_data)
		return
	if p_data.has("position"):
		if limit_far_position_fix:
			var lp = World.get_local_player() as Node2D
			if lp != null and (p_data["position"] - lp.position).length() > 1000:
				node.position = p_data["position"]
		else:
			node.position = p_data["position"]
	if p_data.has("z_level"):
		node.set("z_level", p_data["z_level"])
	if p_data.has("health"):
		node.set("health", p_data["health"])
	if p_data.has("dead"):
		node.set("dead", p_data["dead"])
	if p_data.has("limb_hp") and node.get("body") != null:
		node.get("body").limb_hp = p_data["limb_hp"].duplicate()
	if p_data.has("limb_broken") and node.get("body") != null:
		node.get("body").limb_broken = p_data["limb_broken"].duplicate()
	if p_data.has("hands") and node.has_method("sync_hands"):
		_sync_player_hands(node, p_data["hands"], p_data.get("hand_states", []))
	if p_data.has("equipped_data") and "equipped_data" in node:
		node.set("equipped_data", p_data["equipped_data"].duplicate(true))
	if p_data.has("equipped"):
		var eq = node.get("equipped")
		for slot in p_data["equipped"]:
			var item = p_data["equipped"][slot]
			if item == null:
				eq[slot] = null
			elif item is Dictionary and item.has("item_type"):
				eq[slot] = item["item_type"] if item["item_type"] != "" else null
			elif item is String:
				eq[slot] = item if item != "" else null
			else:
				eq[slot] = null
		if node.has_method("_update_clothing_sprites"):
			node.call("_update_clothing_sprites")
	if p_data.has("is_lying_down"):
		node.set("is_lying_down", p_data["is_lying_down"])
		if node.has_method("_update_sprite"):
			node.call("_update_sprite")
		if node.has_method("_update_water_submerge"):
			node.call("_update_water_submerge")
	if p_data.has("is_sneaking"):
		node.set("is_sneaking", p_data["is_sneaking"])
		var alpha: float = p_data.get("sneak_alpha", 1.0)
		node.set("sneak_alpha", alpha)
		if node.has_method("_apply_sneak_alpha"):
			node.call("_apply_sneak_alpha", alpha)
		if node.has_method("_update_water_submerge"):
			node.call("_update_water_submerge")
	if node.has_method("_update_hands_ui"):
		node.call("_update_hands_ui")
	if node.get("_hud") != null:
		node.get("_hud").update_stats(node.get("health"), node.get("stamina"))

func _sync_player_hands(node: Node2D, hand_ids: Array, hand_states: Array) -> void:
	var resolved_ids: Array = []
	for i in range(2):
		var entity_id := str(hand_ids[i]) if i < hand_ids.size() else ""
		if entity_id == "":
			resolved_ids.append("")
			continue

		var hand_item = World.get_entity(entity_id)
		if hand_item == null and i < hand_states.size():
			var hand_state = hand_states[i]
			if hand_state is Dictionary and not hand_state.is_empty():
				hand_item = lj._reconnect._recreate_hand_item(hand_state)

		if hand_item != null and is_instance_valid(hand_item):
			resolved_ids.append(World.get_entity_id(hand_item))
		else:
			resolved_ids.append("")

	node.call("sync_hands", resolved_ids)

func handle_purge_missing_objects(valid_ids: Array) -> void:
	var main_node = World.main_scene
	if main_node == null: return
	var groups = ["pickable", "minable_object", "choppable_object", "inspectable", "door", "gate", "breakable_object"]
	for group in groups:
		for obj in lj.get_tree().get_nodes_in_group(group):
			if obj is Node2D and obj.get_parent() == main_node:
				var obj_id := World.register_entity(obj)
				if not valid_ids.has(obj_id):
					obj.queue_free()

func handle_spawn_object_for_late_join(obj_data: Dictionary) -> void:
	var main_node = World.main_scene
	if main_node == null: return
	var obj_name = str(obj_data["name"])
	var entity_id = str(obj_data.get("entity_id", ""))
	var obj = World.get_entity(entity_id)

	if obj != null:
		if obj_data.has("z_level"):
			var new_z = obj_data["z_level"]
			var old_z = obj.get("z_level")
			if old_z != new_z:
				var tile = World._world_to_tile(obj.global_position)
				World.unregister_solid(tile, old_z, obj)
				World.register_solid(tile, new_z, obj)
				obj.set("z_level", new_z)
				if obj_data.has("z_index"):
					obj.z_index = int(obj_data["z_index"])
				else:
					obj.z_index = (new_z - 1) * 200 + (obj.z_index % 200)

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
						var s = load(obj_data["script_path"])
						if s: obj = Node2D.new(); obj.set_script(s)
		if obj != null:
			obj.name = obj_name
			_apply_pre_add_object_state(obj, obj_data)
			main_node.add_child(obj)
			World.register_entity(obj, entity_id)
			if obj_data.has("z_index"):
				obj.z_index = int(obj_data["z_index"])
			elif obj_data.has("z_level"):
				obj.z_index = (obj.z_level - 1) * 200 + (obj.z_index % 200)
			if obj_data.has("child_index"):
				var child_index: int = clampi(int(obj_data["child_index"]), 0, max(0, main_node.get_child_count() - 1))
				main_node.move_child(obj, child_index)

	if obj != null:
		if obj_data.has("child_index"):
			var desired_child_index: int = clampi(int(obj_data["child_index"]), 0, max(0, main_node.get_child_count() - 1))
			main_node.move_child(obj, desired_child_index)
		if obj_data.has("z_index"):
			obj.z_index = int(obj_data["z_index"])
		if obj_data.has("position"):    obj.position = obj_data["position"]
		if obj_data.has("hits"):
			if obj.has_method("set_hits"): obj.call("set_hits", obj_data["hits"])
			else: obj.set("hits", obj_data["hits"])
		if obj_data.has("amount"):        obj.set("amount",        obj_data["amount"])
		if obj_data.has("metal_type"):    obj.set("metal_type",    obj_data["metal_type"])
		if obj_data.has("stored_balance") and obj.has_method("_update_merchant_balance"):
			obj.call("_update_merchant_balance", int(obj_data["stored_balance"]))
		if obj_data.has("key_id") and "key_id" in obj:
			obj.set("key_id", obj_data["key_id"])
		if obj_data.has("is_locked") and "is_locked" in obj:
			obj.set("is_locked", obj_data["is_locked"])
		if obj_data.has("decor_configs") and "decor_configs" in obj:
			obj.set("decor_configs", obj_data["decor_configs"].duplicate(true))
			if obj.has_method("rebuild_decor"):
				obj.call("rebuild_decor")
		if obj_data.has("state"):
			obj.set("state", obj_data["state"])
			if obj.has_method("_update_sprite"):   obj.call("_update_sprite")
			if obj.has_method("_update_solidity"): obj.call("_update_solidity")
		if obj_data.has("is_on"):         obj.set("is_on",         obj_data["is_on"])
		if obj_data.has("_coal_count"):   obj.set("_coal_count",   obj_data["_coal_count"])
		if obj_data.has("_ironore_count"): obj.set("_ironore_count", obj_data["_ironore_count"])
		if obj_data.has("_fuel_type"):    obj.set("_fuel_type",    obj_data["_fuel_type"])
		if obj_data.has("_smelting"):     obj.set("_smelting",     obj_data["_smelting"])
		if obj_data.has("contents") and "contents" in obj:
			obj.set("contents", obj_data["contents"].duplicate(true))
			if obj.has_method("_update_sprite"):
				obj.call("_update_sprite")
		if obj.has_method("_set_sprite") and obj_data.has("is_on"): obj.call("_set_sprite", obj_data["is_on"])
