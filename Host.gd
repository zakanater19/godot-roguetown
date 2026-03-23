# res://Host.gd
# AutoLoad singleton — register as "Host" in project.godot [autoload].
extends Node

const PORT:        int = 9904
const MAX_CLIENTS: int = 200

# peer_id (int) → player Node2D
var peers: Dictionary = {}

var _spawner: MultiplayerSpawner = null

# ── Session ID tracking (round-duration, wiped at round end) ─────────────────
# Maps public IP string → { "session_id": float, "active_peer_id": int }
# active_peer_id is set to -1 when that player is disconnected.
# Localhost connections are never entered here (they always get fresh IDs).
var _ip_sessions: Dictionary = {}

# Maps peer_id (int) → session_id (float).
# Host is always session_id 1.0. Clients start from 2.0 upward.
var session_ids: Dictionary = {}

var _next_session_id: float = 2.0

# IPs that are treated as local connections and are never IP-blocked.
const LOCAL_IPS: Array = ["127.0.0.1", "::1", "localhost", ""]

func _ready() -> void:
	# ── Peer lifecycle ───────────────────────────────────────────────────────
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func start_host() -> void:
	var enet := ENetMultiplayerPeer.new()
	var err: int = enet.create_server(PORT, MAX_CLIENTS)
	
	if err == OK:
		multiplayer.multiplayer_peer = enet
		print("Host: server listening on port %d" % PORT)
		# The host/server is always session ID 1.
		session_ids[1] = 1.0
		ServerBrowser.start_broadcasting()
		_setup_spawner()
		
		# Refresh debug UI now that we are hosting
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
		
		# Ensure debug UI is hidden for clients
		if has_node("/root/Sidebar"):
			get_node("/root/Sidebar").refresh_debug_visibility()
	else:
		push_error("Host: failed to start client (error %d)" % err)

func _setup_spawner() -> void:
	# Wait until the main scene has fully loaded and Main is in the tree
	while get_tree().root.get_node_or_null("Main") == null:
		await get_tree().process_frame

	var main: Node = get_tree().root.get_node("Main")

	if _spawner == null:
		# ── MultiplayerSpawner ───────────────────────────────────────────────────
		_spawner = MultiplayerSpawner.new()
		_spawner.name = "PlayerSpawner"
		_spawner.add_spawnable_scene("res://player.tscn")
		_spawner.spawned.connect(_on_spawner_spawned)
		main.add_child(_spawner)
		
		# FIX: Use a relative path ("..") to watch the Main node (which is the spawner's parent).
		_spawner.spawn_path = NodePath("..")

# ── Peer signals ─────────────────────────────────────────────────────────────

func _on_peer_connected(id: int) -> void:
	print("Host: peer connected — id ", id)
	_assign_session_id(id)

func _on_peer_disconnected(id: int) -> void:
	print("Host: peer disconnected — id ", id)
	# Mark the session as inactive so the IP slot is free for reconnection,
	# but preserve the IP entry and session_id for the rest of the round.
	for ip in _ip_sessions:
		if _ip_sessions[ip]["active_peer_id"] == id:
			_ip_sessions[ip]["active_peer_id"] = -1
			break
	_despawn_player_for_peer(id)

func _on_spawner_spawned(node: Node) -> void:
	var auth: int = node.get_multiplayer_authority()
	if not peers.has(auth):
		peers[auth] = node

# ── Session ID helpers ────────────────────────────────────────────────────────

# Returns the remote IP address of a connected ENet peer, or "" on failure.
func _get_peer_ip(peer_id: int) -> String:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return ""
	var ep := enet.get_peer(peer_id)
	if ep == null:
		return ""
	return ep.get_remote_address()

# Returns true if the given IP string is a local/loopback address.
func _is_local_ip(ip: String) -> bool:
	if ip in LOCAL_IPS:
		return true
	# Also catch any other 127.x.x.x range just in case.
	if ip.begins_with("127."):
		return true
	return false

