extends "res://scripts/tools/world_stream_probe.gd"

# Two-process regression for the reconnect-hand identity boundary. The client
# rebuilds a held item from captured state, then uses the production Q/drop RPC.
var _client_id: int = 0
var _client_reported: bool = false
var _client_valid: bool = false

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--hand-probe=server") or args.has("--hand-probe=client"):
		call_deferred("_run_hand_probe", args.has("--hand-probe=server"))

func _run_hand_probe(server: bool) -> void:
	Engine.max_fps = 120
	LateJoin.set_process(false)
	LateJoin._version_check_sent = true
	BootstrapNet._version_check_sent = true
	_main = ProbeMain.new()
	_main.name = "Main"
	for z in range(1, 6):
		var tm := TileMapLayer.new()
		tm.name = "TileMapLayer_Z%d" % z
		tm.tile_set = load("res://assets/tileset.tres")
		_main.add_child(tm)
	add_child(_main)
	Host._setup_spawner()

	var port := 19151
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hand-port="):
			port = arg.trim_prefix("--hand-port=").to_int()
	var peer := ENetMultiplayerPeer.new()
	if server:
		_check(peer.create_server(port, 2) == OK, "reconnect-hand server binds")
		multiplayer.multiplayer_peer = peer
		World.get_tilemap(3).set_cell(A, 0, Vector2i.ZERO)
		multiplayer.peer_connected.connect(_on_hand_client_connected)
		var start := Time.get_ticks_msec()
		while not _client_reported and Time.get_ticks_msec() - start < 15000:
			await get_tree().process_frame
		var server_player: Node = World.utils.find_player_by_peer(_client_id)
		var server_valid := _client_reported and _client_valid and server_player != null and server_player.hands[0] == null
		_check(server_valid, "reconstructed held item drops through the production RPC")
		print("RECONNECT_HAND_SERVER_%s" % ("PASS" if _failures.is_empty() else "FAIL"))
		_finish_hand_client.rpc()
		# Let the client close first so shutdown does not race two ENet peers.
		await get_tree().create_timer(0.8).timeout
		if multiplayer.multiplayer_peer != null:
			multiplayer.multiplayer_peer.close()
			multiplayer.multiplayer_peer = null
		await get_tree().process_frame
		get_tree().quit(0 if _failures.is_empty() else 1)
		return

	_check(peer.create_client("127.0.0.1", port) == OK, "reconnect-hand client connects")
	multiplayer.multiplayer_peer = peer
	await multiplayer.connected_to_server
	await get_tree().create_timer(20.0).timeout
	push_error("RECONNECT_HAND_CLIENT_TIMEOUT")
	get_tree().quit(1)

func _on_hand_client_connected(peer_id: int) -> void:
	_client_id = peer_id
	var player := _add_player(peer_id, A)
	var item := load("res://objects/keyring.tscn").instantiate() as Node2D
	item.name = "ReconnectHeldKeyring"
	item.position = World.tile_to_pixel(A)
	var saved_id := "probe:reconnected_hand:%d" % peer_id
	World.add_registered_entity(_main, item, saved_id)
	player.hands[0] = item
	for child in item.get_children():
		if child is CollisionShape2D:
			child.disabled = true
	await get_tree().create_timer(0.5).timeout
	_reconstruct_and_drop.rpc_id(peer_id, {
		"entity_id": saved_id,
		"name": item.name,
		"scene_file_path": item.scene_file_path,
		"position": item.position,
		"contents": item.get("contents").duplicate(true),
	}, A)

@rpc("authority", "call_remote", "reliable")
func _reconstruct_and_drop(hand_state: Dictionary, drop_tile: Vector2i) -> void:
	var start := Time.get_ticks_msec()
	var player: Node = null
	while player == null and Time.get_ticks_msec() - start < 5000:
		await get_tree().process_frame
		player = World.get_local_player()
	var valid := player != null
	var item: Node = null
	if valid:
		item = LateJoin._reconnect._recreate_hand_item(hand_state)
		valid = item != null and World.get_entity_id(item) == str(hand_state["entity_id"])
	if valid:
		player.hands[0] = item
		player.active_hand = 0
		player._update_hands_ui()
		player.backend.drop_item_from_hand(0)
		var drop_start := Time.get_ticks_msec()
		while player.hands[0] != null and Time.get_ticks_msec() - drop_start < 5000:
			await get_tree().process_frame
		valid = player.hands[0] == null
		var drop_delta: Vector2 = (item.global_position - World.tile_to_pixel(drop_tile)).abs()
		valid = valid and drop_delta.x <= player.DROP_SPREAD + 0.1 and drop_delta.y <= player.DROP_SPREAD + 0.1
		valid = valid and World.get_entity(str(hand_state["entity_id"])) == item
	_check(valid, "reconnect client can Q-drop reconstructed item")
	_report_hand_result.rpc_id(1, valid)

@rpc("any_peer", "call_remote", "reliable")
func _report_hand_result(valid: bool) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == _client_id:
		_client_reported = true
		_client_valid = valid

@rpc("authority", "call_remote", "reliable")
func _finish_hand_client() -> void:
	print("RECONNECT_HAND_CLIENT_%s" % ("PASS" if _failures.is_empty() else "FAIL"))
	await get_tree().create_timer(0.15).timeout
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	await get_tree().process_frame
	get_tree().quit(0 if _failures.is_empty() else 1)
