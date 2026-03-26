extends RefCounted

var world: Node

func _init(p_world: Node) -> void:
	world = p_world

func register_solid(pos: Vector2i, z_level: int, obj: Node) -> void:
	if not world.solid_grid[z_level].has(pos): world.solid_grid[z_level][pos] =[]
	if not obj in world.solid_grid[z_level][pos]: world.solid_grid[z_level][pos].append(obj)

func unregister_solid(pos: Vector2i, z_level: int, obj: Node) -> void:
	if world.solid_grid[z_level].has(pos):
		world.solid_grid[z_level][pos].erase(obj)
		if world.solid_grid[z_level][pos].is_empty(): world.solid_grid[z_level].erase(pos)

func is_solid(pos: Vector2i, z_level: int) -> bool:
	var tm = world.get_tilemap(z_level)
	if tm != null and tm.get_cell_source_id(pos) == 1: return true
	return world.solid_grid[z_level].has(pos)

func try_move(from: Vector2i, z_level: int, dir: Vector2i) -> Vector2i:
	if dir == Vector2i.ZERO: return from
	var next := from + dir
	if next.x < 0 or next.x >= world.GRID_WIDTH or next.y < 0 or next.y >= world.GRID_HEIGHT: return from
	if is_solid(next, z_level): return from
	return next

func break_wall(pos: Vector2i, z_level: int, parent: Node, rock_name: String = "") -> void:
	var tm = world.get_tilemap(z_level)
	if tm == null: return
	tm.set_cell(pos, 0, Vector2i(1, 0))
	var scene = load("res://objects/rock.tscn") as PackedScene
	if scene:
		var rock: Node2D = scene.instantiate()
		rock.z_level = z_level
		if rock_name != "": rock.name = rock_name
		rock.position = world.utils.tile_to_pixel(pos)
		parent.add_child(rock)

func get_tile_description(source_id: int, atlas_coords: Vector2i) -> String:
	match source_id:
		0:
			match atlas_coords:
				Vector2i(0, 0): return "short tangled grass, wild and unkempt"
				Vector2i(1, 0): return "rough cobble, jagged worn stones"
				Vector2i(2, 0): return "rough dirt, uneven and loose"
				Vector2i(4, 0): return "worn wooden planks, creaking underfoot"
				Vector2i(5, 0): return "cobblestone floor, rough and uneven"
				Vector2i(8, 0): return "greenblocks, a green patterned floor"
				_: return "floor, some kind of stone"
		1:
			match atlas_coords:
				Vector2i(3, 0): return "a rock wall, solid and immovable"
				Vector2i(6, 0): return "a stone wall, solid but workable"
				Vector2i(7, 0): return "a wooden wall, solid and sturdy"
				_: return "a wall"
		5: return "water, murky and still"
		_: return "empty space, nothing here"

func handle_rpc_try_move(sender_id: int, dir: Vector2i, is_sprinting: bool) -> void:
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if player == null or player.dead: return
	for _gp_id in world.grab_map:
		var _gentry = world.grab_map[_gp_id]
		if _gentry.get("is_player", false) and _gentry.get("target_peer_id", -1) == sender_id:
			world.rpc_confirm_move.rpc(sender_id, player.tile_pos, false)
			if not player.exhausted: world.combat.server_try_resist(sender_id)
			return
	if not player.combat_mode:
		if dir.y > 0: player.facing = 0
		elif dir.y < 0: player.facing = 1
		elif dir.x > 0: player.facing = 2
		elif dir.x < 0: player.facing = 3
	var old_tile: Vector2i = player.tile_pos
	var next_tile: Vector2i = player.tile_pos + dir
	if next_tile.x < 0 or next_tile.x >= world.GRID_WIDTH or next_tile.y < 0 or next_tile.y >= world.GRID_HEIGHT:
		world.rpc_confirm_move.rpc(sender_id, player.tile_pos, false)
		return
	if is_solid(next_tile, player.z_level):
		world.rpc_confirm_move.rpc(sender_id, player.tile_pos, false)
		return
	var occupants = world.utils.get_entities_at_tile(next_tile, player.z_level)
	var blocking_player: Node = null
	for ent in occupants:
		if ent.is_in_group("player") and not ent.dead:
			if world.grab_map.has(sender_id):
				var gentry = world.grab_map[sender_id]
				if gentry.get("is_player", false) and gentry.get("target") == ent: continue
			if not (ent.get("is_lying_down") == true or ent.get("sleep_state") != 0):
				blocking_player = ent
				break
	if blocking_player != null:
		if not player.combat_mode and not blocking_player.combat_mode:
			player.tile_pos = next_tile
			blocking_player.tile_pos = old_tile
			world.combat.drag_grabbed_entity(sender_id, old_tile)
			world.rpc_confirm_move.rpc(player.get_multiplayer_authority(), next_tile, is_sprinting)
			world.rpc_confirm_move.rpc(blocking_player.get_multiplayer_authority(), old_tile, false)
			world.apply_gravity_to_player(blocking_player)
			world.apply_gravity_to_player(player)
		else:
			var push_dest = next_tile + dir
			if push_dest.x >= 0 and push_dest.x < world.GRID_WIDTH and push_dest.y >= 0 and push_dest.y < world.GRID_HEIGHT:
				if not is_solid(push_dest, player.z_level):
					var dest_occupants = world.utils.get_entities_at_tile(push_dest, player.z_level)
					var dest_blocked = false
					for ent in dest_occupants:
						if ent.is_in_group("player") and not ent.dead:
							if not (ent.get("is_lying_down") == true or ent.get("sleep_state") != 0):
								dest_blocked = true
								break
					if not dest_blocked:
						blocking_player.tile_pos = push_dest
						player.tile_pos = next_tile
						world.combat.drag_grabbed_entity(sender_id, old_tile)
						world.rpc_confirm_move.rpc(blocking_player.get_multiplayer_authority(), push_dest, false)
						world.rpc_confirm_move.rpc(player.get_multiplayer_authority(), next_tile, is_sprinting)
						world.apply_gravity_to_player(blocking_player)
						world.apply_gravity_to_player(player)
						return
			world.rpc_confirm_move.rpc(sender_id, player.tile_pos, false)
	else:
		player.tile_pos = next_tile
		world.combat.drag_grabbed_entity(sender_id, old_tile)
		world.rpc_confirm_move.rpc(sender_id, next_tile, is_sprinting)
		world.apply_gravity_to_player(player)

