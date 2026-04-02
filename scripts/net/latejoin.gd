# res://scripts/net/latejoin.gd
# AutoLoad singleton — register as "LateJoin" in project.godot
# Thin dispatcher: delegates heavy work to latejoin_sync.gd and latejoin_reconnect.gd

extends Node

const SYNC_INTERVAL: float = 1.0
## Max bytes per PCK chunk sent over RPC.
const PCK_CHUNK_SIZE: int  = 32768   # 32 KB

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted (client-only) when the version check—and any PCK download—is
## complete and it is safe to change to the game scene.
signal ready_to_enter_game

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _world_state: Dictionary = {
	"tiles":   {},
	"objects": {},
	"players": {},
}

var _pending_joins: Array[int] = []
var _state_dirty:  bool  = false
var _sync_timer:   float = 0.0

var client_connected:      bool = false
var map_loaded:            bool = false
var sync_requested:        bool = false
var version_checked:       bool = false
var _version_check_sent:   bool = false

# PCK download state (client-side only)
var _pck_buffer:           Dictionary = {}   # chunk_index → PackedByteArray
var _pck_total_chunks:     int  = 0
var _pck_chunks_received:  int  = 0

var _disconnected_players: Dictionary = {}

var _sync:      RefCounted = null
var _reconnect: RefCounted = null

func _ready() -> void:
	_sync      = preload("res://scripts/net/latejoin_sync.gd").new(self)
	_reconnect = preload("res://scripts/net/latejoin_reconnect.gd").new(self)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	if not multiplayer.is_server():
		print("LateJoin: Client mode - Press F5 to manually attempt reconnection")


func _on_connected_to_server() -> void:
	client_connected = true

	# If we're reconnecting from inside the game scene the map is already loaded —
	# no scene change will happen, so set the flag directly.
	if get_tree().root.has_node("Main"):
		map_loaded = true

	LoadingScreen.update_status("Checking version...")

	if not _version_check_sent:
		_version_check_sent = true
		_send_version_check_deferred()


func _on_server_disconnected() -> void:
	client_connected       = false
	map_loaded             = false
	sync_requested         = false
	version_checked        = false
	_version_check_sent    = false
	_pck_buffer.clear()
	_pck_total_chunks      = 0
	_pck_chunks_received   = 0
	LoadingScreen.hide_loading()


func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return

	if not multiplayer.is_server() and Input.is_key_pressed(KEY_F5):
		_attempt_manual_reconnection()

	# World sync is triggered once the game scene is loaded AND version is confirmed.
	if not multiplayer.is_server():
		if client_connected and map_loaded and version_checked and not sync_requested:
			sync_requested = true
			request_sync.rpc_id(1)

	_sync_timer += delta
	if _sync_timer >= SYNC_INTERVAL:
		_sync_timer = 0.0
		if _state_dirty and multiplayer.is_server():
			_broadcast_state_updates()
			_state_dirty = false


# ---------------------------------------------------------------------------
# Version check — triggered right after connection, before scene change
# ---------------------------------------------------------------------------

func _send_version_check_deferred() -> void:
	await get_tree().create_timer(0.1).timeout
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var is_reconnect := get_tree().root.has_node("Main")
	request_version_check.rpc_id(1,
		GameVersion.get_version(),
		GameVersion.build_manifest(),
		is_reconnect)


# ---------------------------------------------------------------------------
# State registration (called by the game)
# ---------------------------------------------------------------------------

func register_tile_change(tile_pos: Vector2i, z_level: int, source_id: int, atlas_coords: Vector2i) -> void:
	var key = str(tile_pos.x) + "_" + str(tile_pos.y) + "_" + str(z_level)
	_world_state["tiles"][key] = {"tile_pos": tile_pos, "z_level": z_level, "source_id": source_id, "atlas_coords": atlas_coords}
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

func get_world_state() -> Dictionary:
	return _world_state.duplicate(true)

func is_player_disconnected(peer_id: int) -> bool:
	return _disconnected_players.has(peer_id)

func update_disconnected_health(peer_id: int, new_health: int) -> void:
	if _disconnected_players.has(peer_id):
		_disconnected_players[peer_id]["state"]["health"] = new_health

# ---------------------------------------------------------------------------
# Peer events
# ---------------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	print("LateJoin: Peer connected - ", id)

func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var player_node = _find_player_by_peer(id)
	if player_node == null:
		return
	_reconnect.handle_player_disconnection(id, player_node)

func _find_player_by_peer(peer_id: int) -> Node:
	for p in get_tree().get_nodes_in_group("player"):
		if p.get_multiplayer_authority() == peer_id: return p
	return null

