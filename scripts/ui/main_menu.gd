# res://scripts/ui/main_menu.gd
extends Control

const CONNECT_TIMEOUT_SEC: float = 3.0
const CONNECT_RETRY_COUNT: int = 3

@onready var main_buttons = $MainButtons
@onready var host_options = $HostOptionsPanel
@onready var server_name_input = $HostOptionsPanel/VBoxContainer/HBoxContainer/ServerNameInput
@onready var max_players_spinbox = $HostOptionsPanel/VBoxContainer/MaxPlayersHBox/MaxPlayersSpinBox
@onready var server_list = $ServerListPanel
@onready var dc_ip_input = $ServerListPanel/VBoxContainer/DirectConnectHBox/DCIPInput
@onready var dc_port_spin = $ServerListPanel/VBoxContainer/DirectConnectHBox/DCPortInput
@onready var server_container = $ServerListPanel/VBoxContainer/ScrollContainer/ServerContainer
@onready var version_label = $VersionLabel

var _known_servers: Array = []
var _pending_connect_ip: String = ""
var _pending_connect_port: int = Host.PORT
var _is_connecting: bool = false
var _connect_retry_index: int = 0
var _connect_attempt_serial: int = 0

func _ready() -> void:
	version_label.text = "Version: " + GameVersion.APP_VERSION
	Sidebar.set_visible(false)
	ServerBrowser.server_found.connect(_on_server_found)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)
	if not LoadingScreen.primary_action_pressed.is_connected(_on_loading_retry_pressed):
		LoadingScreen.primary_action_pressed.connect(_on_loading_retry_pressed)
	if not LoadingScreen.secondary_action_pressed.is_connected(_on_loading_server_list_pressed):
		LoadingScreen.secondary_action_pressed.connect(_on_loading_server_list_pressed)
	_handle_auto_restart()

func _handle_auto_restart() -> void:
	if Host.auto_restart_server:
		Host.auto_restart_server = false
		LoadingScreen.show_loading("Restarting server...")
		await get_tree().create_timer(0.5).timeout
		Host.start_host(int(max_players_spinbox.value), "*", server_name_input.text.strip_edges())
		Lobby.init_server_lobby()
		_transition_to_game()
	elif Host.auto_reconnect_client:
		Host.auto_reconnect_client = false
		await get_tree().create_timer(1.5).timeout
		_begin_client_connection(Host.last_server_address, Host.last_server_port, "Reconnecting...")
	else:
		_check_pending_reconnect()

func _check_pending_reconnect() -> void:
	var path := "user://pending_reconnect.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		DirAccess.remove_absolute(path)
		return
	var ip: String = str(parsed.get("ip", ""))
	var port: int  = int(parsed.get("port", Host.PORT))
	var pack_path: String = str(parsed.get("pack_path", ""))
	if ip == "":
		DirAccess.remove_absolute(path)
		return
	var has_matching_patch: bool = GameVersion.has_active_content_patch()
	if not has_matching_patch and pack_path != "":
		has_matching_patch = FileAccess.file_exists(pack_path)
	if not has_matching_patch:
		DirAccess.remove_absolute(path)
		return

	_begin_client_connection(ip, port, "Reconnecting after update...")

func _on_host_pressed() -> void:
	main_buttons.visible = false
	host_options.visible = true

func _on_start_hosting_pressed() -> void:
	LoadingScreen.show_loading("Starting server...")
	var max_p = int(max_players_spinbox.value)
	var srv_name = server_name_input.text.strip_edges()
	if srv_name == "": srv_name = "Roguetown Server"
	Host.start_host(max_p, "*", srv_name)
	Lobby.init_server_lobby()
	_transition_to_game()

func _on_cancel_host_pressed() -> void:
	host_options.visible = false
	main_buttons.visible = true

func _on_join_pressed() -> void:
	_known_servers.clear()
	for child in server_container.get_children():
		child.queue_free()
		
	main_buttons.visible = false
	server_list.visible = true
	ServerBrowser.start_listening()

