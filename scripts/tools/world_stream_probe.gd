extends Node

# Integration probe: launch this scene twice with --stream-probe=server/client.
# Both peers use the real stream RPCs, player spawner, FOV and object scenes.
const A := Vector2i(100, 100)
const B := Vector2i(350, 350)
const NEAR_ID := "world:StreamNearTree"
const FAR_ID := "world:StreamFarTree"
var _failures: Array[String] = []
var _main: Node2D
var _client_peer: int = 0

class ProbeMain:
	extends "res://scripts/core/main.gd"

	func _ready() -> void:
		World.register_main(self)
		_ensure_runtime_grass_layers()
		_register_existing_render_distance_nodes()
		region_generation_ready = true

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--stream-probe=server") or args.has("--stream-probe=client"):
		call_deferred("_run", args.has("--stream-probe=server"))

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
	# Match main.tscn: a map-authored NPC enters/readies before its parent
	# registers WorldStream. Runtime-only spawns miss this initialization case.
	var authored_mob := load("res://npcs/spider.tscn").instantiate() as Node2D
	authored_mob.name = "Spider"
	authored_mob.position = Defs.tile_to_pixel(A + Vector2i(0, 4))
	authored_mob.set_meta("entity_id", "world:StreamSpider")
	_main.add_child(authored_mob)
	_check(authored_mob.find_children("*", "MultiplayerSynchronizer", true, false).is_empty(), "streamed NPC has no native synchronizer before tree entry")
	add_child(_main)
	authored_mob.set_process(false)
	Host._setup_spawner()
	var peer := ENetMultiplayerPeer.new()
	var port := 19145
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stream-port="):
			port = arg.trim_prefix("--stream-port=").to_int()
	if server:
		_check(peer.create_server(port, 4) == OK, "test server binds port")
		multiplayer.multiplayer_peer = peer
		for center in [A, B]:
			for y in range(center.y - 5, center.y + 6):
				for x in range(center.x - 5, center.x + 6):
					World.get_tilemap(3).set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
		_add_tree("StreamNearTree", A + Vector2i(3, 0))
		_add_tree("StreamFarTree", B + Vector2i(3, 0))
		var canopy := load("res://objects/tree_spawn.tscn").instantiate() as Node2D
		canopy.name = "StreamCanopy"
		canopy.position = Defs.tile_to_pixel(A + Vector2i(-3, -3))
		canopy.set("seed_override", 1234)
		_main.add_child(canopy)
		_add_player(42, A + Vector2i(2, 0))
		multiplayer.peer_connected.connect(_on_client_connected)
		print("STREAM_PROBE_SERVER_READY")
		await get_tree().create_timer(45.0).timeout
		push_error("STREAM_PROBE_SERVER_TIMEOUT")
		get_tree().quit(1)
		return
	_check(peer.create_client("127.0.0.1", port) == OK, "test client connects")
	multiplayer.multiplayer_peer = peer
	await multiplayer.connected_to_server
	WorldStream.begin_client()
	await _wait_for_window(A)
	var near := World.get_entity(NEAR_ID)
	_check(near != null, "near tree arrives from host")
	var first_instance := near.get_instance_id() if near != null else 0
	_check(World.get_entity(FAR_ID) == null, "far tree is absent")
	_check(World.get_entity("player:Player_42") != null, "near remote player spawns")
	_check(World.get_entity("world:StreamSpider") != null, "near NPC arrives")
	_check(not get_tree().get_nodes_in_group("leaf_canopy").is_empty(), "tree canopy is reconstructed")
	var local_player := World.get_local_player()
	_check(local_player != null and local_player.hands[0] != null, "held item state arrives")
	_check(World.get_tilemap(3).get_cell_source_id(A) == 0, "near terrain arrives")
	_check(World.get_tilemap(3).get_cell_source_id(B) == -1, "far terrain is unloaded")
	_stage.rpc_id(1, "away")
	await _wait_for_window(B)
	_check(World.get_entity(NEAR_ID) == null, "leaving frees near tree")
	_check(World.get_entity("player:Player_42") == null, "leaving despawns remote player")
	_check(World.get_entity("world:StreamSpider") == null, "leaving frees NPC")
	_check(get_tree().get_nodes_in_group("leaf_canopy").is_empty(), "leaving frees tree canopy")
	_check(is_instance_valid(local_player.hands[0]), "held item survives window change")
	_check(World.get_tilemap(3).get_cell_source_id(A) == -1, "leaving unloads terrain")
	var far := World.get_entity(FAR_ID)
	_check(far != null and far.get("state") == "stump", "entry gets fresh far tree state")
	_check(is_equal_approx(World.get_tile_movement_multiplier(B + Vector2i(3, 0), 3), 1.5), "streamed stump retains slowdown")
	_check(not World.is_solid(B + Vector2i(3, 0), 3), "streamed stump has no stale collision")
	_stage.rpc_id(1, "return")
	await _wait_for_window(A)
	near = World.get_entity(NEAR_ID)
	_check(near != null and near.get_instance_id() != first_instance, "return instantiates a new tree object")
	_check(near != null and near.get("state") == "stump", "return gets state changed while unloaded")
	_check(World.get_entity(FAR_ID) == null, "return frees far tree")
	_check(World.get_entity("player:Player_42") != null, "remote player respawns on return")
	_check(World.get_entity("world:StreamSpider") != null, "NPC returns from host state")
	var returned_mob := World.get_entity("world:StreamSpider")
	_check(returned_mob != null and returned_mob.get("health") == 73 and returned_mob.get("facing") == 2, "NPC state changed while unloaded arrives on return")
	_check(returned_mob != null and returned_mob.get("tile_pos") == A + Vector2i(1, 4), "NPC movement while unloaded arrives on return")
	_check(returned_mob != null and returned_mob.find_children("*", "MultiplayerSynchronizer", true, false).is_empty(), "reloaded NPC has no native synchronizer")
	_check(not get_tree().get_nodes_in_group("leaf_canopy").is_empty(), "canopy returns")
	_stage.rpc_id(1, "finish")
	print("STREAM_PROBE_CLIENT_%s failures=%d resident=%d" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size(), WorldStream.index.nodes.size()])
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if _failures.is_empty() else 1)

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
		push_error("STREAM_PROBE_FAIL: " + description)
	else:
		print("STREAM_PROBE_PASS: " + description)