# Called when a new peer connects. Assigns a round-scoped session ID to the
# peer, or refuses the connection if a different peer from the same public IP
# is already active.
func _assign_session_id(peer_id: int) -> void:
	var ip := _get_peer_ip(peer_id)
	var is_local := _is_local_ip(ip)

	if not is_local and _ip_sessions.has(ip):
		var session: Dictionary = _ip_sessions[ip]
		if session["active_peer_id"] != -1:
			# A client from this public IP is already connected — refuse.
			print("Host: refusing peer %d — IP %s already has an active session (session %.0f)" % [peer_id, ip, session["session_id"]])
			var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
			if enet != null:
				var ep := enet.get_peer(peer_id)
				if ep != null:
					ep.peer_disconnect()
			return
		else:
			# Same public IP reconnecting after a drop — reuse their session ID.
			var existing_sid: float = session["session_id"]
			session["active_peer_id"] = peer_id
			session_ids[peer_id] = existing_sid
			print("Host: peer %d reconnected — reassigned session ID %.0f for IP %s" % [peer_id, existing_sid, ip])
			return

	# New connection (or localhost) — hand out the next available session ID.
	var sid := _next_session_id
	_next_session_id += 1.0
	session_ids[peer_id] = sid

	# Only track public IPs in _ip_sessions; localhost connections are unrestricted.
	if not is_local:
		_ip_sessions[ip] = {"session_id": sid, "active_peer_id": peer_id}

	print("Host: peer %d assigned session ID %.0f (IP: %s%s)" % [peer_id, sid, ip, " [local]" if is_local else ""])

# Call this at the end of a round to wipe all session data for the next round.
func clear_session_data() -> void:
	_ip_sessions.clear()
	session_ids.clear()
	_next_session_id = 2.0
	# Re-register the host's own permanent ID.
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		session_ids[1] = 1.0
	print("Host: session data cleared for new round.")

# ── Spawn / Despawn ───────────────────────────────────────────────────────────

func spawn_player(peer_id: int, p_name: String = "noob", p_class: String = "peasant", is_latejoin: bool = false) -> void:
	if peers.has(peer_id):
		return

	var main: Node = get_tree().root.get_node_or_null("Main")
	if main == null:
		push_error("Host: Main node not found")
		return

	# All peers get a fresh instance of player.tscn
	var player_scene := load("res://player.tscn") as PackedScene
	if player_scene == null:
		push_error("Host: res://player.tscn not found — cannot spawn for peer %d" % peer_id)
		return

	var player: Node2D = player_scene.instantiate()
	player.name = "Player_%d" % peer_id
	player.set_multiplayer_authority(peer_id)
	
	player.character_name = p_name
	player.character_class = p_class
	
	# SPAWNER LOGIC (Priority Arrays)
	var preferred_spawns: Array[String] = []
	
	if is_latejoin:
		if p_class in["swordsman", "miner", "adventurer"]:
			# Adventurers always prefer their class spawn, not the town latejoin
			preferred_spawns = [p_class, "adventurer", "latejoin"]
		elif p_class == "bandit":
			# Antags prefer their specific latejoin, fallback to their class spawn
			preferred_spawns = ["antag latejoin", "bandit", "latejoin"]
		else:
			# Towners prefer latejoin
			preferred_spawns =["latejoin", p_class]
	else:
		# Round start
		if p_class in["swordsman", "miner", "adventurer"]:
			preferred_spawns =[p_class, "adventurer", "latejoin"]
		else:
			preferred_spawns = [p_class, "latejoin"]
			
	var spawners = get_tree().get_nodes_in_group("spawners")
	var valid_spawners =[]
	
	# Iterate through our priorities and grab the first matching spawners found
	for pref in preferred_spawns:
		for spawner in spawners:
			if spawner.get("spawn_type") == pref:
				valid_spawners.append(spawner)
		
		# If we found at least one match for this priority, stop searching!
		if not valid_spawners.is_empty():
			break
			
	# Final fallback to absolutely any spawner on the map
	if valid_spawners.is_empty() and spawners.size() > 0:
		valid_spawners = spawners
		
	if valid_spawners.size() > 0:
		var chosen_spawner = valid_spawners.pick_random()
		player.position = chosen_spawner.global_position
	else:
		# Explicitly set the hardcoded spawn point fallback if no spawners exist
		player.position = Vector2(32032, 32032)
	
	player.tile_pos = Vector2i(int(player.position.x / 64.0), int(player.position.y / 64.0))
	
	main.add_child(player)
	
	# Explicitly sync name/class via RPC — bypasses MultiplayerSynchronizer
	# which does not reliably transmit these properties to clients.
	if player.has_method("set_character_name"):
		player.set_character_name(p_name, p_class)
		
	# FORCE the client to acknowledge this spawn position so they don't overwrite it
	if peer_id != 1 and player.has_method("rpc_set_spawn_position"):
		player.rpc_set_spawn_position.rpc_id(peer_id, player.position)
	
	peers[peer_id] = player

func _despawn_player_for_peer(peer_id: int) -> void:
	if not peers.has(peer_id):
		return
	
	# Note: LateJoin.gd handles the player node preservation via its own signal listener.
	# We only need to manage the Host's peer dictionary here.
	peers.erase(peer_id)

# ── Query ─────────────────────────────────────────────────────────────────────

func get_player_for_peer(peer_id: int) -> Node:
	return peers.get(peer_id, null)
	
