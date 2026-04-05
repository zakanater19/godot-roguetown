# res://scripts/ui/main_menu.gd
extends Control

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

func _ready() -> void:
	version_label.text = "Version: " + GameVersion.APP_VERSION
	Sidebar.set_visible(false)
	ServerBrowser.server_found.connect(_on_server_found)
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
		LoadingScreen.show_loading("Reconnecting...")
		await get_tree().create_timer(1.5).timeout
		Host.start_client_custom(Host.last_server_address, Host.last_server_port)
		_transition_to_game()
	else:
		_check_pending_reconnect()

func _check_pending_reconnect() -> void:
	var path := "user://pending_reconnect.json"
	if not FileAccess.file_exists(path):
		return
	if not GameVersion.patch_applied:
		DirAccess.remove_absolute(path)
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
	if ip == "":
		DirAccess.remove_absolute(path)
		return

	LoadingScreen.show_loading("Reconnecting after update...")
	Host.start_client_custom(ip, port)
	_transition_to_game()

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
	LoadingScreen.show_loading("Connecting to %s:%d..." % [ip, port])
	Host.start_client_custom(ip, port)
	_transition_to_game()

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
	LoadingScreen.show_loading("Connecting to server...")
	Host.start_client_custom(ip, port)
	_transition_to_game()

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
