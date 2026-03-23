# file: project/world.gd
# ==============================================================================
# AutoLoad singleton — registered as "World" in project.godot.
#
# Owns all world-physics queries and tile-mutating operations so that
# other scripts (player, objects) never reach into the tilemap directly.

extends Node

# --- CONFIGURATION ---
# TILE_SIZE / GRID_WIDTH / GRID_HEIGHT are the single source of truth.
# All other scripts (player.gd, main.gd, etc.) reference World.TILE_SIZE etc.
const TILE_SIZE:   int = 64
const GRID_WIDTH:  int = 1000
const GRID_HEIGHT: int = 1000

# Set by main.gd in _ready() once the TileMapLayer node exists
var tilemap: TileMapLayer = null

# --- STATE ---
var solid_grid: Dictionary = {}
var tile_hit_counts: Dictionary = {}
const WALL_HITS_TO_BREAK: int = 3        # rock wall  (source 1, atlas col 3)
const STONE_WALL_HITS_TO_BREAK: int = 10  # stone wall (source 1, atlas col 6)
const WOODEN_WALL_HITS_TO_BREAK: int = 5  # wooden wall (source 1, atlas col 7)

var server_action_cooldowns: Dictionary = {}

# --- LAWS ---
var current_laws: Array =[
	"1. You may not injure a king or, through inaction, allow a king to come to harm.",
	"2. You must obey orders given to you by a king, except where such orders would conflict with the First Law.",
]

# ---------------------------------------------------------------------------
# Grab System State
# ---------------------------------------------------------------------------
# _grab_map[grabber_peer_id] -> { "target": Node, "is_player": bool, "target_peer_id": int, "limb": String }
var _grab_map: Dictionary = {}

const GRAB_COOLDOWN_MS:   int = 1000
const RESIST_COOLDOWN_MS: int = 1000
var _grab_cooldown_map:   Dictionary = {}
var _resist_cooldown_map: Dictionary = {}

# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Hook into multiplayer disconnects to clean up grabs automatically
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	
	print("LateJoin: Peer disconnected - ", id)
	
	# Drop grab if the disconnecting player was grabbing someone
	if _grab_map.has(id):
		_release_grab_for_peer(id, true)

# ---------------------------------------------------------------------------
# Server Validation Helpers
# ---------------------------------------------------------------------------

func _is_within_interaction_range(player: Node, target_pos: Vector2) -> bool:
	var target_tile = Vector2i(int(target_pos.x / TILE_SIZE), int(target_pos.y / TILE_SIZE))
	var diff = (target_tile - player.tile_pos).abs()
	return diff.x <= 1 and diff.y <= 1

func _server_check_action_cooldown(player: Node, is_attack: bool = false) -> bool:
	var current_time = Time.get_ticks_msec()
	var peer_id = player.get_multiplayer_authority()
	var next_allowed = server_action_cooldowns.get(peer_id, 0)
	
	# 100ms grace period for varying network latency
	if current_time < next_allowed - 100:
		return false
	
	var delay = 0.5
	var held_item = player.hands[player.active_hand]
	if held_item != null and held_item.has_method("get_use_delay"):
		delay = held_item.get_use_delay()
		
	if is_attack and delay < 1.0:
		delay = 1.0
	
	if player.exhausted:
		delay *= 3.0
		
	server_action_cooldowns[peer_id] = current_time + int(delay * 1000)
	return true

# ---------------------------------------------------------------------------
# Query & Registration
# ---------------------------------------------------------------------------

func register_solid(pos: Vector2i, obj: Node) -> void:
	if not solid_grid.has(pos):
		solid_grid[pos] =[]
	if not obj in solid_grid[pos]:
		solid_grid[pos].append(obj)

func unregister_solid(pos: Vector2i, obj: Node) -> void:
	if solid_grid.has(pos):
		solid_grid[pos].erase(obj)
		if solid_grid[pos].is_empty():
			solid_grid.erase(pos)

func is_solid(pos: Vector2i) -> bool:
	if tilemap != null and tilemap.get_cell_source_id(pos) == 1:
		return true
	return solid_grid.has(pos)

# ---------------------------------------------------------------------------
# Movement Validation
# ---------------------------------------------------------------------------

func try_move(from: Vector2i, dir: Vector2i) -> Vector2i:
	if dir == Vector2i.ZERO:
		return from
	var next := from + dir
	if next.x < 0 or next.x >= GRID_WIDTH or next.y < 0 or next.y >= GRID_HEIGHT:
		return from
	if is_solid(next):
		return from
	return next

# ---------------------------------------------------------------------------
# Entities Queries
# ---------------------------------------------------------------------------

func get_entities_at_tile(tile: Vector2i, exclude_peer: int = 0) -> Array:
	var result :=[]

	# Check NPCs
	for npc in get_tree().get_nodes_in_group("npc"):
		if npc.tile_pos == tile:
			result.append(npc)
			continue
		if npc.get("moving") == true:
			var visual_tile := Vector2i(
				int(npc.global_position.x / TILE_SIZE),
				int(npc.global_position.y / TILE_SIZE)
			)
			if visual_tile == tile:
				result.append(npc)

	# Check Players
	for p in get_tree().get_nodes_in_group("player"):
		if p.get_multiplayer_authority() == exclude_peer:
			continue
		if p.dead:
			continue
		if p.tile_pos == tile:
			result.append(p)
			continue
		if p.get("moving") == true:
			var visual_tile := Vector2i(
				int(p.global_position.x / TILE_SIZE),
				int(p.global_position.y / TILE_SIZE)
			)
			if visual_tile == tile:
				result.append(p)

	return result


