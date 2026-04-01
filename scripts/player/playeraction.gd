# res://scripts/player/playeraction.gd
extends RefCounted

var player: Node2D

func _init(p_player: Node2D) -> void:
	player = p_player

# ===========================================================================
# Action Execution
# ===========================================================================

func apply_action_cooldown(item: Node, is_attack: bool = false) -> void:
	var delay = 0.5
	if item != null and item.has_method("get_use_delay"):
		delay = item.get_use_delay()

	if is_attack and delay < 1.0:
		delay = 1.0

	if player.exhausted:
		delay *= 3.0

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
	if active_item != null:
		# Combine ground coins
		if active_item.get("is_coin_stack") and object_node.get("is_coin_stack"):
			if active_item.get("item_type") == object_node.get("item_type"):
				if player.multiplayer.is_server():
					World.rpc_request_combine_ground_coin(object_node.get_path(), player.active_hand)
				else:
					World.rpc_request_combine_ground_coin.rpc_id(1, object_node.get_path(), player.active_hand)
		return

	if player.multiplayer.is_server():
		World.rpc_request_pickup(object_node.get_path(), player.active_hand)
	else:
		World.rpc_request_pickup.rpc_id(1, object_node.get_path(), player.active_hand)

func drop_item_from_hand(hand_idx: int) -> void:
	if player.hands[hand_idx] == null:
		return
	var obj = player.hands[hand_idx]
	if player.multiplayer.is_server():
		World.rpc_drop_item_at.rpc(player.get_path(), obj.get_path(), player.tile_pos, player.DROP_SPREAD, hand_idx)
	else:
		World.rpc_request_drop.rpc_id(1, obj.get_path(), player.tile_pos, player.DROP_SPREAD, hand_idx)

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

	player.throwing_mode = false
	if player._throw_label != null:
		player._throw_label.visible = false

	if player.multiplayer.is_server():
		World.rpc_request_throw(obj.get_path(), player.active_hand, dir, throw_range)
	else:
		World.rpc_request_throw.rpc_id(1, obj.get_path(), player.active_hand, dir, throw_range)

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

	var held_item    = player.hands[player.active_hand]
	var is_pickaxe:  bool = false
	var is_sword:    bool = false
	var is_clothing: bool = false

	if held_item != null:
		var i_type = held_item.get("item_type")
		is_pickaxe = (i_type == "Pickaxe" or "Pickaxe" in held_item.name or "pickaxe" in held_item.name.to_lower())
		is_sword = (i_type == "Sword" or "Sword" in held_item.name or "sword" in held_item.name.to_lower()) or (i_type == "Dirk" or "Dirk" in held_item.name or "dirk" in held_item.name.to_lower())
		is_clothing = held_item.get("slot") != null

	var can_attack: bool = false
	var can_mine:   bool = false
	var can_chop:   bool = false
	var can_break:  bool = false

	if held_item == null:
		if player.intent == "harm":
			can_attack = true
	else:
		if is_sword:
			can_attack = true
			can_chop   = true
			can_break  = true
		elif is_pickaxe:
			can_mine = true
			if player.intent == "harm":
				can_attack = true
		else:
			if player.intent == "harm" and not is_clothing:
				can_attack = true

	var source_id = tm.get_cell_source_id(target_tile)
	var atlas_coords = tm.get_cell_atlas_coords(target_tile)
	var is_wooden_wall = (source_id == 1 and atlas_coords == Vector2i(7, 0))

	var target_found = false
	var is_exerting = false
	var is_attack_action = false

	if can_attack:
		var entities_at := World.get_entities_at_tile(target_tile, player.z_level, player.multiplayer.get_unique_id())
		if not entities_at.is_empty():
			target_found = true
			is_exerting = true
			is_attack_action = true

	if not target_found:
		for obj in player.get_tree().get_nodes_in_group("door"):
			if obj.get("z_level") != null and obj.z_level != player.z_level: continue
			if Vector2i(int(obj.global_position.x / World.TILE_SIZE), int(obj.global_position.y / World.TILE_SIZE)) == target_tile:
				if held_item == null:
					target_found = true
					is_exerting = false
				elif is_sword or (is_pickaxe and player.intent == "harm"):
					target_found = true
					is_exerting = true
				break

	if not target_found and can_chop:
		for obj in player.get_tree().get_nodes_in_group("choppable_object"):
			if obj.get("z_level") != null and obj.z_level != player.z_level: continue
			if Vector2i(int(obj.global_position.x / World.TILE_SIZE), int(obj.global_position.y / World.TILE_SIZE)) == target_tile:
				target_found = true
				is_exerting = true
				break

	if not target_found and can_break:
		for obj in player.get_tree().get_nodes_in_group("breakable_object"):
			if obj.get("z_level") != null and obj.z_level != player.z_level: continue
			if Vector2i(int(obj.global_position.x / World.TILE_SIZE), int(obj.global_position.y / World.TILE_SIZE)) == target_tile:
				target_found = true
				is_exerting = true
				break

	if not target_found and can_mine:
		for obj in player.get_tree().get_nodes_in_group("minable_object"):
			if obj.get("z_level") != null and obj.z_level != player.z_level: continue
			if Vector2i(int(obj.global_position.x / World.TILE_SIZE), int(obj.global_position.y / World.TILE_SIZE)) == target_tile:
				target_found = true
				is_exerting = true
				break

	if not target_found and source_id == 1:
		if is_wooden_wall:
			if is_sword or (is_pickaxe and player.intent == "harm"):
				target_found = true
				is_exerting = true
		elif can_mine:
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

	apply_action_cooldown(player.hands[player.active_hand], is_attack_action)

	var acted: bool = false
	if is_attack_action:
		var limb = "chest"
		if player._hud != null:
			limb = player._hud.targeted_limb

		if player.multiplayer.is_server():
			World.rpc_deal_damage_at_tile(target_tile, limb)
		else:
			World.rpc_deal_damage_at_tile.rpc_id(1, target_tile, limb)
		acted = true

	if acted:
		return

	for obj in player.get_tree().get_nodes_in_group("door"):
		if obj.get("z_level") != null and obj.z_level != player.z_level: continue
		if Vector2i(int(obj.global_position.x / World.TILE_SIZE), int(obj.global_position.y / World.TILE_SIZE)) == target_tile:
			if player.multiplayer.is_server():
				World.rpc_request_hit_door(obj.get_path())
			else:
				World.rpc_request_hit_door.rpc_id(1, obj.get_path())
			return

	if can_chop:
		for obj in player.get_tree().get_nodes_in_group("choppable_object"):
			if obj.get("z_level") != null and obj.z_level != player.z_level: continue
			if Vector2i(int(obj.global_position.x / World.TILE_SIZE), int(obj.global_position.y / World.TILE_SIZE)) == target_tile:
				if player.multiplayer.is_server():
					World.rpc_request_hit_tree(obj.get_path())
				else:
					World.rpc_request_hit_tree.rpc_id(1, obj.get_path())
				return

	if can_break:
		for obj in player.get_tree().get_nodes_in_group("breakable_object"):
			if obj.get("z_level") != null and obj.z_level != player.z_level: continue
			if Vector2i(int(obj.global_position.x / World.TILE_SIZE), int(obj.global_position.y / World.TILE_SIZE)) == target_tile:
				if player.multiplayer.is_server():
					World.rpc_request_hit_breakable(obj.get_path())
				else:
					World.rpc_request_hit_breakable.rpc_id(1, obj.get_path())
				return

	if can_mine or (is_sword and is_wooden_wall):
		for obj in player.get_tree().get_nodes_in_group("minable_object"):
			if obj.get("z_level") != null and obj.z_level != player.z_level: continue
			if Vector2i(int(obj.global_position.x / World.TILE_SIZE), int(obj.global_position.y / World.TILE_SIZE)) == target_tile:
				if player.multiplayer.is_server():
					World.rpc_request_hit_rock(obj.get_path())
				else:
					World.rpc_request_hit_rock.rpc_id(1, obj.get_path())
				return

		if tm.get_cell_source_id(target_tile) == 1:
			if player.multiplayer.is_server():
				World.rpc_damage_wall(target_tile)
			else:
				World.rpc_damage_wall.rpc_id(1, target_tile)
