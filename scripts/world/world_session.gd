# res://scripts/world/world_session.gd
# Handles respawn requests and round-end / restart logic.
extends RefCounted

const GHOST_SCENE = preload("res://core/ghost.tscn")

var world: Node

func _init(p_world: Node) -> void:
	world = p_world

func handle_player_death(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.get("is_ghost") == true:
		return

	var peer_id: int = player.get_multiplayer_authority()
	if peer_id <= 0:
		return
	if world.utils.find_player_by_peer(peer_id) != player:
		return

	player.rpc_make_corpse.rpc()

	if world.grab_map.has(peer_id):
		world.combat.release_grab_for_peer(peer_id, true)
	for gp_id in world.grab_map:
		var entry = world.grab_map[gp_id]
		if entry.get("is_player") and entry.get("target") == player:
			entry["target_peer_id"] = -1

	var ghost = GHOST_SCENE.instantiate()
	ghost.name = "Ghost_%d_%d" % [peer_id, Time.get_ticks_usec()]
	ghost.set_multiplayer_authority(peer_id)
	ghost.set("character_name", player.get("character_name"))
	ghost.set("character_class", player.get("character_class"))
	ghost.set("z_level", player.get("z_level"))
	ghost.set("view_z_level", player.get("z_level"))
	var corpse_tile: Vector2i = player.get("tile_pos")
	var corpse_pixel: Vector2 = world.tile_to_pixel(corpse_tile)
	ghost.set("tile_pos", corpse_tile)
	ghost.set("pixel_pos", corpse_pixel)
	ghost.position = corpse_pixel
	world.main_scene.add_child(ghost)
	if ghost.has_method("rpc_sync_ghost_state"):
		ghost.rpc_sync_ghost_state.rpc(player.get("character_name"), player.get("character_class"), corpse_tile, player.get("z_level"))

	Host.peers[peer_id] = ghost
	LateJoin.update_player_state(peer_id, {"position": ghost.position, "z_level": ghost.get("z_level")})

func handle_rpc_request_respawn(sender_id: int, request_peer_id: int) -> void:
	if sender_id != request_peer_id: return
	var current_entity = world.utils.find_player_by_peer(sender_id)
	if current_entity != null and current_entity.get("is_ghost") == true:
		Host.peers.erase(sender_id)
		current_entity.queue_free()
		if LateJoin._disconnected_players.has(sender_id):
			LateJoin._disconnected_players.erase(sender_id)
		if world.grab_map.has(sender_id):
			world.combat.release_grab_for_peer(sender_id, true)
		world.rpc_return_to_lobby.rpc_id(sender_id)
		return

	var old_player = current_entity
	if old_player != null and old_player.get("dead") == true:
		old_player.rpc_make_corpse.rpc()
		Host.peers.erase(sender_id)
		if LateJoin._disconnected_players.has(sender_id):
			LateJoin._disconnected_players.erase(sender_id)
		if world.grab_map.has(sender_id):
			world.combat.release_grab_for_peer(sender_id, true)
		for gp_id in world.grab_map:
			var entry = world.grab_map[gp_id]
			if entry.get("is_player") and entry.get("target") == old_player:
				entry["target_peer_id"] = -1
		world.rpc_return_to_lobby.rpc_id(sender_id)

func handle_rpc_execute_round_end() -> void:
	Sidebar.add_message(
		"\n[color=#ff4444][b][font_size=24]THE ROUND HAS ENDED! RESTARTING IN 5 SECONDS...[/font_size][/b][/color]\n"
	)
	world.get_tree().create_timer(5.0).timeout.connect(_on_round_restart_timeout)

func _on_round_restart_timeout() -> void:
	if world.get_tree().current_scene.name != "MainMenu":
		Host.execute_round_restart()
