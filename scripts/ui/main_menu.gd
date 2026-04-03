# res://scripts/ui/main_menu.gd
extends Control

@onready var main_buttons = $MainButtons
@onready var host_options = $HostOptionsPanel
@onready var max_players_spinbox = $HostOptionsPanel/VBoxContainer/HBoxContainer/MaxPlayersSpinBox
@onready var server_list = $ServerListPanel
@onready var server_container = $ServerListPanel/VBoxContainer/ScrollContainer/ServerContainer

var _known_servers: Array =[]

func _ready() -> void:
	Sidebar.set_visible(false)
	ServerBrowser.server_found.connect(_on_server_found)
	if _check_server_restart():
		return
	if _check_round_restart_reconnect():
		return
	_check_pending_reconnect()


func _check_server_restart() -> bool:
	var args := OS.get_cmdline_args()
	if not "--server-restart" in args:
		return false
	var max_p := 200
	var bind_ip := "*"
	for arg in args:
		if arg.begins_with("--max-players="):
			max_p = int(arg.substr(14))
		elif arg.begins_with("--bind-ip="):
			bind_ip = arg.substr(10)
	LoadingScreen.show_loading("Restarting server...")
	Host.start_host(max_p, bind_ip)
	Lobby.init_server_lobby()
	_transition_to_game()
	return true


func _check_round_restart_reconnect() -> bool:
	var args := OS.get_cmdline_args()
	if not "--round-restart" in args:
		return false
	var ip := ""
	var port := Host.PORT
	for arg in args:
		if arg.begins_with("--connect-ip="):
			ip = arg.substr(13)
		elif arg.begins_with("--connect-port="):
			port = int(arg.substr(15))
	if ip == "":
		return false
	LoadingScreen.show_loading("Reconnecting after round restart...")
	Host.start_client_custom(ip, port)
	_transition_to_game()
	return true


func _check_pending_reconnect() -> void:
	var path := "user://pending_reconnect.json"
	if not FileAccess.file_exists(path):
		return
	# Only auto-reconnect if a patch was applied in this exact session.
	# Without this guard a stale file left by a force-closed session (editor
	# stop, crash, etc.) would silently skip the main menu every launch.
	if not GameVersion.patch_applied:
		DirAccess.remove_absolute(path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	# Do NOT delete here — LateJoin.receive_sync_complete() deletes it after a
	# successful resume, and LateJoin._on_server_disconnected() deletes it if
	# the connection fails, so we never loop on a dead server.

	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		DirAccess.remove_absolute(path)  # malformed — discard immediately
		return
	var ip: String = str(parsed.get("ip", ""))
	var port: int  = int(parsed.get("port", Host.PORT))
	if ip == "":
		DirAccess.remove_absolute(path)  # empty ip — discard
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
	Host.start_host(max_p)
	Lobby.init_server_lobby()
	_transition_to_game()

func _on_cancel_host_pressed() -> void:
	host_options.visible = false
	main_buttons.visible = true

func _on_join_pressed() -> void:
	# Clear previous list on new join attempt
	_known_servers.clear()
	for child in server_container.get_children():
		child.queue_free()
		
	main_buttons.visible = false
	server_list.visible = true
	ServerBrowser.start_listening()

func _on_server_found(ip: String, port: int, current_players: int = 1, max_players: int = 200) -> void:
	var server_id = ip + ":" + str(port)
	
	# Check our tracking list instead of the UI tree
	if server_id in _known_servers:
		return
	
	_known_servers.append(server_id)
		
	var btn := Button.new()
	btn.name = server_id
	btn.text = "Server at " + ip + ":" + str(port) + " - " + str(current_players) + "/" + str(max_players)
	btn.custom_minimum_size.y = 40
	btn.pressed.connect(func(): _join_game(ip, port))
	server_container.add_child(btn)

func _join_game(ip: String, port: int) -> void:
	ServerBrowser.stop_listening()
	LoadingScreen.show_loading("Connecting to server...")
	Host.start_client_custom(ip, port)
	# Load the game scene immediately so Main/PlayerSpawner exists before the server
	# tries to replicate existing entities to us.  Version check + any PCK patch run
	# in the background and complete before request_sync is sent (_process gates on
	# both map_loaded AND version_checked).
	_transition_to_game()

func _on_back_pressed() -> void:
	ServerBrowser.stop_listening()
	_known_servers.clear() # Reset list
	host_options.visible = false
	main_buttons.visible = true
	server_list.visible = false

func _transition_to_game() -> void:
	Sidebar.set_visible(true)
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	Lobby.show_lobby()

func _on_quit_pressed() -> void:
	get_tree().quit()
	
