# res://scripts/world/world_session.gd
# Handles respawn requests and round-end / restart logic.
extends RefCounted

var world: Node

func _init(p_world: Node) -> void:
	world = p_world

func handle_rpc_request_respawn(sender_id: int, request_peer_id: int) -> void:
	if sender_id != request_peer_id: return
	var old_player = world.utils.find_player_by_peer(sender_id) as Node2D
	if old_player != null and old_player.dead:
		old_player.rpc_make_corpse.rpc()
		Host.peers.erase(sender_id)
		if LateJoin._disconnected_players.has(sender_id):
			LateJoin._disconnected_players.erase(sender_id)
		if world.grab_map.has(sender_id):
			world.combat.release_grab_for_peer(sender_id, true)
		for gp_id in world.grab_map:
			var entry = world.grab_map[gp_id]
			if entry.get("is_player") and entry.get("target") == old_player:
				entry["target_peer_id"] = 1
		world.rpc_return_to_lobby.rpc_id(sender_id)

func handle_rpc_execute_round_end() -> void:
	Sidebar.add_message(
		"\n[color=#ff4444][b][font_size=24]THE ROUND HAS ENDED! RESTARTING IN 5 SECONDS...[/font_size][/b][/color]\n"
	)
	world.get_tree().create_timer(5.0).timeout.connect(_on_round_restart_timeout)

func _on_round_restart_timeout() -> void:
	if world.get_tree().current_scene.name != "MainMenu":
		Host.execute_round_restart()