func _attempt_manual_reconnection() -> void:
	if multiplayer.is_server(): return
	# Reset flags so the version-check / sync flow fires again on reconnect.
	client_connected     = false
	sync_requested       = false
	version_checked      = false
	_version_check_sent  = false
	var enet = ENetMultiplayerPeer.new()
	var err  = enet.create_client("127.0.0.1", Host.PORT, 3)
	if err == OK: multiplayer.multiplayer_peer = enet

func _broadcast_state_updates() -> void:
	pass

# ---------------------------------------------------------------------------
# RPC: sync request (client → server)
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func request_sync() -> void:
	if not multiplayer.is_server():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0: peer_id = multiplayer.get_unique_id()

	print("LateJoin: Peer requested sync - ", peer_id)

	if not _pending_joins.has(peer_id):
		_pending_joins.append(peer_id)

	_sync.send_world_state_to_peer(peer_id)
	_reconnect.handle_reconnection(peer_id)
	# Sent last — client hides loading screen once this arrives.
	receive_sync_complete.rpc_id(peer_id)

# ---------------------------------------------------------------------------
# RPC: world state delivery (server → client)
# ---------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func receive_tile_changes(tile_changes: Dictionary) -> void:
	_sync.handle_receive_tile_changes(tile_changes)

@rpc("authority", "call_remote", "reliable")
func receive_object_states(object_states: Dictionary) -> void:
	_sync.handle_receive_object_states(object_states)

@rpc("authority", "call_remote", "reliable")
func receive_player_states(player_states: Dictionary) -> void:
	_sync.handle_receive_player_states(player_states)

@rpc("authority", "call_remote", "reliable")
func purge_missing_objects(valid_names: Array) -> void:
	_sync.handle_purge_missing_objects(valid_names)

@rpc("authority", "call_remote", "reliable")
func spawn_object_for_late_join(obj_data: Dictionary) -> void:
	_sync.handle_spawn_object_for_late_join(obj_data)

@rpc("authority", "call_remote", "reliable")
func receive_laws(laws: Array) -> void:
	World.current_laws = laws
	if Sidebar.has_method("refresh_laws_ui"): Sidebar.refresh_laws_ui()

# ---------------------------------------------------------------------------
# RPC: reconnection (server → client)
# ---------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func rpc_update_player_authority(player_path: NodePath, new_peer_id: int) -> void:
	_reconnect.retry_update_authority(player_path, new_peer_id, 20)

@rpc("authority", "call_local", "reliable")
func rpc_set_disconnect_indicator(player_path: NodePath, show: bool) -> void:
	_reconnect.retry_set_disconnect_indicator(player_path, show, 20)

@rpc("authority", "call_remote", "reliable")
func reconnection_confirmed(player_path: NodePath) -> void:
	_reconnect.retry_reconnection_confirmed(player_path, 20)

@rpc("authority", "call_remote", "reliable")
func receive_reconnect_state(player_path: NodePath, player_state: Dictionary) -> void:
	_reconnect.retry_receive_reconnect_state(player_path, player_state, 20)

@rpc("any_peer", "call_remote", "reliable")
func client_reconnection_confirmed() -> void:
	if has_node("/root/Main"):
		var main = get_node("/root/Main")
		if main.has_method("_on_client_reconnected"): main.call("_on_client_reconnected")

# ---------------------------------------------------------------------------
# RPC: version check  (client → server → client)
# ---------------------------------------------------------------------------

## Client sends its content hash and manifest.
## is_reconnect = true when the client is already in the game scene (F5 reconnect) —
## the server skips PCK delivery in that case since applying a PCK mid-session
## cannot update already-running scripts.
@rpc("any_peer", "call_remote", "reliable")
func request_version_check(client_version: String, client_manifest: Dictionary, is_reconnect: bool = false) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0: peer_id = multiplayer.get_unique_id()

	var server_version  := GameVersion.get_version()
	var server_manifest := GameVersion.build_manifest()

	if client_version == server_version:
		print("LateJoin: version match for peer %d" % peer_id)
		receive_version_response.rpc_id(peer_id, server_version, {}, false)
		return

	print("LateJoin: version mismatch for peer %d (%s vs %s)" \
		% [peer_id, client_version.left(8), server_version.left(8)])

	# Prefer PCK delivery when a patch file is available and this is a fresh join.
	var pck_path := "user://server_patch.pck"
	if not is_reconnect and FileAccess.file_exists(pck_path):
		print("LateJoin: sending PCK to peer %d" % peer_id)
		receive_version_response.rpc_id(peer_id, server_version, {}, true)
		_send_pck_to_peer(peer_id, pck_path)
	else:
		# No PCK — fall back to data-resource diffs (items / recipes).
		var diffs := GameVersion.build_diff(server_manifest, client_manifest)
		print("LateJoin: sending %d resource diff(s) to peer %d" % [diffs.size(), peer_id])
		receive_version_response.rpc_id(peer_id, server_version, diffs, false)


