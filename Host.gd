# res://Host.gd
extends Node

const PORT:        int = 9904
var max_clients: int = 200

var peers: Dictionary = {}
var _spawner: MultiplayerSpawner = null

var _ip_sessions: Dictionary = {}
var session_ids: Dictionary = {}
var _next_session_id: float = 2.0
const LOCAL_IPS: Array =["127.0.0.1", "::1", "localhost", ""]

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func start_host(custom_max_clients: int = 200) -> void:
	max_clients = custom_max_clients
	var enet := ENetMultiplayerPeer.new()
	var err: int = enet.create_server(PORT, max_clients)
	if err == OK:
		multiplayer.multiplayer_peer = enet
		print("Host: server listening on port %d with max players %d" % [PORT, max_clients])
		session_ids[1] = 1.0
		ServerBrowser.start_broadcasting()
		_setup_spawner()
		if has_node("/root/Sidebar"):
			get_node("/root/Sidebar").refresh_debug_visibility()
	else:
		push_error("Host: failed to start server (error %d)" % err)

func start_client_custom(ip: String, port: int) -> void:
	var enet := ENetMultiplayerPeer.new()
	var err: int = enet.create_client(ip, port)
	if err == OK:
		multiplayer.multiplayer_peer = enet
		print("Host: joined as client to %s:%d" % [ip, port])
		_setup_spawner()
		if has_node("/root/Sidebar"):
			get_node("/root/Sidebar").refresh_debug_visibility()
	else:
		push_error("Host: failed to start client (error %d)" % err)

func _setup_spawner() -> void:
	while get_tree().root.get_node_or_null("Main") == null:
		await get_tree().process_frame
	var main: Node = get_tree().root.get_node("Main")
	if _spawner == null:
		_spawner = MultiplayerSpawner.new()
		_spawner.name = "PlayerSpawner"
		_spawner.add_spawnable_scene("res://player.tscn")
		_spawner.spawned.connect(_on_spawner_spawned)
		main.add_child(_spawner)
		_spawner.spawn_path = NodePath("..")

func _on_peer_connected(id: int) -> void:
	print("Host: peer connected — id ", id)
	_assign_session_id(id)

func _on_peer_disconnected(id: int) -> void:
	print("Host: peer disconnected — id ", id)
	for ip in _ip_sessions:
		if _ip_sessions[ip]["active_peer_id"] == id:
			_ip_sessions[ip]["active_peer_id"] = -1
			break
	_despawn_player_for_peer(id)

func _on_spawner_spawned(node: Node) -> void:
	var auth: int = node.get_multiplayer_authority()
	if not peers.has(auth):
		peers[auth] = node

func _get_peer_ip(peer_id: int) -> String:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null: return ""
	var ep := enet.get_peer(peer_id)
	if ep == null: return ""
	return ep.get_remote_address()

func _is_local_ip(ip: String) -> bool:
	if ip in LOCAL_IPS: return true
	if ip.begins_with("127."): return true
	return false

func _assign_session_id(peer_id: int) -> void:
	var ip := _get_peer_ip(peer_id)
	var is_local := _is_local_ip(ip)

	if not is_local and _ip_sessions.has(ip):
		var session: Dictionary = _ip_sessions[ip]
		if session["active_peer_id"] != -1:
			var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
			if enet != null:
				var ep := enet.get_peer(peer_id)
				if ep != null: ep.peer_disconnect()
			return
		else:
			var existing_sid: float = session["session_id"]
			session["active_peer_id"] = peer_id
			session_ids[peer_id] = existing_sid
			return

	var sid := _next_session_id
	_next_session_id += 1.0
	session_ids[peer_id] = sid
	if not is_local: _ip_sessions[ip] = {"session_id": sid, "active_peer_id": peer_id}

func clear_session_data() -> void:
	_ip_sessions.clear()
	session_ids.clear()
	_next_session_id = 2.0
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		session_ids[1] = 1.0

func spawn_player(peer_id: int, p_name: String = "noob", p_class: String = "peasant", is_latejoin: bool = false) -> void:
	if peers.has(peer_id): return
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main == null: return
	var player_scene := load("res://player.tscn") as PackedScene
	if player_scene == null: return

	var player: Node2D = player_scene.instantiate()
	
	# Ensures completely unique names for players upon respawning, which fixes the
	# MultiplayerSpawner collision errors. The client reads to_int() up to the first non-digit
	# and accurately finds their peer ID logic anyway (e.g. Player_1_248434 to_int() returns 1)
	player.name = "Player_%d_%d" % [peer_id, Time.get_ticks_usec()]
	
	player.set_multiplayer_authority(peer_id)
	player.character_name = p_name
	player.character_class = p_class
	
	var preferred_spawns: Array[String] =[]
	if is_latejoin:
		if p_class in["swordsman", "miner", "adventurer"]: preferred_spawns =[p_class, "adventurer", "latejoin"]
		elif p_class == "bandit": preferred_spawns =["antag latejoin", "bandit", "latejoin"]
		else: preferred_spawns =["latejoin", p_class]
	else:
		if p_class in["swordsman", "miner", "adventurer"]: preferred_spawns =[p_class, "adventurer", "latejoin"]
		else: preferred_spawns =[p_class, "latejoin"]
			
	var spawners = get_tree().get_nodes_in_group("spawners")
	var valid_spawners =[]
	
	for pref in preferred_spawns:
		for spawner in spawners:
			if spawner.get("spawn_type") == pref:
				valid_spawners.append(spawner)
		if not valid_spawners.is_empty(): break
			
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
	if not peers.has(peer_id): return
	peers.erase(peer_id)

func get_player_for_peer(peer_id: int) -> Node:
	return peers.get(peer_id, null)