extends Node

# The host retains the world. Clients pull a square window on every floor.
# World objects are freed on exit and reconstructed from current host state.
const RADIUS_TILES: int = 50
const REQUEST_INTERVAL: float = 0.10
const KEEPALIVE_INTERVAL: float = 0.2
const PRESENTATION_RADIUS: int = 20 # FOV/light-map coverage, inside the loaded window.
const TILE_BATCH_SIZE: int = 128
const OBJECT_BATCH_SIZE: int = 8
const ACTOR_DELTA_FIELDS: Array[StringName] = [&"equipped", &"equipped_data", &"stats", &"skills"]
const SpatialIndex = preload("res://scripts/world/entity_spatial_index.gd")

var index = SpatialIndex.new()
var _presentation_index = SpatialIndex.new()
var _presented: Dictionary = {}
var _presentation_dirty: bool = true
var _presentation_center := Vector2i(-9999, -9999)
var map_root: Node = null
var client_enabled: bool = false
var loaded_rect := Rect2i()
var _client_serial: int = 0
var _receiving_serial: int = -1
var _waiting: bool = false
var _timer: float = 0.0
var _last_requested_tile := Vector2i(-9999, -9999)
var _server_peers: Dictionary = {}
var _actors_needing_state: Dictionary = {}
var _pending_prune: Dictionary = {}
var _actor_delta_states: Dictionary = {}
var _actor_delta_timer: float = 0.0

func _ready() -> void:
	multiplayer.peer_disconnected.connect(func(id: int): _server_peers.erase(id))
	multiplayer.server_disconnected.connect(reset_client)

static func window_at(tile: Vector2i) -> Rect2i:
	return Rect2i(tile - Vector2i.ONE * RADIUS_TILES, Vector2i.ONE * (RADIUS_TILES * 2 + 1))

static func difference(rect: Rect2i, previous: Rect2i) -> Array[Rect2i]:
	var overlap := rect.intersection(previous)
	if not overlap.has_area():
		return [rect] if rect.has_area() else []
	var parts: Array[Rect2i] = [
		Rect2i(rect.position, Vector2i(rect.size.x, overlap.position.y - rect.position.y)),
		Rect2i(Vector2i(rect.position.x, overlap.end.y), Vector2i(rect.size.x, rect.end.y - overlap.end.y)),
		Rect2i(Vector2i(rect.position.x, overlap.position.y), Vector2i(overlap.position.x - rect.position.x, overlap.size.y)),
		Rect2i(Vector2i(overlap.end.x, overlap.position.y), Vector2i(rect.end.x - overlap.end.x, overlap.size.y)),
	]
	var result: Array[Rect2i] = []
	for part in parts:
		if part.has_area():
			result.append(part)
	return result

func attach_main(node: Node) -> void:
	map_root = node
	index.clear()
	_presentation_index.clear()
	_presented.clear()
	_server_peers.clear()
	_actors_needing_state.clear()
	_actor_delta_states.clear()
	reset_client()

func detach_main(node: Node) -> void:
	if map_root != node:
		return
	map_root = null
	index.clear()
	_presentation_index.clear()
	_presented.clear()
	_server_peers.clear()
	_actors_needing_state.clear()
	_actor_delta_states.clear()
	reset_client()

func reset_client() -> void:
	client_enabled = false
	loaded_rect = Rect2i()
	_client_serial += 1
	_receiving_serial = -1
	_waiting = false
	_timer = 0.0
	_last_requested_tile = Vector2i(-9999, -9999)
	_presentation_center = Vector2i(-9999, -9999)
	_presentation_dirty = true
	_pending_prune.clear()

func reset_peer(peer_id: int) -> void:
	# Invalidate an in-flight window before a same-connection resync. The next
	# request must reload the window after the client's scene was cleared.
	_server_peers.erase(peer_id)

func register_node(node: Node2D) -> void:
	if map_root == null:
		return
	if not multiplayer.is_server():
		node.set_meta("render_distance_leaf_entity", node.is_in_group("leaf_canopy"))
		node.set_meta("fov_visible", node.visible)
		_presentation_index.insert(node)
		_presentation_dirty = true
		node.set_notify_transform(true)
		_set_presented(node, false)
	if node.get_parent() != map_root:
		return
	World.register_entity(node)
	index.insert(node)
	node.set_notify_transform(true)
	if client_enabled and node is WorldObject:
		_pending_prune[node.get_instance_id()] = node