## Server reply: diffs dict is populated when doing resource-only sync;
## has_pck = true means PCK chunks will follow and the client should wait.
@rpc("authority", "call_remote", "reliable")
func receive_version_response(_server_version: String, diffs: Dictionary, has_pck: bool) -> void:
	if has_pck:
		# PCK chunks are en route; _assemble_and_apply_pck() will continue the flow.
		LoadingScreen.update_status("Downloading update...", 0.0)
		return

	# Resource-diff or no-change path.
	if not diffs.is_empty():
		LoadingScreen.update_status("Applying updates...", 0.0,
			str(diffs.size()) + " resource(s) different")
		GameVersion.apply_resource_diff(diffs)

	version_checked = true
	LoadingScreen.update_status("Entering game...")
	ready_to_enter_game.emit()


## Sent by the server as the very last RPC in the sync sequence.
## Client hides the loading screen, revealing the lobby / game underneath.
@rpc("authority", "call_remote", "reliable")
func receive_sync_complete() -> void:
	LoadingScreen.hide_loading()

# ---------------------------------------------------------------------------
# PCK delivery  (server → client, chunked)
# ---------------------------------------------------------------------------

func _send_pck_to_peer(peer_id: int, pck_path: String) -> void:
	var file: FileAccess = FileAccess.open(pck_path, FileAccess.READ)
	if file == null:
		push_error("LateJoin: cannot open PCK at %s" % pck_path)
		return

	var data: PackedByteArray = file.get_buffer(file.get_length())
	file.close()

	var total_size:   int = data.size()
	var total_chunks: int = int(ceil(float(total_size) / float(PCK_CHUNK_SIZE)))

	print("LateJoin: sending PCK (%d KB, %d chunks) to peer %d" \
		% [total_size >> 10, total_chunks, peer_id])

	receive_pck_header.rpc_id(peer_id, total_size, total_chunks)
	for i in range(total_chunks):
		var start: int = i * PCK_CHUNK_SIZE
		var end:   int = mini(start + PCK_CHUNK_SIZE, total_size)
		receive_pck_chunk.rpc_id(peer_id, i, data.slice(start, end))


@rpc("authority", "call_remote", "reliable")
func receive_pck_header(total_size: int, total_chunks: int) -> void:
	_pck_buffer.clear()
	_pck_total_chunks    = total_chunks
	_pck_chunks_received = 0
	LoadingScreen.update_status(
		"Downloading update...", 0.0,
		"0 / %d KB" % (total_size >> 10))


@rpc("authority", "call_remote", "reliable")
func receive_pck_chunk(chunk_index: int, data: PackedByteArray) -> void:
	_pck_buffer[chunk_index] = data
	_pck_chunks_received    += 1

	var progress := float(_pck_chunks_received) / float(_pck_total_chunks)
	LoadingScreen.update_status(
		"Downloading update...", progress,
		"%d / %d chunks" % [_pck_chunks_received, _pck_total_chunks])

	if _pck_chunks_received == _pck_total_chunks:
		_assemble_and_apply_pck()


func _assemble_and_apply_pck() -> void:
	LoadingScreen.update_status("Applying update...")

	# Reassemble in chunk-index order (reliable ENet preserves order, but
	# using the index makes this correct even if that assumption ever changes).
	var assembled := PackedByteArray()
	for i in range(_pck_total_chunks):
		assembled.append_array(_pck_buffer[i])
	_pck_buffer.clear()

	# Write patch to disk — GameVersion._ready() will apply it on next boot.
	var out: FileAccess = FileAccess.open("user://pending_patch.pck", FileAccess.WRITE)
	if out == null:
		push_error("LateJoin: cannot write user://pending_patch.pck")
		return
	out.store_buffer(assembled)
	out.close()
	assembled = PackedByteArray()   # free memory

	# Persist the server address so main_menu can auto-connect after restart.
	var reconnect_data := {"ip": Host.last_server_address, "port": Host.last_server_port}
	var rf := FileAccess.open("user://pending_reconnect.json", FileAccess.WRITE)
	if rf != null:
		rf.store_string(JSON.stringify(reconnect_data))
		rf.close()
	else:
		push_warning("LateJoin: could not write pending_reconnect.json")

	LoadingScreen.update_status("Restarting to apply update...")
	await get_tree().create_timer(0.6).timeout

	# Restart so the PCK is loaded before any scripts or scenes initialise.
	OS.create_process(OS.get_executable_path(), OS.get_cmdline_args())
	get_tree().quit()
