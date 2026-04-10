# res://scripts/net/latejoin.gd
# AutoLoad singleton - register as "LateJoin" in project.godot
# Thin dispatcher: delegates heavy work to latejoin_sync.gd and latejoin_reconnect.gd

extends Node

const SYNC_INTERVAL: float = 1.0

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

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
var _state_dirty: bool = false
var _sync_timer: float = 0.0

var client_connected: bool = false
var map_loaded: bool = false
var sync_requested: bool = false
var version_checked: bool = false
var _version_check_sent: bool = false
var is_manual_reconnect: bool = false

var _disconnected_players: Dictionary = {}

var _sync: RefCounted = null
var _reconnect: RefCounted = null

func _ready() -> void:
	_sync = preload("res://scripts/net/latejoin_sync.gd").new(self)
	_reconnect = preload("res://scripts/net/latejoin_reconnect.gd").new(self)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if not BootstrapNet.ready_to_enter_game.is_connected(_on_bootstrap_ready_to_enter_game):
		BootstrapNet.ready_to_enter_game.connect(_on_bootstrap_ready_to_enter_game)

	if not multiplayer.is_server():
		print("LateJoin: Client mode - Press F5 to manually attempt reconnection")

func _on_connected_to_server() -> void:
	client_connected = true

	if is_manual_reconnect:
		map_loaded = true

	if not _version_check_sent:
		_version_check_sent = true
		BootstrapNet.begin_version_check(is_manual_reconnect)

func _on_server_disconnected() -> void:
	client_connected = false
	map_loaded = false
	sync_requested = false
	version_checked = false
	_version_check_sent = false
	is_manual_reconnect = false
	LoadingScreen.hide_loading()
	BootstrapNet.reset_client_state(true)

func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return

	if not multiplayer.is_server() and Input.is_key_pressed(KEY_F5):
		_attempt_manual_reconnection()

	if not multiplayer.is_server():
		if client_connected and map_loaded and BootstrapNet.version_checked and not sync_requested:
			sync_requested = true
			request_sync.rpc_id(1)

	_sync_timer += delta
	if _sync_timer >= SYNC_INTERVAL:
		_sync_timer = 0.0
		if _state_dirty and multiplayer.is_server():
			_broadcast_state_updates()
			_state_dirty = false

func register_tile_change(tile_pos: Vector2i, z_level: int, source_id: int, atlas_coords: Vector2i) -> void:
	var key: String = str(tile_pos.x) + "_" + str(tile_pos.y) + "_" + str(z_level)
	_world_state["tiles"][key] = {
		"tile_pos": tile_pos,
		"z_level": z_level,
		"source_id": source_id,
		"atlas_coords": atlas_coords,
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

func get_world_state() -> Dictionary:
	return _world_state.duplicate(true)

func is_player_disconnected(peer_id: int) -> bool:
	return _disconnected_players.has(peer_id)

func update_disconnected_health(peer_id: int, new_health: int) -> void:
	if _disconnected_players.has(peer_id):
		_disconnected_players[peer_id]["state"]["health"] = new_health

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
		if p.get_multiplayer_authority() == peer_id and p.get("is_possessed") != false:
			return p
	return null

func _attempt_manual_reconnection() -> void:
	if multiplayer.is_server():
		return
	client_connected = false
	sync_requested = false
	version_checked = false
	_version_check_sent = false
	is_manual_reconnect = true
	BootstrapNet.reset_client_state(false)
	var enet: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = enet.create_client("127.0.0.1", Host.PORT, 3)
	if err == OK:
		multiplayer.multiplayer_peer = enet

func _on_bootstrap_ready_to_enter_game() -> void:
	version_checked = true
	ready_to_enter_game.emit()

func _broadcast_state_updates() -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func request_sync() -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()

	print("LateJoin: Peer requested sync - ", peer_id)

	if not _pending_joins.has(peer_id):
		_pending_joins.append(peer_id)

	_sync.send_world_state_to_peer(peer_id)
	_reconnect.handle_reconnection(peer_id)
	receive_sync_complete.rpc_id(peer_id)

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
	if Sidebar.has_method("refresh_laws_ui"):
		Sidebar.refresh_laws_ui()

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
	if World.main_scene != null and World.main_scene.has_method("_on_client_reconnected"):
		World.main_scene.call("_on_client_reconnected")

# ---------------------------------------------------------------------------
# Legacy version check compatibility wrappers
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func request_version_check(
		client_version: String,
		_client_manifest: Dictionary,
		_client_app_version: String = "",
		_is_reconnect: bool = false) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()
	BootstrapNet.handle_legacy_request_version_check(
		peer_id,
		client_version,
		_client_manifest,
		_client_app_version,
		_is_reconnect)

@rpc("authority", "call_remote", "reliable")
func receive_version_error(error_msg: String) -> void:
	BootstrapNet.handle_receive_version_error(error_msg)

@rpc("authority", "call_remote", "reliable")
func receive_version_warning(warning_msg: String) -> void:
	BootstrapNet.handle_receive_version_warning(warning_msg)

@rpc("authority", "call_remote", "reliable")
func receive_version_response(server_version: String, diffs: Dictionary, has_pck: bool) -> void:
	BootstrapNet.handle_receive_version_response(server_version, diffs, has_pck)

@rpc("authority", "call_remote", "reliable")
func receive_sync_complete() -> void:
	LoadingScreen.hide_loading()
	DirAccess.remove_absolute("user://pending_reconnect.json")

func _send_pck_to_peer(peer_id: int, pck_path: String) -> void:
	BootstrapNet._send_pck_to_peer(peer_id, pck_path, true)

@rpc("authority", "call_remote", "reliable")
func receive_pck_header(total_size: int, total_chunks: int) -> void:
	BootstrapNet.handle_receive_pck_header(total_size, total_chunks)

@rpc("authority", "call_remote", "reliable")
func receive_pck_chunk(chunk_index: int, data: PackedByteArray) -> void:
	BootstrapNet.handle_receive_pck_chunk(chunk_index, data)

func _assemble_and_apply_pck() -> void:
	BootstrapNet._assemble_and_apply_pck()

func _get_downloaded_pack_path() -> String:
	return BootstrapNet._get_downloaded_pack_path()
