# res://scripts/world/world_physics.gd
# Gravity simulation: calculates landing z-level and applies fall damage.
extends RefCounted

var world: Node

func _init(p_world: Node) -> void:
	world = p_world

func calculate_gravity_z(tile_pos: Vector2i, current_z: int) -> int:
	var check_z = current_z
	while check_z > 1:
		var tm = world.get_tilemap(check_z)
		if tm != null and tm.get_cell_source_id(tile_pos) != -1:
			return check_z
		if world.is_solid(tile_pos, check_z - 1):
			return check_z
		check_z -= 1
	return 1

func apply_gravity_to_player(player: Node2D) -> void:
	if player == null or player.dead or world.utils.is_ghost(player): return
	var land_z = calculate_gravity_z(player.tile_pos, player.z_level)
	if land_z >= player.z_level: return

	var drop = player.z_level - land_z
	player.rpc_sync_z_level(land_z)
	player.rpc_sync_z_level.rpc(land_z)

	var agility = 10
	if "stats" in player and player.stats.has("agility"):
		agility = player.stats.get("agility", 10)

	var avoid_chance = clamp(50.0 + (agility - 10) * 5.0 - ((drop - 1) * 20.0), 0.0, 100.0)
	var avoided = randf() * 100.0 < avoid_chance

	if avoided:
		var peer_id = player.get_multiplayer_authority()
		world.rpc_send_direct_message.rpc_id(peer_id, "[color=#aaffaa]You land safely.[/color]")
	else:
		var dmg = randi_range(CombatDefs.FALL_DAMAGE_MIN, CombatDefs.FALL_DAMAGE_MAX) * drop
		var target_limb = "chest"
		if drop >= 2:
			target_limb = Defs.LIMBS.pick_random()
		player.receive_damage.rpc(dmg, target_limb)
		world.rpc_broadcast_damage_log.rpc("Gravity", player.character_name, dmg, player.tile_pos, land_z, false, false, target_limb, "")
		if not player.get("is_lying_down"):
			player.set("is_lying_down", true)
			if player.has_method("_update_sprite"):        player.call("_update_sprite")
			if player.has_method("_update_water_submerge"): player.call("_update_water_submerge")
			player.rpc("_rpc_sync_lying_down", true)
