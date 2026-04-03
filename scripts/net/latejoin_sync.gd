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

	var player_states = {}
	for p in lj.get_tree().get_nodes_in_group("player"):
		var node = p as Node2D
		var pid  = node.get_multiplayer_authority()
		if pid == peer_id:
			continue
		var hand_names = []
		for h in node.get("hands"):
			hand_names.append(h.name if (h != null and is_instance_valid(h)) else "")
		var equipped_data = lj._reconnect.capture_equipped_state(node)
		var eq_data_state = node.get("equipped_data").duplicate(true) if "equipped_data" in node else {}
		player_states[pid] = {
			"position":     node.position,
			"z_level":      node.get("z_level"),
			"disconnected": false,
			"health":       node.get("health"),
			"limb_hp":      node.get("body").limb_hp.duplicate() if node.get("body") != null else {},
			"limb_broken":  node.get("body").limb_broken.duplicate() if node.get("body") != null else {},
			"hands":        hand_names,
			"equipped":     equipped_data,
			"equipped_data": eq_data_state,
			"is_lying_down": node.get("is_lying_down") == true,
			"is_sneaking":  node.get("is_sneaking") == true,
			"sneak_alpha":  node.get("sneak_alpha") if "sneak_alpha" in node else 1.0
		}

	if not player_states.is_empty():
		lj.rpc_id(peer_id, "receive_player_states", player_states)

	lj.rpc_id(peer_id, "receive_laws", World.current_laws)

func sync_objects_for_late_joiner(peer_id: int) -> void:
	var main_node = lj.get_tree().root.get_node_or_null("Main")
	if main_node == null:
		return

	var objects_to_sync   = []
	var valid_object_names = []
	var sync_groups = ["pickable", "minable_object", "choppable_object", "inspectable", "door", "gate", "breakable_object"]

	for group in sync_groups:
		for obj in lj.get_tree().get_nodes_in_group(group):
			if obj is Node2D and obj.get_parent() == main_node:
				if not objects_to_sync.has(obj):
					objects_to_sync.append(obj)
					valid_object_names.append(obj.name)

	lj.rpc_id(peer_id, "purge_missing_objects", valid_object_names)

	for obj in objects_to_sync:
		var obj_data = get_object_sync_data(obj)
		if obj_data != null:
			lj.rpc_id(peer_id, "spawn_object_for_late_join", obj_data)

