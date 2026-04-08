# res://scripts/player/playersneak.gd
# Handles sneak toggle, alpha fade, proximity reveal, and sneak-reveal broadcast.
extends RefCounted

var player: Node2D

func _init(p_player: Node2D) -> void:
	player = p_player

func toggle_sneak_mode() -> void:
	if not player._is_local_authority(): return
	var new_val: bool = not player.is_sneaking
	if player.multiplayer.has_multiplayer_peer():
		player._rpc_sync_sneak_mode.rpc(new_val)
	else:
		set_sneak_mode_local(new_val)

func set_sneak_mode_local(val: bool) -> void:
	player.is_sneaking = val
	if not player.is_sneaking:
		player.sneak_alpha = 1.0
		player._sneak_was_hidden = false
		apply_sneak_alpha(1.0)
	player._update_water_submerge()
	if player.multiplayer.has_multiplayer_peer() and player._is_local_authority() and Lighting.has_method("report_local_world_light_now"):
		Lighting.report_local_world_light_now()
	if player._hud != null and player._is_local_authority():
		player._hud.update_sneak_display(player.is_sneaking)

func apply_sneak_alpha(alpha: float) -> void:
	var all_sprites: Array[String] = [
		"Sprite2D", "TrousersSprite", "ClothingSprite", "ChestSprite",
		"GlovesSprite", "BackpackSprite", "WaistSprite", "BootsSprite",
		"HelmetSprite", "FaceSprite", "CloakSprite"
	]
	for sname in all_sprites:
		var s: Node = player.get_node_or_null(sname)
		if s != null:
			s.self_modulate = Color(1.0, 1.0, 1.0, alpha)

func handle_sync_sneak_alpha(alpha: float) -> void:
	player.sneak_alpha = alpha
	apply_sneak_alpha(alpha)

func process_sneak_alpha(delta: float) -> void:
	if player.multiplayer.has_multiplayer_peer():
		return
	var tile_light: float = Lighting.get_tile_world_light(player.tile_pos)
	var sneak_level: int = player.skills.get("sneaking", 0)
	var dark_threshold: float = 0.10 + sneak_level * 0.08
	var fade_speed: float = 0.3 + sneak_level * 0.15
	var reveal_radius: int = max(1, 5 - sneak_level * 2)
	var proximity_revealed: bool = false
	if reveal_radius > 0:
		for p in player.get_tree().get_nodes_in_group("player"):
			if p == player or p.get("dead") == true or p.get("is_ghost") == true: continue
			if p.get("z_level") != player.z_level: continue
			var dist: int = (p.get("tile_pos") - player.tile_pos).abs().x + (p.get("tile_pos") - player.tile_pos).abs().y
			if dist <= reveal_radius:
				proximity_revealed = true
				break

	if tile_light >= dark_threshold or proximity_revealed:
		if player.sneak_alpha < 1.0:
			player.sneak_alpha = 1.0
			apply_sneak_alpha(1.0)
			player._last_synced_sneak_alpha = 1.0
		if player._sneak_was_hidden:
			player._sneak_was_hidden = false
			if not player.multiplayer.has_multiplayer_peer():
				broadcast_sneak_revealed()
	else:
		var new_alpha := move_toward(player.sneak_alpha, 0.0, fade_speed * delta)
		if abs(new_alpha - player.sneak_alpha) > 0.001:
			player.sneak_alpha = new_alpha
			apply_sneak_alpha(player.sneak_alpha)
			if abs(player.sneak_alpha - player._last_synced_sneak_alpha) >= 0.04:
				player._last_synced_sneak_alpha = player.sneak_alpha
		if player.sneak_alpha <= 0.5:
			player._sneak_was_hidden = true

func broadcast_sneak_revealed() -> void:
	if not player.multiplayer.has_multiplayer_peer():
		Sidebar.add_message("[color=#ff4444][font_size=28]" + player.character_name + " is revealed!![/font_size][/color]")
	elif player.multiplayer.is_server():
		World.rpc_broadcast_sneak_reveal.rpc(player.character_name, player.tile_pos, player.z_level)
	else:
		World.rpc_request_sneak_reveal.rpc_id(1, player.character_name, player.tile_pos, player.z_level)