func handle_rpc_confirm_move(peer_id: int, new_pos: Vector2i, is_sprinting: bool) -> void:
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	if player == null: return
	player.is_sprinting = is_sprinting
	player.tile_pos = new_pos
	if player.has_method("_start_move_lerp"): player._start_move_lerp()
	if world.has_node("/root/LateJoin"): world.get_node("/root/LateJoin").update_player_state(peer_id, {"position": player.position})

func handle_rpc_damage_wall(sender_id: int, pos: Vector2i) -> void:
	if not world.multiplayer.is_server(): return
	var attacker: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if attacker == null or attacker.dead: return
	var tm = world.get_tilemap(attacker.z_level)
	if tm == null or tm.get_cell_source_id(pos) != 1: return
	var atlas_coords: Vector2i = tm.get_cell_atlas_coords(pos)
	if attacker.body != null and attacker.body.is_arm_broken(attacker.active_hand): return
	if (pos - attacker.tile_pos).abs().x > 1 or (pos - attacker.tile_pos).abs().y > 1: return
	if not world.utils.server_check_action_cooldown(attacker): return
	var holding_sword: bool = false
	var holding_pickaxe: bool = false
	if attacker.hands[attacker.active_hand] != null:
		var h = attacker.hands[attacker.active_hand]
		var i_type = h.get("item_type")
		if (i_type == "Sword") or ("Sword" in h.name) or (i_type == "Dirk"): holding_sword = true
		elif (i_type == "Pickaxe") or ("Pickaxe" in h.name): holding_pickaxe = true
	var hits_needed: int
	if atlas_coords == Vector2i(3, 0): 
		if holding_sword: return
		hits_needed = world.WALL_HITS_TO_BREAK
	elif atlas_coords == Vector2i(6, 0): 
		if holding_sword: return
		hits_needed = world.STONE_WALL_HITS_TO_BREAK
	elif atlas_coords == Vector2i(7, 0): 
		if holding_sword: hits_needed = world.WOODEN_WALL_HITS_TO_BREAK
		elif holding_pickaxe and attacker.combat_mode: hits_needed = world.WOODEN_WALL_HITS_TO_BREAK
		else: return
	else: return
	if not world.tile_hit_counts[attacker.z_level].has(pos): world.tile_hit_counts[attacker.z_level][pos] = 0
	world.tile_hit_counts[attacker.z_level][pos] += 1
	if world.tile_hit_counts[attacker.z_level][pos] >= hits_needed:
		world.tile_hit_counts[attacker.z_level].erase(pos)
		if atlas_coords == Vector2i(3, 0):
			world.rpc_confirm_break_wall.rpc(pos, attacker.z_level, "WallRock_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000))
		elif atlas_coords == Vector2i(7, 0): world.rpc_confirm_replace_tile.rpc(pos, attacker.z_level, 0, Vector2i(4, 0))
		else: world.rpc_confirm_break_stone_wall.rpc(pos, attacker.z_level)
	else: world.rpc_confirm_hit_wall.rpc(pos, attacker.z_level)

func handle_rpc_confirm_hit_wall(pos: Vector2i, z_level: int) -> void:
	var main = world.get_tree().root.get_node_or_null("Main")
	if main != null and main.has_method("shake_tile"): main.shake_tile(pos, z_level)

func handle_rpc_confirm_break_wall(pos: Vector2i, z_level: int, rock_name: String) -> void:
	var main = world.get_tree().root.get_node_or_null("Main")
	if main != null:
		break_wall(pos, z_level, main, rock_name)
		if world.has_node("/root/LateJoin"): world.get_node("/root/LateJoin").register_tile_change(pos, 0, Vector2i(1, 0)) # NOTE: Needs z integration on latejoin

func handle_rpc_confirm_replace_tile(pos: Vector2i, z_level: int, source_id: int, atlas_coords: Vector2i) -> void:
	var tm = world.get_tilemap(z_level)
	if tm == null: return
	tm.set_cell(pos, source_id, atlas_coords)

func handle_rpc_confirm_break_stone_wall(pos: Vector2i, z_level: int) -> void:
	var tm = world.get_tilemap(z_level)
	if tm == null: return
	tm.set_cell(pos, 0, Vector2i(5, 0))