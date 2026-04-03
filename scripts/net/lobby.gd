# res://scripts/net/lobby.gd
extends Node

var game_started: bool = false
var countdown: float = 300.0
var ready_players: Dictionary = {} 
var round_time: float = 0.0

var _ui_layer: CanvasLayer
var _main_content: Control
var _time_label: Label
var _ready_btn: Button
var _force_btn: Button

var _name_input: LineEdit
var _class_option: OptionButton

var _latejoin_panel: Panel
var _lj_name_input: LineEdit
var _lj_class_option: OptionButton

var _subclass_panel: Panel
var _pending_action: String = ""

var _error_dialog: AcceptDialog
var _chat_input: LineEdit

var _sync_timer: float = 0.0

func _ready() -> void:
	_build_ui()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func show_lobby() -> void:
	if _ui_layer != null:
		_ui_layer.visible = true

func init_server_lobby() -> void:
	reset_lobby_state()
	ready_players[1] = {"ready": false, "name": "noob", "class": "peasant"}

func reset_lobby_state() -> void:
	ready_players.clear()
	game_started = false
	countdown = 300.0
	round_time = 0.0
	_pending_action = ""
	if _ui_layer != null:
		_ui_layer.visible = false
	if _main_content != null:
		_main_content.visible = true
	if _latejoin_panel != null:
		_latejoin_panel.visible = false
	if _subclass_panel != null:
		_subclass_panel.visible = false
	
	if _name_input != null:
		_name_input.visible = true
		_name_input.editable = true
	if _class_option != null:
		_class_option.visible = true
		_class_option.disabled = false
	if _ready_btn != null:
		_ready_btn.text = "Unready"
		_ready_btn.remove_theme_color_override("font_color")