func unregister_node(node: Node2D) -> void:
	if client_enabled and node.is_in_group(Defs.GROUP_PLAYER):
		for item in node.get("hands"):
			if is_instance_valid(item):
				_pending_prune[item.get_instance_id()] = item
	if index.nodes.has(node.get_instance_id()):
		World.unregister_entity(node)
	index.erase(node)
	_presentation_index.erase(node)
	_presented.erase(node.get_instance_id())
	_pending_prune.erase(node.get_instance_id())
	_actors_needing_state.erase(node.get_instance_id())
	_actor_delta_states.erase(node.get_instance_id())

func update_node(node: Node2D) -> void:
	index.update(node)
	if _presentation_index.update(node):
		_presentation_dirty = true
	if client_enabled and node is WorldObject:
		_pending_prune[node.get_instance_id()] = node

func begin_client() -> void:
	if multiplayer.is_server() or map_root == null:
		return
	reset_client()
	client_enabled = true
	# Scene-authored scenery is only a host source, never a second client world.
	var held: Dictionary = LateJoin._sync._collect_held_object_ids()
	for node: Node2D in index.nodes.values():
		if (node is WorldObject or node.is_in_group(Defs.GROUP_NPC)) and not held.has(World.get_entity_id(node)):
			node.free()
	for z in range(1, 6):
		var tm := World.get_tilemap(z)
		if tm != null:
			tm.clear()
		var grass: TileMapLayer = map_root._grass_decor_layers.get(z)
		if grass != null:
			grass.clear()
		var regions := map_root.get_node_or_null("RegionMapLayer_Z%d" % z) as TileMapLayer
		if regions != null:
			regions.clear()
	Lighting.rebuild_roof_map()

func contains_tile(tile: Vector2i) -> bool:
	return not client_enabled or loaded_rect.has_point(tile)

func _process(delta: float) -> void:
	if map_root == null or not is_instance_valid(map_root):
		return
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		_actor_delta_timer += delta
		if _actor_delta_timer >= REQUEST_INTERVAL:
			_actor_delta_timer = 0.0
			_sync_actor_deltas()
		return
	if not client_enabled:
		return
	_prune_pending_objects()
	var player := World.get_local_player() as Node2D
	if player == null or not multiplayer.get_peers().has(1):
		return
	_update_local_visibility(player)
	for actor: Node in _actors_needing_state.values():
		if is_instance_valid(actor):
			request_actor_state.rpc_id(1, World.get_entity_id(actor))
	_actors_needing_state.clear()
	_timer += delta
	if _waiting or _timer < REQUEST_INTERVAL:
		return
	var tile: Vector2i = player.get("tile_pos")
	if tile == _last_requested_tile and _timer < KEEPALIVE_INTERVAL:
		return
	_timer = 0.0
	_last_requested_tile = tile
	_client_serial += 1
	_waiting = true
	request_window.rpc_id(1, _client_serial)

func _update_local_visibility(player: Node2D) -> void:
	var center := Defs.world_to_tile(player.global_position)
	if not _presentation_dirty and center == _presentation_center:
		return
	_presentation_dirty = false
	_presentation_center = center
	var rect := Rect2i(center - Vector2i.ONE * PRESENTATION_RADIUS, Vector2i.ONE * (PRESENTATION_RADIUS * 2 + 1))
	var nearby: Dictionary = _presentation_index.query(rect)
	for id: int in _presented:
		if not nearby.has(id) and is_instance_valid(_presented[id]):
			_set_presented(_presented[id], false)
	for id: int in nearby:
		if not _presented.has(id):
			_set_presented(nearby[id], true)
	_presented = nearby

func _set_presented(node: Node2D, active: bool) -> void:
	node.set_meta("render_distance_visible", active)
	if node.has_method("set_render_distance_visible"):
		node.call("set_render_distance_visible", active)
	else:
		var combined := active and bool(node.get_meta("fov_visible", true))
		if node.has_method("_set_fov_visibility"):
			node.call("_set_fov_visibility", combined)
		else:
			node.visible = combined
			if node is CollisionObject2D:
				node.input_pickable = combined
	if active:
		node.add_to_group(Defs.GROUP_Z_ENTITY)
	else:
		node.remove_from_group(Defs.GROUP_Z_ENTITY)
	if node.get_meta("render_distance_leaf_entity", false):
		if active:
			node.add_to_group("leaf_canopy")
		else:
			node.remove_from_group("leaf_canopy")

