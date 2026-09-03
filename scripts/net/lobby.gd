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
var _host_dashboard: Control
var _host_server_label: Label
var _host_phase_label: Label
var _host_time_label: Label
var _host_player_stats_label: Label
var _host_count_label: Label
var _host_player_list: VBoxContainer
var _host_force_btn: Button
var _host_restart_btn: Button
var _host_roster_refresh_timer: float = 0.0
var _host_roster_signature: String = ""
var _host_restart_requested: bool = false

func _ready() -> void:
	_build_ui()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func show_lobby() -> void:
	if _ui_layer != null:
		_ui_layer.visible = true
	var host_console_active := Host.is_host_mode and multiplayer.is_server()
	if _host_dashboard != null:
		_host_dashboard.visible = host_console_active
	if _main_content != null:
		_main_content.visible = not host_console_active
	if host_console_active:
		_host_roster_signature = ""
		_refresh_host_dashboard(true)

func init_server_lobby() -> void:
	reset_lobby_state()

func reset_lobby_state() -> void:
	ready_players.clear()
	game_started = false
	countdown = 300.0
	round_time = 0.0
	_pending_action = ""
	_host_restart_requested = false
	if _ui_layer != null:
		_ui_layer.visible = false
	if _main_content != null:
		_main_content.visible = true
	if _host_dashboard != null:
		_host_dashboard.visible = false
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

	var builder = preload("res://scripts/net/lobby_ui.gd").new(self)
	builder.build(bg)

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

	if _host_dashboard != null and _host_dashboard.visible:
		_update_host_stats()
		_host_roster_refresh_timer += delta
		if _host_roster_refresh_timer >= 0.25:
			_host_roster_refresh_timer = 0.0
			_refresh_host_dashboard()

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
		var local_peer_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else -1
		
		var validation_error = _get_validation_error(p_name, local_peer_id)
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
	var local_peer_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else -1
	
	var validation_error = _get_validation_error(p_name, local_peer_id)
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

func _get_validation_error(p_name: String, except_peer_id: int = -1) -> String:
	if p_name.length() > 30:
		return "Name must be 30 characters or less."
	if p_name.length() == 0:
		return "Name cannot be empty."
	var regex = RegEx.new()
	regex.compile("^[a-zA-Z]+$")
	if not regex.search(p_name):
		return "Name must contain only letters."
	if is_name_taken(p_name, except_peer_id):
		return "That name is already in use by an active or disconnected player."
	return ""

func is_name_taken(p_name: String, _except_peer_id: int = -1) -> bool:
	var wanted_name: String = p_name.to_lower()
	for peer_id in Host.peers:
		var p = Host.peers[peer_id]
		if is_instance_valid(p) and str(p.get("character_name")).to_lower() == wanted_name:
			return true
	for p in get_tree().get_nodes_in_group("player"):
		if p == null or not is_instance_valid(p):
			continue
		if str(p.get("character_name")).to_lower() == wanted_name:
			return true
	for peer_id in LateJoin._disconnected_players:
		var data = LateJoin._disconnected_players[peer_id]
		if str(data.state.get("character_name", "")).to_lower() == wanted_name:
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

func _on_restart_round_pressed() -> void:
	if Host.is_host_mode and multiplayer.is_server() and game_started and not _host_restart_requested:
		_host_restart_requested = true
		_update_host_stats()
		# Use the existing synchronized round-end RPC so every client schedules
		# its reconnect before the server closes the current ENet peer.
		World.rpc_request_round_end()

@rpc("any_peer", "call_local", "reliable")
func request_set_ready(is_ready: bool, p_name: String, p_class: String) -> void:
	if not multiplayer.is_server(): return
	if game_started: return
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()
	
	if _get_validation_error(p_name, peer_id) != "":
		rpc_show_name_error.rpc_id(multiplayer.get_remote_sender_id(), "Name invalid or taken.")
		return
	
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
		# Peer 1 is the graphical server console, never a player.
		if int(peer_id) == multiplayer.get_unique_id():
			continue
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
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0: peer_id = multiplayer.get_unique_id()
	if Host.is_host_mode and peer_id == multiplayer.get_unique_id(): return
	
	if _get_validation_error(p_name, peer_id) != "":
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
	_update_host_stats()
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
	# Client spawn confirmations hide the player lobby. The graphical server
	# console stays visible for the whole round.
	if Host.is_host_mode and multiplayer.is_server() and _host_dashboard != null and _host_dashboard.visible:
		return
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
		_refresh_host_dashboard(true)

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		ready_players.erase(id)
		_refresh_host_dashboard(true)

