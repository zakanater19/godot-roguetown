extends "res://scripts/tools/world_stream_probe.gd"

# Three-process regression for the complete player-grab lifecycle. Both real
# clients predict movement, receive the same relationship graph, and report
# their final logical and visual positions after every dragged step.
var _connected: Array[int] = []
var _reports: Dictionary = {}

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--grab-probe=server") or args.has("--grab-probe=client"):
		call_deferred("_run_grab_probe", args.has("--grab-probe=server"))

func _run_grab_probe(server: bool) -> void:
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

	var port := 19149
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--grab-port="):
			port = arg.trim_prefix("--grab-port=").to_int()
	var peer := ENetMultiplayerPeer.new()
	if server:
		_check(peer.create_server(port, 4) == OK, "grab server binds")
		multiplayer.multiplayer_peer = peer
		for y in range(A.y - 6, A.y + 7):
			for x in range(A.x - 6, A.x + 7):
				World.get_tilemap(3).set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
		multiplayer.peer_connected.connect(_on_grab_client_connected)
		var connect_start := Time.get_ticks_msec()
		while _connected.size() < 2 and Time.get_ticks_msec() - connect_start < 15000:
			await get_tree().process_frame
		_check(_connected.size() == 2, "both grab clients connect")
		if _connected.size() != 2:
			get_tree().quit(1)
			return
		await get_tree().create_timer(0.5).timeout
		var first := _connected[0]
		var second := _connected[1]
		var positions := {
			first: A,
			second: A + Vector2i.DOWN,
		}
		await _verify_grab_state("initial", first, second, positions, -1)
		await _exercise_grab_round("forward", first, second, positions)
		await _exercise_grab_round("reverse", second, first, positions)
		_finish_grab_clients.rpc()
		await get_tree().create_timer(0.4).timeout
		print("GRAB_SYNC_SERVER_%s" % ("PASS" if _failures.is_empty() else "FAIL"))
		get_tree().quit(0 if _failures.is_empty() else 1)
		return

	_check(peer.create_client("127.0.0.1", port) == OK, "grab client connects")
	multiplayer.multiplayer_peer = peer
	await multiplayer.connected_to_server
	WorldStream.begin_client()
	await get_tree().create_timer(60.0).timeout
	push_error("GRAB_SYNC_CLIENT_TIMEOUT")
	get_tree().quit(1)

func _on_grab_client_connected(peer_id: int) -> void:
	var spawn_tile := A if _connected.is_empty() else A + Vector2i.DOWN
	_connected.append(peer_id)
	_add_player(peer_id, spawn_tile)

func _exercise_grab_round(label: String, grabber_peer: int, target_peer: int, positions: Dictionary) -> void:
	_request_grab_client.rpc_id(grabber_peer, target_peer)
	var grab_start := Time.get_ticks_msec()
	while not World.grab_map.has(grabber_peer) and Time.get_ticks_msec() - grab_start < 5000:
		await get_tree().process_frame
	_check(World.grab_map.has(grabber_peer), label + " grab starts on server")
	await _verify_grab_state(label + " grabbed", _connected[0], _connected[1], positions, grabber_peer)

	# A grabbed player cannot create a cycle or become a second grabber. This
	# rejected request must not consume the cooldown for the reverse round.
	_request_grab_client.rpc_id(target_peer, grabber_peer)
	await get_tree().create_timer(0.2).timeout
	_check(World.grab_map.size() == 1 and World.grab_map.has(grabber_peer), label + " cyclic grab is rejected")

	for direction in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		var previous_grabber_tile: Vector2i = positions[grabber_peer]
		var expected_grabber_tile: Vector2i = previous_grabber_tile + direction
		positions[grabber_peer] = expected_grabber_tile
		positions[target_peer] = previous_grabber_tile
		_move_grabber_client.rpc_id(grabber_peer, direction)
		var move_start := Time.get_ticks_msec()
		while Time.get_ticks_msec() - move_start < 5000:
			await get_tree().process_frame
			var server_grabber: Node = World.utils.find_player_by_peer(grabber_peer)
			var server_target: Node = World.utils.find_player_by_peer(target_peer)
			if server_grabber != null and server_target != null and server_grabber.tile_pos == positions[grabber_peer] and server_target.tile_pos == positions[target_peer]:
				break
		await _verify_grab_state("%s step %s" % [label, direction], _connected[0], _connected[1], positions, grabber_peer)

	_release_grab_client.rpc_id(grabber_peer)
	var release_start := Time.get_ticks_msec()
	while World.grab_map.has(grabber_peer) and Time.get_ticks_msec() - release_start < 5000:
		await get_tree().process_frame
	_check(not World.grab_map.has(grabber_peer), label + " release commits on server")
	await _verify_grab_state(label + " released", _connected[0], _connected[1], positions, -1)