func _calculate_combat_roll(attacker: Node, defender: Node, base_amount: int, is_sword_attack: bool) -> Dictionary:
	var result = {"damage": base_amount, "blocked": false, "block_type": ""}
	if not defender.is_in_group("player"):
		return result

	var d_has_sword = false
	if "hands" in defender and defender.hands != null:
		for h in defender.hands:
			if h != null:
				var i_type = h.get("item_type")
				if (i_type != null and (i_type == "Sword" or i_type == "Dirk")) or ("Sword" in h.name) or ("sword" in h.name.to_lower()) or ("Dirk" in h.name) or ("dirk" in h.name.to_lower()):
					d_has_sword = true
					break

	var a_skill = 0
	if attacker != null and attacker.is_in_group("player") and is_sword_attack:
		if "skills" in attacker:
			a_skill = attacker.skills.get("sword_fighting", 0)

	# Determine the defender's combat stance ("dodge" is the default if not set)
	var d_stance: String = defender.get("combat_stance") if defender.get("combat_stance") != null else "dodge"

	var avoidance_chance = 0.0
	var valid_dodge_tiles =[]
	
	var can_defend = true
	if "stamina" in defender and defender.stamina < 3.0:
		can_defend = false
	if "exhausted" in defender and defender.exhausted:
		can_defend = false
	if "grabbed_by" in defender and defender.grabbed_by != null and is_instance_valid(defender.grabbed_by):
		can_defend = false

	if can_defend:
		if d_stance == "parry" and d_has_sword:
			# --- PARRY: skill-based, only when armed ---
			var d_skill = 0
			if "skills" in defender:
				d_skill = defender.skills.get("sword_fighting", 0)
			# Changed multiplier from 19.6 to 17.0 (5 levels advantage = 85% parry chance)
			avoidance_chance = clamp(float(d_skill - a_skill) * 17.0, 0.0, 98.0)
			result.block_type = "parried"
		else:
			# --- DODGE: agility-based, always available ---
			for dir in[Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var check_tile = defender.tile_pos + dir
				if check_tile.x < 0 or check_tile.x >= GRID_WIDTH or check_tile.y < 0 or check_tile.y >= GRID_HEIGHT: continue
				if is_solid(check_tile): continue
				
				var occupants = get_entities_at_tile(check_tile)
				var blocked = false
				for ent in occupants:
					if ent.is_in_group("player") and not ent.dead:
						if not (ent.get("is_lying_down") == true or ent.get("sleep_state") != 0):
							blocked = true
							break
				if not blocked:
					valid_dodge_tiles.append(check_tile)

			if valid_dodge_tiles.is_empty():
				avoidance_chance = 0.0
				result.block_type = ""
			else:
				# Base 10 agility = 20% dodge. Each point above/below 10 adds/removes 5%.
				var d_agility = 10
				if "stats" in defender:
					d_agility = defender.stats.get("agility", 10)
				avoidance_chance = clamp((d_agility - 10) * 5.0 + 20.0, 0.0, 85.0)
				result.block_type = "dodged"

	# --- DIRECTIONAL COMBAT MODIFIERS ---
	if attacker != null and (attacker.is_in_group("player") or attacker.is_in_group("npc")):
		var diff = attacker.tile_pos - defender.tile_pos
		var attack_dir = -1 # 0: S, 1: N, 2: E, 3: W
		if abs(diff.x) > abs(diff.y):
			attack_dir = 2 if diff.x > 0 else 3
		elif abs(diff.x) < abs(diff.y) or diff.y != 0:
			attack_dir = 0 if diff.y > 0 else 1

		if attack_dir != -1:
			var d_facing = defender.facing
			if attack_dir == d_facing:
				# Attack from the Front — full avoidance chance
				avoidance_chance *= 1.0
			else:
				var is_back = false
				if d_facing == 0 and attack_dir == 1: is_back = true
				elif d_facing == 1 and attack_dir == 0: is_back = true
				elif d_facing == 2 and attack_dir == 3: is_back = true
				elif d_facing == 3 and attack_dir == 2: is_back = true

				if is_back:
					if not defender.combat_mode:
						avoidance_chance = 0.0
					else:
						avoidance_chance *= 0.1
				else:
					# Attack from Side
					avoidance_chance *= 0.5

	if randf() * 100.0 < avoidance_chance:
		result.damage  = 0
		result.blocked = true
		if result.block_type == "dodged" and not valid_dodge_tiles.is_empty():
			result.dodge_tile = valid_dodge_tiles.pick_random()
	else:
		result.block_type = ""

	return result


func deal_damage_at_tile(tile: Vector2i, amount: int, attacker_id: int = 0, is_sword_attack: bool = false) -> Dictionary:
	var results  = {}
	var attacker = _find_player_by_peer(attacker_id)
	var entities := get_entities_at_tile(tile, attacker_id)

	for entity in entities:
		var roll = _calculate_combat_roll(attacker, entity, amount, is_sword_attack)
		results[entity] = roll
		if roll.damage > 0:
			if entity.is_in_group("player"):
				entity.receive_damage.rpc(roll.damage)
			elif entity.has_method("receive_damage"):
				entity.receive_damage(roll.damage)
		elif roll.blocked:
			if entity.is_in_group("player"):
				if entity.has_method("rpc_consume_stamina"):
					var tgt_peer = entity.get_multiplayer_authority()
					if tgt_peer == 1 or tgt_peer in multiplayer.get_peers():
						entity.rpc_consume_stamina.rpc_id(tgt_peer, 3.0)
				if roll.block_type == "dodged" and roll.has("dodge_tile"):
					entity.tile_pos = roll.dodge_tile
					rpc_confirm_move.rpc(entity.get_multiplayer_authority(), roll.dodge_tile, false)

	return results

# ---------------------------------------------------------------------------
# Item Placement
# ---------------------------------------------------------------------------

func drop_item_at(obj: Node2D, tile: Vector2i, spread: float) -> void:
	var drop_offset := Vector2(
		randf_range(-spread, spread),
		randf_range(-spread, spread)
	)
	obj.global_position = tile_to_pixel(tile) + drop_offset
	obj.z_index = 5

# ---------------------------------------------------------------------------
# Throw (DDA raycasting)
# ---------------------------------------------------------------------------

func cast_throw(from_tile: Vector2i, from_pixel: Vector2, dir: Vector2, max_tiles: int) -> Vector2i:
	if dir == Vector2.ZERO:
		return from_tile

	var ray_dir    := dir.normalized()
	var map_check  := from_tile
	var last_valid := from_tile
	var ray_start  := from_pixel / float(TILE_SIZE)

	var ray_step_size := Vector2(
		1e30 if ray_dir.x == 0 else abs(1.0 / ray_dir.x),
		1e30 if ray_dir.y == 0 else abs(1.0 / ray_dir.y)
	)

	var ray_length_1d: Vector2
	var step: Vector2i

	if ray_dir.x < 0:
		step.x = -1
		ray_length_1d.x = (ray_start.x - float(map_check.x)) * ray_step_size.x
	else:
		step.x = 1
		ray_length_1d.x = (float(map_check.x + 1) - ray_start.x) * ray_step_size.x

	if ray_dir.y < 0:
		step.y = -1
		ray_length_1d.y = (ray_start.y - float(map_check.y)) * ray_step_size.y
	else:
		step.y = 1
		ray_length_1d.y = (float(map_check.y + 1) - ray_start.y) * ray_step_size.y

	var max_dist    := float(max_tiles)
	var current_dist := 0.0

	while current_dist < max_dist:
		if ray_length_1d.x < ray_length_1d.y:
			map_check.x  += step.x
			current_dist  = ray_length_1d.x
			ray_length_1d.x += ray_step_size.x
		else:
			map_check.y  += step.y
			current_dist  = ray_length_1d.y
			ray_length_1d.y += ray_step_size.y

		if map_check.x < 0 or map_check.x >= GRID_WIDTH or map_check.y < 0 or map_check.y >= GRID_HEIGHT:
			break

		if is_solid(map_check):
			return last_valid

		last_valid = map_check

	return last_valid

# ---------------------------------------------------------------------------
# Pathfinding (A*) - Optimized for GDScript
# ---------------------------------------------------------------------------

func find_path(start: Vector2i, target: Vector2i) -> Array[Vector2i]:
	var open: Array[Vector2i] =[start]
	var open_set := {start: true} # O(1) lookup for checking if a node is in 'open'
	
	var closed := {}
	var came_from := {}
	var g_score := {start: 0}
	
	# Inline Manhattan distance (integer math is faster than floats)
	var start_h: int = abs(start.x - target.x) + abs(start.y - target.y)
	var f_score := {start: start_h}

	var iterations := 0
	var max_iterations := 500

	# Pre-allocate direction arrays WITH STRICT TYPING to fix the inference error
	var dirs_x: Array[int] =[1, -1, 0, 0]
	var dirs_y: Array[int] =[0, 0, 1, -1]

	# Track the best node in case we hit the iteration limit
	var best_node := start
	var best_h: int = start_h

	while not open.is_empty():
		iterations += 1
		if iterations > max_iterations:
			# Early exit: return a partial path to the closest node found so far.
			# This prevents mobs from freezing if the player is just out of range.
			return _reconstruct_path(came_from, best_node)

		# 1. Fast Linear Scan
		var current := open[0]
		var current_idx := 0
		var min_f: int = f_score[current]

		for i in range(1, open.size()):
			var node := open[i]
			var f: int = f_score[node]
			if f < min_f:
				min_f = f
				current = node
				current_idx = i

		if current == target:
			return _reconstruct_path(came_from, current)

		# 2. O(1) Array Removal (Swap with last element and pop)
		var last_node = open.pop_back()
		if current_idx < open.size():
			open[current_idx] = last_node
		
		open_set.erase(current)
		closed[current] = true

		var current_g: int = g_score[current]
		var cx: int = current.x
		var cy: int = current.y

		for i in 4:
			# Explicitly type as int to satisfy the static analyzer
			var nx: int = cx + dirs_x[i]
			var ny: int = cy + dirs_y[i]
			var neighbor := Vector2i(nx, ny)

			# Bounds check
			if nx < 0 or nx >= GRID_WIDTH or ny < 0 or ny >= GRID_HEIGHT:
				continue

			if closed.has(neighbor):
				continue

			# Solid check
			if neighbor != target and is_solid(neighbor):
				continue

			var tentative_g: int = current_g + 1

			# 999999 acts as our Integer 'INF'
			if tentative_g < g_score.get(neighbor, 999999):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				
				# Inline Heuristic (Manhattan distance)
				var h: int = abs(nx - target.x) + abs(ny - target.y)
				f_score[neighbor] = tentative_g + h
				
				# Track closest node for partial pathing fallback
				if h < best_h:
					best_h = h
					best_node = neighbor

				# 3. O(1) check if neighbor is in open
				if not open_set.has(neighbor):
					open.append(neighbor)
					open_set[neighbor] = true

	return[]

func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] =[]
	path.append(current)
	while came_from.has(current):
		current = came_from[current]
		path.append(current)
	path.reverse()
	if not path.is_empty():
		path.remove_at(0)
	return path

# ---------------------------------------------------------------------------
# Mutation
# ---------------------------------------------------------------------------

func break_wall(pos: Vector2i, parent: Node, rock_name: String = "") -> void:
	if tilemap == null: return
	# Changed replacement tile to Rough Cobble (0, 1, 0)
	tilemap.set_cell(pos, 0, Vector2i(1, 0))
	
	# Fix: Use runtime load() instead of preload() to prevent cyclic dependency crash
	var scene = load("res://objects/rock.tscn") as PackedScene
	if scene:
		var rock: Node2D = scene.instantiate()
		if rock_name != "": rock.name = rock_name
		rock.position = tile_to_pixel(pos)
		parent.add_child(rock)

# ---------------------------------------------------------------------------
# Descriptions
# ---------------------------------------------------------------------------

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
		5:
			return "water, murky and still"
		_:
			return "empty space, nothing here"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func tile_to_pixel(t: Vector2i) -> Vector2:
	return Vector2((t.x + 0.5) * TILE_SIZE, (t.y + 0.5) * TILE_SIZE)

func _world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / TILE_SIZE), int(world_pos.y / TILE_SIZE))

func get_local_player() -> Node:
	if not multiplayer.has_multiplayer_peer():
		return null
	var local_id = multiplayer.get_unique_id()
	return _find_player_by_peer(local_id)

# ===========================================================================
# RPC Wrappers — Multiplayer
# ===========================================================================

func _find_player_by_peer(peer_id: int) -> Node:
	for p in get_tree().get_nodes_in_group("player"):
		if p.get_multiplayer_authority() == peer_id:
			return p
	return null

# ---------------------------------------------------------------------------
# Laws
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_update_laws(new_laws: Array) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()

	var player = _find_player_by_peer(peer_id)
	if player == null or player.character_class != "king":
		return # Only the king can edit laws

	rpc_update_laws.rpc(new_laws)

