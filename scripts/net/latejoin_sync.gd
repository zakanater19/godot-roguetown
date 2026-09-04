# res://scripts/net/latejoin_sync.gd
# Handles world-state synchronisation for late-joining clients.
extends RefCounted

const WORLD_SNAPSHOT_SCHEMA_VERSION: int = 1
const TILE_RECORD_SIZE: int = 7

var lj: Node  # reference to the LateJoin autoload node
var _snapshot_revision: int = 0
var _last_snapshot_checksum: String = ""
var _last_snapshot_packet: Dictionary = {}
var _last_applied_snapshot_revision: int = 0
var _last_applied_tile_checksum: String = ""
var _last_applied_grass_checksum: String = ""

func _init(latejoin_node: Node) -> void:
	lj = latejoin_node

func reset_snapshot_state() -> void:
	_last_applied_snapshot_revision = 0
	_last_snapshot_checksum = ""
	_last_snapshot_packet.clear()
	_last_applied_tile_checksum = ""
	_last_applied_grass_checksum = ""

# ---------------------------------------------------------------------------
# Server-side: push world state to a joining peer
# ---------------------------------------------------------------------------

func send_world_state_to_peer(peer_id: int) -> void:
	send_world_snapshot_to_peer(peer_id)
	lj.rpc_id(peer_id, "receive_laws", World.current_laws)

func send_world_snapshot_to_peer(peer_id: int) -> void:
	var packet := _build_snapshot_packet()
	if packet.is_empty():
		return
	# Existing peers receive live reliable deltas. A late-join snapshot is large
	# and must only be sent/applied by the peer that requested it.
	_send_snapshot_packet(peer_id, packet)

func broadcast_world_snapshot_if_changed(force: bool = false) -> void:
	if not lj.multiplayer.is_server():
		return
	var previous_checksum := _last_snapshot_checksum
	var packet := _build_snapshot_packet()
	if packet.is_empty():
		return
	if not force and previous_checksum == str(packet.get("checksum", "")):
		return
	for peer_id in lj.multiplayer.get_peers():
		_send_snapshot_packet(int(peer_id), packet)

func _build_snapshot_packet() -> Dictionary:
	if World.main_scene == null:
		return {}
	var tile_snapshot := _capture_full_tile_snapshot()
	var grass_snapshot := _capture_grass_snapshot()
	var snapshot := {
		"schema_version": WORLD_SNAPSHOT_SCHEMA_VERSION,
		"tiles": tile_snapshot,
		"tile_checksum": _checksum_bytes(var_to_bytes(tile_snapshot)),
		"grass": grass_snapshot,
		"grass_checksum": _checksum_bytes(var_to_bytes(grass_snapshot)),
		"objects": _capture_world_objects(),
		"players": _capture_player_states(),
		"mobs": _capture_mob_states(),
	}
	var raw: PackedByteArray = var_to_bytes(snapshot)
	var checksum := _checksum_bytes(raw)
	if checksum != _last_snapshot_checksum or _last_snapshot_packet.is_empty():
		_snapshot_revision += 1
		_last_snapshot_checksum = checksum
		_last_snapshot_packet = {
			"schema_version": WORLD_SNAPSHOT_SCHEMA_VERSION,
			"revision": _snapshot_revision,
			"raw_size": raw.size(),
			"checksum": checksum,
			"payload": raw.compress(FileAccess.COMPRESSION_GZIP),
		}
	return _last_snapshot_packet

func _send_snapshot_packet(peer_id: int, packet: Dictionary) -> void:
	lj.rpc_id(
		peer_id,
		"receive_world_snapshot",
		int(packet["schema_version"]),
		int(packet["revision"]),
		int(packet["raw_size"]),
		str(packet["checksum"]),
		packet["payload"]
	)

