# res://scripts/player/playercombat.gd
extends RefCounted

var player: Node2D

func _init(p_player: Node2D) -> void:
	player = p_player

# ===========================================================================
# Combat Stats and Damage Logic
# ===========================================================================

func get_strength_damage_modifier() -> float:
	var str_val = player.stats.get("strength", 10)
	return (str_val - 10) * CombatDefs.STRENGTH_DAMAGE_SCALE

func get_weapon_damage(item: Node) -> int:
	var base_damage: int = CombatDefs.UNARMED_BASE_DAMAGE
	if item != null:
		var force = item.get("force")
		if force != null:
			base_damage = force

	var modifier = get_strength_damage_modifier()
	var final_damage = int(round(base_damage * (1.0 + modifier)))
	if final_damage < 0:
		final_damage = 0
	return final_damage

# ===========================================================================
# Combat Toggling
# ===========================================================================

func toggle_combat_mode() -> void:
	var new_mode = !player.combat_mode
	set_combat_mode_local(new_mode)
	
	if player.multiplayer.has_multiplayer_peer():
		if player.multiplayer.is_server():
			player.rpc("_sync_combat_mode", new_mode)
		else:
			player.rpc_id(1, "_sync_combat_mode", new_mode)

func set_combat_mode_local(mode: bool) -> void:
	player.combat_mode = mode
	player.intent = "harm" if player.combat_mode else "help"
	if player._combat_indicator != null:
		player._combat_indicator.visible = player.combat_mode
	if player._hud != null and player._is_local_authority():
		player._hud.update_combat_display(player.combat_mode)

# ===========================================================================
# Combat Stance Toggling (dodge <-> parry)
# ===========================================================================

func toggle_combat_stance() -> void:
	var new_stance: String = "parry" if player.combat_stance == "dodge" else "dodge"
	set_combat_stance_local(new_stance)

	if player.multiplayer.has_multiplayer_peer():
		if player.multiplayer.is_server():
			player.rpc("_sync_combat_stance", new_stance)
		else:
			player.rpc_id(1, "_sync_combat_stance", new_stance)

func set_combat_stance_local(stance: String) -> void:
	player.combat_stance = stance
	if player._hud != null and player._is_local_authority():
		player._hud.update_stance_display(stance)

# ===========================================================================
# Taking Damage & Death
# ===========================================================================

func receive_damage(amount: int) -> void:
	if player.dead:
		return

	var spray := Node2D.new()
	spray.set_script(player.BloodSpray)
	spray.position = player.pixel_pos
	player.get_parent().add_child(spray)

	player.health -= amount
	if player.health < 0:
		player.health = 0
	if player.health <= 0:
		die()

func die() -> void:
	if player.multiplayer.is_server():
		for i in range(2):
			if player.hands[i] != null:
				World.rpc_drop_item_at.rpc(player.get_path(), player.hands[i].get_path(), player.tile_pos, player.DROP_SPREAD, i)

	if player.misc:
		player.misc.close_menus()
	if player.crafting:
		player.crafting.close_menus()

	player.dead = true
	
	# Show death message to local player if nearby
	var local_player = World.get_local_player()
	if local_player != null and local_player.z_level == player.z_level:
		var diff = local_player.tile_pos - player.tile_pos
		if diff.x * diff.x + diff.y * diff.y <= 144:
			if player.get_tree().root.has_node("Sidebar"):
				player.get_tree().root.get_node("Sidebar").add_message("[color=purple]" + player.character_name + " Seizes up and goes limp.[/color]")

func die_visuals() -> void:
	var sprite: Sprite2D = player.get_node_or_null("Sprite2D")
	if sprite != null:
		sprite.rotation_degrees = 90.0

	for slot in["HelmetSprite", "FaceSprite", "ChestSprite", "TrousersSprite", "BootsSprite", "ClothingSprite", "WaistSprite", "GlovesSprite"]:
		var s: Sprite2D = player.get_node_or_null(slot)
		if s != null:
			s.rotation_degrees = 90.0
			if slot == "HelmetSprite" or slot == "FaceSprite":
				# Offset (0, -10) rotated 90 degrees becomes (-(-10), 0) = (10, 0)
				s.position = Vector2(10, 0)

	if player._dead_container != null:
		player._dead_container.visible = true