@rpc("authority", "call_local", "reliable")
func rpc_update_laws(new_laws: Array) -> void:
	current_laws = new_laws
	if Sidebar.has_method("refresh_laws_ui"):
		Sidebar.refresh_laws_ui()

# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_try_move(dir: Vector2i, is_sprinting: bool = false) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()
	var player := _find_player_by_peer(peer_id)
	if player == null or player.dead:
		return

	# Block movement if this player is currently being grabbed — trigger resist instead
	for _gp_id in _grab_map:
		var _gentry = _grab_map[_gp_id]
		if _gentry.get("is_player", false) and _gentry.get("target_peer_id", -1) == peer_id:
			rpc_confirm_move.rpc(peer_id, player.tile_pos, false)
			# Exhausted players cannot struggle free via WASD either
			if not player.exhausted:
				_server_try_resist(peer_id)
			return

	# Update Facing
	if not player.combat_mode:
		if   dir.y > 0: player.facing = 0
		elif dir.y < 0: player.facing = 1
		elif dir.x > 0: player.facing = 2
		elif dir.x < 0: player.facing = 3

	var old_tile: Vector2i = player.tile_pos
	var next_tile: Vector2i = player.tile_pos + dir
	
	# World Bounds
	if next_tile.x < 0 or next_tile.x >= GRID_WIDTH or next_tile.y < 0 or next_tile.y >= GRID_HEIGHT:
		rpc_confirm_move.rpc(peer_id, player.tile_pos, false)
		return
		
	# Solid Wall Check
	if is_solid(next_tile):
		rpc_confirm_move.rpc(peer_id, player.tile_pos, false)
		return

	# Colliding with Players
	var occupants = get_entities_at_tile(next_tile)
	var blocking_player = null
	for ent in occupants:
		if ent.is_in_group("player") and not ent.dead:
			# Allow walking into our own grabbed target's tile
			if _grab_map.has(peer_id):
				var gentry = _grab_map[peer_id]
				if gentry.get("is_player", false) and gentry.get("target") == ent:
					continue
			# Lying down or sleeping players do not block movement
			var ent_prone: bool = ent.get("is_lying_down") == true or ent.get("sleep_state") != 0
			if not ent_prone:
				blocking_player = ent
				break
			
	if blocking_player != null:
		if not player.combat_mode and not blocking_player.combat_mode:
			# Swap mechanic (both not in combat)
			player.tile_pos = next_tile
			blocking_player.tile_pos = old_tile
			_drag_grabbed_entity(peer_id, old_tile)
			rpc_confirm_move.rpc(player.get_multiplayer_authority(), next_tile, is_sprinting)
			rpc_confirm_move.rpc(blocking_player.get_multiplayer_authority(), old_tile, false)
		else:
			# Push mechanic (one or both are in combat mode)
			var push_dest = next_tile + dir
			if push_dest.x >= 0 and push_dest.x < GRID_WIDTH and push_dest.y >= 0 and push_dest.y < GRID_HEIGHT:
				if not is_solid(push_dest):
					var dest_occupants = get_entities_at_tile(push_dest)
					var dest_blocked = false
					for ent in dest_occupants:
						if ent.is_in_group("player") and not ent.dead:
							var ent_prone: bool = ent.get("is_lying_down") == true or ent.get("sleep_state") != 0
							if not ent_prone:
								dest_blocked = true
								break
					
					if not dest_blocked:
						# Successful Push
						blocking_player.tile_pos = push_dest
						player.tile_pos = next_tile
						_drag_grabbed_entity(peer_id, old_tile)
						rpc_confirm_move.rpc(blocking_player.get_multiplayer_authority(), push_dest, false)
						rpc_confirm_move.rpc(player.get_multiplayer_authority(), next_tile, is_sprinting)
						return
			
			# Blocked, can't push them there
			rpc_confirm_move.rpc(peer_id, player.tile_pos, false)
	else:
		# Standard Move
		player.tile_pos = next_tile
		_drag_grabbed_entity(peer_id, old_tile)
		rpc_confirm_move.rpc(peer_id, next_tile, is_sprinting)


@rpc("authority", "call_local", "reliable")
func rpc_confirm_move(peer_id: int, new_pos: Vector2i, is_sprinting: bool = false) -> void:
	var player := _find_player_by_peer(peer_id)
	if player == null:
		return
	player.is_sprinting = is_sprinting
	player.tile_pos = new_pos
	if player.has_method("_start_move_lerp"):
		player._start_move_lerp()
	
	# Update LateJoin with player position
	if has_node("/root/LateJoin"):
		LateJoin.update_player_state(peer_id, {"position": player.position})

# ---------------------------------------------------------------------------
# Active Shoving Right Click Functionality
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_shove(target_tile: Vector2i) -> void:
	if not multiplayer.is_server(): return
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0: peer_id = multiplayer.get_unique_id()
	
	var attacker = _find_player_by_peer(peer_id)
	if attacker == null or not attacker.combat_mode or attacker.dead: return

	var diff = (target_tile - attacker.tile_pos).abs()
	if diff.x > 1 or diff.y > 1: return

	if not _server_check_action_cooldown(attacker, true): return

	var occupants = get_entities_at_tile(target_tile)
	var target_player = null
	for ent in occupants:
		if ent.is_in_group("player") and not ent.dead:
			target_player = ent
			break
			
	if target_player != null:
		var shove_dir = target_tile - attacker.tile_pos
		var shove_dest = target_player.tile_pos + shove_dir
		
		var dest_blocked = false
		if shove_dest.x < 0 or shove_dest.x >= GRID_WIDTH or shove_dest.y < 0 or shove_dest.y >= GRID_HEIGHT:
			dest_blocked = true
		elif is_solid(shove_dest):
			dest_blocked = true
		else:
			var dest_occupants = get_entities_at_tile(shove_dest)
			for ent in dest_occupants:
				if ent.is_in_group("player") and not ent.dead:
					var ent_prone: bool = ent.get("is_lying_down") == true or ent.get("sleep_state") != 0
					if not ent_prone:
						dest_blocked = true
						break
		
		if not dest_blocked:
			target_player.tile_pos = shove_dest
			rpc_confirm_move.rpc(target_player.get_multiplayer_authority(), shove_dest, false)
			
			rpc_broadcast_damage_log.rpc(attacker.character_name, target_player.character_name, 0, attacker.tile_pos, false, true)


# ---------------------------------------------------------------------------
# Damage
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_deal_damage_at_tile(tile: Vector2i, targeted_limb: String = "chest") -> void:
	if not multiplayer.is_server():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()

	var attacker = _find_player_by_peer(peer_id)
	if attacker == null or attacker.dead:
		return
		
	# Security Check: Ensure the player is actually close enough to melee attack this tile
	var diff = (tile - attacker.tile_pos).abs()
	if diff.x > 1 or diff.y > 1:
		return
		
	if not _server_check_action_cooldown(attacker, true): return
		
	# Calculate damage on the server based on what the attacker is actually holding
	var held_item = attacker.hands[attacker.active_hand]
	var amount: int = attacker._get_weapon_damage(held_item)
	
	var is_sword_attack: bool = false
	if held_item != null:
		var i_type = held_item.get("item_type")
		is_sword_attack = (i_type == "Sword") or ("Sword" in held_item.name) or ("sword" in held_item.name.to_lower()) or (i_type == "Dirk") or ("Dirk" in held_item.name) or ("dirk" in held_item.name.to_lower())

	var source_tile: Vector2i = attacker.tile_pos
	
	var entities := get_entities_at_tile(tile, peer_id)
	for entity in entities:
		var roll = _calculate_combat_roll(attacker, entity, amount, is_sword_attack)
		
		# Identify name for logs
		var target_name: String = ""
		if entity.is_in_group("player"):
			target_name = entity.character_name
			if roll.damage > 0:
				entity.receive_damage.rpc(roll.damage, targeted_limb)
			elif roll.blocked:
				if entity.has_method("rpc_consume_stamina"):
					var tgt_peer = entity.get_multiplayer_authority()
					if tgt_peer == 1 or tgt_peer in multiplayer.get_peers():
						entity.rpc_consume_stamina.rpc_id(tgt_peer, 3.0)
				if roll.block_type == "dodged" and roll.has("dodge_tile"):
					entity.tile_pos = roll.dodge_tile
					rpc_confirm_move.rpc(entity.get_multiplayer_authority(), roll.dodge_tile, false)
		elif entity.has_method("receive_damage"):
			target_name = entity.name.get_slice("@", 0)
			if roll.damage > 0:
				entity.receive_damage(roll.damage)
		else:
			continue

		rpc_broadcast_damage_log.rpc(attacker.character_name, target_name, roll.damage, source_tile, roll.blocked, false, targeted_limb, roll.get("block_type", ""))

