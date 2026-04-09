# res://scripts/player/playeraction.gd
extends RefCounted

var player: Node2D

func _init(p_player: Node2D) -> void:
	player = p_player

# ===========================================================================
# Action Execution
# ===========================================================================

func apply_action_cooldown(item: Node, is_attack: bool = false) -> void:
	var delay = CombatDefs.DEFAULT_ACTION_DELAY
	if item != null and item.has_method("get_use_delay"):
		delay = item.get_use_delay()

	if is_attack and delay < CombatDefs.MIN_ATTACK_DELAY:
		delay = CombatDefs.MIN_ATTACK_DELAY

	if player.exhausted:
		delay *= CombatDefs.EXHAUSTED_DELAY_MULT

	player.action_cooldown = delay

func face_toward(world_pos: Vector2) -> void:
	var delta: Vector2 = world_pos - player.pixel_pos
	if abs(delta.x) >= abs(delta.y):
		player.facing = 2 if delta.x >= 0 else 3
	else:
		player.facing = 0 if delta.y >= 0 else 1
	player._update_sprite()

func on_object_picked_up(object_node: Node) -> void:
	if not player._is_local_authority():
		return

	var active_item = player.hands[player.active_hand]
	var target_object_id := World.get_entity_id(object_node)
	if active_item != null:
		# Combine ground coins
		if active_item.get("is_coin_stack") and object_node.get("is_coin_stack"):
			if active_item.get("item_type") == object_node.get("item_type"):
				if player.multiplayer.is_server():
					World.rpc_request_combine_ground_coin(target_object_id, player.active_hand)
				else:
					World.rpc_request_combine_ground_coin.rpc_id(1, target_object_id, player.active_hand)
		return

	if player.multiplayer.is_server():
		World.rpc_request_pickup(target_object_id, player.active_hand)
	else:
		World.rpc_request_pickup.rpc_id(1, target_object_id, player.active_hand)

func drop_item_from_hand(hand_idx: int) -> void:
	if player.hands[hand_idx] == null:
		return
	var obj = player.hands[hand_idx]
	var obj_id := World.get_entity_id(obj)
	if player.multiplayer.is_server():
		World.rpc_drop_item_at.rpc(player.get_multiplayer_authority(), obj_id, player.tile_pos, player.DROP_SPREAD, hand_idx)
	else:
		World.rpc_request_drop.rpc_id(1, obj_id, player.tile_pos, player.DROP_SPREAD, hand_idx)

func drop_held_object() -> void:
	drop_item_from_hand(player.active_hand)

func throw_held_object(mouse_world_pos: Vector2) -> void:
	var mouse_tile := Vector2i(int(mouse_world_pos.x / World.TILE_SIZE), int(mouse_world_pos.y / World.TILE_SIZE))
	var dist_vec: Vector2i = (mouse_tile - player.tile_pos).abs()
	var dist: float = float(max(dist_vec.x, dist_vec.y))
	var throw_range: int = int(clamp(dist, 1.0, float(player.THROW_TILES)))

	var dir: Vector2 = (mouse_world_pos - player.pixel_pos).normalized()
	if dir == Vector2.ZERO:
		return

	apply_action_cooldown(player.hands[player.active_hand], true)

	var obj: Node = player.hands[player.active_hand]
	var obj_id := World.get_entity_id(obj)

	player.throwing_mode = false
	if player._throw_label != null:
		player._throw_label.visible = false

	if player.multiplayer.is_server():
		World.rpc_request_throw(obj_id, player.active_hand, dir, throw_range)
	else:
		World.rpc_request_throw.rpc_id(1, obj_id, player.active_hand, dir, throw_range)

func interact_held_object() -> void:
	if player.hands[player.active_hand] != null:
		var item = player.hands[player.active_hand]
		if item.has_method("interact_in_hand"):
			if player.multiplayer.is_server():
				World.rpc_request_interact_hand_item(player.active_hand)
			else:
				World.rpc_request_interact_hand_item.rpc_id(1, player.active_hand)

