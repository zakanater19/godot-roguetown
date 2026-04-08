# res://scripts/net/Host.gd
extends Node

const PORT: int = 9904

var last_server_address: String = ""
var last_server_port: int = PORT

var max_clients: int = 200
var server_name: String = "Roguetown Server"
var peers: Dictionary = {}
var _spawner: MultiplayerSpawner = null
var _ip_sessions: Dictionary = {}
var _peer_ips: Dictionary = {}   # peer_id → normalized IP, cached at connect time
var session_ids: Dictionary = {}
var _next_session_id: float = 2.0

var auto_restart_server: bool = false
var auto_reconnect_client: bool = false
var is_host_mode: bool = false

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func start_host(custom_max_clients: int = 200, bind_ip: String = "*", custom_name: String = "") -> void:
	max_clients = custom_max_clients
	if custom_name != "":
		server_name = custom_name
	else:
		server_name = "Roguetown Server"
		
	is_host_mode = true

	var enet := ENetMultiplayerPeer.new()
	if bind_ip != "" and bind_ip != "*":
		enet.set_bind_ip(bind_ip)

	var err: Error = enet.create_server(PORT, max_clients, 3) as Error
	if err == OK:
		multiplayer.multiplayer_peer = enet
		print("Host: server listening on %s:%d with max players %d" %[bind_ip, PORT, max_clients])
		session_ids[1] = 1.0
		ServerBrowser.start_broadcasting(server_name)
		_setup_spawner()
		print("Host: generating server bundle...")
		var pck_err: Error = GameVersion.generate_server_pck()
		if pck_err != OK:
			push_error("Host: server_patch.pck generation FAILED (error %d) — %s" %[
				pck_err, GameVersion.pck_generation_error])
			push_error("Host: out-of-date clients will be rejected until the bundle can be generated.")
		else:
			print("Host: server bundle ready.")

		Sidebar.refresh_admin_visibility()
	else:
		push_error("Host: failed to start server (error %d)" % err)


func start_client_custom(ip: String, port: int) -> Error:
	last_server_address = ip
	last_server_port    = port
	is_host_mode = false

	var enet := ENetMultiplayerPeer.new()

	var err: Error = enet.create_client(ip, port, 3) as Error
	if err == OK:
		multiplayer.multiplayer_peer = enet
		print("Host: attempting client connection to %s:%d" % [ip, port])
		Sidebar.refresh_admin_visibility()
	return err


func execute_round_restart() -> void:
	if is_host_mode:
		auto_restart_server = true
	else:
		auto_reconnect_client = true

	multiplayer.multiplayer_peer = null
	peers.clear()
	_spawner = null

	Lobby.reset_lobby_state()

	LateJoin._world_state = {"tiles": {}, "objects": {}, "players": {}}
	LateJoin._pending_joins.clear()
	LateJoin._disconnected_players.clear()
	LateJoin._state_dirty = false
	LateJoin.client_connected = false
	LateJoin.map_loaded = false
	LateJoin.sync_requested = false
	LateJoin.is_manual_reconnect = false

	Sidebar._messages.clear()
	if Sidebar._rtl != null:
		Sidebar._rtl.text = ""
	Sidebar.set_visible(false)

	ServerBrowser.stop_listening()
	ServerBrowser.stop_broadcasting()

	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _setup_spawner() -> void:
	while World.main_scene == null:
		await get_tree().process_frame

	var main: Node = World.main_scene

	if _spawner == null or not is_instance_valid(_spawner):
		_spawner = MultiplayerSpawner.new()
		_spawner.name = "PlayerSpawner"
		_spawner.add_spawnable_scene("res://scenes/player.tscn")
		_spawner.spawned.connect(_on_spawner_spawned)

	if _spawner.get_parent() != main:
		if _spawner.get_parent() != null:
			_spawner.get_parent().remove_child(_spawner)
		main.add_child(_spawner)

	_spawner.spawn_path = NodePath("..")


func _on_peer_connected(id: int) -> void:
	print("Host: peer connected — id ", id)
	
	# Enforce max players strictly
	if multiplayer.get_peers().size() > max_clients:
		print("Host: Server is full. Rejecting peer ", id)
		_disconnect_peer(id)
		return

	var ip := _query_peer_ip_from_enet(id)
	if ip != "":
		_peer_ips[id] = ip
	_assign_session_id(id)


func _on_peer_disconnected(id: int) -> void:
	print("Host: peer disconnected — id ", id)

	for ip in _ip_sessions.keys():
		var session: Dictionary = _ip_sessions[ip]
		if int(session.get("active_peer_id", -1)) == id:
			session["active_peer_id"] = -1
			_ip_sessions[ip] = session
			break

	_despawn_player_for_peer(id)


func _on_spawner_spawned(node: Node) -> void:
	var auth: int = node.get_multiplayer_authority()
	if not peers.has(auth):
		peers[auth] = node