@rpc("any_peer", "call_remote", "reliable")
func rpc_damage_wall(pos: Vector2i) -> void:
	if not multiplayer.is_server(): return
	if tilemap == null or tilemap.get_cell_source_id(pos) != 1: return

	var atlas_coords := tilemap.get_cell_atlas_coords(pos)
	
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0: peer_id = multiplayer.get_unique_id()
	var attacker = _find_player_by_peer(peer_id)
	if attacker == null or attacker.dead: return
	
	var diff = (pos - attacker.tile_pos).abs()
	if diff.x > 1 or diff.y > 1: return
	
	if not _server_check_action_cooldown(attacker): return
	
	var holding_sword: bool = false
	var holding_pickaxe: bool = false
	if attacker.hands[attacker.active_hand] != null:
		var h = attacker.hands[attacker.active_hand]
		var i_type = h.get("item_type")
		if (i_type == "Sword") or ("Sword" in h.name) or ("sword" in h.name.to_lower()) or (i_type == "Dirk") or ("Dirk" in h.name) or ("dirk" in h.name.to_lower()):
			holding_sword = true
		elif (i_type == "Pickaxe") or ("Pickaxe" in h.name) or ("pickaxe" in h.name.to_lower()):
			holding_pickaxe = true
			
	var hits_needed: int
	if atlas_coords == Vector2i(3, 0): # Rock
		if holding_sword: return # Swords cannot break rock walls
		hits_needed = WALL_HITS_TO_BREAK
	elif atlas_coords == Vector2i(6, 0): # Stone
		if holding_sword: return # Swords cannot break stone walls
		hits_needed = STONE_WALL_HITS_TO_BREAK
	elif atlas_coords == Vector2i(7, 0): # Wooden Wall
		if holding_sword:
			hits_needed = WOODEN_WALL_HITS_TO_BREAK
		elif holding_pickaxe and attacker.combat_mode:
			hits_needed = WOODEN_WALL_HITS_TO_BREAK
		else:
			return # Cannot break wooden wall unarmed or with non-combat pickaxe
	else:
		return  # unknown solid tile, ignore

	if not tile_hit_counts.has(pos):
		tile_hit_counts[pos] = 0
	tile_hit_counts[pos] += 1

	if tile_hit_counts[pos] >= hits_needed:
		tile_hit_counts.erase(pos)
		if atlas_coords == Vector2i(3, 0):
			# Rock wall: spawn rock item (existing behaviour)
			var rock_name = "WallRock_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000)
			rpc_confirm_break_wall.rpc(pos, rock_name)
		elif atlas_coords == Vector2i(7, 0):
			# Wooden wall -> Wooden floor (source 0, atlas 4, 0)
			rpc_confirm_replace_tile.rpc(pos, 0, Vector2i(4, 0))
		else:
			# Stone wall: replace with cobblestone floor (source 0, col 5), no rock drop
			rpc_confirm_break_stone_wall.rpc(pos)
	else:
		rpc_confirm_hit_wall.rpc(pos)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_hit_wall(pos: Vector2i) -> void:
	var main = get_tree().root.get_node_or_null("Main")
	if main != null and main.has_method("shake_tile"):
		main.shake_tile(pos)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_break_wall(pos: Vector2i, rock_name: String) -> void:
	var main = get_tree().root.get_node_or_null("Main")
	if main != null:
		break_wall(pos, main, rock_name)
		# Register tile change with LateJoin (replaced Grass with Rough Cobble 0, 1, 0)
		if has_node("/root/LateJoin"):
			LateJoin.register_tile_change(pos, 0, Vector2i(1, 0))

@rpc("authority", "call_local", "reliable")
func rpc_confirm_replace_tile(pos: Vector2i, source_id: int, atlas_coords: Vector2i) -> void:
	if tilemap == null: return
	tilemap.set_cell(pos, source_id, atlas_coords)
	if has_node("/root/LateJoin"):
		LateJoin.register_tile_change(pos, source_id, atlas_coords)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_break_stone_wall(pos: Vector2i) -> void:
	# Replace stone wall tile with cobblestone floor (source 0, atlas col 5)
	if tilemap == null: return
	tilemap.set_cell(pos, 0, Vector2i(5, 0))
	# Register tile change with LateJoin
	if has_node("/root/LateJoin"):
		LateJoin.register_tile_change(pos, 0, Vector2i(5, 0))