func use_held_object(mouse_world_pos: Vector2) -> void:
	var tm = World.get_tilemap(player.z_level)
	if tm == null:
		return

	var target_tile := Vector2i(
		int(mouse_world_pos.x / World.TILE_SIZE),
		int(mouse_world_pos.y / World.TILE_SIZE)
	)

	var diff: Vector2i = (target_tile - player.tile_pos).abs()
	if diff.x > 1 or diff.y > 1:
		return

	var held_item = player.hands[player.active_hand]
	var is_sword := Defs.is_tool_sword(held_item)
	var is_clothing := false
	if held_item != null:
		is_clothing = held_item.get("slot") != null and held_item.get("slot") != ""

	var can_attack := false
	if held_item == null:
		can_attack = (player.intent == Defs.INTENT_HARM)
	elif is_sword:
		can_attack = true
	else:
		can_attack = (player.intent == Defs.INTENT_HARM and not is_clothing)

	var source_id = tm.get_cell_source_id(target_tile)
	var atlas_coords = tm.get_cell_atlas_coords(target_tile)
	var wall_material_id := TileDefs.get_material_id(source_id, atlas_coords) if source_id == 1 else ""

	var door_target = _find_object_at_tile(Defs.GROUP_DOOR, target_tile)
	var gate_target = _find_gate_at_tile(target_tile)
	var choppable_target = _find_object_at_tile(Defs.GROUP_CHOPPABLE, target_tile)
	var breakable_target = _find_object_at_tile(Defs.GROUP_BREAKABLE, target_tile)
	var minable_target = _find_object_at_tile(Defs.GROUP_MINABLE, target_tile)

	var target_found = false
	var is_exerting = false
	var is_attack_action = false

	if can_attack:
		var entities_at := World.get_entities_at_tile(target_tile, player.z_level, player.multiplayer.get_unique_id())
		if not entities_at.is_empty():
			target_found = true
			is_exerting = true
			is_attack_action = true

	if not target_found and door_target != null:
		if held_item == null:
			target_found = true
		elif door_target.has_method("can_accept_item_interaction") and door_target.can_accept_item_interaction(held_item):
			target_found = true
		elif MaterialRegistry.can_tool_affect(door_target, held_item):
			target_found = true
			is_exerting = true

	if not target_found and gate_target != null:
		if held_item == null:
			target_found = true
		elif MaterialRegistry.can_tool_affect(gate_target, held_item):
			target_found = true
			is_exerting = true

	if not target_found and choppable_target != null and MaterialRegistry.can_tool_affect(choppable_target, held_item):
		target_found = true
		is_exerting = true

	if not target_found and breakable_target != null and MaterialRegistry.can_tool_affect(breakable_target, held_item):
		target_found = true
		is_exerting = true

	if not target_found and minable_target != null and MaterialRegistry.can_tool_affect(minable_target, held_item):
		target_found = true
		is_exerting = true

	if not target_found and wall_material_id != "" and MaterialRegistry.can_tool_affect(wall_material_id, held_item):
		target_found = true
		is_exerting = true

	if not target_found:
		return

	if is_exerting:
		if player.exhausted:
			Sidebar.add_message("[color=#ffaaaa]You are too exhausted to act![/color]")
			return
		if player.stamina < 5.0:
			player.exhausted = true
			Sidebar.add_message("[color=#ffaaaa]You overexerted yourself![/color]")
		player.backend.spend_stamina(5.0)

	apply_action_cooldown(held_item, is_attack_action)

	if is_attack_action:
		var limb = "chest"
		if player._hud != null:
			limb = player._hud.targeted_limb

		if player.multiplayer.is_server():
			World.rpc_deal_damage_at_tile(target_tile, limb)
		else:
			World.rpc_deal_damage_at_tile.rpc_id(1, target_tile, limb)
		return

	if door_target != null:
		if player.multiplayer.is_server():
			World.rpc_request_hit_door(door_target.get_path())
		else:
			World.rpc_request_hit_door.rpc_id(1, door_target.get_path())
		return

	if gate_target != null:
		if player.multiplayer.is_server():
			World.rpc_request_hit_gate(gate_target.get_path())
		else:
			World.rpc_request_hit_gate.rpc_id(1, gate_target.get_path())
		return

	if choppable_target != null and MaterialRegistry.can_tool_affect(choppable_target, held_item):
		if player.multiplayer.is_server():
			World.rpc_request_hit_tree(choppable_target.get_path())
		else:
			World.rpc_request_hit_tree.rpc_id(1, choppable_target.get_path())
		return

	if breakable_target != null and MaterialRegistry.can_tool_affect(breakable_target, held_item):
		if player.multiplayer.is_server():
			World.rpc_request_hit_breakable(breakable_target.get_path())
		else:
			World.rpc_request_hit_breakable.rpc_id(1, breakable_target.get_path())
		return

	if minable_target != null and MaterialRegistry.can_tool_affect(minable_target, held_item):
		if player.multiplayer.is_server():
			World.rpc_request_hit_rock(minable_target.get_path())
		else:
			World.rpc_request_hit_rock.rpc_id(1, minable_target.get_path())
		return

	if wall_material_id != "" and MaterialRegistry.can_tool_affect(wall_material_id, held_item):
		if player.multiplayer.is_server():
			World.rpc_damage_wall(target_tile)
		else:
			World.rpc_damage_wall.rpc_id(1, target_tile)

func _find_object_at_tile(group_name: String, target_tile: Vector2i) -> Node:
	for obj in player.get_tree().get_nodes_in_group(group_name):
		if obj.get("z_level") != null and obj.z_level != player.z_level:
			continue
		var obj_tile := Vector2i(int(obj.global_position.x / World.TILE_SIZE), int(obj.global_position.y / World.TILE_SIZE))
		if obj_tile == target_tile:
			return obj
	return null

func _find_gate_at_tile(target_tile: Vector2i) -> Node:
	for obj in player.get_tree().get_nodes_in_group(Defs.GROUP_GATE):
		if obj.get("z_level") != null and obj.z_level != player.z_level:
			continue
		var obj_tile_x = int(obj.global_position.x / World.TILE_SIZE)
		var obj_tile_y = int(obj.global_position.y / World.TILE_SIZE)
		if target_tile == Vector2i(obj_tile_x, obj_tile_y):
			return obj
		if target_tile == Vector2i(obj_tile_x - 1, obj_tile_y):
			return obj
		if target_tile == Vector2i(obj_tile_x + 1, obj_tile_y):
			return obj
	return null