func _wait_for_window(center: Vector2i) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 12000:
		await get_tree().process_frame
		if WorldStream.loaded_rect == WorldStream.window_at(center) and not WorldStream._waiting:
			await get_tree().create_timer(0.05).timeout
			return
	_check(false, "window completes at %s" % center)

func _add_tree(node_name: String, tile: Vector2i) -> Node2D:
	var tree := load("res://objects/tree.tscn").instantiate() as Node2D
	tree.name = node_name
	tree.position = Defs.tile_to_pixel(tile)
	tree.set_meta("entity_id", "world:" + node_name)
	_main.add_child(tree)
	return tree

func _add_player(peer_id: int, tile: Vector2i) -> Node2D:
	var player := load("res://scenes/player.tscn").instantiate() as Node2D
	player.name = "Player_%d" % peer_id
	player.set_multiplayer_authority(peer_id)
	player.set("tile_pos", tile)
	player.position = Defs.tile_to_pixel(tile)
	_main.add_child(player)
	return player

func _on_client_connected(peer_id: int) -> void:
	_client_peer = peer_id
	var player := _add_player(peer_id, A)
	var item := load("res://objects/dirk.tscn").instantiate() as Node2D
	item.name = "StreamHeldDirk"
	item.position = Defs.tile_to_pixel(A)
	item.set_meta("entity_id", "world:StreamHeldDirk")
	_main.add_child(item)
	player.hands[0] = item

@rpc("any_peer", "call_remote", "reliable")
func _stage(stage: String) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != _client_peer:
		return
	var player := World._find_player_by_peer(_client_peer)
	if stage == "away":
		var tree := World.get_entity(FAR_ID)
		tree.set("state", "stump")
		tree.call("_update_solidity")
		player.set("tile_pos", B)
		player.position = Defs.tile_to_pixel(B)
	elif stage == "return":
		var mob := World.get_entity("world:StreamSpider")
		World.unregister_solid(mob.get("tile_pos"), mob.get("z_level"), mob)
		mob.set("tile_pos", A + Vector2i(1, 4))
		mob.position = Defs.tile_to_pixel(mob.get("tile_pos"))
		mob.set("health", 73)
		mob.set("facing", 2)
		World.register_solid(mob.get("tile_pos"), mob.get("z_level"), mob)
		var tree := World.get_entity(NEAR_ID)
		tree.set("state", "stump")
		tree.call("_update_solidity")
		var distant_actor := World.get_entity("player:Player_42")
		WorldStream.broadcast_actor(distant_actor, "receive_damage", [1, "chest"], true)
		player.set("tile_pos", A)
		player.position = Defs.tile_to_pixel(A)
	elif stage == "finish":
		_check(World.get_entity(NEAR_ID) != null and World.get_entity(FAR_ID) != null, "host retains both distant and near trees")
		_check(World.get_tilemap(3).get_cell_source_id(A) == 0 and World.get_tilemap(3).get_cell_source_id(B) == 0, "host retains all terrain")
		print("STREAM_PROBE_SERVER_PASS")
		await get_tree().create_timer(0.5).timeout
		get_tree().quit(0 if _failures.is_empty() else 1)