func _verify_grab_state(label: String, first_peer: int, second_peer: int, positions: Dictionary, grabber_peer: int) -> void:
	var first: Node = World.utils.find_player_by_peer(first_peer)
	var second: Node = World.utils.find_player_by_peer(second_peer)
	var server_valid := first != null and second != null
	if server_valid:
		server_valid = first.tile_pos == positions[first_peer] and second.tile_pos == positions[second_peer]
		if grabber_peer == -1:
			server_valid = server_valid and first.grabbed_target == null and first.grabbed_by == null
			server_valid = server_valid and second.grabbed_target == null and second.grabbed_by == null
		else:
			var server_grabber = first if first_peer == grabber_peer else second
			var server_target = second if first_peer == grabber_peer else first
			server_valid = server_valid and server_grabber.grabbed_target == server_target and server_target.grabbed_by == server_grabber
	_check(server_valid, label + " authoritative state")

	_reports.clear()
	_verify_grab_clients.rpc(label, first_peer, second_peer, positions[first_peer], positions[second_peer], grabber_peer)
	var report_start := Time.get_ticks_msec()
	while _reports.size() < 2 and Time.get_ticks_msec() - report_start < 12000:
		await get_tree().process_frame
	_check(_reports.size() == 2 and not _reports.values().has(false), label + " matches on both clients")

@rpc("authority", "call_remote", "reliable")
func _request_grab_client(target_peer: int) -> void:
	var target: Node = World.utils.find_player_by_peer(target_peer)
	if target != null:
		World.rpc_request_grab.rpc_id(1, World.get_entity_id(target), "chest")

@rpc("authority", "call_remote", "reliable")
func _move_grabber_client(direction: Vector2i) -> void:
	var player := World.get_local_player()
	if player != null:
		player._try_move(direction)

@rpc("authority", "call_remote", "reliable")
func _release_grab_client() -> void:
	World.rpc_request_release_grab.rpc_id(1)

@rpc("authority", "call_remote", "reliable")
func _verify_grab_clients(label: String, first_peer: int, second_peer: int, first_tile: Vector2i, second_tile: Vector2i, grabber_peer: int) -> void:
	var start := Time.get_ticks_msec()
	var valid := false
	while Time.get_ticks_msec() - start < 10000:
		await get_tree().process_frame
		var first: Node = World.utils.find_player_by_peer(first_peer)
		var second: Node = World.utils.find_player_by_peer(second_peer)
		valid = first != null and second != null
		if not valid:
			continue
		valid = first.tile_pos == first_tile and second.tile_pos == second_tile
		valid = valid and not first.moving and not second.moving
		valid = valid and first.pixel_pos.distance_to(World.tile_to_pixel(first_tile)) < 0.1
		valid = valid and second.pixel_pos.distance_to(World.tile_to_pixel(second_tile)) < 0.1
		if grabber_peer == -1:
			valid = valid and first.grabbed_target == null and first.grabbed_by == null
			valid = valid and second.grabbed_target == null and second.grabbed_by == null
		else:
			var grabber = first if first_peer == grabber_peer else second
			var target = second if first_peer == grabber_peer else first
			valid = valid and grabber.grabbed_target == target and target.grabbed_by == grabber
		if valid:
			break
	_check(valid, label + " local view")
	_report_grab_state.rpc_id(1, valid)

@rpc("any_peer", "call_remote", "reliable")
func _report_grab_state(valid: bool) -> void:
	if multiplayer.is_server() and _connected.has(multiplayer.get_remote_sender_id()):
		_reports[multiplayer.get_remote_sender_id()] = valid

@rpc("authority", "call_remote", "reliable")
func _finish_grab_clients() -> void:
	print("GRAB_SYNC_CLIENT_%s" % ("PASS" if _failures.is_empty() else "FAIL"))
	await get_tree().create_timer(0.7).timeout
	get_tree().quit(0 if _failures.is_empty() else 1)
