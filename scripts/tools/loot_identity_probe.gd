extends "res://scripts/tools/world_stream_probe.gd"

# Two-process regression for equipped-item theft. A real client requests the
# theft and both peers must resolve exactly one pouch under the server's ID.
const TARGET_PEER := 42

var _client_id: int = 0
var _client_reported: bool = false
var _client_valid: bool = false
var _verification_sent: bool = false

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--loot-probe=server") or args.has("--loot-probe=client"):
		call_deferred("_run_loot_probe", args.has("--loot-probe=server"))

func _run_loot_probe(server: bool) -> void:
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

	var port := 19153
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--loot-port="):
			port = arg.trim_prefix("--loot-port=").to_int()
	var peer := ENetMultiplayerPeer.new()
	if server:
		_check(peer.create_server(port, 2) == OK, "loot-identity server binds")
		multiplayer.multiplayer_peer = peer
		for x in range(A.x - 2, A.x + 3):
			World.get_tilemap(3).set_cell(Vector2i(x, A.y), 0, Vector2i.ZERO)
		multiplayer.peer_connected.connect(_on_loot_client_connected)
		var start := Time.get_ticks_msec()
		while not _client_reported and Time.get_ticks_msec() - start < 15000:
			await get_tree().process_frame
		var target: Node = World.utils.find_player_by_peer(TARGET_PEER)
		var server_valid := _client_reported and _client_valid and target != null
		server_valid = server_valid and target.equipped.get("pocket_1") == null and target.equipped_data.get("pocket_1") == null
		_check(server_valid, "pouch theft produces one shared entity on both peers")
		print("LOOT_IDENTITY_SERVER_%s" % ("PASS" if _failures.is_empty() else "FAIL"))
		_finish_loot_client.rpc()
		await get_tree().create_timer(0.8).timeout
		if multiplayer.multiplayer_peer != null:
			multiplayer.multiplayer_peer.close()
			multiplayer.multiplayer_peer = null
		await get_tree().process_frame
		get_tree().quit(0 if _failures.is_empty() else 1)
		return

	_check(peer.create_client("127.0.0.1", port) == OK, "loot-identity client connects")
	multiplayer.multiplayer_peer = peer
	await multiplayer.connected_to_server
	await get_tree().create_timer(20.0).timeout
	push_error("LOOT_IDENTITY_CLIENT_TIMEOUT")
	get_tree().quit(1)

func _on_loot_client_connected(peer_id: int) -> void:
	_client_id = peer_id
	_add_player(peer_id, A)
	var target: Node2D = _add_player(TARGET_PEER, A + Vector2i.RIGHT)
	target.equipped["pocket_1"] = "Pouch"
	target.equipped_data["pocket_1"] = {
		"contents": [
			{"item_type": "BrownKey", "key_id": 7},
			null,
			null,
			null,
		],
	}
	await get_tree().create_timer(0.7).timeout
	_request_pouch_theft.rpc_id(peer_id, World.get_entity_id(target))

@rpc("authority", "call_remote", "reliable")
func _request_pouch_theft(target_id: String) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 5000:
		await get_tree().process_frame
		if World.get_local_player() != null and World.get_entity(target_id) != null:
			break
	World.rpc_request_loot_item.rpc_id(1, target_id, multiplayer.get_unique_id(), "equip", "pocket_1")

@rpc("authority", "call_remote", "reliable")
func _verify_pouch_theft(target_id: String, pouch_id: String) -> void:
	var start := Time.get_ticks_msec()
	var valid := false
	while Time.get_ticks_msec() - start < 5000:
		await get_tree().process_frame
		var target: Node = World.get_entity(target_id)
		var pouch: Node = World.get_entity(pouch_id)
		valid = target != null and pouch != null
		if valid:
			valid = target.equipped.get("pocket_1") == null and target.equipped_data.get("pocket_1") == null
			valid = valid and pouch.get("contents").size() == Defs.POUCH_SLOT_COUNT
			valid = valid and pouch.get("contents")[0].get("key_id", -1) == 7
			var matching_pouches := 0
			for node in get_tree().get_nodes_in_group("pickable"):
				if node != null and is_instance_valid(node) and node.get("item_type") == "Pouch":
					matching_pouches += 1
			valid = valid and matching_pouches == 1
		if valid:
			break
	_check(valid, "loot client has one authoritative stolen pouch")
	_report_loot_result.rpc_id(1, valid)

@rpc("any_peer", "call_remote", "reliable")
func _report_loot_result(valid: bool) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == _client_id:
		_client_reported = true
		_client_valid = valid

@rpc("authority", "call_remote", "reliable")
func _finish_loot_client() -> void:
	print("LOOT_IDENTITY_CLIENT_%s" % ("PASS" if _failures.is_empty() else "FAIL"))
	await get_tree().create_timer(0.15).timeout
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	await get_tree().process_frame
	get_tree().quit(0 if _failures.is_empty() else 1)

func _process(_delta: float) -> void:
	if not MultiplayerSession.is_active(multiplayer):
		return
	if not multiplayer.is_server() or _client_id == 0 or _client_reported or _verification_sent:
		return
	var target: Node = World.utils.find_player_by_peer(TARGET_PEER)
	if target == null or target.equipped.get("pocket_1") != null:
		return
	for node in get_tree().get_nodes_in_group("pickable"):
		if node != null and is_instance_valid(node) and node.get("item_type") == "Pouch":
			_verify_pouch_theft.rpc_id(_client_id, World.get_entity_id(target), World.get_entity_id(node))
			_verification_sent = true
			return
