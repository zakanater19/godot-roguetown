# res://serverbrowser.gd
extends Node

signal server_found(ip: String, port: int, current_players: int, max_players: int)

const GAME_ID: String = "godotroguetown"

const GAME_PORT: int = 9904
const DISCOVERY_PORT: int = 9905

const BROADCAST_INTERVAL: float = 1.0
const PUBLIC_HEARTBEAT_INTERVAL: float = 10.0
const PUBLIC_POLL_INTERVAL: float = 5.0

# Optional ProjectSettings keys:
#   roguetown/network/public_registry_base_url
#   roguetown/network/public_server_host
#   roguetown/network/public_server_port
#   roguetown/network/public_server_name
#
# Optional environment variables:
#   ROGUETOWN_PUBLIC_REGISTRY_URL
#   ROGUETOWN_PUBLIC_HOST
#   ROGUETOWN_PUBLIC_PORT
#   ROGUETOWN_SERVER_NAME
#
# Public discovery needs a tiny HTTP registry service.
# This script assumes:
#   POST {base_url}/servers   -> upsert/heartbeat this server
#   GET  {base_url}/servers   -> list live servers
#
# If "address" is blank in the POST body, your registry should infer it from the
# request source IP. If you port-forward to a different external port than 9904,
# set ROGUETOWN_PUBLIC_PORT (or the ProjectSetting) to that external port.

const SETTING_REGISTRY_BASE_URL: String = "roguetown/network/public_registry_base_url"
const SETTING_PUBLIC_HOST: String = "roguetown/network/public_server_host"
const SETTING_PUBLIC_PORT: String = "roguetown/network/public_server_port"
const SETTING_SERVER_NAME: String = "roguetown/network/public_server_name"

const ENV_REGISTRY_BASE_URL: String = "ROGUETOWN_PUBLIC_REGISTRY_URL"
const ENV_PUBLIC_HOST: String = "ROGUETOWN_PUBLIC_HOST"
const ENV_PUBLIC_PORT: String = "ROGUETOWN_PUBLIC_PORT"
const ENV_SERVER_NAME: String = "ROGUETOWN_SERVER_NAME"

var _broadcaster: PacketPeerUDP = null
var _listener: PacketPeerUDP = null

var _heartbeat_request: HTTPRequest = null
var _list_request: HTTPRequest = null

var _broadcast_timer: float = 0.0
var _public_heartbeat_timer: float = 0.0
var _public_poll_timer: float = 0.0

var _heartbeat_in_flight: bool = false
var _list_in_flight: bool = false

var _is_broadcasting_server: bool = false
var _is_listening_for_servers: bool = false

var _registry_base_url: String = ""
var _public_server_host: String = ""
var _public_server_port: int = GAME_PORT
var _public_server_name: String = ""


func _ready() -> void:
	set_process(true)
	_ensure_http_requests()
	_load_config()


func start_broadcasting() -> void:
	_load_config()

	_is_broadcasting_server = true
	_broadcast_timer = 0.0
	_public_heartbeat_timer = 0.0

	if _broadcaster != null:
		_broadcaster.close()
		_broadcaster = null

	_broadcaster = PacketPeerUDP.new()
	_broadcaster.set_broadcast_enabled(true)
	_broadcaster.set_dest_address("255.255.255.255", DISCOVERY_PORT)

	var err := _broadcaster.bind(0)
	if err != OK:
		push_warning("ServerBrowser: failed to bind LAN broadcaster (error %d)" % err)
		_broadcaster = null
	else:
		_broadcast_lan_server()

	_send_public_heartbeat()


func stop_broadcasting() -> void:
	_is_broadcasting_server = false
	_broadcast_timer = 0.0
	_public_heartbeat_timer = 0.0

	if _broadcaster != null:
		_broadcaster.close()
		_broadcaster = null

	if _heartbeat_request != null and _heartbeat_in_flight:
		_heartbeat_request.cancel_request()
		_heartbeat_in_flight = false