func _update_host_stats() -> void:
	if _host_dashboard == null or not _host_dashboard.visible:
		return
	if _host_server_label != null:
		_host_server_label.text = "%s\nPort %d  •  Max players %d" % [Host.server_name, Host.PORT, Host.max_clients]
	if _host_phase_label != null:
		_host_phase_label.text = "IN PROGRESS" if game_started else "LOBBY"
		_host_phase_label.add_theme_color_override(
			"font_color",
			Color(0.35, 0.9, 0.55) if game_started else Color(0.95, 0.75, 0.3)
		)
	if _host_time_label != null:
		if game_started:
			_host_time_label.text = "Round time: %s" % _format_host_time(round_time)
		else:
			_host_time_label.text = "Auto start: %s" % _format_host_time(maxf(0.0, countdown))
	if _host_player_stats_label != null:
		var connected_peer_ids := multiplayer.get_peers()
		var state_count := 0
		for peer_id in connected_peer_ids:
			if game_started:
				var entity: Node = Host.peers.get(peer_id, null)
				if entity != null and is_instance_valid(entity):
					state_count += 1
			elif bool(ready_players.get(peer_id, {}).get("ready", false)):
				state_count += 1
		_host_player_stats_label.text = (
			"Active characters: %d / %d" if game_started else "Ready players: %d / %d"
		) % [state_count, connected_peer_ids.size()]
	if _host_force_btn != null:
		_host_force_btn.visible = not game_started
		_host_force_btn.disabled = game_started
	if _host_restart_btn != null:
		_host_restart_btn.visible = game_started
		_host_restart_btn.disabled = not game_started or _host_restart_requested
		_host_restart_btn.text = "Restarting..." if _host_restart_requested else "Restart Round"

func _refresh_host_dashboard(force: bool = false) -> void:
	if _host_dashboard == null or not _host_dashboard.visible or not multiplayer.is_server():
		return

	var connected_peer_ids: Array = Array(multiplayer.get_peers())
	connected_peer_ids.sort()
	var roster_signature := "%s|%s" % [str(game_started), str(connected_peer_ids)]
	for peer_id_variant in connected_peer_ids:
		var peer_id := int(peer_id_variant)
		var data: Dictionary = ready_players.get(peer_id, {})
		var entity: Node = Host.peers.get(peer_id, null)
		roster_signature += "|%d:%s:%s:%s:%s" % [
			peer_id,
			str(data.get("ready", false)),
			str(data.get("name", "")),
			str(data.get("class", "")),
			str(entity != null and is_instance_valid(entity))
		]
	if not force and roster_signature == _host_roster_signature:
		return
	_host_roster_signature = roster_signature

	if _host_count_label != null:
		_host_count_label.text = "Connected players  %d / %d" % [connected_peer_ids.size(), Host.max_clients]
	if _host_player_list == null:
		return
	for child in _host_player_list.get_children():
		child.queue_free()

	if connected_peer_ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No players connected"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
		empty_label.add_theme_font_size_override("font_size", 18)
		empty_label.custom_minimum_size.y = 52.0
		_host_player_list.add_child(empty_label)
		return

	for peer_id_variant in connected_peer_ids:
		_add_host_player_row(int(peer_id_variant))

func _add_host_player_row(peer_id: int) -> void:
	var data: Dictionary = ready_players.get(peer_id, {})
	var entity: Node = Host.peers.get(peer_id, null)
	var has_entity := entity != null and is_instance_valid(entity)
	var player_name := str(data.get("name", "Connecting..."))
	var player_class := str(data.get("class", "peasant"))
	if has_entity:
		player_name = str(entity.get("character_name"))
		player_class = str(entity.get("character_class"))

	var player_state := "Not ready"
	if game_started:
		player_state = "Playing" if has_entity else "Choosing character"
	elif bool(data.get("ready", false)):
		player_state = "Ready"

	var row := PanelContainer.new()
	row.custom_minimum_size.y = 64.0
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.12, 0.13, 0.15, 0.92)
	row_style.corner_radius_top_left = 4
	row_style.corner_radius_top_right = 4
	row_style.corner_radius_bottom_left = 4
	row_style.corner_radius_bottom_right = 4
	row.add_theme_stylebox_override("panel", row_style)
	_host_player_list.add_child(row)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	row.add_child(margin)
	var details := VBoxContainer.new()
	margin.add_child(details)

	var name_label := Label.new()
	name_label.text = "%s   [#%d]" % [player_name, peer_id]
	name_label.add_theme_font_size_override("font_size", 19)
	details.add_child(name_label)
	var detail_label := Label.new()
	detail_label.text = "%s  •  %s" % [player_class.capitalize(), player_state]
	detail_label.add_theme_font_size_override("font_size", 15)
	detail_label.add_theme_color_override(
		"font_color",
		Color(0.45, 0.9, 0.58) if player_state in ["Ready", "Playing"] else Color(0.72, 0.72, 0.72)
	)
	details.add_child(detail_label)

func _format_host_time(seconds: float) -> String:
	var total_seconds := maxi(0, int(seconds))
	return "%02d:%02d" % [floori(float(total_seconds) / 60.0), total_seconds % 60]