func _checksum_bytes(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()

func _capture_full_tile_snapshot() -> PackedInt32Array:
	var records: Array = []
	for z in range(1, 6):
		var tilemap := World.get_tilemap(z)
		if tilemap == null:
			continue
		for cell in tilemap.get_used_cells():
			records.append({
				"z": z,
				"cell": cell,
				"source": tilemap.get_cell_source_id(cell),
				"atlas": tilemap.get_cell_atlas_coords(cell),
				"alternative": tilemap.get_cell_alternative_tile(cell),
			})
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["z"]) != int(b["z"]):
			return int(a["z"]) < int(b["z"])
		var a_cell: Vector2i = a["cell"]
		var b_cell: Vector2i = b["cell"]
		if a_cell.y != b_cell.y:
			return a_cell.y < b_cell.y
		return a_cell.x < b_cell.x
	)

	var packed := PackedInt32Array()
	packed.resize(records.size() * TILE_RECORD_SIZE)
	var cursor := 0
	for record in records:
		var cell: Vector2i = record["cell"]
		var atlas: Vector2i = record["atlas"]
		packed[cursor] = int(record["z"])
		packed[cursor + 1] = cell.x
		packed[cursor + 2] = cell.y
		packed[cursor + 3] = int(record["source"])
		packed[cursor + 4] = atlas.x
		packed[cursor + 5] = atlas.y
		packed[cursor + 6] = int(record["alternative"])
		cursor += TILE_RECORD_SIZE
	return packed

func _capture_grass_snapshot() -> Array:
	var main_node := World.main_scene
	if main_node == null or not main_node.has_method("capture_runtime_grass_snapshot"):
		return []
	var grass: Array = main_node.call("capture_runtime_grass_snapshot")
	grass.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("z_level", 3)) != int(b.get("z_level", 3)):
			return int(a.get("z_level", 3)) < int(b.get("z_level", 3))
		var a_cell: Vector2i = a.get("tile_pos", Vector2i.ZERO)
		var b_cell: Vector2i = b.get("tile_pos", Vector2i.ZERO)
		if a_cell.y != b_cell.y:
			return a_cell.y < b_cell.y
		return a_cell.x < b_cell.x
	)
	return grass

func _capture_world_objects() -> Array:
	var objects_to_sync: Array = []
	var held_object_ids := _collect_held_object_ids()
	for obj in _collect_world_objects():
		var obj_id := World.register_entity(obj)
		if held_object_ids.has(obj_id):
			continue
		var obj_data := get_object_sync_data(obj)
		if not obj_data.is_empty():
			objects_to_sync.append(obj_data)
	objects_to_sync.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("entity_id", "")) < str(b.get("entity_id", ""))
	)
	return objects_to_sync

func _collect_world_objects() -> Array:
	var main_node := World.main_scene
	var results: Array = []
	if main_node == null:
		return results
	var sync_groups = ["pickable", "minable_object", "choppable_object", "inspectable", "door", "gate", "breakable_object"]
	for group in sync_groups:
		for obj in lj.get_tree().get_nodes_in_group(group):
			if obj is Node2D and obj.get_parent() == main_node and not results.has(obj):
				results.append(obj)
	return results

func _capture_player_states() -> Dictionary:
	var states: Dictionary = {}
	for player_node in lj.get_tree().get_nodes_in_group("player"):
		if not (player_node is Node2D):
			continue
		var entity_id := World.register_entity(player_node)
		states[entity_id] = _build_player_sync_state(player_node)
	return states

func _capture_mob_states() -> Array:
	var mobs: Array = []
	for mob in lj.get_tree().get_nodes_in_group("npc"):
		if not (mob is Node2D) or mob.get_parent() != World.main_scene:
			continue
		var entity_id := World.register_entity(mob)
		mobs.append({
			"entity_id": entity_id,
			"name": str(mob.name),
			"scene_file_path": mob.scene_file_path,
			"position": mob.position,
			"z_level": mob.get("z_level"),
			"tile_pos": mob.get("tile_pos"),
			"facing": mob.get("facing"),
			"health": mob.get("health"),
			"dead": mob.get("dead") == true,
		})
	mobs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("entity_id", "")) < str(b.get("entity_id", ""))
	)
	return mobs

