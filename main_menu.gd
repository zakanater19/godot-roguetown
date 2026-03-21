# res://main_menu.gd
extends Control

@onready var main_buttons = $MainButtons
@onready var server_list = $ServerListPanel
@onready var server_container = $ServerListPanel/VBoxContainer/ScrollContainer/ServerContainer

var _known_servers: Array = []

func _ready() -> void:
	Sidebar.set_visible(false)
	ServerBrowser.server_found.connect(_on_server_found)

func _on_host_pressed() -> void:
	Host.start_host()
	Lobby.init_server_lobby()
	_transition_to_game()

func _on_join_pressed() -> void:
	# Clear previous list on new join attempt
	_known_servers.clear()
	for child in server_container.get_children():
		child.queue_free()
		
	main_buttons.visible = false
	server_list.visible = true
	ServerBrowser.start_listening()

func _on_server_found(ip: String, port: int) -> void:
	var server_id = ip + ":" + str(port)
	
	# Check our tracking list instead of the UI tree
	if server_id in _known_servers:
		return
	
	_known_servers.append(server_id)
		
	var btn := Button.new()
	btn.name = server_id
	btn.text = "Server at " + ip + ":" + str(port)
	btn.custom_minimum_size.y = 40
	btn.pressed.connect(func(): _join_game(ip, port))
	server_container.add_child(btn)

func _join_game(ip: String, port: int) -> void:
	ServerBrowser.stop_listening()
	Host.start_client_custom(ip, port)
	_transition_to_game()

func _on_back_pressed() -> void:
	ServerBrowser.stop_listening()
	_known_servers.clear() # Reset list
	main_buttons.visible = true
	server_list.visible = false

func _transition_to_game() -> void:
	Sidebar.set_visible(true)
	get_tree().change_scene_to_file("res://main.tscn")
	Lobby.show_lobby()

func _on_quit_pressed() -> void:
	get_tree().quit()