func _prune_pending_objects() -> void:
	if _pending_prune.is_empty():
		return
	var held: Dictionary = LateJoin._sync._collect_held_object_ids()
	var pending := _pending_prune.values()
	_pending_prune.clear()
	for node: Node2D in pending:
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if not loaded_rect.has_point(Defs.world_to_tile(node.global_position)) and not held.has(World.get_entity_id(node)):
			node.free()

func configure_actor(actor: Node2D) -> void:
	if map_root == null or actor.get_parent() != map_root or not actor.is_in_group(Defs.GROUP_PLAYER):
		return
	var sync := actor.get_node_or_null("StateSync") as MultiplayerSynchronizer
	if sync == null:
		return
	if multiplayer.is_server():
		# Godot's spawner frees/recreates remote player scenes using this filter.
		sync.add_visibility_filter(func(peer_id: int): return actor_visible_to_peer(actor, peer_id))
		if actor.get("is_ghost") != true:
			_actor_delta_states[actor.get_instance_id()] = {"actor": actor, "values": {}}
	else:
		_actors_needing_state[actor.get_instance_id()] = actor

func _sync_actor_deltas() -> void:
	var peers := multiplayer.get_peers()
	if peers.is_empty():
		return
	for entry: Dictionary in _actor_delta_states.values():
		var actor: Node2D = entry["actor"]
		if not is_instance_valid(actor) or actor.is_queued_for_deletion():
			continue
		var previous: Dictionary = entry["values"]
		var changed: Dictionary = {}
		for field in ACTOR_DELTA_FIELDS:
			var value: Dictionary = actor.get(field)
			if not previous.has(field) or value != previous[field]:
				# Copy nested inventory data: in-place mutations must also be sent.
				previous[field] = value.duplicate(true)
				changed[field] = previous[field]
		if changed.is_empty():
			continue
		for peer_id in peers:
			if actor_visible_to_peer(actor, peer_id):
				receive_actor_delta.rpc_id(peer_id, World.get_entity_id(actor), changed)

@rpc("authority", "call_remote", "reliable")
func receive_actor_delta(entity_id: String, changed: Dictionary) -> void:
	# Unlike a native ON_CHANGE packet, this addresses the persistent autoload.
	# A late update can outlive an actor's synchronizer after radius despawn.
	# Spawn state and request_actor_state restore all four fields on re-entry.
	var actor := World.get_entity(entity_id)
	if actor == null or not actor.is_in_group(Defs.GROUP_PLAYER) or actor.get("is_ghost") == true:
		return
	for field in ACTOR_DELTA_FIELDS:
		if changed.get(field) is Dictionary:
			actor.set(field, changed[field])

func actor_visible_to_peer(actor: Node2D, peer_id: int) -> bool:
	if not is_instance_valid(actor):
		return false
	if actor.get_multiplayer_authority() == peer_id and actor.get("is_possessed") != false:
		return true
	var observer := World._find_player_by_peer(peer_id)
	return observer != null and window_at(observer.get("tile_pos")).has_point(actor.get("tile_pos"))

