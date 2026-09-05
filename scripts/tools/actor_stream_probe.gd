extends "res://scripts/tools/world_stream_probe.gd"

# Three-process regression: one host and two real clients. A fake remote actor
# cannot expose errors sent back to the owning peer during visibility changes.
var _connected: Array[int] = []
var _reports: Dictionary = {}

func _run(server: bool) -> void:
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
	var port := 19147
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stream-port="):
			port = arg.trim_prefix("--stream-port=").to_int()
	var peer := ENetMultiplayerPeer.new()
	if server:
		_check(peer.create_server(port, 4) == OK, "server binds")
		multiplayer.multiplayer_peer = peer
		World.get_tilemap(3).set_cell(A, 0, Vector2i.ZERO)
		World.get_tilemap(3).set_cell(B, 0, Vector2i.ZERO)
		_add_tree("StreamNearTree", A + Vector2i(3, 0))
		multiplayer.peer_connected.connect(_on_client_connected)
		var start := Time.get_ticks_msec()
		while _connected.size() < 2 and Time.get_ticks_msec() - start < 15000:
			await get_tree().process_frame
		_check(_connected.size() == 2, "both clients connect")
		if _connected.size() != 2:
			get_tree().quit(1)
			return
		await _verify_all("initial", 0)
		var mover := World._find_player_by_peer(_connected[0])
		for cycle in range(1, 5):
			mover.tile_pos = B
			mover.position = Defs.tile_to_pixel(B)
			await _verify_all("away", cycle - 1)
			if cycle == 1:
				# Match reconnect's in-tree authority reassignment while the other
				# client has this actor despawned by its radius filter.
				var sync := mover.get_node("StateSync") as MultiplayerSynchronizer
				var sync_id := sync.get_instance_id()
				LateJoin._reconnect.retry_update_authority(mover.get_path(), 77, 0)
				LateJoin._reconnect.retry_update_authority(mover.get_path(), _connected[0], 0)
				_check(sync.get_instance_id() == sync_id and sync.get_multiplayer_authority() == 1, "reconnect preserves the registered host synchronizer")
				await get_tree().create_timer(0.3).timeout
			# Chopping/building changes inventory and character dictionaries while
			# the clients have unloaded each other. Exercise native ON_CHANGE too.
			var tree := World.get_entity(NEAR_ID)
			tree.set("state", "stump")
			tree.call("_update_solidity")
			World.get_tilemap(3).erase_cell(A)
			for id in _connected:
				var actor := World._find_player_by_peer(id)
				actor.skills = {"sword_fighting": cycle, "blacksmithing": cycle, "sneaking": 0}
				actor.stats = {"strength": 10 + cycle, "agility": 10}
				# Exercise nested in-place mutations, not just dictionary replacement.
				actor.equipped_data["stream_probe"] = {"revision": cycle - 1}
			await get_tree().create_timer(0.2).timeout
			for id in _connected:
				var actor := World._find_player_by_peer(id)
				actor.equipped_data["stream_probe"]["revision"] = cycle
				var other_id := _connected[1] if id == _connected[0] else _connected[0]
				# Deliberately deliver an already-in-flight update after despawn.
				WorldStream.receive_actor_delta.rpc_id(other_id, World.get_entity_id(actor), {"stats": actor.stats})
			await _verify_all("changed", cycle)
			mover.tile_pos = A
			mover.position = Defs.tile_to_pixel(A)
			await _verify_all("return", cycle)
		_finish_clients.rpc()
		await get_tree().create_timer(0.3).timeout
		print("ACTOR_STREAM_SERVER_%s" % ("PASS" if _failures.is_empty() else "FAIL"))
		get_tree().quit(0 if _failures.is_empty() else 1)
		return
	_check(peer.create_client("127.0.0.1", port) == OK, "client connects")
	multiplayer.multiplayer_peer = peer
	await multiplayer.connected_to_server
	WorldStream.begin_client()
	await get_tree().create_timer(90.0).timeout
	push_error("ACTOR_STREAM_CLIENT_TIMEOUT")
	get_tree().quit(1)

func _on_client_connected(peer_id: int) -> void:
	_connected.append(peer_id)
	_add_player(peer_id, A)

func _verify_all(phase: String, revision: int) -> void:
	_reports.clear()
	_verify_clients.rpc(phase, revision, _connected)
	var start := Time.get_ticks_msec()
	while _reports.size() < 2 and Time.get_ticks_msec() - start < 15000:
		await get_tree().process_frame
	_check(_reports.size() == 2 and not _reports.values().has(false), "%s revision %d on both clients" % [phase, revision])

@rpc("authority", "call_remote", "reliable")
func _verify_clients(phase: String, revision: int, peer_ids: Array[int]) -> void:
	var own_id := multiplayer.get_unique_id()
	var moving_peer := peer_ids[0] == own_id
	var other_id := peer_ids[1] if moving_peer else peer_ids[0]
	var separated := phase == "away" or phase == "changed"
	var center := B if moving_peer and separated else A
	var start := Time.get_ticks_msec()
	var valid := false
	while Time.get_ticks_msec() - start < 12000:
		await get_tree().process_frame
		var local := World.get_local_player()
		var other := World._find_player_by_peer(other_id)
		valid = local != null and local.tile_pos == center and WorldStream.loaded_rect == WorldStream.window_at(center) and not WorldStream._waiting
		valid = valid and (other == null if separated else other != null)
		if valid:
			valid = int(local.skills.get("blacksmithing", -1)) == revision
			valid = valid and local.get_node("StateSync").get_multiplayer_authority() == 1
			if revision > 0:
				valid = valid and local.equipped_data.get("stream_probe", {}).get("revision", -1) == revision
		if valid and not separated:
			valid = int(other.skills.get("blacksmithing", -1)) == revision
			if revision > 0:
				valid = valid and other.equipped_data.get("stream_probe", {}).get("revision", -1) == revision
		if valid and phase == "return" and moving_peer:
			var tree := World.get_entity(NEAR_ID)
			valid = tree != null and tree.get("state") == "stump" and World.get_tilemap(3).get_cell_source_id(A) == -1
		if valid:
			break
	_check(valid, "%s revision %d (%s)" % [phase, revision, "moving" if moving_peer else "stationary"])
	# Leave time for native delta packets after the spawn/despawn and RPC checks.
	await get_tree().create_timer(0.2).timeout
	_report.rpc_id(1, valid)

@rpc("any_peer", "call_remote", "reliable")
func _report(valid: bool) -> void:
	if multiplayer.is_server() and _connected.has(multiplayer.get_remote_sender_id()):
		_reports[multiplayer.get_remote_sender_id()] = valid

@rpc("authority", "call_remote", "reliable")
func _finish_clients() -> void:
	print("ACTOR_STREAM_CLIENT_%s" % ("PASS" if _failures.is_empty() else "FAIL"))
	# Let the host stop first; otherwise the fixture's simultaneous disconnects
	# exercise unrelated reconnect callbacks while the transport is closing.
	await get_tree().create_timer(0.6).timeout
	get_tree().quit(0 if _failures.is_empty() else 1)