func _on_direct_connect_pressed() -> void:
	var ip = dc_ip_input.text.strip_edges()
	var port = int(dc_port_spin.value)
	if ip.is_empty():
		ip = "127.0.0.1"
	if port <= 0: port = Host.PORT
	ServerBrowser.stop_listening()
	_begin_client_connection(ip, port)

func _on_server_found(ip: String, port: int, current_players: int, max_players: int, srv_name: String) -> void:
	var server_id = ip + ":" + str(port)
	
	if server_id in _known_servers:
		return
	
	_known_servers.append(server_id)
		
	var display_name = srv_name.strip_edges()
	if display_name.is_empty(): display_name = "Server"
		
	var btn := Button.new()
	btn.name = server_id
	btn.text = display_name + " at " + ip + ":" + str(port) + " (" + str(current_players) + "/" + str(max_players) + ")"
	btn.custom_minimum_size.y = 40
	btn.pressed.connect(func(): _join_game(ip, port))
	server_container.add_child(btn)

func _join_game(ip: String, port: int) -> void:
	ServerBrowser.stop_listening()
	_begin_client_connection(ip, port)

func _begin_client_connection(ip: String, port: int, stage: String = "Connecting...") -> void:
	ServerBrowser.stop_listening()
	_pending_connect_ip = ip
	_pending_connect_port = port
	_connect_retry_index = 0
	_start_client_connection_attempt(stage)

func _start_client_connection_attempt(stage: String) -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	_is_connecting = true
	_connect_attempt_serial += 1
	var attempt_serial: int = _connect_attempt_serial
	LoadingScreen.show_loading(stage)
	LoadingScreen.update_status(stage, -1.0, "%s:%d" % [_pending_connect_ip, _pending_connect_port])
	Host.start_client_custom(_pending_connect_ip, _pending_connect_port)
	_watch_connection_timeout(attempt_serial)

func _watch_connection_timeout(attempt_serial: int) -> void:
	await get_tree().create_timer(CONNECT_TIMEOUT_SEC).timeout
	if not _is_connecting:
		return
	if attempt_serial != _connect_attempt_serial:
		return
	_handle_connection_attempt_failed(attempt_serial)

func _on_connected_to_server() -> void:
	if not _is_connecting:
		return
	_is_connecting = false
	LoadingScreen.show_loading("Connected.")
	LoadingScreen.update_status("Connected.", -1.0, "Joining game...")
	_transition_to_game()
	Host._setup_spawner()

func _on_connection_failed() -> void:
	pass

func _on_server_disconnected() -> void:
	pass

func _handle_connection_attempt_failed(attempt_serial: int) -> void:
	if not _is_connecting:
		return
	if attempt_serial != _connect_attempt_serial:
		return
	_is_connecting = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	if _connect_retry_index < CONNECT_RETRY_COUNT:
		_connect_retry_index += 1
		var retry_stage := "%d/%d retrying..." % [_connect_retry_index, CONNECT_RETRY_COUNT]
		_start_client_connection_attempt(retry_stage)
		return
	_handle_connection_failed()

func _handle_connection_failed() -> void:
	if _pending_connect_ip == "":
		return
	_is_connecting = false
	LoadingScreen.show_action_prompt(
		"Unable to connect.",
		"%s:%d" % [_pending_connect_ip, _pending_connect_port],
		"Retry",
		"Server List"
	)

func _on_loading_retry_pressed() -> void:
	if _pending_connect_ip == "":
		return
	_begin_client_connection(_pending_connect_ip, _pending_connect_port)

func _on_loading_server_list_pressed() -> void:
	LoadingScreen.hide_loading()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	main_buttons.visible = false
	host_options.visible = false
	server_list.visible = true
	ServerBrowser.start_listening()

func _on_back_pressed() -> void:
	ServerBrowser.stop_listening()
	_known_servers.clear()
	host_options.visible = false
	main_buttons.visible = true
	server_list.visible = false

func _transition_to_game() -> void:
	Sidebar.set_visible(true)
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	Lobby.show_lobby()

func _on_quit_pressed() -> void:
	get_tree().quit()
