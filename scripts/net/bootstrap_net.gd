extends Node

# Keep this RPC surface small and stable. Gameplay/network feature RPCs should
# live elsewhere so older clients can still reach patching before they update.
signal ready_to_enter_game

const PCK_CHUNK_SIZE: int = 32768
const PCK_UPLOAD_BPS: int = 1048576

var version_checked: bool = false
var _version_check_sent: bool = false

var _pck_buffer: Dictionary = {}
var _pck_total_chunks: int = 0
var _pck_chunks_received: int = 0
var _pending_pck_version: String = ""
var _restarting_for_patch: bool = false

func reset_client_state(clear_pending_reconnect: bool = false) -> void:
	version_checked = false
	_version_check_sent = false
	_pck_buffer.clear()
	_pck_total_chunks = 0
	_pck_chunks_received = 0
	_pending_pck_version = ""
	if clear_pending_reconnect and not _restarting_for_patch:
		DirAccess.remove_absolute("user://pending_reconnect.json")

func begin_version_check(is_manual_reconnect: bool) -> void:
	if multiplayer.is_server():
		return
	if _version_check_sent:
		return
	_version_check_sent = true
	LoadingScreen.update_status("Checking version...")
	_send_version_check_deferred(is_manual_reconnect)

func _send_version_check_deferred(is_manual_reconnect: bool) -> void:
	await get_tree().create_timer(0.1).timeout
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	request_version_check_bootstrap.rpc_id(1,
		GameVersion.get_version(),
		GameVersion.build_manifest(),
		GameVersion.APP_VERSION,
		is_manual_reconnect)

@rpc("any_peer", "call_remote", "reliable")
func request_version_check_bootstrap(
		client_version: String,
		_client_manifest: Dictionary,
		_client_app_version: String = "",
		_is_reconnect: bool = false) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()
	_handle_version_check_request(peer_id, client_version, false)

func handle_legacy_request_version_check(
		peer_id: int,
		client_version: String,
		_client_manifest: Dictionary,
		_client_app_version: String = "",
		_is_reconnect: bool = false) -> void:
	_handle_version_check_request(peer_id, client_version, true)

func _handle_version_check_request(peer_id: int, client_version: String, legacy: bool) -> void:
	var server_version: String = GameVersion.get_version()

	if client_version == server_version:
		_send_version_response(peer_id, server_version, {}, false, legacy)
		return

	if GameVersion.server_pck_ready:
		_send_version_response(peer_id, server_version, {}, true, legacy)
		_send_pck_to_peer(peer_id, GameVersion.get_server_bundle_path(), legacy)
		return

	var bundle_error: String = GameVersion.pck_generation_error
	if bundle_error == "":
		bundle_error = "unknown server bundle error"

	var err_msg: String = (
		"[color=red]Server update bundle unavailable:[/color] %s\n"
		+ "This server cannot patch out-of-date clients until the bundle is regenerated."
	) % bundle_error
	_send_version_error(peer_id, err_msg, legacy)

func _send_version_response(peer_id: int, server_version: String, diffs: Dictionary, has_pck: bool, legacy: bool) -> void:
	if legacy:
		LateJoin.receive_version_response.rpc_id(peer_id, server_version, diffs, has_pck)
	else:
		receive_version_response_bootstrap.rpc_id(peer_id, server_version, diffs, has_pck)

func _send_version_error(peer_id: int, err_msg: String, legacy: bool) -> void:
	if legacy:
		LateJoin.receive_version_error.rpc_id(peer_id, err_msg)
	else:
		receive_version_error_bootstrap.rpc_id(peer_id, err_msg)

func _send_pck_header(peer_id: int, total_size: int, total_chunks: int, legacy: bool) -> void:
	if legacy:
		LateJoin.receive_pck_header.rpc_id(peer_id, total_size, total_chunks)
	else:
		receive_pck_header_bootstrap.rpc_id(peer_id, total_size, total_chunks)

func _send_pck_chunk(peer_id: int, chunk_index: int, data: PackedByteArray, legacy: bool) -> void:
	if legacy:
		LateJoin.receive_pck_chunk.rpc_id(peer_id, chunk_index, data)
	else:
		receive_pck_chunk_bootstrap.rpc_id(peer_id, chunk_index, data)

@rpc("authority", "call_remote", "reliable")
func receive_version_error_bootstrap(error_msg: String) -> void:
	handle_receive_version_error(error_msg)

func handle_receive_version_error(error_msg: String) -> void:
	push_error("BootstrapNet version error: " + error_msg)
	LoadingScreen.show_loading("Version error - cannot connect")
	LoadingScreen.update_status(error_msg, -1.0, "Close this window to return to the main menu")

@rpc("authority", "call_remote", "reliable")
func receive_version_warning_bootstrap(warning_msg: String) -> void:
	handle_receive_version_warning(warning_msg)

