# res://scripts/player/playersneak.gd
# Handles sneak requests and replicated alpha updates.
extends RefCounted

var player: Node2D

func _init(p_player: Node2D) -> void:
	player = p_player

func toggle_sneak_mode() -> void:
	if not player._is_local_authority(): return
	var new_val: bool = not player.is_sneaking
	player._rpc_sync_sneak_mode.rpc_id(1, new_val)

func set_sneak_mode_local(val: bool) -> void:
	player.is_sneaking = val
	if not player.is_sneaking:
		player.sneak_alpha = 1.0
		player._sneak_was_hidden = false
		apply_sneak_alpha(1.0)
	player._update_water_submerge()
	if player._is_local_authority() and Lighting.has_method("report_local_world_light_now"):
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