# ---------------------------------------------------------------------------
# Rocks Mining
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_hit_rock(rock_path: NodePath) -> void:
	if not multiplayer.is_server(): return
	var rock = get_node_or_null(rock_path)
	if rock == null: return

	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0: peer_id = multiplayer.get_unique_id()
	var player = _find_player_by_peer(peer_id)
	if player == null or player.dead: return
	
	if not _is_within_interaction_range(player, rock.global_position): return
	if not _server_check_action_cooldown(player): return

	rock.hits += 1
	# Register object state with LateJoin
	if has_node("/root/LateJoin"):
		LateJoin.register_object_state(rock_path, {"hits": rock.hits, "type": "rock"})
	
	if rock.hits >= rock.HITS_TO_BREAK:
		var drops =["pebble", "pebble"]
		if randf() < 0.20: drops.append("coal")
		if randf() < 0.10: drops.append("ironore")

		var drop_data =[]
		for d in drops:
			drop_data.append({"type": d, "name": "Drop_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000)})
		rpc_confirm_break_rock.rpc(rock_path, drop_data)
	else:
		rpc_confirm_hit_rock.rpc(rock_path)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_hit_rock(rock_path: NodePath) -> void:
	var rock = get_node_or_null(rock_path)
	if rock != null:
		var main = get_tree().root.get_node_or_null("Main")
		rock.perform_hit(main)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_break_rock(rock_path: NodePath, drops_data: Array) -> void:
	var rock = get_node_or_null(rock_path)
	if rock != null:
		rock.perform_break(drops_data)
		# Unregister object from LateJoin (rock is broken)
		if has_node("/root/LateJoin"):
			LateJoin.unregister_object(rock_path)

# ---------------------------------------------------------------------------
# Tree Chopping
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_hit_tree(tree_path: NodePath) -> void:
	if not multiplayer.is_server(): return
	var tree = get_node_or_null(tree_path)
	if tree == null: return

	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0: peer_id = multiplayer.get_unique_id()
	var player = _find_player_by_peer(peer_id)
	if player == null or player.dead: return
	
	if not _is_within_interaction_range(player, tree.global_position): return
	if not _server_check_action_cooldown(player): return

	tree.hits += 1
	# Register object state with LateJoin
	if has_node("/root/LateJoin"):
		LateJoin.register_object_state(tree_path, {"hits": tree.hits, "type": "tree"})
	
	if tree.hits >= tree.HITS_TO_BREAK:
		var log_names =[]
		for i in range(3):
			log_names.append("Log_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000))
		rpc_confirm_break_tree.rpc(tree_path, log_names)
	else:
		rpc_confirm_hit_tree.rpc(tree_path)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_hit_tree(tree_path: NodePath) -> void:
	var tree = get_node_or_null(tree_path)
	if tree != null:
		var main = get_tree().root.get_node_or_null("Main")
		tree.perform_hit(main)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_break_tree(tree_path: NodePath, log_names: Array) -> void:
	var tree = get_node_or_null(tree_path)
	if tree != null:
		tree.perform_break(log_names)
		# Unregister object from LateJoin (tree is broken)
		if has_node("/root/LateJoin"):
			LateJoin.unregister_object(tree_path)

# ---------------------------------------------------------------------------
# Breakable Objects (Furniture)
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_hit_breakable(obj_path: NodePath) -> void:
	if not multiplayer.is_server(): return
	var obj = get_node_or_null(obj_path)
	if obj == null: return

	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0: peer_id = multiplayer.get_unique_id()
	var player = _find_player_by_peer(peer_id)
	if player == null or player.dead: return
	
	if not _is_within_interaction_range(player, obj.global_position): return
	if not _server_check_action_cooldown(player): return

	obj.hits += 1
	# Register object state with LateJoin
	if has_node("/root/LateJoin"):
		LateJoin.register_object_state(obj_path, {"hits": obj.hits, "type": "breakable"})
	
	if obj.hits >= obj.HITS_TO_BREAK:
		rpc_confirm_break_breakable.rpc(obj_path)
	else:
		rpc_confirm_hit_breakable.rpc(obj_path)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_hit_breakable(obj_path: NodePath) -> void:
	var obj = get_node_or_null(obj_path)
	if obj != null and obj.has_method("perform_hit"):
		var main = get_tree().root.get_node_or_null("Main")
		obj.perform_hit(main)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_break_breakable(obj_path: NodePath) -> void:
	var obj = get_node_or_null(obj_path)
	if obj != null and obj.has_method("perform_break"):
		obj.perform_break()
		# Unregister object from LateJoin
		if has_node("/root/LateJoin"):
			LateJoin.unregister_object(obj_path)

# ---------------------------------------------------------------------------
# Door Interactions
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_hit_door(door_path: NodePath) -> void:
	if not multiplayer.is_server(): return
	var door = get_node_or_null(door_path)
	if door == null: return

	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0: peer_id = multiplayer.get_unique_id()
	var player = _find_player_by_peer(peer_id)
	if player == null or player.dead: return
	
	if not _is_within_interaction_range(player, door.global_position): return
	
	var held_item = player.hands[player.active_hand]
	if held_item == null:
		# Empty hand - toggle door
		if door.state != door.DoorState.DESTROYED:
			rpc_confirm_toggle_door.rpc(door_path)
	else:
		var i_type = held_item.get("item_type")
		var is_sword = (i_type == "Sword") or ("Sword" in held_item.name) or ("sword" in held_item.name.to_lower()) or (i_type == "Dirk") or ("Dirk" in held_item.name) or ("dirk" in held_item.name.to_lower())
		var is_pickaxe = (i_type == "Pickaxe") or ("Pickaxe" in held_item.name) or ("pickaxe" in held_item.name.to_lower())
		
		if is_sword or (is_pickaxe and player.combat_mode):
			if not _server_check_action_cooldown(player): return
			# Sword or Combat-mode Pickaxe - damage door
			door.hits += 1
			
			if door.hits >= door.HITS_TO_BREAK * 2:
				rpc_confirm_remove_door.rpc(door_path)
			elif door.hits == door.HITS_TO_BREAK:
				rpc_confirm_destroy_door.rpc(door_path)
			else:
				rpc_confirm_hit_door.rpc(door_path)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_toggle_door(_door_path: NodePath) -> void:
	var door = get_node_or_null(_door_path)
	if door != null:
		door.toggle_door()

@rpc("authority", "call_local", "reliable")
func rpc_confirm_hit_door(door_path: NodePath) -> void:
	var door = get_node_or_null(door_path)
	if door != null:
		var main = get_tree().root.get_node_or_null("Main")
		door.perform_hit(main)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_destroy_door(door_path: NodePath) -> void:
	var door = get_node_or_null(door_path)
	if door != null:
		var main = get_tree().root.get_node_or_null("Main")
		door.perform_hit(main)
		door.destroy_door()

@rpc("authority", "call_local", "reliable")
func rpc_confirm_remove_door(door_path: NodePath) -> void:
	var door = get_node_or_null(door_path)
	if door != null:
		var main = get_tree().root.get_node_or_null("Main")
		door.perform_hit(main)
		door.remove_completely()

# ---------------------------------------------------------------------------
# Clothing (own equip/unequip)
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_equip(item_path: NodePath, slot_name: String, hand_index: int) -> void:
	if not multiplayer.is_server(): return
	if hand_index < 0 or hand_index > 1: return
	
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0: peer_id = multiplayer.get_unique_id()
	
	var player = _find_player_by_peer(peer_id)
	if player == null or player.dead: return
	
	var item = get_node_or_null(item_path)
	if item == null or player.hands[hand_index] != item: return
	
	rpc_confirm_equip.rpc(peer_id, item_path, slot_name, hand_index)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_equip(peer_id: int, item_path: NodePath, slot_name: String, hand_index: int) -> void:
	var player = _find_player_by_peer(peer_id)
	var obj    = get_node_or_null(item_path)
	if player != null and obj != null:
		player._perform_equip(obj, slot_name, hand_index)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_unequip(slot_name: String, hand_index: int) -> void:
	if not multiplayer.is_server(): return
	if hand_index < 0 or hand_index > 1: return
	
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0: peer_id = multiplayer.get_unique_id()
	
	var player = _find_player_by_peer(peer_id)
	if player == null or player.dead: return
	
	var unique_name = "Unequip_" + slot_name + "_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000)
	rpc_confirm_unequip.rpc(peer_id, slot_name, unique_name, hand_index)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_unequip(peer_id: int, slot_name: String, new_node_name: String, hand_index: int) -> void:
	var player = _find_player_by_peer(peer_id)
	if player != null:
		player._perform_unequip(slot_name, new_node_name, hand_index)

# ---------------------------------------------------------------------------
# Furnace
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_furnace_action(furnace_path: NodePath, action: String, hand_idx: int) -> void:
	if not multiplayer.is_server(): return
	if hand_idx < 0 or hand_idx > 1: return
	
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0: peer_id = multiplayer.get_unique_id()

	var furnace = get_node_or_null(furnace_path)
	if furnace == null: return
	
	var player = _find_player_by_peer(peer_id)
	if player == null or player.dead: return
	
	if not _is_within_interaction_range(player, furnace.global_position): return
	
	if action.begins_with("insert_") and player.hands[hand_idx] == null:
		return

	if action == "eject":
		var names  =[]
		var total  = furnace._coal_count + furnace._ironore_count
		for i in total:
			names.append("Eject_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000))
		rpc_confirm_furnace_action.rpc(peer_id, furnace_path, action, hand_idx, names)
	else:
		rpc_confirm_furnace_action.rpc(peer_id, furnace_path, action, hand_idx,[])

@rpc("authority", "call_local", "reliable")
func rpc_confirm_furnace_action(peer_id: int, furnace_path: NodePath, action: String, hand_idx: int, generated_names: Array) -> void:
	var player  = _find_player_by_peer(peer_id)
	var furnace = get_node_or_null(furnace_path)
	if furnace != null:
		furnace._perform_action(action, player, hand_idx, generated_names)

# ---------------------------------------------------------------------------
# Item Interactions (Pickup, Drop, Throw)
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_pickup(item_path: NodePath, hand_index: int) -> void:
	if not multiplayer.is_server():
		return
	if hand_index < 0 or hand_index > 1: return
		
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()
		
	var player = _find_player_by_peer(peer_id)
	if player == null or player.dead: return
	
	var item = get_node_or_null(item_path)
	if item == null: return
	
	if not _is_within_interaction_range(player, item.global_position): return
	
	rpc_confirm_pickup.rpc(peer_id, item_path, hand_index)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_pickup(peer_id: int, item_path: NodePath, hand_index: int) -> void:
	var player = _find_player_by_peer(peer_id)
	var obj    = get_node_or_null(item_path)
	if player == null or obj == null:
		return

	player.hands[hand_index] = obj
	for child in obj.get_children():
		if child is CollisionShape2D:
			child.disabled = true

	if player._is_local_authority():
		player._update_hands_ui()

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_drop(item_path: NodePath, tile: Vector2i, spread: float, hand_index: int) -> void:
	if not multiplayer.is_server():
		return
	if hand_index < 0 or hand_index > 1: return
		
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()
		
	var player = _find_player_by_peer(peer_id)
	if player == null or player.dead: return
	
	var item = get_node_or_null(item_path)
	if item == null or player.hands[hand_index] != item: return
	
	var diff = (tile - player.tile_pos).abs()
	if diff.x > 1 or diff.y > 1: return
	
	rpc_drop_item_at.rpc(peer_id, item_path, tile, spread, hand_index)

@rpc("authority", "call_local", "reliable")
func rpc_drop_item_at(peer_id: int, item_path: NodePath, tile: Vector2i, spread: float, hand_index: int) -> void:
	var player = _find_player_by_peer(peer_id)
	if player != null:
		player.hands[hand_index] = null
		if player._is_local_authority():
			player._update_hands_ui()

	var obj := get_node_or_null(item_path)
	if obj == null:
		return

	var sprite: Node = obj.get_node_or_null("Sprite2D")
	if sprite != null:
		sprite.rotation_degrees = 0.0
		sprite.scale = Vector2(abs(sprite.scale.x), abs(sprite.scale.y))
	drop_item_at(obj, tile, spread)
	for child in obj.get_children():
		if child is CollisionShape2D:
			child.disabled = false

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_throw(item_path: NodePath, hand_index: int, dir: Vector2, throw_range: int) -> void:
	if not multiplayer.is_server():
		return
	if hand_index < 0 or hand_index > 1: return
		
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()
		
	var player = _find_player_by_peer(peer_id)
	if player == null or player.dead: return
	
	var item = get_node_or_null(item_path)
	if item == null or player.hands[hand_index] != item: return
	
	if not _server_check_action_cooldown(player, true): return
	
	var safe_range = int(clamp(throw_range, 1, player.THROW_TILES))
	var land_tile = cast_throw(player.tile_pos, player.pixel_pos, dir, safe_range)
	var land_pixel = tile_to_pixel(land_tile)
	
	rpc_confirm_throw.rpc(peer_id, item_path, hand_index, land_pixel)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_throw(peer_id: int, item_path: NodePath, hand_index: int, land_pixel: Vector2) -> void:
	var player = _find_player_by_peer(peer_id)
	var obj    = get_node_or_null(item_path)
	if player == null or obj == null:
		return

	player.hands[hand_index] = null
	if player._is_local_authority():
		player._is_throwing = true
		player._update_hands_ui()

	obj.z_index = 7
	var sprite: Node = obj.get_node_or_null("Sprite2D")
	if sprite != null:
		sprite.rotation_degrees = 0.0
		sprite.scale = Vector2(abs(sprite.scale.x), abs(sprite.scale.y))

	# Apply DROP_SPREAD offset
	var spread_offset := Vector2(
		randf_range(-player.DROP_SPREAD, player.DROP_SPREAD),
		randf_range(-player.DROP_SPREAD, player.DROP_SPREAD)
	)
	var final_pos := land_pixel + spread_offset

	var tween = get_tree().create_tween()
	tween.tween_property(obj, "global_position", final_pos, player.THROW_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		if player._is_local_authority():
			player._is_throwing = false
		obj.z_index = 5
		for child in obj.get_children():
			if child is CollisionShape2D:
				child.disabled = false
		if multiplayer.is_server():
			var land_tile_check = Vector2i(int(land_pixel.x / TILE_SIZE), int(land_pixel.y / TILE_SIZE))
			var dmg = player._get_weapon_damage(obj)
			
			var attacker_p    := _find_player_by_peer(peer_id)
			var src_tile: Vector2i = attacker_p.tile_pos if attacker_p != null else land_tile_check

			var hit_results = deal_damage_at_tile(land_tile_check, dmg, peer_id, false)
			var throw_targets = get_entities_at_tile(land_tile_check, peer_id)

			for entity in throw_targets:
				var target_name: String = ""
				if entity.is_in_group("player"):
					target_name = entity.character_name
				elif entity.has_method("receive_damage"):
					target_name = entity.name.get_slice("@", 0)

				if target_name != "":
					var roll = hit_results.get(entity, {"damage": dmg, "blocked": false})
					rpc_broadcast_damage_log.rpc(attacker_p.character_name, target_name, roll.damage, src_tile, roll.blocked, false, "", roll.get("block_type", ""))
	)

# ---------------------------------------------------------------------------
# Chat
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_send_chat(message: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()
	var sender := _find_player_by_peer(peer_id)
	if sender == null:
		return
	rpc_broadcast_chat.rpc(peer_id, message, sender.tile_pos)

@rpc("authority", "call_local", "reliable")
func rpc_broadcast_chat(sender_peer_id: int, message: String, sender_tile: Vector2i) -> void:
	var local_player := get_local_player()
	if local_player == null:
		return
	var diff: Vector2i = local_player.tile_pos - sender_tile
	if diff.length_squared() > 144:
		return
	
	# Find the sender player node by peer ID
	var sender_node = _find_player_by_peer(sender_peer_id)
	if sender_node == null:
		return
		
	if local_player.get("sleep_state") == 2: # SleepState.ASLEEP
		Sidebar.add_message("[color=#aaaaaa]you hear someone talking...[/color]")
		return
	
	# Show the floating text above the SENDER's head, not the local player's
	if sender_node.has_method("_show_chat_message"):
		sender_node._show_chat_message(message)
	
	# Show the "[name] says: message" in the sidebar log on the local player
	if local_player.has_method("_show_inspect_text"):
		var sender_name = sender_node.character_name
		local_player._show_inspect_text(sender_name + " says: " + message, "")

# ---------------------------------------------------------------------------
# Damage Log
# ---------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func rpc_broadcast_damage_log(attacker_name: String, target_name: String, amount: int, source_tile: Vector2i, blocked: bool = false, is_shove: bool = false, targeted_limb: String = "", block_type: String = "") -> void:
	var local_player := get_local_player()
	if local_player == null:
		return
	var diff: Vector2i = local_player.tile_pos - source_tile
	if diff.length_squared() > 144:
		return

	var is_target = (target_name == local_player.character_name)
	
	if local_player.get("sleep_state") == 2: # SleepState.ASLEEP
		if is_target:
			Sidebar.add_message("[color=#ff0000][b]YOU FEEL PAIN!!![/b][/color]")
		else:
			Sidebar.add_message("[color=#aaaaaa]you hear a scuffle...[/color]")
		return

	var disp_attacker = "You" if attacker_name == local_player.character_name else attacker_name
	var disp_target   = "You" if is_target else target_name
	
	var limb_str = targeted_limb
	match targeted_limb:
		"r_arm": limb_str = "right arm"
		"l_arm": limb_str = "left arm"
		"r_leg": limb_str = "right leg"
		"l_leg": limb_str = "left leg"

	var log_text = ""
	if is_shove:
		log_text = "[color=#ffcc00][font_size=14]" + disp_attacker + " shoved " + disp_target + "![/font_size][/color]"
	elif blocked:
		var block_word: String = "parried" if block_type == "parried" else "dodged"
		log_text = "[color=#aaaaaa][font_size=14]" + disp_target + " " + block_word + " " + disp_attacker + "'s attack![/font_size][/color]"
	else:
		if limb_str != "":
			log_text = "[color=#ff4444][font_size=14]" + disp_attacker + " hit " + disp_target + " in the " + limb_str + " for " + str(amount) + " damage[/font_size][/color]"
		else:
			log_text = "[color=#ff4444][font_size=14]" + disp_attacker + " hit " + disp_target + " for " + str(amount) + " damage[/font_size][/color]"

	Sidebar.add_message(log_text)

# ---------------------------------------------------------------------------
# Looting
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_notify_loot_warning(target_peer_id: int, looter_peer_id: int, item_desc: String) -> void:
	if not multiplayer.is_server():
		return
		
	var looter = _find_player_by_peer(looter_peer_id)
	if looter == null or looter.dead: return
		
	if target_peer_id == 1:
		rpc_deliver_loot_warning(looter_peer_id, item_desc)
	elif target_peer_id in multiplayer.get_peers():
		rpc_deliver_loot_warning.rpc_id(target_peer_id, looter_peer_id, item_desc)

@rpc("authority", "call_remote", "reliable")
func rpc_deliver_loot_warning(looter_peer_id: int, item_desc: String) -> void:
	var local_player := get_local_player()
	if local_player != null and local_player.has_method("show_loot_warning"):
		local_player.show_loot_warning(looter_peer_id, item_desc)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_loot_item(target_peer_id: int, looter_peer_id: int, slot_type: String, slot_index: Variant) -> void:
	if not multiplayer.is_server():
		return
	
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0: peer_id = multiplayer.get_unique_id()
	if peer_id != looter_peer_id: return

	var target := _find_player_by_peer(target_peer_id)
	var looter := _find_player_by_peer(looter_peer_id)
	if target == null or looter == null or looter.dead:
		return

	var diff: Vector2i = (target.tile_pos - looter.tile_pos).abs()
	if diff.x > 1 or diff.y > 1:
		return

	var drop_tile: Vector2i = target.tile_pos
	const SPREAD: float     = 14.0

	if slot_type == "hand":
		var idx: int  = int(slot_index)
		var obj: Node = target.hands[idx]
		if obj == null or not is_instance_valid(obj):
			return
		rpc_drop_item_at.rpc(target_peer_id, obj.get_path(), drop_tile, SPREAD, idx)

	elif slot_type == "equip":
		var equip_slot: String = str(slot_index)
		var item_name: String  = target.equipped.get(equip_slot, "")
		if item_name == "":
			return
		var new_name := "Loot_" + equip_slot + "_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000)
		rpc_confirm_loot_unequip_drop.rpc(target_peer_id, equip_slot, new_name, drop_tile, SPREAD)


@rpc("authority", "call_local", "reliable")
func rpc_confirm_loot_unequip_drop(target_peer_id: int, equip_slot: String, new_node_name: String, drop_tile: Vector2i, spread: float) -> void:
	var target := _find_player_by_peer(target_peer_id)
	if target == null:
		return

	var item_name: String = target.equipped.get(equip_slot, "")
	if item_name == "":
		return
		
	var scene_path = ItemRegistry.get_scene_path(item_name)
	if scene_path == "":
		return

	var scene := load(scene_path) as PackedScene
	if scene == null:
		return

	target.equipped[equip_slot] = null
	target._update_clothing_sprites()

	if target._is_local_authority():
		if target._hud != null:
			target._hud.update_clothing_display(target.equipped)

	var item: Node2D = scene.instantiate()
	item.name        = new_node_name
	item.position    = tile_to_pixel(drop_tile)
	
	if "equipped_data" in target and target.equipped_data.get(equip_slot) != null:
		if "contents" in target.equipped_data[equip_slot] and "contents" in item:
			item.set("contents", target.equipped_data[equip_slot]["contents"].duplicate(true))
		target.equipped_data[equip_slot] = null
		
	target.get_parent().add_child(item)
	drop_item_at(item, drop_tile, spread)
	for child in item.get_children():
		if child is CollisionShape2D:
			child.disabled = false


# ---------------------------------------------------------------------------
# Crafting
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_craft(looter_peer_id: int, recipe_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0: 
		peer_id = multiplayer.get_unique_id()
		
	if peer_id != looter_peer_id: 
		return
		
	var player = _find_player_by_peer(peer_id)
	if player == null or player.dead: 
		return
		
	var recipes = {
		"sword": {"req": "IronIngot", "req_amt": 1, "scene": "res://objects/sword.tscn"},
		"pickaxe": {"req": "IronIngot", "req_amt": 1, "scene": "res://objects/pickaxe.tscn"},
		"wooden_floor": {"req": "Log", "req_amt": 1, "tile":[0, Vector2i(4, 0)]},
		"cobble_floor": {"req": "Pebble", "req_amt": 1, "tile":[0, Vector2i(5, 0)]},
		"stone_wall": {"req": "Pebble", "req_amt": 2, "tile":[1, Vector2i(6, 0)]}
	}
	if not recipes.has(recipe_id): 
		return
	var recipe = recipes[recipe_id]
	
	var avail =[]
	for i in range(2):
		if player.hands[i] != null: 
			avail.append(player.hands[i])
			
	for obj in get_tree().get_nodes_in_group("pickable"):
		if obj == player.hands[0] or obj == player.hands[1]: 
			continue
		var obj_tile = Vector2i(int(obj.global_position.x / TILE_SIZE), int(obj.global_position.y / TILE_SIZE))
		var diff = (obj_tile - player.tile_pos).abs()
		if diff.x <= 1 and diff.y <= 1:
			avail.append(obj)
			
	var matched_nodes =[]
	var req_type = recipe["req"]
	var req_amt  = recipe["req_amt"]
	
	for obj in avail:
		if matched_nodes.size() >= req_amt:
			break
		var itype = obj.get("item_type") if obj.get("item_type") != null else obj.name.get_slice("@", 0)
		if itype == req_type:
			matched_nodes.append(obj)
			
	if matched_nodes.size() < req_amt:
		return
		
	var result_name = "Craft_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000)
	
	var consumed_paths =[]
	for n in matched_nodes:
		consumed_paths.append(n.get_path())
		
	if recipe.has("scene"):
		rpc_confirm_craft_item.rpc(peer_id, consumed_paths, recipe["scene"], result_name, player.tile_pos)
	elif recipe.has("tile"):
		var tile_data = recipe["tile"]
		rpc_confirm_craft_tile.rpc(peer_id, consumed_paths, player.tile_pos, tile_data[0], tile_data[1])

@rpc("authority", "call_local", "reliable")
func rpc_confirm_craft_item(peer_id: int, consumed_paths: Array, scene_path: String, result_name: String, drop_tile: Vector2i) -> void:
	for p in consumed_paths:
		var n = get_node_or_null(p)
		if n != null:
			var player = _find_player_by_peer(peer_id)
			if player != null:
				for i in range(2):
					if player.hands[i] == n:
						player.hands[i] = null
						if player._is_local_authority():
							player._update_hands_ui()
						break
			n.queue_free()
			
	var scene = load(scene_path) as PackedScene
	if scene == null:
		return
	var item: Node2D = scene.instantiate()
	item.name = result_name
	
	var main = get_tree().root.get_node_or_null("Main")
	if main:
		main.add_child(item)
		drop_item_at(item, drop_tile, 14.0)
		for child in item.get_children():
			if child is CollisionShape2D:
				child.disabled = false

@rpc("authority", "call_local", "reliable")
func rpc_confirm_craft_tile(peer_id: int, consumed_paths: Array, tile_pos: Vector2i, source_id: int, atlas_coords: Vector2i) -> void:
	for p in consumed_paths:
		var n = get_node_or_null(p)
		if n != null:
			var player = _find_player_by_peer(peer_id)
			if player != null:
				for i in range(2):
					if player.hands[i] == n:
						player.hands[i] = null
						if player._is_local_authority():
							player._update_hands_ui()
						break
			n.queue_free()
			
	if tilemap != null:
		tilemap.set_cell(tile_pos, source_id, atlas_coords)
		if has_node("/root/LateJoin"):
			LateJoin.register_tile_change(tile_pos, source_id, atlas_coords)

# ---------------------------------------------------------------------------
# Grab System
# ---------------------------------------------------------------------------

func _limb_display_name(limb: String) -> String:
	match limb:
		"head":  return "head"
		"chest": return "chest"
		"r_arm": return "right arm"
		"l_arm": return "left arm"
		"r_leg": return "right leg"
		"l_leg": return "left leg"
	return limb

func _release_grab_for_peer(grabber_peer_id: int, silent: bool = false) -> void:
	if not _grab_map.has(grabber_peer_id):
		return
	var entry = _grab_map[grabber_peer_id]
	_grab_map.erase(grabber_peer_id)
	var is_player: bool     = entry.get("is_player", false)
	var target_peer_id: int = entry.get("target_peer_id", -1)

	# Resolve names for chat messages
	var grabber_name := ""
	var target_name  := ""
	var grabber_node := _find_player_by_peer(grabber_peer_id)
	if grabber_node != null:
		grabber_name = grabber_node.character_name
	var target_node: Node = entry.get("target", null)
	if target_node != null and is_instance_valid(target_node):
		if is_player:
			target_name = target_node.character_name if "character_name" in target_node else ""
		else:
			var itype = target_node.get("item_type")
			target_name = itype if itype != null else target_node.name.get_slice("@", 0)

	rpc_confirm_grab_released.rpc(grabber_peer_id, is_player, target_peer_id, grabber_name, target_name, silent)

func _drag_grabbed_entity(grabber_peer_id: int, old_tile: Vector2i) -> void:
	if not _grab_map.has(grabber_peer_id):
		return
	var entry = _grab_map[grabber_peer_id]
	var target: Node = entry.get("target", null)
	if target == null or not is_instance_valid(target):
		var was_player: bool = entry.get("is_player", false)
		var was_peer: int    = entry.get("target_peer_id", -1)
		_grab_map.erase(grabber_peer_id)
		rpc_confirm_grab_released.rpc(grabber_peer_id, was_player, was_peer, "", "", true)
		return

	if entry.get("is_player", false):
		var target_peer_id: int = entry.get("target_peer_id", -1)
		target.tile_pos = old_tile
		rpc_confirm_move.rpc(target_peer_id, old_tile, false)
	else:
		var old_pixel := tile_to_pixel(old_tile)
		rpc_confirm_drag_object.rpc(target.get_path(), old_pixel)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_grab(target_path: NodePath, limb: String = "chest") -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()
	var grabber := _find_player_by_peer(peer_id)
	if grabber == null or grabber.dead:
		return

	# Grabber must have an empty active hand to grab
	if grabber.hands[grabber.active_hand] != null:
		return

	# Grab cooldown check
	var now_ms := Time.get_ticks_msec()
	if _grab_cooldown_map.has(peer_id) and now_ms < _grab_cooldown_map[peer_id]:
		return
	_grab_cooldown_map[peer_id] = now_ms + GRAB_COOLDOWN_MS

	var target := get_node_or_null(target_path)
	if target == null or not is_instance_valid(target):
		return

	# Release any existing grab before starting a new one
	if _grab_map.has(peer_id):
		_release_grab_for_peer(peer_id)

	# Range check
	if not _is_within_interaction_range(grabber, target.global_position):
		return

	var is_player: bool = target.is_in_group("player")
	var target_peer_id: int = -1

	if is_player:
		# Note: dead players CAN be grabbed (dragging corpses is allowed)
		target_peer_id = target.get_multiplayer_authority()

	# Sanitise limb value
	var safe_limb := limb if limb in["head", "chest", "r_arm", "l_arm", "r_leg", "l_leg"] else "chest"

	_grab_map[peer_id] = {
		"target":         target,
		"is_player":      is_player,
		"target_peer_id": target_peer_id,
		"limb":           safe_limb
	}

	var grabber_name: String = grabber.character_name
	var target_name: String = ""
	if is_player:
		target_name = target.character_name
	else:
		var itype = target.get("item_type")
		target_name = itype if itype != null else target.name.get_slice("@", 0)

	var grab_hand: int = grabber.active_hand
	rpc_confirm_grab_start.rpc(peer_id, is_player, target_peer_id, target_path, grabber_name, target_name, safe_limb, grab_hand)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_release_grab() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()
	_release_grab_for_peer(peer_id)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_resist() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()
	var grabbed := _find_player_by_peer(peer_id)
	if grabbed == null or grabbed.dead:
		return

	# Check if this player is actually being grabbed
	var is_grabbed := false
	for gp_id in _grab_map:
		var entry = _grab_map[gp_id]
		if entry.get("is_player", false) and entry.get("target_peer_id", -1) == peer_id:
			is_grabbed = true
			break

	if not is_grabbed:
		# Not actually grabbed — notify them
		rpc_confirm_resist_result.rpc(-1, peer_id, false)
		return

	_server_try_resist(peer_id)

# Internal resist logic — called from rpc_request_resist (Z key) and from
# rpc_try_move when a grabbed player attempts to walk away.
func _server_try_resist(peer_id: int) -> void:
	# Resist cooldown
	var now_ms := Time.get_ticks_msec()
	if _resist_cooldown_map.has(peer_id) and now_ms < _resist_cooldown_map[peer_id]:
		return
	_resist_cooldown_map[peer_id] = now_ms + RESIST_COOLDOWN_MS

	var grabbed := _find_player_by_peer(peer_id)
	if grabbed == null or grabbed.dead:
		return

	# Find who is grabbing this player
	var grabber_peer_id: int = -1
	var grabber: Node        = null
	for gp_id in _grab_map:
		var entry = _grab_map[gp_id]
		if entry.get("is_player", false) and entry.get("target_peer_id", -1) == peer_id:
			grabber_peer_id = gp_id
			grabber         = _find_player_by_peer(gp_id)
			break

	if grabber == null or grabber_peer_id == -1:
		return

	var grabbed_str: float = float(grabbed.stats.get("strength", 10))
	var grabber_str: float = float(grabber.stats.get("strength", 10))
	var total_str: float   = max(grabbed_str + grabber_str, 1.0)

	# Exhausted player cannot resist at all — server-side hard block
	if grabbed.exhausted:
		return

	# Stamina costs scale with relative strength
	var resist_cost: float  = 20.0 * (grabber_str / total_str)
	var grabber_cost: float = 20.0 * (grabbed_str / total_str)

	# Break-free chance is proportional to the grabbed player's fraction of total strength
	var break_chance: float = (grabbed_str / total_str) * 100.0

	# Lying down gives a much lower chance to break free
	if grabbed.get("is_lying_down") == true:
		break_chance *= 0.2

	# Apply stamina cost to the grabbed player
	var tgt_peer := grabbed.get_multiplayer_authority()
	if tgt_peer == 1 or tgt_peer in multiplayer.get_peers():
		grabbed.rpc_consume_stamina.rpc_id(tgt_peer, resist_cost)

	# Apply stamina cost to the grabber
	var grabber_tgt_peer := grabber.get_multiplayer_authority()
	if grabber_tgt_peer == 1 or grabber_tgt_peer in multiplayer.get_peers():
		grabber.rpc_consume_stamina.rpc_id(grabber_tgt_peer, grabber_cost)

	if randf() * 100.0 < break_chance:
		_release_grab_for_peer(grabber_peer_id, true)
		rpc_confirm_resist_result.rpc(grabber_peer_id, peer_id, true)
	else:
		rpc_confirm_resist_result.rpc(grabber_peer_id, peer_id, false)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_grab_start(grabber_peer_id: int, is_player: bool, target_peer_id: int, target_path: NodePath, grabber_name: String = "", target_name: String = "", limb: String = "chest", grab_hand: int = 0) -> void:
	var grabber := _find_player_by_peer(grabber_peer_id)
	if grabber == null:
		return
	var target := get_node_or_null(target_path)
	if target == null:
		return

	if grabber._is_local_authority():
		grabber.grabbed_target = target
		grabber.grab_hand_idx  = grab_hand
		grabber._update_grab_ui()

	# Only set grabbed_by on the target if it is a living player (dead players can't respond)
	if is_player and target_peer_id != -1:
		var grabbed_player := _find_player_by_peer(target_peer_id)
		if grabbed_player != null and not grabbed_player.dead and grabbed_player._is_local_authority():
			grabbed_player.grabbed_by = grabber
			grabbed_player._update_grab_ui()

	# Chat messages — only shown for player grabs
	if is_player and target_name != "":
		var local_player := get_local_player()
		if local_player == null:
			return
		var local_peer := local_player.get_multiplayer_authority()
		var limb_display := _limb_display_name(limb)
		if local_peer == grabber_peer_id:
			Sidebar.add_message("[color=#ffcc44]You grab " + target_name + " by the " + limb_display + "![/color]")
		elif local_peer == target_peer_id:
			Sidebar.add_message("[color=#ff4444]" + grabber_name + " grabs you by the " + limb_display + "![/color]")

@rpc("authority", "call_local", "reliable")
func rpc_confirm_grab_released(grabber_peer_id: int, is_player: bool, target_peer_id: int, grabber_name: String = "", target_name: String = "", silent: bool = false) -> void:
	var grabber := _find_player_by_peer(grabber_peer_id)
	if grabber != null and grabber._is_local_authority():
		grabber.grabbed_target = null
		grabber.grab_hand_idx  = -1
		grabber._update_grab_ui()

	if is_player and target_peer_id != -1:
		var grabbed_player := _find_player_by_peer(target_peer_id)
		if grabbed_player != null and grabbed_player._is_local_authority():
			grabbed_player.grabbed_by = null
			grabbed_player._update_grab_ui()

	# Chat messages — only shown for player grabs AND if not silent
	if is_player and target_name != "" and not silent:
		var local_player := get_local_player()
		if local_player == null:
			return
		var local_peer := local_player.get_multiplayer_authority()
		if local_peer == grabber_peer_id:
			Sidebar.add_message("[color=#aaaaaa]You release " + target_name + ".[/color]")
		elif local_peer == target_peer_id:
			Sidebar.add_message("[color=#aaffaa]" + grabber_name + " releases you.[/color]")

@rpc("authority", "call_local", "reliable")
func rpc_confirm_resist_result(grabber_peer_id: int, grabbed_peer_id: int, broke_free: bool) -> void:
	var local_player := get_local_player()
	if local_player == null:
		return
	var local_peer := local_player.get_multiplayer_authority()

	if grabber_peer_id == -1:
		# Player pressed Z but was not being grabbed
		if local_peer == grabbed_peer_id:
			Sidebar.add_message("[color=#ffaaaa]You are not being grabbed.[/color]")
		return

	if broke_free:
		var grabber := _find_player_by_peer(grabber_peer_id)
		if grabber != null and grabber._is_local_authority():
			grabber.grabbed_target = null
			grabber.grab_hand_idx  = -1
			grabber._update_grab_ui()
		var grabbed := _find_player_by_peer(grabbed_peer_id)
		if grabbed != null and grabbed._is_local_authority():
			grabbed.grabbed_by = null
			grabbed._update_grab_ui()

		if local_peer == grabbed_peer_id:
			Sidebar.add_message("[color=#aaffaa]You broke free from the grab![/color]")
		elif local_peer == grabber_peer_id:
			Sidebar.add_message("[color=#ffaaaa]Your target broke free![/color]")
	else:
		if local_peer == grabbed_peer_id:
			Sidebar.add_message("[color=#ffaaaa]You failed to resist the grab.[/color]")

@rpc("authority", "call_local", "reliable")
func rpc_confirm_drag_object(obj_path: NodePath, new_pixel: Vector2) -> void:
	var obj := get_node_or_null(obj_path)
	if obj != null:
		obj.global_position = new_pixel

# ---------------------------------------------------------------------------
# Satchel Insert/Extract
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_satchel_insert(satchel_path: NodePath, hand_idx: int) -> void:
	if not multiplayer.is_server():
		return
	if hand_idx < 0 or hand_idx > 1:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()

	var player := _find_player_by_peer(peer_id)
	if player == null or player.dead:
		return

	var satchel := get_node_or_null(satchel_path)
	if satchel == null:
		return

	# Range check: satchel must be adjacent (or on same tile) to the player
	if not _is_within_interaction_range(player, satchel.global_position):
		return

	# The player must actually be holding something in that hand
	var item: Node = player.hands[hand_idx]
	if item == null or not is_instance_valid(item):
		return

	# Resolve item_type — use the item's own property if present, else strip @
	var itype: String = item.get("item_type") if item.get("item_type") != null else item.name.get_slice("@", 0)

	var scene_path: String = ItemRegistry.get_scene_path(itype)
	if scene_path == "":
		return

	# Find a free slot
	var slot_index: int = -1
	for i in satchel.contents.size():
		if satchel.contents[i] == null:
			slot_index = i
			break

	if slot_index == -1:
		# Satchel is full — do nothing
		return

	rpc_confirm_satchel_insert.rpc(peer_id, satchel_path, item.get_path(), hand_idx, slot_index, scene_path, itype)


@rpc("authority", "call_local", "reliable")
func rpc_confirm_satchel_insert(
		peer_id: int,
		satchel_path: NodePath,
		_item_path: NodePath,
		hand_idx: int,
		slot_index: int,
		scene_path: String,
		itype: String) -> void:

	var satchel: Node = get_node_or_null(satchel_path)
	if satchel == null:
		return

	# Write the slot data on every client so contents stays in sync
	if slot_index >= 0 and slot_index < satchel.contents.size():
		satchel.contents[slot_index] = {"scene_path": scene_path, "item_type": itype}

	# Clear the holding player's hand and destroy the item node on every client
	var player := _find_player_by_peer(peer_id)
	if player != null:
		if player.hands[hand_idx] != null and is_instance_valid(player.hands[hand_idx]):
			player.hands[hand_idx].queue_free()
		player.hands[hand_idx] = null
		if player._is_local_authority():
			player._update_hands_ui()

	# Refresh the satchel UI if it is open on this client
	if satchel.has_method("_refresh_ui"):
		satchel._refresh_ui()


# --- Extract ---

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_satchel_extract(satchel_path: NodePath, slot_index: int, hand_idx: int) -> void:
	if not multiplayer.is_server():
		return
	if hand_idx < 0 or hand_idx > 1:
		return
	if slot_index < 0 or slot_index >= 10:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()

	var player := _find_player_by_peer(peer_id)
	if player == null or player.dead:
		return

	# The destination hand must be empty
	if player.hands[hand_idx] != null:
		return

	var satchel := get_node_or_null(satchel_path)
	if satchel == null:
		return

	if not _is_within_interaction_range(player, satchel.global_position):
		return

	# Validate the slot has something in it
	if slot_index >= satchel.contents.size():
		return
	var slot = satchel.contents[slot_index]
	if slot == null:
		return

	var scene_path: String = slot.get("scene_path", "")
	if scene_path == "":
		return

	var new_node_name: String = "SatchelExtract_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000)

	rpc_confirm_satchel_extract.rpc(peer_id, satchel_path, slot_index, hand_idx, new_node_name, scene_path)


@rpc("authority", "call_local", "reliable")
func rpc_confirm_satchel_extract(
		peer_id: int,
		satchel_path: NodePath,
		slot_index: int,
		hand_idx: int,
		new_node_name: String,
		scene_path: String) -> void:

	var satchel: Node = get_node_or_null(satchel_path)
	if satchel == null:
		return

	# Clear the slot on every client
	if slot_index >= 0 and slot_index < satchel.contents.size():
		satchel.contents[slot_index] = null

	# Spawn the item and place it into the player's hand on every client
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return

	var item: Node2D = scene.instantiate()
	item.name = new_node_name

	# Position the item at the satchel's tile for sanity; it will be hidden
	# behind the hand-position logic as soon as the player processes a frame.
	item.position = satchel.global_position

	# Add to the scene tree (same parent as the satchel)
	satchel.get_parent().add_child(item)

	# Disable its collision so it doesn't litter the ground
	for child in item.get_children():
		if child is CollisionShape2D:
			child.disabled = true

	var player := _find_player_by_peer(peer_id)
	if player != null:
		player.hands[hand_idx] = item
		if player._is_local_authority():
			player._update_hands_ui()

	# Refresh the satchel UI if it is open on this client
	if satchel.has_method("_refresh_ui"):
		satchel._refresh_ui()
		