func _normalize_ip(ip: String) -> String:
	var normalized := ip.strip_edges().to_lower()

	if normalized == "localhost":
		return "127.0.0.1"

	if normalized == "0:0:0:0:0:0:0:1":
		return "::1"

	if normalized.begins_with("::ffff:"):
		normalized = normalized.substr(7)

	return normalized


func _is_local_ip(ip: String) -> bool:
	var normalized := _normalize_ip(ip)
	return normalized == "::1" or \
		   normalized.begins_with("127.") or \
		   normalized.begins_with("192.168.") or \
		   normalized.begins_with("10.") or \
		   normalized.begins_with("172.")


func _get_peer_ip(peer_id: int) -> String:
	if _peer_ips.has(peer_id):
		return _peer_ips[peer_id]
	return _query_peer_ip_from_enet(peer_id)


func _query_peer_ip_from_enet(peer_id: int) -> String:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return ""
	var ep := enet.get_peer(peer_id)
	if ep == null:
		return ""
	return _normalize_ip(ep.get_remote_address())


func _disconnect_peer(peer_id: int) -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return

	var ep := enet.get_peer(peer_id)
	if ep != null:
		ep.peer_disconnect()


func _assign_session_id(peer_id: int) -> void:
	var ip := _get_peer_ip(peer_id)
	if ip == "":
		push_warning("Host: peer %d connected without a readable remote IP; disconnecting." % peer_id)
		_disconnect_peer(peer_id)
		return

	var is_local := _is_local_ip(ip)

	if not is_local and _ip_sessions.has(ip):
		var session: Dictionary = _ip_sessions[ip]

		if int(session.get("active_peer_id", -1)) != -1:
			print("Host: rejecting duplicate active peer %d from IP %s" %[peer_id, ip])
			_disconnect_peer(peer_id)
			return

		var existing_sid: float = float(session.get("session_id", _next_session_id))
		session["active_peer_id"] = peer_id
		_ip_sessions[ip] = session
		session_ids[peer_id] = existing_sid
		return

	var sid := _next_session_id
	_next_session_id += 1.0
	session_ids[peer_id] = sid

	if not is_local:
		_ip_sessions[ip] = {
			"session_id": sid,
			"active_peer_id": peer_id
		}


func clear_session_data() -> void:
	_ip_sessions.clear()
	_peer_ips.clear()
	session_ids.clear()
	_next_session_id = 2.0

	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		session_ids[1] = 1.0


func spawn_player(peer_id: int, p_name: String = "noob", p_class: String = "peasant", is_latejoin: bool = false) -> void:
	if peers.has(peer_id):
		return

	var main: Node = World.main_scene
	if main == null:
		return

	var player_scene := load("res://scenes/player.tscn") as PackedScene
	if player_scene == null:
		return

	var player: Node2D = player_scene.instantiate()

	player.name = "Player_%d_%d" %[peer_id, Time.get_ticks_usec()]
	player.set_multiplayer_authority(peer_id)
	player.character_name = p_name
	player.character_class = p_class

	var preferred_spawns: Array[String] = []

	if is_latejoin:
		if p_class in["swordsman", "miner", "adventurer"]:
			preferred_spawns =[p_class, "adventurer", "latejoin"]
		elif p_class == "bandit":
			preferred_spawns =["antag latejoin", "bandit", "latejoin"]
		else:
			preferred_spawns = ["latejoin", p_class]
	else:
		if p_class in["swordsman", "miner", "adventurer"]:
			preferred_spawns =[p_class, "adventurer", "latejoin"]
		else:
			preferred_spawns =[p_class, "latejoin"]

	var spawners = get_tree().get_nodes_in_group("spawners")
	var valid_spawners =[]

	for pref in preferred_spawns:
		for spawner in spawners:
			if spawner.get("spawn_type") == pref:
				valid_spawners.append(spawner)
		if not valid_spawners.is_empty():
			break

	if valid_spawners.is_empty() and spawners.size() > 0:
		valid_spawners = spawners

	if valid_spawners.size() > 0:
		var chosen_spawner = valid_spawners.pick_random()
		player.position = chosen_spawner.global_position
		if "z_level" in chosen_spawner:
			player.z_level = chosen_spawner.z_level
	else:
		player.position = Vector2(32032, 32032)
		player.z_level = 3

	player.tile_pos = Vector2i(int(player.position.x / 64.0), int(player.position.y / 64.0))

	main.add_child(player)

	if player.has_method("set_character_name"):
		player.set_character_name(p_name, p_class)

	if peer_id != 1 and player.has_method("rpc_set_spawn_position"):
		player.rpc_set_spawn_position.rpc_id(peer_id, player.position)

	peers[peer_id] = player


func _despawn_player_for_peer(peer_id: int) -> void:
	if not peers.has(peer_id):
		return
	peers.erase(peer_id)


func get_player_for_peer(peer_id: int) -> Node:
	return peers.get(peer_id, null)
