extends CanvasLayer

var _panel_container: PanelContainer

func _ready() -> void:
	layer = 100
	visible = false
	
	# Background tint
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	# Center panel
	_panel_container = PanelContainer.new()
	_panel_container.set_anchors_preset(Control.PRESET_CENTER)
	
	# Basic styling
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 1.0)
	style.border_width_bottom = 2
	style.border_width_top = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	_panel_container.add_theme_stylebox_override("panel", style)
	add_child(_panel_container)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_panel_container.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	margin.add_child(vbox)
	
	var title = Label.new()
	title.text = "PAUSE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)
	
	var quit_btn = Button.new()
	quit_btn.text = "Quit to Main Menu"
	quit_btn.custom_minimum_size = Vector2(200, 40)
	quit_btn.add_theme_font_size_override("font_size", 16)
	quit_btn.pressed.connect(_on_quit_pressed)
	vbox.add_child(quit_btn)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed and not event.echo:
		var current_scene = get_tree().current_scene
		# Do not open the ESC menu if we are already at the Main Menu
		if current_scene != null and current_scene.name == "MainMenu":
			return
			
		visible = not visible
		get_viewport().set_input_as_handled()

func _on_quit_pressed() -> void:
	visible = false
	
	# 1. Close Networking cleanly by invoking the Godot destructor
	# This avoids the "peer->close()" bug which skips the disconnect notification
	multiplayer.multiplayer_peer = null
		
	# 2. Clean up Host state
	Host.peers.clear()
	Host._spawner = null
	
	# 3. Clean up Lobby state
	Lobby.ready_players.clear()
	Lobby.game_started = false
	Lobby.countdown = 300.0
	Lobby.round_time = 0.0
	if Lobby._ui_layer != null:
		Lobby._ui_layer.visible = false
		
	# 4. Clean up LateJoin state
	LateJoin._world_state = {"tiles": {}, "objects": {}, "players": {}}
	LateJoin._pending_joins.clear()
	LateJoin._disconnected_players.clear()
	LateJoin._state_dirty = false
	LateJoin.client_connected = false
	LateJoin.map_loaded = false
	LateJoin.sync_requested = false
	
	# 5. Clean up Sidebar state
	Sidebar._messages.clear()
	if Sidebar._rtl != null:
		Sidebar._rtl.text = ""
	Sidebar.set_visible(false)
	
	# 6. Stop ServerBrowser network binds if any stuck open
	ServerBrowser.stop_listening()
	ServerBrowser.stop_broadcasting()
	
	# 7. Transition back
	get_tree().change_scene_to_file("res://main_menu.tscn")