func _build_player_sync_state(node: Node2D) -> Dictionary:
	var state: Dictionary = lj._reconnect.capture_player_state(node)
	var hand_states: Array = lj._reconnect.capture_hands_state(node)
	var hand_ids: Array = []
	for hand_item in node.get("hands"):
		hand_ids.append(World.get_entity_id(hand_item) if hand_item != null and is_instance_valid(hand_item) else "")
	state["hands"] = hand_ids
	state["hand_states"] = hand_states
	state["equipped"] = lj._reconnect.capture_equipped_state(node)
	state["entity_id"] = World.get_entity_id(node)
	state["peer_id"] = node.get_multiplayer_authority()
	state["is_ghost"] = node.get("is_ghost") == true
	state["is_possessed"] = node.get("is_possessed") != false
	state["is_sneaking"] = node.get("is_sneaking") == true
	state["sneak_alpha"] = node.get("sneak_alpha") if "sneak_alpha" in node else 1.0
	state["equipped_data"] = node.get("equipped_data").duplicate(true) if "equipped_data" in node else {}
	state["stats"] = node.get("stats").duplicate(true) if "stats" in node else {}
	return state

func sync_objects_for_late_joiner(peer_id: int) -> void:
	send_world_snapshot_to_peer(peer_id)

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
	if obj.has_method("capture_authoritative_state"):
		data["authoritative_state"] = obj.call("capture_authoritative_state")

	if "z_level"       in obj: data["z_level"]       = obj.get("z_level")
	if "z_index"       in obj: data["z_index"]       = obj.get("z_index")
	if "hits"          in obj: data["hits"]           = obj.get("hits")
	if "state"         in obj: data["state"]          = obj.get("state")
	if "is_on"         in obj: data["is_on"]          = obj.get("is_on")
	if "has_torch"     in obj: data["has_torch"]      = obj.get("has_torch")
	if "direction_rotation" in obj: data["direction_rotation"] = obj.get("direction_rotation")
	if "_coal_count"   in obj: data["_coal_count"]    = obj.get("_coal_count")
	if "_ironore_count" in obj: data["_ironore_count"] = obj.get("_ironore_count")
	if "_ore_item_type" in obj: data["_ore_item_type"] = obj.get("_ore_item_type")
	if "_fuel_type"    in obj: data["_fuel_type"]     = obj.get("_fuel_type")
	if "_smelting"     in obj: data["_smelting"]      = obj.get("_smelting")
	if "contents"      in obj: data["contents"]       = obj.get("contents").duplicate(true)
	if "amount"        in obj: data["amount"]         = obj.get("amount")
	if "metal_type"    in obj: data["metal_type"]     = obj.get("metal_type")
	if "stored_balance" in obj: data["stored_balance"] = obj.get("stored_balance")
	if "items_picked"  in obj: data["items_picked"]  = obj.get("items_picked")
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
	if obj_data.has("authoritative_state") and obj.has_method("apply_authoritative_state"):
		obj.call("apply_authoritative_state", obj_data["authoritative_state"], false)

	var pre_add_keys := [
		"z_level",
		"direction_rotation",
		"has_torch",
		"is_on",
		"tree_id",
		"piece_kind",
		"support_segment_name",
		"hits_to_break",
		"drop_count",
		"atlas_index",
		"solid_piece",
		"blocks_fov",
		"decor_configs",
		"items_picked",
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

func handle_receive_world_snapshot(
	 schema_version: int,
	 revision: int,
	 raw_size: int,
	 checksum: String,
	 payload: PackedByteArray
) -> bool:
	if schema_version != WORLD_SNAPSHOT_SCHEMA_VERSION:
		push_error("LateJoin: unsupported world snapshot schema %d" % schema_version)
		return false
	if revision <= _last_applied_snapshot_revision:
		return true
	if raw_size <= 0 or payload.is_empty():
		push_error("LateJoin: received an empty world snapshot")
		return false

	var raw := payload.decompress(raw_size, FileAccess.COMPRESSION_GZIP)
	if raw.size() != raw_size:
		push_error("LateJoin: world snapshot decompression failed")
		return false
	if _checksum_bytes(raw) != checksum:
		push_error("LateJoin: world snapshot checksum mismatch")
		return false
	var decoded: Variant = bytes_to_var(raw)
	if not (decoded is Dictionary):
		push_error("LateJoin: invalid world snapshot payload")
		return false
	var snapshot: Dictionary = decoded
	if int(snapshot.get("schema_version", -1)) != WORLD_SNAPSHOT_SCHEMA_VERSION:
		push_error("LateJoin: decoded world snapshot schema mismatch")
		return false

	# Apply the complete payload in one handler, so no gameplay frame can observe
	# a purge from one RPC and the replacements from later RPCs.
	var tile_geometry_changed := true
	var tile_checksum := str(snapshot.get("tile_checksum", ""))
	# Full snapshots are only sent for join/reconnect. Always restore geometry:
	# cached checksums describe the previous local scene, not necessarily the
	# scene currently registered in World after a reconnect or patch restart.
	_apply_full_tile_snapshot(snapshot.get("tiles", PackedInt32Array()))
	_last_applied_tile_checksum = tile_checksum
	var grass_checksum := str(snapshot.get("grass_checksum", ""))
	_apply_grass_snapshot(snapshot.get("grass", []))
	_last_applied_grass_checksum = grass_checksum
	_apply_world_object_snapshot(snapshot.get("objects", []))
	_apply_mob_snapshot(snapshot.get("mobs", []))
	handle_receive_player_states({"by_entity": snapshot.get("players", {})})
	_last_applied_snapshot_revision = revision

	# Visibility is requested from the authority after its world data is in
	# place. Lighting remains a local rendering system over the synced state.
	if tile_geometry_changed and Lighting != null and Lighting.has_method("rebuild_roof_map"):
		Lighting.call_deferred("rebuild_roof_map")
	if FOV != null and FOV.has_method("refresh_local_fov"):
		FOV.call_deferred("refresh_local_fov", false)
	return true

func _apply_full_tile_snapshot(packed: PackedInt32Array) -> void:
	if packed.size() % TILE_RECORD_SIZE != 0:
		push_error("LateJoin: invalid tile record count in world snapshot")
		return
	for z in range(1, 6):
		var tilemap := World.get_tilemap(z)
		if tilemap != null:
			tilemap.clear()
	for cursor in range(0, packed.size(), TILE_RECORD_SIZE):
		var z := int(packed[cursor])
		var tilemap := World.get_tilemap(z)
		if tilemap == null:
			continue
		tilemap.set_cell(
			Vector2i(int(packed[cursor + 1]), int(packed[cursor + 2])),
			int(packed[cursor + 3]),
			Vector2i(int(packed[cursor + 4]), int(packed[cursor + 5])),
			int(packed[cursor + 6])
		)

func _apply_grass_snapshot(grass_snapshot: Array) -> void:
	var main_node := World.main_scene
	if main_node != null and main_node.has_method("apply_runtime_grass_snapshot"):
		main_node.call("apply_runtime_grass_snapshot", grass_snapshot)

func _apply_world_object_snapshot(object_snapshot: Array) -> void:
	var valid_ids: Array = []
	for raw_data in object_snapshot:
		if raw_data is Dictionary:
			valid_ids.append(str(raw_data.get("entity_id", "")))
	handle_purge_missing_objects(valid_ids)
	for raw_data in object_snapshot:
		if raw_data is Dictionary:
			handle_spawn_object_for_late_join(raw_data)

func _apply_mob_snapshot(mob_snapshot: Array) -> void:
	if not lj.is_inside_tree():
		return
	var scene_tree := lj.get_tree()
	var valid_ids: Array = []
	for raw_data in mob_snapshot:
		if raw_data is Dictionary:
			valid_ids.append(str(raw_data.get("entity_id", "")))

	for local_mob in scene_tree.get_nodes_in_group("npc"):
		if local_mob is Node2D and local_mob.get_parent() == World.main_scene:
			if not valid_ids.has(World.get_entity_id(local_mob)):
				local_mob.queue_free()

	for raw_data in mob_snapshot:
		if not (raw_data is Dictionary):
			continue
		var data: Dictionary = raw_data
		var entity_id := str(data.get("entity_id", ""))
		var mob := World.get_entity(entity_id) as Node2D
		if mob == null:
			var scene_path := str(data.get("scene_file_path", ""))
			var scene := load(scene_path) as PackedScene if not scene_path.is_empty() else null
			if scene != null:
				mob = scene.instantiate() as Node2D
				mob.name = str(data.get("name", "Mob"))
				mob.set_meta("entity_id", entity_id)
				World.main_scene.add_child(mob)
				World.register_entity(mob, entity_id)
		if mob == null:
			continue
		var old_tile: Vector2i = mob.get("tile_pos") if "tile_pos" in mob else Defs.world_to_tile(mob.global_position)
		var old_z: int = int(mob.get("z_level")) if "z_level" in mob else 3
		World.unregister_solid(old_tile, old_z, mob)
		for field_name in ["z_level", "tile_pos", "facing", "health", "dead"]:
			if data.has(field_name) and field_name in mob:
				mob.set(field_name, data[field_name])
		if data.has("position"):
			mob.position = data["position"]
		if data.get("dead", false) != true:
			World.register_solid(mob.get("tile_pos"), int(mob.get("z_level")), mob)

func handle_receive_tile_changes(tile_changes: Dictionary) -> void:
	for key in tile_changes:
		var change  = tile_changes[key]
		var z_level = change.get("z_level", 3)
		var tm      = World.get_tilemap(z_level)
		if tm != null:
			tm.set_cell(change["tile_pos"], change["source_id"], change["atlas_coords"])
			World.handle_runtime_tile_change(
				change["tile_pos"],
				z_level,
				change["source_id"],
				change["atlas_coords"]
			)

func handle_receive_grass_cuts(grass_cuts: Dictionary) -> void:
	for key in grass_cuts:
		var cut: Dictionary = grass_cuts[key]
		World.remove_runtime_grass_decor(
			cut.get("tile_pos", Vector2i.ZERO),
			int(cut.get("z_level", 3))
		)

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
			if obj_data.has("is_on")       and "is_on"         in obj: obj.set("is_on",         obj_data["is_on"])
			if obj_data.has("has_torch")   and "has_torch"     in obj: obj.set("has_torch",     obj_data["has_torch"])
			if obj_data.has("direction_rotation") and "direction_rotation" in obj: obj.set("direction_rotation", obj_data["direction_rotation"])
			if obj_data.has("_coal_count") and "_coal_count"   in obj: obj.set("_coal_count",   obj_data["_coal_count"])
			if obj_data.has("_ironore_count") and "_ironore_count" in obj: obj.set("_ironore_count", obj_data["_ironore_count"])
			if obj_data.has("_ore_item_type") and "_ore_item_type" in obj: obj.set("_ore_item_type", obj_data["_ore_item_type"])
			if obj_data.has("_fuel_type")  and "_fuel_type"    in obj: obj.set("_fuel_type",    obj_data["_fuel_type"])
			if obj_data.has("_smelting")   and "_smelting"     in obj: obj.set("_smelting",     obj_data["_smelting"])
			if obj_data.has("amount")     and "amount"     in obj: obj.set("amount",     obj_data["amount"])
			if obj_data.has("metal_type") and "metal_type" in obj: obj.set("metal_type", obj_data["metal_type"])
			if obj_data.has("stored_balance") and obj.has_method("_update_merchant_balance"): obj.call("_update_merchant_balance", int(obj_data["stored_balance"]))
			if obj_data.has("items_picked") and obj.has_method("set_items_picked"): obj.call("set_items_picked", int(obj_data["items_picked"]))
			if obj_data.has("contents")   and "contents"   in obj: obj.set("contents",   obj_data["contents"].duplicate(true))
			if obj_data.has("key_id")     and "key_id"     in obj: obj.set("key_id",     obj_data["key_id"])
			if obj_data.has("is_locked")  and "is_locked"  in obj: obj.set("is_locked",  obj_data["is_locked"])
			if obj.has_method("_set_sprite") and obj_data.has("is_on"): obj.call("_set_sprite", obj_data["is_on"])
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
		var restore_state := p_data.duplicate(true)
		if restore_state.has("hand_states"):
			restore_state["hands"] = restore_state["hand_states"].duplicate(true)
		lj._reconnect.restore_player_state(node, restore_state)
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
	var held_object_ids := _collect_held_object_ids()
	var groups = ["pickable", "minable_object", "choppable_object", "inspectable", "door", "gate", "breakable_object"]
	for group in groups:
		for obj in lj.get_tree().get_nodes_in_group(group):
			if obj == null or not is_instance_valid(obj):
				continue
			if not (obj is Node2D):
				continue
			if obj.is_queued_for_deletion() or obj.get_parent() != main_node:
				continue
			var obj_id := World.get_entity_id(obj)
			if held_object_ids.has(obj_id):
				continue
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
			if entity_id != "":
				obj.set_meta("entity_id", entity_id)
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
		# Runtime objects can already exist from deterministic scene setup (tree
		# spawners are the important case). Apply authoritative construction state
		# to those retained nodes too, not only to newly instantiated objects.
		_apply_pre_add_object_state(obj, obj_data)
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
		if obj_data.has("items_picked") and obj.has_method("set_items_picked"):
			obj.call("set_items_picked", int(obj_data["items_picked"]))
		if obj_data.has("key_id") and "key_id" in obj:
			obj.set("key_id", obj_data["key_id"])
		if obj_data.has("is_locked") and "is_locked" in obj:
			obj.set("is_locked", obj_data["is_locked"])
		if obj_data.has("decor_configs") and "decor_configs" in obj:
			obj.set("decor_configs", obj_data["decor_configs"].duplicate(true))
			if obj.has_method("rebuild_decor"):
				obj.call("rebuild_decor")
		if obj_data.has("solid_piece") and obj.has_method("set_solid_enabled"):
			obj.call("set_solid_enabled", bool(obj_data["solid_piece"]))
		if (
			(obj_data.has("piece_kind") or obj_data.has("atlas_index"))
			and obj.has_method("_update_sprite")
		):
			obj.call("_update_sprite")
		if obj_data.has("state"):
			obj.set("state", obj_data["state"])
			if obj.has_method("_update_sprite"):   obj.call("_update_sprite")
			if obj.has_method("_update_solidity"): obj.call("_update_solidity")
		if obj_data.has("direction_rotation") and "direction_rotation" in obj:
			obj.set("direction_rotation", obj_data["direction_rotation"])
		if obj_data.has("has_torch") and "has_torch" in obj:
			obj.set("has_torch", obj_data["has_torch"])
		if obj_data.has("is_on"):         obj.set("is_on",         obj_data["is_on"])
		if obj_data.has("_coal_count"):   obj.set("_coal_count",   obj_data["_coal_count"])
		if obj_data.has("_ironore_count"): obj.set("_ironore_count", obj_data["_ironore_count"])
		if obj_data.has("_ore_item_type"): obj.set("_ore_item_type", obj_data["_ore_item_type"])
		if obj_data.has("_fuel_type"):    obj.set("_fuel_type",    obj_data["_fuel_type"])
		if obj_data.has("_smelting"):     obj.set("_smelting",     obj_data["_smelting"])
		if obj_data.has("contents") and "contents" in obj:
			obj.set("contents", obj_data["contents"].duplicate(true))
			if obj.has_method("_update_sprite"):
				obj.call("_update_sprite")
		if obj.has_method("_set_sprite") and obj_data.has("is_on"): obj.call("_set_sprite", obj_data["is_on"])
		if obj_data.has("authoritative_state") and obj.has_method("apply_authoritative_state"):
			obj.call("apply_authoritative_state", obj_data["authoritative_state"], true)