func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 15
	add_child(_ui_layer)

	_error_dialog = AcceptDialog.new()
	_ui_layer.add_child(_error_dialog)

	var bg = ColorRect.new()
	bg.color = Color(0.15, 0.15, 0.15, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_layer.add_child(bg)

	_main_content = Control.new()
	_main_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(_main_content)

	var builder = preload("res://scripts/net/lobby_ui.gd").new(self)
	builder.build(bg, _main_content)

	_ui_layer.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if _ui_layer == null or not _ui_layer.visible:
		return
		
	if _chat_input != null and _chat_input.has_focus():
		if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
			_chat_input.visible = false
			_chat_input.clear()
			_chat_input.release_focus()
			get_viewport().set_input_as_handled()
			return
		
	if event is InputEventKey and event.keycode == KEY_T and event.pressed and not event.echo:
		if _chat_input != null and not _chat_input.visible:
			_chat_input.visible = true
			_chat_input.grab_focus()
			get_viewport().set_input_as_handled()
			return

func _on_chat_submitted(text: String) -> void:
	_chat_input.visible = false
	_chat_input.clear()
	_chat_input.release_focus()
	if text.strip_edges() == "":
		return
		
	if multiplayer.is_server():
		rpc_send_lobby_chat(text)
	elif multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and multiplayer.get_peers().has(1):
		rpc_send_lobby_chat.rpc_id(1, text)

@rpc("any_peer", "call_local", "reliable")
func rpc_send_lobby_chat(message: String) -> void:
	if not multiplayer.is_server():
		return
		
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()
		
	var sender_name = "Unknown"
	if ready_players.has(peer_id):
		sender_name = ready_players[peer_id].get("name", "noob")
		
	var formatted = "[color=#88ccff][b][Lobby][/b] " + sender_name + ": " + message + "[/color]"
	
	rpc_receive_lobby_chat.rpc(formatted)

@rpc("authority", "call_local", "reliable")
func rpc_receive_lobby_chat(formatted_message: String) -> void:
	# Only append chat if the player is currently viewing the lobby UI
	if _ui_layer != null and _ui_layer.visible:
		Sidebar.add_message(formatted_message)

func _process(delta: float) -> void:
	# Guard: if there is no multiplayer peer (e.g. after a disconnect/before hosting),
	# skip all multiplayer calls to prevent "No multiplayer peer is assigned" spam.
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return

	if _force_btn != null:
		_force_btn.visible = multiplayer.is_server() and not game_started

	if not game_started and multiplayer.is_server():
		countdown -= delta
		if countdown <= 0:
			_start_game()
		else:
			_sync_timer += delta
			if _sync_timer >= 1.0:
				_sync_timer = 0.0
				sync_countdown.rpc(countdown)

	if not game_started and _time_label != null:
		_time_label.text = str(max(0, int(countdown))) + "s"

	if game_started:
		round_time += delta * Lighting.time_multiplier

func _on_ready_pressed() -> void:
	if not game_started:
		var p_name = _name_input.text.strip_edges()
		
		var validation_error = _get_validation_error(p_name)
		if validation_error != "":
			_show_error(validation_error)
			return

		var p_class = _class_option.get_item_text(_class_option.selected)
		var p_data = ready_players.get(multiplayer.get_unique_id(), {"ready": false, "name": "noob", "class": "peasant"})
		var is_ready = not p_data.get("ready", false)
		
		# Intercept Adventurer selection before readying up
		if is_ready and p_class == "adventurer":
			_pending_action = "ready"
			_subclass_panel.visible = true
			_main_content.visible = false
			return
		
		_send_ready_request(is_ready, p_name, p_class)
	else:
		_latejoin_panel.visible = true
		_main_content.visible = false

func _on_confirm_latejoin_pressed() -> void:
	var p_name = _lj_name_input.text.strip_edges()
	
	var validation_error = _get_validation_error(p_name)
	if validation_error != "":
		_show_error(validation_error)
		return
		
	var p_class = _lj_class_option.get_item_text(_lj_class_option.selected)
	
	# Intercept Adventurer selection before spawning
	if p_class == "adventurer":
		_pending_action = "latejoin"
		_subclass_panel.visible = true
		_latejoin_panel.visible = false
		return
	
	_send_latejoin_request(p_name, p_class)

func _on_subclass_chosen(subclass: String) -> void:
	_subclass_panel.visible = false
	_main_content.visible = true
	
	if _pending_action == "ready":
		var p_name = _name_input.text.strip_edges()
		_send_ready_request(true, p_name, subclass)
	elif _pending_action == "latejoin":
		var p_name = _lj_name_input.text.strip_edges()
		_send_latejoin_request(p_name, subclass)

func _send_ready_request(is_ready: bool, p_name: String, p_class: String) -> void:
	if multiplayer.is_server():
		request_set_ready(is_ready, p_name, p_class)
	elif multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and multiplayer.get_peers().has(1):
		request_set_ready.rpc_id(1, is_ready, p_name, p_class)
	else:
		_show_error("Connecting to server... Please try again in a moment.")

func _send_latejoin_request(p_name: String, p_class: String) -> void:
	if multiplayer.is_server():
		request_latejoin(p_name, p_class)
	elif multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and multiplayer.get_peers().has(1):
		request_latejoin.rpc_id(1, p_name, p_class)
	else:
		_show_error("Connecting to server... Please try again in a moment.")

func _get_validation_error(p_name: String) -> String:
	if p_name.length() > 30:
		return "Name must be 30 characters or less."
	if p_name.length() == 0:
		return "Name cannot be empty."
	var regex = RegEx.new()
	regex.compile("^[a-zA-Z]+$")
	if not regex.search(p_name):
		return "Name must contain only letters."
	if is_name_taken(p_name):
		return "That name is already in use by an active or disconnected player."
	return ""

func is_name_taken(p_name: String) -> bool:
	for peer_id in Host.peers:
		var p = Host.peers[peer_id]
		if is_instance_valid(p) and p.character_name == p_name:
			return true
	for peer_id in LateJoin._disconnected_players:
		var data = LateJoin._disconnected_players[peer_id]
		if data.state.character_name == p_name:
			return true
	return false

func _show_error(msg: String) -> void:
	_error_dialog.dialog_text = msg
	_error_dialog.popup_centered()

@rpc("authority", "call_local", "reliable")
func rpc_show_name_error(msg: String) -> void:
	_show_error(msg)

func _on_force_pressed() -> void:
	if multiplayer.is_server() and not game_started:
		_start_game()

@rpc("any_peer", "call_local", "reliable")
func request_set_ready(is_ready: bool, p_name: String, p_class: String) -> void:
	if not multiplayer.is_server(): return
	if game_started: return
	
	if _get_validation_error(p_name) != "":
		rpc_show_name_error.rpc_id(multiplayer.get_remote_sender_id(), "Name invalid or taken.")
		return
	
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()
	
	ready_players[peer_id] = {"ready": is_ready, "name": p_name, "class": p_class}
	sync_ready_state.rpc(peer_id, is_ready, p_name, p_class)

@rpc("authority", "call_local", "reliable")
func sync_ready_state(peer_id: int, is_ready: bool, p_name: String, p_class: String) -> void:
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()
	
	ready_players[peer_id] = {"ready": is_ready, "name": p_name, "class": p_class}
	if peer_id == multiplayer.get_unique_id():
		if _ready_btn != null:
			_ready_btn.text = "Ready" if is_ready else "Unready"
			if is_ready:
				_ready_btn.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
				_name_input.editable = false
				_class_option.disabled = true
			else:
				_ready_btn.remove_theme_color_override("font_color")
				_name_input.editable = true
				_class_option.disabled = false

func _start_game() -> void:
	if not multiplayer.is_server(): return
	if game_started: return
	
	game_started = true
	sync_game_started.rpc()
	
	# Determine King candidate if any
	var king_candidates =[]
	for peer_id in ready_players:
		var data = ready_players[peer_id]
		if data.get("ready", false) == true and data.get("class", "peasant") == "king":
			king_candidates.append(peer_id)
			
	var chosen_king = -1
	if king_candidates.size() > 0:
		chosen_king = king_candidates.pick_random()
		
	# Spawn evaluated players
	for peer_id in ready_players:
		var data = ready_players[peer_id]
		if data.get("ready", false) == true:
			if data.get("class", "peasant") == "king" and peer_id != chosen_king:
				# Failed to get the role
				data["ready"] = false
				sync_ready_state.rpc(peer_id, false, data.get("name", "noob"), data.get("class", "peasant"))
				rpc_show_name_error.rpc_id(peer_id, "You failed to get the King role. Please latejoin as another class.")
			else:
				Host.spawn_player(peer_id, data.get("name", "noob"), data.get("class", "peasant"), false)
				rpc_hide_lobby.rpc_id(peer_id)

@rpc("any_peer", "call_local", "reliable")
func request_latejoin(p_name: String, p_class: String) -> void:
	if not multiplayer.is_server(): return
	if not game_started: return
	
	if _get_validation_error(p_name) != "":
		rpc_show_name_error.rpc_id(multiplayer.get_remote_sender_id(), "Name invalid or taken.")
		return
		
	if p_class == "king":
		var king_exists = false
		for peer in Host.peers:
			var p = Host.peers[peer]
			if is_instance_valid(p) and p.get("character_class") == "king":
				king_exists = true
				break
		if LateJoin != null and "LateJoin" in str(LateJoin.name):
			for peer in LateJoin._disconnected_players:
				var d = LateJoin._disconnected_players[peer]
				if d.state.get("character_class") == "king":
					king_exists = true
					break
		
		if king_exists:
			rpc_show_name_error.rpc_id(multiplayer.get_remote_sender_id(), "The King role is already taken.")
			return
	
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0: peer_id = multiplayer.get_unique_id()
	
	if not Host.peers.has(peer_id):
		# Latejoin gets true flag
		Host.spawn_player(peer_id, p_name, p_class, true)
	
	rpc_hide_lobby.rpc_id(peer_id)

@rpc("authority", "call_remote", "unreliable")
func sync_countdown(time_left: float) -> void:
	countdown = time_left

@rpc("authority", "call_local", "reliable")
func sync_game_started() -> void:
	game_started = true
	round_time = 0.0
	if _time_label != null:
		_time_label.text = "Game in progress"
	if _ready_btn != null:
		_ready_btn.text = "Latejoin"
		_ready_btn.remove_theme_color_override("font_color")
	if _name_input != null:
		_name_input.visible = false
	if _class_option != null:
		_class_option.visible = false

@rpc("authority", "call_local", "reliable")
func rpc_hide_lobby() -> void:
	if _ui_layer != null:
		_ui_layer.visible = false

@rpc("authority", "call_remote", "reliable")
func sync_full_lobby_state(time_left: float, is_started: bool, ready_dict: Dictionary, r_time: float = 0.0, lighting_offset: float = 0.0, time_multiplier: float = 1.0) -> void:
	countdown = time_left
	game_started = is_started
	ready_players = ready_dict
	round_time = r_time
	Lighting.time_offset = lighting_offset
	Lighting.time_multiplier = time_multiplier
	
	if game_started:
		if _time_label != null: _time_label.text = "Game in progress"
		if _ready_btn != null: 
			_ready_btn.text = "Latejoin"
			_ready_btn.remove_theme_color_override("font_color")
		if _name_input != null: _name_input.visible = false
		if _class_option != null: _class_option.visible = false
	else:
		var my_data = ready_players.get(multiplayer.get_unique_id(), {"ready": false})
		var my_ready = my_data.get("ready", false)
		if _ready_btn != null: 
			_ready_btn.text = "Ready" if my_ready else "Unready"
			if my_ready:
				_ready_btn.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
			else:
				_ready_btn.remove_theme_color_override("font_color")
		if _name_input != null:
			_name_input.visible = true
			_name_input.editable = not my_ready
		if _class_option != null:
			_class_option.visible = true
			_class_option.disabled = my_ready

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		ready_players[id] = {"ready": false, "name": "noob", "class": "peasant"}
		sync_full_lobby_state.rpc_id(id, countdown, game_started, ready_players, round_time, Lighting.time_offset, Lighting.time_multiplier)

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		ready_players.erase(id)