@rpc("any_peer", "call_remote", "reliable")
func request_actor_state(entity_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var actor := World.get_entity(entity_id) as Node2D
	if peer_id <= 1 or actor == null or not actor.is_in_group(Defs.GROUP_PLAYER) or not actor_visible_to_peer(actor, peer_id):
		return
	receive_actor_state.rpc_id(peer_id, entity_id, LateJoin._sync._build_player_sync_state(actor))

@rpc("authority", "call_remote", "reliable")
func receive_actor_state(entity_id: String, state: Dictionary) -> void:
	var actor := World.get_entity(entity_id) as Node2D
	if actor != null:
		LateJoin._sync._apply_synced_player_state(actor, state, false)

func broadcast_actor(actor: Node, method: StringName, arguments: Array, call_local: bool = false) -> void:
	if not multiplayer.is_server():
		return
	if call_local:
		# rpc_id(1) preserves call_local's sender identity even while servicing
		# another client's inbound RPC (damage/death can occur on that stack).
		actor.rpc_id.callv([1, method] + arguments)
	receive_actor_event.rpc(World.get_entity_id(actor), method, arguments)

@rpc("authority", "call_remote", "reliable")
func receive_actor_event(entity_id: String, method: StringName, arguments: Array) -> void:
	# The stable autoload receives events even while an actor is unloaded.
	# Re-entry requests a fresh full state, so absent actors need no event cache.
	var actor := World.get_entity(entity_id)
	if actor != null and (actor.is_in_group(Defs.GROUP_PLAYER) or actor.is_in_group(Defs.GROUP_NPC)) and actor.has_method(method):
		actor.callv(method, arguments)

@rpc("any_peer", "call_remote", "reliable")
func request_window(serial: int) -> void:
	if not multiplayer.is_server() or map_root == null:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id <= 1:
		return
	var state: Dictionary = _server_peers.get(peer_id, {})
	if state.get("busy", false):
		return
	var now := Time.get_ticks_msec()
	if serial <= int(state.get("serial", -1)) or now - int(state.get("last_ms", -1000)) < 80:
		receive_window_end.rpc_id(peer_id, serial)
		return
	var player := World._find_player_by_peer(peer_id)
	if player == null:
		receive_window_end.rpc_id(peer_id, serial)
		return
	# Never trust a requested client position or radius for interest queries.
	var center: Vector2i = player.get("tile_pos")
	state["busy"] = true
	state["serial"] = serial
	state["last_ms"] = now
	_server_peers[peer_id] = state
	await _send_window(peer_id, serial, center, state)

func _peer_is_current(peer_id: int, state: Dictionary, scene: Node) -> bool:
	return is_instance_valid(scene) and map_root == scene and multiplayer.is_server() and multiplayer.get_peers().has(peer_id) and _server_peers.get(peer_id) == state

func _send_window(peer_id: int, serial: int, center: Vector2i, state: Dictionary) -> void:
	var scene := map_root
	var rect := window_at(center)
	var previous: Rect2i = state.get("rect", Rect2i())
	var known: Dictionary = state.get("known", {})
	var nearby := index.query(rect)
	var held: Dictionary = LateJoin._sync._collect_held_object_ids()
	var current: Dictionary = {}
	var additions: Array[Node2D] = []
	for node: Node2D in nearby.values():
		if not (node is WorldObject) and not node.is_in_group(Defs.GROUP_NPC):
			continue
		var entity_id := World.get_entity_id(node)
		if held.has(entity_id):
			continue
		current[entity_id] = true
		if not known.has(entity_id) or node.is_in_group(Defs.GROUP_NPC):
			additions.append(node)
	var removed: Array[String] = []
	for entity_id: String in known:
		if not current.has(entity_id) and not held.has(entity_id):
			removed.append(entity_id)
	receive_window_begin.rpc_id(peer_id, serial, center, removed)
	var cells: Array[Vector2i] = []
	for part in difference(rect, previous):
		for y in range(part.position.y, part.end.y):
			for x in range(part.position.x, part.end.x):
				cells.append(Vector2i(x, y))
	cells.sort_custom(func(a: Vector2i, b: Vector2i): return a.distance_squared_to(center) < b.distance_squared_to(center))
	for cursor in range(0, cells.size(), TILE_BATCH_SIZE):
		if not _peer_is_current(peer_id, state, scene):
			return
		var batch := cells.slice(cursor, cursor + TILE_BATCH_SIZE)
		receive_window_tiles.rpc_id(peer_id, serial, _capture_cells(batch))
		await get_tree().process_frame
	additions = additions.filter(func(node): return is_instance_valid(node) and not node.is_queued_for_deletion())
	additions.sort_custom(func(a: Node2D, b: Node2D): return a.position.distance_squared_to(Defs.tile_to_pixel(center)) < b.position.distance_squared_to(Defs.tile_to_pixel(center)))
	for cursor in range(0, additions.size(), OBJECT_BATCH_SIZE):
		if not _peer_is_current(peer_id, state, scene):
			return
		var objects: Array = []
		for node: Node2D in additions.slice(cursor, cursor + OBJECT_BATCH_SIZE):
			if not is_instance_valid(node) or node.is_queued_for_deletion():
				continue
			if not rect.has_point(Defs.world_to_tile(node.global_position)):
				current.erase(World.get_entity_id(node))
				continue
			var data: Dictionary = LateJoin._sync.get_object_sync_data(node)
			data.erase("child_index")
			if node.is_in_group(Defs.GROUP_NPC):
				data["stream_mob"] = true
				for field in ["tile_pos", "facing", "health", "dead"]:
					data[field] = node.get(field)
			objects.append(data)
		receive_window_objects.rpc_id(peer_id, serial, objects)
		await get_tree().process_frame
	if not _peer_is_current(peer_id, state, scene):
		return
	state["rect"] = rect
	state["known"] = current
	state["busy"] = false
	receive_window_end.rpc_id(peer_id, serial)

func _capture_cells(cells: Array[Vector2i]) -> PackedInt32Array:
	# Nine integers per occupied cell: z, x, y, source, atlas x/y, alternative,
	# grass source and grass variant. Empty cells need no record on entry.
	var records := PackedInt32Array()
	for z in range(1, 6):
		var tm := World.get_tilemap(z)
		var grass: TileMapLayer = map_root._grass_decor_layers.get(z)
		for tile in cells:
			var source := tm.get_cell_source_id(tile) if tm != null else -1
			var grass_source := grass.get_cell_source_id(tile) if grass != null else -1
			if source == -1 and grass_source == -1:
				continue
			var atlas := tm.get_cell_atlas_coords(tile) if tm != null else Vector2i(-1, -1)
			var alternative := tm.get_cell_alternative_tile(tile) if tm != null else 0
			var variant := grass.get_cell_atlas_coords(tile).x if grass_source != -1 else 0
			records.append_array(PackedInt32Array([z, tile.x, tile.y, source, atlas.x, atlas.y, alternative, grass_source, variant]))
	return records

@rpc("authority", "call_remote", "reliable")
func receive_window_begin(serial: int, center: Vector2i, removed: Array[String]) -> void:
	if not client_enabled or serial != _client_serial:
		return
	_receiving_serial = serial
	var rect := window_at(center)
	for part in difference(loaded_rect, rect):
		_clear_cells(part)
	loaded_rect = rect
	var held: Dictionary = LateJoin._sync._collect_held_object_ids()
	for entity_id in removed:
		var node := World.get_entity(entity_id)
		if (node is WorldObject or (node != null and node.is_in_group(Defs.GROUP_NPC))) and not held.has(entity_id):
			node.free()
	for node: Node2D in index.nodes.values():
		if node is WorldObject:
			_pending_prune[node.get_instance_id()] = node
	_prune_pending_objects()

func _clear_cells(rect: Rect2i) -> void:
	for z in range(1, 6):
		var tm := World.get_tilemap(z)
		var grass: TileMapLayer = map_root._grass_decor_layers.get(z)
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var tile := Vector2i(x, y)
				if tm != null:
					tm.erase_cell(tile)
				if grass != null:
					grass.erase_cell(tile)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			Lighting.update_roof_map_at(Vector2i(x, y))

@rpc("authority", "call_remote", "reliable")
func receive_window_tiles(serial: int, records: PackedInt32Array) -> void:
	if not client_enabled or serial != _receiving_serial or records.size() % 9 != 0:
		return
	var changed: Dictionary = {}
	for cursor in range(0, records.size(), 9):
		var z := records[cursor]
		var tile := Vector2i(records[cursor + 1], records[cursor + 2])
		if z < 1 or z > 5 or not loaded_rect.has_point(tile):
			continue
		var tm := World.get_tilemap(z)
		if tm != null:
			tm.set_cell(tile, records[cursor + 3], Vector2i(records[cursor + 4], records[cursor + 5]), records[cursor + 6])
		var grass: TileMapLayer = map_root._grass_decor_layers.get(z)
		if grass != null:
			grass.set_cell(tile, records[cursor + 7], Vector2i(records[cursor + 8], 0))
		changed[tile] = true
	for tile: Vector2i in changed:
		Lighting.update_roof_map_at(tile)

@rpc("authority", "call_remote", "reliable")
func receive_window_objects(serial: int, objects: Array) -> void:
	if not client_enabled or serial != _receiving_serial:
		return
	for data: Dictionary in objects:
		if data.get("stream_mob", false):
			LateJoin._sync._apply_mob_snapshot([data], false)
		else:
			LateJoin._sync.handle_spawn_object_for_late_join(data)

@rpc("authority", "call_remote", "reliable")
func receive_window_end(serial: int) -> void:
	if not client_enabled or serial != _client_serial:
		return
	_waiting = false
	FOV.refresh_local_fov(false)
