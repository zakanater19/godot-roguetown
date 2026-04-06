# res://scripts/world/world_combat.gd
extends RefCounted

var world: Node

func _init(p_world: Node) -> void:
	world = p_world

func calculate_combat_roll(attacker: Node, defender: Node, base_amount: int, is_sword_attack: bool) -> Dictionary:
	var result = {"damage": base_amount, "blocked": false, "block_type": ""}
	if not defender.is_in_group("player"): return result
	var d_has_sword = false
	if "hands" in defender and defender.get("hands") != null:
		for h in defender.get("hands"):
			if h != null:
				var i_type = h.get("item_type")
				if i_type != null:
					var _idata = ItemRegistry.get_by_type(i_type)
					if _idata != null and _idata.can_parry:
						d_has_sword = true
						break
	var a_skill = 0
	if attacker != null and attacker.is_in_group("player") and is_sword_attack:
		if "skills" in attacker: a_skill = attacker.get("skills").get("sword_fighting", 0)
	var d_stance: String = defender.get("combat_stance") if defender.get("combat_stance") != null else "dodge"
	var avoidance_chance = 0.0
	var valid_dodge_tiles =[]
	var can_defend = true
	if "stamina" in defender and defender.get("stamina") < CombatDefs.STAMINA_MIN_TO_DEFEND: can_defend = false
	if "exhausted" in defender and defender.get("exhausted"): can_defend = false
	if "grabbed_by" in defender and defender.get("grabbed_by") != null and is_instance_valid(defender.get("grabbed_by")): can_defend = false
	
	# Corpses (dead or unpossessed) cannot defend
	if defender.get("dead") == true or defender.get("is_possessed") == false: can_defend = false
	
	if can_defend:
		if d_stance == "parry" and d_has_sword:
			var d_skill = 0
			if "skills" in defender: d_skill = defender.get("skills").get("sword_fighting", 0)
			avoidance_chance = clamp(float(d_skill - a_skill) * CombatDefs.PARRY_AVOIDANCE_SCALE, 0.0, CombatDefs.PARRY_AVOIDANCE_MAX)
			result.block_type = "parried"
		else:
			for dir in[Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var check_tile = defender.get("tile_pos") + dir
				if check_tile.x < 0 or check_tile.x >= world.GRID_WIDTH or check_tile.y < 0 or check_tile.y >= world.GRID_HEIGHT: continue
				if world.tiles.is_solid(check_tile, defender.get("z_level")): continue
				var occupants = world.utils.get_entities_at_tile(check_tile, defender.get("z_level"))
				var blocked = false
				for ent in occupants:
					if ent.is_in_group("player") and not ent.get("dead"):
						if not (ent.get("is_lying_down") == true or ent.get("sleep_state") != 0):
							blocked = true
							break
				if not blocked: valid_dodge_tiles.append(check_tile)
			if valid_dodge_tiles.is_empty():
				avoidance_chance = 0.0
				result.block_type = ""
			else:
				var d_agility = 10
				if "stats" in defender: d_agility = defender.get("stats").get("agility", 10)
				avoidance_chance = clamp((d_agility - 10) * CombatDefs.DODGE_AGILITY_SCALE + CombatDefs.DODGE_BASE_CHANCE, 0.0, CombatDefs.DODGE_AVOIDANCE_MAX)
				result.block_type = "dodged"
				
	if attacker != null and (attacker.is_in_group("player") or attacker.is_in_group("npc")):
		var diff = attacker.get("tile_pos") - defender.get("tile_pos")
		var attack_dir = -1
		if abs(diff.x) > abs(diff.y): attack_dir = 2 if diff.x > 0 else 3
		elif abs(diff.x) < abs(diff.y) or diff.y != 0: attack_dir = 0 if diff.y > 0 else 1
		if attack_dir != -1:
			var d_facing = defender.get("facing") if defender.get("facing") != null else 0
			if attack_dir == d_facing: avoidance_chance *= 1.0
			else:
				var is_back = false
				if d_facing == 0 and attack_dir == 1: is_back = true
				elif d_facing == 1 and attack_dir == 0: is_back = true
				elif d_facing == 2 and attack_dir == 3: is_back = true
				elif d_facing == 3 and attack_dir == 2: is_back = true
				if is_back:
					if not defender.get("combat_mode"): avoidance_chance = 0.0
					else: avoidance_chance *= CombatDefs.BACK_ATTACK_AVOIDANCE_MULT
				else: avoidance_chance *= CombatDefs.SIDE_ATTACK_AVOIDANCE_MULT
				
	if randf() * 100.0 < avoidance_chance:
		result.damage = 0
		result.blocked = true
		if result.block_type == "dodged" and result.has("dodge_tile") and not valid_dodge_tiles.is_empty():
			result.dodge_tile = valid_dodge_tiles.pick_random()
	else: result.block_type = ""
	return result

func deal_damage_at_tile(tile: Vector2i, z_level: int, amount: int, attacker_id: int = 0, is_sword_attack: bool = false) -> Dictionary:
	var results = {}
	var attacker = world.utils.find_player_by_peer(attacker_id)
	var entities = world.utils.get_entities_at_tile(tile, z_level, attacker_id)
	for entity in entities:
		var roll = calculate_combat_roll(attacker, entity, amount, is_sword_attack)
		results[entity] = roll
		if roll.damage > 0:
			if entity.is_in_group("player"):
				var target_limb = "chest"
				if attacker != null and "targeted_limb" in attacker:
					target_limb = attacker.targeted_limb
				entity.receive_damage.rpc(roll.damage, target_limb)
			elif entity.has_method("receive_damage"): entity.receive_damage(roll.damage)
		elif roll.blocked:
			if entity.is_in_group("player") and entity.get("is_possessed") == true:
				if entity.has_method("rpc_consume_stamina"):
					var tgt_peer: int = entity.get_multiplayer_authority()
					if tgt_peer == 1 or tgt_peer in world.multiplayer.get_peers(): entity.rpc_consume_stamina.rpc_id(tgt_peer, CombatDefs.STAMINA_BLOCK_COST)
				if roll.block_type == "dodged" and roll.has("dodge_tile"):
					entity.set("tile_pos", roll.dodge_tile)
					world.rpc_confirm_move.rpc(entity.get_multiplayer_authority(), roll.dodge_tile, false)
	return results

func release_grab_for_peer(grabber_peer_id: int, silent: bool = false) -> void:
	if not world.grab_map.has(grabber_peer_id): return
	var entry = world.grab_map[grabber_peer_id]
	world.grab_map.erase(grabber_peer_id)
	var grabber_node: Node2D = world.utils.find_player_by_peer(grabber_peer_id) as Node2D
	var grabber_name = grabber_node.character_name if grabber_node else ""
	var target_node: Node = entry.get("target")
	var target_name = ""
	if target_node and is_instance_valid(target_node):
		if entry.get("is_player"): target_name = target_node.get("character_name") if "character_name" in target_node else ""
		else: target_name = target_node.get("item_type") if target_node.get("item_type") else target_node.name.get_slice("@", 0)
	world.rpc_confirm_grab_released.rpc(grabber_peer_id, entry.get("is_player"), entry.get("target_peer_id"), grabber_name, target_name, silent)

func drag_grabbed_entity(grabber_peer_id: int, old_tile: Vector2i) -> void:
	if not world.grab_map.has(grabber_peer_id): return
	var entry = world.grab_map[grabber_peer_id]
	var target: Node = entry.get("target")
	if target == null or not is_instance_valid(target):
		var was_player = entry.get("is_player")
		var was_peer = entry.get("target_peer_id")
		world.grab_map.erase(grabber_peer_id)
		world.rpc_confirm_grab_released.rpc(grabber_peer_id, was_player, was_peer, "", "", true)
		return
	if entry.get("is_player"):
		target.set("tile_pos", old_tile)
		var tgt_peer = entry.get("target_peer_id")
		if tgt_peer != -1:
			world.rpc_confirm_move.rpc(tgt_peer, old_tile, false)
		else:
			world.rpc_confirm_drag_corpse.rpc(target.get_path(), old_tile)
	else:
		world.rpc_confirm_drag_object.rpc(target.get_path(), world.utils.tile_to_pixel(old_tile))

func server_try_resist(peer_id: int) -> void:
	var now_ms := Time.get_ticks_msec()
	if world.resist_cooldown_map.has(peer_id) and now_ms < world.resist_cooldown_map[peer_id]: return
	world.resist_cooldown_map[peer_id] = now_ms + CombatDefs.RESIST_COOLDOWN_MS
	var grabbed: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	if grabbed == null or grabbed.get("dead") or grabbed.get("is_possessed") == false: return
	
	var grabber_peer_id: int = -1
	var grabber: Node2D = null
	for gp_id in world.grab_map:
		var entry = world.grab_map[gp_id]
		if entry.get("is_player") and entry.get("target_peer_id") == peer_id:
			grabber_peer_id = gp_id
			grabber = world.utils.find_player_by_peer(gp_id) as Node2D
			break
	if grabber == null or grabber_peer_id == -1 or grabbed.get("exhausted"): return
	var total_str = max(float(grabbed.get("stats").get("strength", 10)) + float(grabber.get("stats").get("strength", 10)), 1.0)
	var resist_cost = CombatDefs.STAMINA_RESIST_BASE * (float(grabber.get("stats").get("strength", 10)) / total_str)
	var grabber_cost = CombatDefs.STAMINA_RESIST_BASE * (float(grabbed.get("stats").get("strength", 10)) / total_str)
	var break_chance = (float(grabbed.get("stats").get("strength", 10)) / total_str) * 100.0
	if grabbed.get("is_lying_down"): break_chance *= CombatDefs.LYING_DOWN_RESIST_MULT
	
	var tgt_peer: int = grabbed.get_multiplayer_authority()
	if tgt_peer == 1 or tgt_peer in world.multiplayer.get_peers(): grabbed.rpc_consume_stamina.rpc_id(tgt_peer, resist_cost)
	var g_tgt_peer: int = grabber.get_multiplayer_authority()
	if g_tgt_peer == 1 or g_tgt_peer in world.multiplayer.get_peers(): grabber.rpc_consume_stamina.rpc_id(g_tgt_peer, grabber_cost)
	
	if randf() * 100.0 < break_chance:
		release_grab_for_peer(grabber_peer_id, true)
		world.rpc_confirm_resist_result.rpc(grabber_peer_id, peer_id, true)
	else: world.rpc_confirm_resist_result.rpc(grabber_peer_id, peer_id, false)

func handle_rpc_request_shove(sender_id: int, target_tile: Vector2i) -> void:
	if not world.multiplayer.is_server(): return
	var attacker: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if attacker == null or not attacker.get("combat_mode") or attacker.get("dead"): return
	if attacker.get("body") != null and attacker.body.is_arm_broken(attacker.get("active_hand")): return
	if (target_tile - attacker.get("tile_pos")).abs().x > 1 or (target_tile - attacker.get("tile_pos")).abs().y > 1: return
	if not world.utils.server_check_action_cooldown(attacker, true): return
	var occupants = world.utils.get_entities_at_tile(target_tile, attacker.get("z_level"))
	var target_player: Node2D = null
	for ent in occupants:
		if ent.is_in_group("player") and not ent.get("dead"):
			target_player = ent as Node2D
			break
	if target_player != null:
		var shove_dest = target_player.get("tile_pos") + (target_tile - attacker.get("tile_pos"))
		var dest_blocked = false
		if shove_dest.x < 0 or shove_dest.x >= world.GRID_WIDTH or shove_dest.y < 0 or shove_dest.y >= world.GRID_HEIGHT: dest_blocked = true
		elif world.tiles.is_solid(shove_dest, target_player.get("z_level")): dest_blocked = true
		else:
			for ent in world.utils.get_entities_at_tile(shove_dest, target_player.get("z_level")):
				if ent.is_in_group("player") and not ent.get("dead"):
					if not (ent.get("is_lying_down") == true or ent.get("sleep_state") != 0):
						dest_blocked = true; break
		if not dest_blocked:
			target_player.set("tile_pos", shove_dest)
			if target_player.get("is_possessed") == true:
				world.rpc_confirm_move.rpc(target_player.get_multiplayer_authority(), shove_dest, false)
			world.rpc_broadcast_damage_log.rpc(attacker.get("character_name"), target_player.get("character_name"), 0, attacker.get("tile_pos"), attacker.get("z_level"), false, true, "", "")
			world.apply_gravity_to_player(target_player)

func handle_rpc_deal_damage_at_tile(sender_id: int, tile: Vector2i, targeted_limb: String) -> void:
	if not world.multiplayer.is_server(): return
	var attacker: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if attacker == null or attacker.get("dead"): return
	if attacker.get("body") != null and attacker.body.is_arm_broken(attacker.get("active_hand")): return
	if (tile - attacker.get("tile_pos")).abs().x > 1 or (tile - attacker.get("tile_pos")).abs().y > 1: return
	if not world.utils.server_check_action_cooldown(attacker, true): return
	var held_item = attacker.hands[attacker.get("active_hand")]
	var amount: int = attacker._get_weapon_damage(held_item)
	var _held_itype = held_item.get("item_type") if held_item != null else null
	var _held_idata = ItemRegistry.get_by_type(_held_itype) if _held_itype != null else null
	var is_sword = _held_idata != null and _held_idata.can_parry
	var entities = world.utils.get_entities_at_tile(tile, attacker.get("z_level"), sender_id)
	for entity in entities:
		var roll = calculate_combat_roll(attacker, entity, amount, is_sword)
		var t_name = ""
		if entity.is_in_group("player"):
			t_name = (entity as Node2D).get("character_name")
			if roll.damage > 0: entity.receive_damage.rpc(roll.damage, targeted_limb)
			elif roll.blocked:
				if entity.has_method("rpc_consume_stamina"): entity.rpc_consume_stamina.rpc_id(entity.get_multiplayer_authority(), CombatDefs.STAMINA_BLOCK_COST)
				if roll.block_type == "dodged" and roll.has("dodge_tile"):
					entity.set("tile_pos", roll.dodge_tile)
					if entity.get("is_possessed") == true:
						world.rpc_confirm_move.rpc(entity.get_multiplayer_authority(), roll.dodge_tile, false)
		elif entity.has_method("receive_damage"):
			t_name = entity.name.get_slice("@", 0)
			if roll.damage > 0: entity.receive_damage(roll.damage)
		else: continue
		var w_type: String = held_item.get("tool_type") if held_item != null else ""
		world.rpc_broadcast_damage_log.rpc(attacker.get("character_name"), t_name, roll.damage, attacker.get("tile_pos"), attacker.get("z_level"), roll.blocked, false, targeted_limb, roll.get("block_type", ""), w_type)

func handle_rpc_request_grab(sender_id: int, target_path: NodePath, limb: String) -> void:
	if not world.multiplayer.is_server(): return
	var grabber: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if grabber == null or grabber.get("dead") or grabber.hands[grabber.get("active_hand")] != null: return
	if grabber.get("body") != null and grabber.body.is_arm_broken(grabber.get("active_hand")): return
	var now_ms := Time.get_ticks_msec()
	if world.grab_cooldown_map.has(sender_id) and now_ms < world.grab_cooldown_map[sender_id]: return
	world.grab_cooldown_map[sender_id] = now_ms + CombatDefs.GRAB_COOLDOWN_MS
	var target := world.get_node_or_null(target_path)
	if target == null or not is_instance_valid(target) or target.get("z_level") != grabber.get("z_level"): return
	if world.grab_map.has(sender_id): release_grab_for_peer(sender_id)
	if not world.utils.is_within_interaction_range(grabber, target.global_position): return
	var is_player = target.is_in_group("player")
	var target_peer = target.get_multiplayer_authority() if (is_player and target.get("is_possessed") == true) else -1
	var safe_limb = limb if limb in Defs.LIMBS else "chest"
	world.grab_map[sender_id] = {"target": target, "is_player": is_player, "target_peer_id": target_peer, "limb": safe_limb}
	var t_name = (target as Node2D).get("character_name") if is_player else (target.get("item_type") if target.get("item_type") else target.name.get_slice("@", 0))
	world.rpc_confirm_grab_start.rpc(sender_id, is_player, target_peer, target_path, grabber.get("character_name"), t_name, safe_limb, grabber.get("active_hand"))

func handle_rpc_request_release_grab(sender_id: int) -> void:
	if world.multiplayer.is_server(): release_grab_for_peer(sender_id)

func handle_rpc_request_resist(sender_id: int) -> void:
	if not world.multiplayer.is_server(): return
	var grabbed: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if grabbed == null or grabbed.get("dead") or grabbed.get("is_possessed") == false: return
	var is_grabbed = false
	for gp_id in world.grab_map:
		if world.grab_map[gp_id].get("is_player") and world.grab_map[gp_id].get("target_peer_id") == sender_id:
			is_grabbed = true; break
	if not is_grabbed: world.rpc_confirm_resist_result.rpc(-1, sender_id, false)
	else: server_try_resist(sender_id)

func handle_rpc_confirm_grab_start(grabber_peer_id: int, is_player: bool, target_peer_id: int, target_path: NodePath, grabber_name: String, target_name: String, limb: String, grab_hand: int) -> void:
	var grabber: Node2D = world.utils.find_player_by_peer(grabber_peer_id) as Node2D
	var target = world.get_node_or_null(target_path)
	if grabber and target:
		if grabber.has_method("_is_local_authority") and grabber._is_local_authority():
			grabber.set("grabbed_target", target)
			grabber.set("grab_hand_idx", grab_hand)
			if grabber.has_method("_update_grab_ui"): grabber._update_grab_ui()
		if is_player:
			var g_player: Node2D = target as Node2D
			if g_player and not g_player.get("dead") and g_player.has_method("_is_local_authority") and g_player._is_local_authority():
				g_player.set("grabbed_by", grabber)
				if g_player.has_method("_update_grab_ui"): g_player._update_grab_ui()
		if is_player and target_name != "" and world.has_node("/root/Sidebar"):
			var lp: Node2D = world.utils.get_local_player() as Node2D
			if lp:
				var sidebar = world.get_node("/root/Sidebar")
				if lp.get_multiplayer_authority() == grabber_peer_id: sidebar.add_message("[color=#ffcc44]You grab " + target_name + " by the " + Defs.LIMB_DISPLAY.get(limb, limb) + "![/color]")
				elif lp.get_multiplayer_authority() == target_peer_id: sidebar.add_message("[color=#ff4444]" + grabber_name + " grabs you by the " + Defs.LIMB_DISPLAY.get(limb, limb) + "![/color]")

func handle_rpc_confirm_grab_released(grabber_peer_id: int, is_player: bool, target_peer_id: int, grabber_name: String, target_name: String, silent: bool) -> void:
	var grabber: Node2D = world.utils.find_player_by_peer(grabber_peer_id) as Node2D
	if grabber and grabber.has_method("_is_local_authority") and grabber._is_local_authority():
		grabber.set("grabbed_target", null)
		grabber.set("grab_hand_idx", -1)
		if grabber.has_method("_update_grab_ui"): grabber._update_grab_ui()
	if is_player and target_peer_id != -1:
		var g_player: Node2D = world.utils.find_player_by_peer(target_peer_id) as Node2D
		if g_player and g_player.has_method("_is_local_authority") and g_player._is_local_authority():
			g_player.set("grabbed_by", null)
			if g_player.has_method("_update_grab_ui"): g_player._update_grab_ui()
	if is_player and target_name != "" and not silent and world.has_node("/root/Sidebar"):
		var lp: Node2D = world.utils.get_local_player() as Node2D
		if lp:
			var sidebar = world.get_node("/root/Sidebar")
			if lp.get_multiplayer_authority() == grabber_peer_id: sidebar.add_message("[color=#aaaaaa]You release " + target_name + ".[/color]")
			elif lp.get_multiplayer_authority() == target_peer_id: sidebar.add_message("[color=#aaffaa]" + grabber_name + " releases you.[/color]")

func handle_rpc_confirm_resist_result(grabber_peer_id: int, grabbed_peer_id: int, broke_free: bool) -> void:
	var lp: Node2D = world.utils.get_local_player() as Node2D
	if not lp: return
	var l_peer = lp.get_multiplayer_authority()
	var sidebar = world.get_node("/root/Sidebar") if world.has_node("/root/Sidebar") else null
	if grabber_peer_id == -1:
		if l_peer == grabbed_peer_id and sidebar: sidebar.add_message("[color=#ffaaaa]You are not being grabbed.[/color]")
		return
	if broke_free:
		var grabber: Node2D = world.utils.find_player_by_peer(grabber_peer_id) as Node2D
		if grabber and grabber.has_method("_is_local_authority") and grabber._is_local_authority():
			grabber.set("grabbed_target", null)
			grabber.set("grab_hand_idx", -1)
			if grabber.has_method("_update_grab_ui"): grabber._update_grab_ui()
		var grabbed: Node2D = world.utils.find_player_by_peer(grabbed_peer_id) as Node2D
		if grabbed and grabbed.has_method("_is_local_authority") and grabbed._is_local_authority():
			grabbed.set("grabbed_by", null)
			if grabbed.has_method("_update_grab_ui"): grabbed._update_grab_ui()
		if sidebar:
			if l_peer == grabbed_peer_id: sidebar.add_message("[color=#aaffaa]You broke free from the grab![/color]")
			elif l_peer == grabber_peer_id: sidebar.add_message("[color=#ffaaaa]Your target broke free![/color]")
	elif l_peer == grabbed_peer_id and sidebar: sidebar.add_message("[color=#ffaaaa]You failed to resist the grab.[/color]")

func handle_rpc_confirm_drag_object(obj_path: NodePath, new_pixel: Vector2) -> void:
	var obj := world.get_node_or_null(obj_path)
	if obj: obj.global_position = new_pixel

func handle_rpc_confirm_drag_corpse(corpse_path: NodePath, new_pos: Vector2i) -> void:
	var corpse = world.get_node_or_null(corpse_path)
	if corpse != null:
		corpse.set("tile_pos", new_pos)
		if corpse.has_method("_start_move_lerp"):
			corpse.call("_start_move_lerp")