func handle_receive_version_warning(warning_msg: String) -> void:
	push_warning("BootstrapNet version warning: " + warning_msg)
	LoadingScreen.update_status(warning_msg, 0.0, "Applying partial patch...")

@rpc("authority", "call_remote", "reliable")
func receive_version_response_bootstrap(server_version: String, diffs: Dictionary, has_pck: bool) -> void:
	handle_receive_version_response(server_version, diffs, has_pck)

func handle_receive_version_response(server_version: String, diffs: Dictionary, has_pck: bool) -> void:
	if has_pck:
		_pending_pck_version = server_version
		LoadingScreen.update_status("Downloading update...", 0.0)
		return

	if not diffs.is_empty():
		LoadingScreen.update_status("Applying updates...", 0.0,
			str(diffs.size()) + " resource(s) different")
		GameVersion.apply_resource_diff(diffs)

	version_checked = true
	LoadingScreen.update_status("Entering game...")
	ready_to_enter_game.emit()

func _send_pck_to_peer(peer_id: int, pck_path: String, legacy: bool) -> void:
	var file := FileAccess.open(pck_path, FileAccess.READ)
	if file == null:
		var err_msg: String = (
			"[color=red]Server error:[/color] PCK patch file could not be opened (%s).\n"
			+ "Please report this to the server administrator."
		) % pck_path
		push_error("BootstrapNet: cannot open PCK at %s" % pck_path)
		_send_version_error(peer_id, err_msg, legacy)
		return

	var total_size: int = file.get_length()
	var total_chunks: int = int(ceil(float(total_size) / float(PCK_CHUNK_SIZE)))
	var delay_per_chunk: float = float(PCK_CHUNK_SIZE) / float(PCK_UPLOAD_BPS)

	_send_pck_header(peer_id, total_size, total_chunks, legacy)

	for i in range(total_chunks):
		if not multiplayer.get_peers().has(peer_id):
			file.close()
			return
		_send_pck_chunk(peer_id, i, file.get_buffer(PCK_CHUNK_SIZE), legacy)
		await get_tree().create_timer(delay_per_chunk).timeout

	file.close()

@rpc("authority", "call_remote", "reliable")
func receive_pck_header_bootstrap(total_size: int, total_chunks: int) -> void:
	handle_receive_pck_header(total_size, total_chunks)

func handle_receive_pck_header(total_size: int, total_chunks: int) -> void:
	_pck_buffer.clear()
	_pck_total_chunks = total_chunks
	_pck_chunks_received = 0
	LoadingScreen.update_status("Downloading update...", 0.0, "0 / %d KB" % (total_size >> 10))

@rpc("authority", "call_remote", "reliable")
func receive_pck_chunk_bootstrap(chunk_index: int, data: PackedByteArray) -> void:
	handle_receive_pck_chunk(chunk_index, data)

func handle_receive_pck_chunk(chunk_index: int, data: PackedByteArray) -> void:
	_pck_buffer[chunk_index] = data
	_pck_chunks_received += 1
	var progress: float = float(_pck_chunks_received) / float(_pck_total_chunks)
	LoadingScreen.update_status("Downloading update...", progress, "%d / %d chunks" % [_pck_chunks_received, _pck_total_chunks])
	if _pck_chunks_received == _pck_total_chunks:
		_assemble_and_apply_pck()

func _assemble_and_apply_pck() -> void:
	LoadingScreen.update_status("Applying update...")
	var assembled := PackedByteArray()
	for i in range(_pck_total_chunks):
		assembled.append_array(_pck_buffer[i])
	_pck_buffer.clear()

	var pack_path := _get_downloaded_pack_path()
	var out: FileAccess = FileAccess.open(pack_path, FileAccess.WRITE)
	if out != null:
		out.store_buffer(assembled)
		out.close()
		out = null

	var reconnect_data: Dictionary = {
		"ip": Host.last_server_address,
		"port": Host.last_server_port,
		"pack_path": pack_path,
	}
	var rf: FileAccess = FileAccess.open("user://pending_reconnect.json", FileAccess.WRITE)
	if rf != null:
		rf.store_string(JSON.stringify(reconnect_data))
		rf.close()
		rf = null

	_restarting_for_patch = true
	LoadingScreen.update_status("Restarting...")
	await get_tree().create_timer(1.0).timeout

	var args: PackedStringArray = GameVersion.build_restart_args(pack_path)
	var pid: int = OS.create_instance(args)
	if pid == -1:
		OS.create_process(OS.get_executable_path(), args)

	get_tree().quit()

func _get_downloaded_pack_path() -> String:
	var version_tag := _pending_pck_version.strip_edges().left(12)
	if version_tag == "":
		version_tag = str(Time.get_unix_time_from_system())
	return "user://server_bundle_%s.pck" % version_tag