func start_listening() -> void:
	_load_config()

	_is_listening_for_servers = true
	_public_poll_timer = 0.0

	if _listener != null:
		_listener.close()
		_listener = null

	_listener = PacketPeerUDP.new()
	var err := _listener.bind(DISCOVERY_PORT)
	if err != OK:
		push_warning("ServerBrowser: failed to bind LAN listener on %d (error %d)" % [DISCOVERY_PORT, err])
		_listener = null

	_poll_public_servers()


func stop_listening() -> void:
	_is_listening_for_servers = false
	_public_poll_timer = 0.0

	if _listener != null:
		_listener.close()
		_listener = null

	if _list_request != null and _list_in_flight:
		_list_request.cancel_request()
		_list_in_flight = false


func _process(delta: float) -> void:
	if _broadcaster != null:
		_broadcast_timer += delta
		if _broadcast_timer >= BROADCAST_INTERVAL:
			_broadcast_timer = 0.0
			_broadcast_lan_server()

	if _is_broadcasting_server and _has_public_registry():
		_public_heartbeat_timer += delta
		if _public_heartbeat_timer >= PUBLIC_HEARTBEAT_INTERVAL:
			_public_heartbeat_timer = 0.0
			_send_public_heartbeat()

	if _listener != null:
		_drain_listener()

	if _is_listening_for_servers and _has_public_registry():
		_public_poll_timer += delta
		if _public_poll_timer >= PUBLIC_POLL_INTERVAL:
			_public_poll_timer = 0.0
			_poll_public_servers()


func _ensure_http_requests() -> void:
	if _heartbeat_request == null:
		_heartbeat_request = HTTPRequest.new()
		_heartbeat_request.name = "PublicHeartbeatRequest"
		add_child(_heartbeat_request)
		_heartbeat_request.request_completed.connect(_on_heartbeat_request_completed)

	if _list_request == null:
		_list_request = HTTPRequest.new()
		_list_request.name = "PublicServerListRequest"
		add_child(_list_request)
		_list_request.request_completed.connect(_on_list_request_completed)


func _load_config() -> void:
	_registry_base_url = _normalize_base_url(_get_config_string(
		SETTING_REGISTRY_BASE_URL,
		ENV_REGISTRY_BASE_URL,
		""
	))

	_public_server_host = _get_config_string(
		SETTING_PUBLIC_HOST,
		ENV_PUBLIC_HOST,
		""
	)

	_public_server_port = _get_config_int(
		SETTING_PUBLIC_PORT,
		ENV_PUBLIC_PORT,
		GAME_PORT
	)

	_public_server_name = _get_config_string(
		SETTING_SERVER_NAME,
		ENV_SERVER_NAME,
		_default_server_name()
	)


func _get_config_string(setting_name: String, env_name: String, fallback: String = "") -> String:
	if ProjectSettings.has_setting(setting_name):
		var configured := str(ProjectSettings.get_setting(setting_name)).strip_edges()
		if configured != "":
			return configured

	var env_value := OS.get_environment(env_name).strip_edges()
	if env_value != "":
		return env_value

	return fallback


func _get_config_int(setting_name: String, env_name: String, fallback: int) -> int:
	if ProjectSettings.has_setting(setting_name):
		var configured = int(ProjectSettings.get_setting(setting_name))
		if configured > 0:
			return configured

	var env_value := OS.get_environment(env_name).strip_edges()
	if env_value != "":
		var parsed := int(env_value)
		if parsed > 0:
			return parsed

	return fallback


func _default_server_name() -> String:
	if ProjectSettings.has_setting("application/config/name"):
		var app_name := str(ProjectSettings.get_setting("application/config/name")).strip_edges()
		if app_name != "":
			return app_name
	return "Roguetown Server"


func _normalize_base_url(value: String) -> String:
	var s := value.strip_edges()
	while s.ends_with("/"):
		s = s.substr(0, s.length() - 1)
	return s


func _has_public_registry() -> bool:
	return _registry_base_url != ""


func _get_registry_servers_url() -> String:
	if not _has_public_registry():
		return ""
	return _registry_base_url + "/servers"