func get_object_sync_data(obj: Node) -> Dictionary:
	if not obj is Node2D:
		return {}

	var data = {
		"scene_file_path": obj.scene_file_path if obj.scene_file_path != "" else "",
		"position":        obj.position,
		"name":            obj.name,
		"groups":          obj.get_groups()
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

	if obj is Area2D:
		var script_str = str(obj.get_script())
		if "rock.gd"  in script_str: data["type"] = "rock"
		elif "tree.gd" in script_str: data["type"] = "tree"
		elif "coin.gd" in script_str: data["type"] = "coin"

	return data

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
	for obj_path in object_states:
		var obj_data = object_states[obj_path]
		var obj      = lj.get_node_or_null(obj_path)
		if obj != null:
			if obj.has_method("set_hits"): obj.call("set_hits", obj_data.get("hits", 0))
			if obj_data.has("amount")     and "amount"     in obj: obj.set("amount",     obj_data["amount"])
			if obj_data.has("metal_type") and "metal_type" in obj: obj.set("metal_type", obj_data["metal_type"])
		else:
			missing[obj_path] = obj_data

	if not missing.is_empty() and retries > 0:
		await lj.get_tree().create_timer(0.1).timeout
		_retry_receive_object_states(missing, retries - 1)

func handle_receive_player_states(player_states: Dictionary) -> void:
	_retry_receive_player_states(player_states, 20)

func _retry_receive_player_states(player_states: Dictionary, retries: int) -> void:
	var missing = {}
	for peer_id in player_states:
		var p_data = player_states[peer_id]
		var node   = lj._find_player_by_peer(peer_id) as Node2D
		if node != null:
			var lp = World.get_local_player() as Node2D
			if lp != null and (p_data["position"] - lp.position).length() > 1000:
				node.position = p_data["position"]
			if p_data.has("z_level"):      node.set("z_level", p_data["z_level"])
			if p_data.has("limb_hp")    and node.get("body") != null: node.get("body").limb_hp    = p_data["limb_hp"].duplicate()
			if p_data.has("limb_broken") and node.get("body") != null: node.get("body").limb_broken = p_data["limb_broken"].duplicate()
			if p_data.has("hands")        and node.has_method("sync_hands"):          node.call("sync_hands", p_data["hands"])
			if p_data.has("equipped_data") and "equipped_data" in node:               node.set("equipped_data", p_data["equipped_data"].duplicate(true))
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
				if node.has_method("_update_sprite"):          node.call("_update_sprite")
				if node.has_method("_update_water_submerge"):  node.call("_update_water_submerge")
			if p_data.has("is_sneaking"):
				node.set("is_sneaking", p_data["is_sneaking"])
				var alpha: float = p_data.get("sneak_alpha", 1.0)
				node.set("sneak_alpha", alpha)
				if node.has_method("_apply_sneak_alpha"):      node.call("_apply_sneak_alpha", alpha)
				if node.has_method("_update_water_submerge"):  node.call("_update_water_submerge")
			if node.has_method("_update_hands_ui"): node.call("_update_hands_ui")
			if node.get("_hud") != null: node.get("_hud").update_stats(node.get("health"), node.get("stamina"))
		else:
			missing[peer_id] = p_data

	if not missing.is_empty() and retries > 0:
		await lj.get_tree().create_timer(0.1).timeout
		_retry_receive_player_states(missing, retries - 1)

func handle_purge_missing_objects(valid_names: Array) -> void:
	var main_node = lj.get_tree().root.get_node_or_null("Main")
	if main_node == null: return
	var groups = ["pickable", "minable_object", "choppable_object", "inspectable", "door", "gate", "breakable_object"]
	for group in groups:
		for obj in lj.get_tree().get_nodes_in_group(group):
			if obj is Node2D and obj.get_parent() == main_node and not obj.name in valid_names:
				obj.queue_free()

func handle_spawn_object_for_late_join(obj_data: Dictionary) -> void:
	var main_node = lj.get_tree().root.get_node_or_null("Main")
	if main_node == null: return
	var obj_name = str(obj_data["name"])
	var obj      = main_node.get_node_or_null(NodePath(obj_name))

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
			if obj_data.has("z_level"): obj.set("z_level", obj_data["z_level"])
			main_node.add_child(obj)
			if obj_data.has("z_level"):
				obj.z_index = (obj.z_level - 1) * 200 + (obj.z_index % 200)

	if obj != null:
		if obj_data.has("position"):    obj.position = obj_data["position"]
		if obj_data.has("hits"):
			if obj.has_method("set_hits"): obj.call("set_hits", obj_data["hits"])
			else: obj.set("hits", obj_data["hits"])
		if obj_data.has("amount"):        obj.set("amount",        obj_data["amount"])
		if obj_data.has("metal_type"):    obj.set("metal_type",    obj_data["metal_type"])
		if obj_data.has("state"):
			obj.set("state", obj_data["state"])
			if obj.has_method("_update_sprite"):   obj.call("_update_sprite")
			if obj.has_method("_update_solidity"): obj.call("_update_solidity")
		if obj_data.has("is_on"):         obj.set("is_on",         obj_data["is_on"])
		if obj_data.has("_coal_count"):   obj.set("_coal_count",   obj_data["_coal_count"])
		if obj_data.has("_ironore_count"): obj.set("_ironore_count", obj_data["_ironore_count"])
		if obj_data.has("_fuel_type"):    obj.set("_fuel_type",    obj_data["_fuel_type"])
		if obj_data.has("_smelting"):     obj.set("_smelting",     obj_data["_smelting"])
		if obj_data.has("contents"):      obj.set("contents",      obj_data["contents"])
		if obj.has_method("_set_sprite") and obj_data.has("is_on"): obj.call("_set_sprite", obj_data["is_on"])