func _get_current_player_count() -> int:
	var current_players := 1
	if multiplayer.multiplayer_peer != null:
		current_players += multiplayer.get_peers().size()
	return current_players


func _broadcast_lan_server() -> void:
	if _broadcaster == null:
		return

	var packet_str := "ROGUETOWN_SERVER:%d:%d:%d" % [
		GAME_PORT,
		_get_current_player_count(),
		int(Host.max_clients)
	]

	_broadcaster.put_packet(packet_str.to_utf8_buffer())


func _drain_listener() -> void:
	if _listener == null:
		return

	while _listener.get_available_packet_count() > 0:
		var packet := _listener.get_packet()
		var sender_ip := _listener.get_packet_ip().strip_edges()
		var msg := packet.get_string_from_utf8().strip_edges()

		if not msg.begins_with("ROGUETOWN_SERVER:"):
			continue

		var parts := msg.split(":")
		if parts.size() < 2:
			continue

		var port := int(parts[1])
		if port <= 0:
			continue

		var current_players := 1
		var max_players := 200

		if parts.size() >= 3:
			current_players = max(1, int(parts[2]))
		if parts.size() >= 4:
			max_players = max(1, int(parts[3]))

		if sender_ip != "":
			server_found.emit(sender_ip, port, current_players, max_players)


func _send_public_heartbeat() -> void:
	if not _has_public_registry():
		return
	if _heartbeat_request == null or _heartbeat_in_flight:
		return

	var payload := {
		"game": GAME_ID,
		"name": _public_server_name,
		"address": _public_server_host,
		"port": _public_server_port,
		"current_players": _get_current_player_count(),
		"max_players": int(Host.max_clients),
		"updated_at": Time.get_unix_time_from_system()
	}

	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := _heartbeat_request.request(
		_get_registry_servers_url(),
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)

	if err == OK:
		_heartbeat_in_flight = true
	else:
		push_warning("ServerBrowser: failed to start public heartbeat request (error %d)" % err)


func _poll_public_servers() -> void:
	if not _has_public_registry():
		return
	if _list_request == null or _list_in_flight:
		return

	var err := _list_request.request(_get_registry_servers_url())
	if err == OK:
		_list_in_flight = true
	else:
		push_warning("ServerBrowser: failed to request public server list (error %d)" % err)


func _on_heartbeat_request_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_heartbeat_in_flight = false

	if result != HTTPRequest.RESULT_SUCCESS:
		push_warning("ServerBrowser: public heartbeat failed (result %d)" % result)
		return

	if response_code < 200 or response_code >= 300:
		push_warning("ServerBrowser: public heartbeat returned HTTP %d" % response_code)


func _on_list_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_list_in_flight = false

	if not _is_listening_for_servers:
		return

	if result != HTTPRequest.RESULT_SUCCESS:
		push_warning("ServerBrowser: public list request failed (result %d)" % result)
		return

	if response_code < 200 or response_code >= 300:
		push_warning("ServerBrowser: public list returned HTTP %d" % response_code)
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed == null:
		return

	var servers: Array = []
	if parsed is Array:
		servers = parsed
	elif parsed is Dictionary and parsed.has("servers") and parsed["servers"] is Array:
		servers = parsed["servers"]

	for entry_variant in servers:
		if not (entry_variant is Dictionary):
			continue

		var entry: Dictionary = entry_variant

		var entry_game := str(entry.get("game", GAME_ID)).strip_edges()
		if entry_game != "" and entry_game != GAME_ID:
			continue

		var address := str(
			entry.get("address", entry.get("ip", entry.get("host", "")))
		).strip_edges()

		var port := int(entry.get("port", GAME_PORT))
		var current_players := int(
			entry.get("current_players", entry.get("players", entry.get("currentPlayers", 1)))
		)
		var max_players := int(
			entry.get("max_players", entry.get("maxPlayers", 200))
		)

		if address == "" or port <= 0:
			continue

		server_found.emit(address, port, max(1, current_players), max(1, max_players))