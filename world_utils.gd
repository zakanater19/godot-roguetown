extends RefCounted

var world: Node

func _init(p_world: Node) -> void:
	world = p_world

func is_within_interaction_range(player: Node, target_pos: Vector2) -> bool:
	var target_tile = Vector2i(int(target_pos.x / world.TILE_SIZE), int(target_pos.y / world.TILE_SIZE))
	var diff = (target_tile - player.tile_pos).abs()
	return diff.x <= 1 and diff.y <= 1

func server_check_action_cooldown(player: Node, is_attack: bool = false) -> bool:
	var current_time = Time.get_ticks_msec()
	var peer_id = player.get_multiplayer_authority()
	var next_allowed = world.server_action_cooldowns.get(peer_id, 0)
	if current_time < next_allowed - 100: return false
	var delay = 0.5
	var held_item = player.hands[player.active_hand]
	if held_item != null and held_item.has_method("get_use_delay"): delay = held_item.get_use_delay()
	if is_attack and delay < 1.0: delay = 1.0
	if player.exhausted: delay *= 3.0
	world.server_action_cooldowns[peer_id] = current_time + int(delay * 1000)
	return true

func get_entities_at_tile(tile: Vector2i, z_level: int, exclude_peer: int = 0) -> Array:
	var result :=[]
	for npc in world.get_tree().get_nodes_in_group("npc"):
		if npc.z_level != z_level: continue
		if npc.tile_pos == tile:
			result.append(npc)
			continue
		if npc.get("moving") == true:
			var visual_tile := Vector2i(int(npc.global_position.x / world.TILE_SIZE), int(npc.global_position.y / world.TILE_SIZE))
			if visual_tile == tile: result.append(npc)
	for p in world.get_tree().get_nodes_in_group("player"):
		if p.z_level != z_level: continue
		if p.get_multiplayer_authority() == exclude_peer: continue
		if p.get("dead"): continue
		if p.tile_pos == tile:
			result.append(p)
			continue
		if p.get("moving") == true:
			var visual_tile := Vector2i(int(p.global_position.x / world.TILE_SIZE), int(p.global_position.y / world.TILE_SIZE))
			if visual_tile == tile: result.append(p)
	return result

func find_player_by_peer(peer_id: int) -> Node:
	for p in world.get_tree().get_nodes_in_group("player"):
		# Ignores unpossessed corpses so actions (grabbing/chatting) reliably 
		# target the currently possessed avatar of the given peer ID.
		if p.get_multiplayer_authority() == peer_id and p.get("is_possessed") != false:
			return p
	return null

func tile_to_pixel(t: Vector2i) -> Vector2:
	return Vector2((t.x + 0.5) * world.TILE_SIZE, (t.y + 0.5) * world.TILE_SIZE)

func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / world.TILE_SIZE), int(world_pos.y / world.TILE_SIZE))

func get_local_player() -> Node:
	if not world.multiplayer.has_multiplayer_peer(): return null
	var local_id = world.multiplayer.get_unique_id()
	return find_player_by_peer(local_id)

func cast_throw(from_tile: Vector2i, from_pixel: Vector2, z_level: int, dir: Vector2, max_tiles: int) -> Vector2i:
	if dir == Vector2.ZERO: return from_tile
	var ray_dir := dir.normalized()
	var map_check := from_tile
	var last_valid := from_tile
	var ray_start := from_pixel / float(world.TILE_SIZE)
	var ray_step_size := Vector2(1e30 if ray_dir.x == 0 else abs(1.0 / ray_dir.x), 1e30 if ray_dir.y == 0 else abs(1.0 / ray_dir.y))
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
	var max_dist := float(max_tiles)
	var current_dist := 0.0
	while current_dist < max_dist:
		if ray_length_1d.x < ray_length_1d.y:
			map_check.x += step.x
			current_dist = ray_length_1d.x
			ray_length_1d.x += ray_step_size.x
		else:
			map_check.y += step.y
			current_dist = ray_length_1d.y
			ray_length_1d.y += ray_step_size.y
		if map_check.x < 0 or map_check.x >= world.GRID_WIDTH or map_check.y < 0 or map_check.y >= world.GRID_HEIGHT: break
		if world.tiles.is_solid(map_check, z_level): return last_valid
		last_valid = map_check
	return last_valid

func find_path(start: Vector2i, target: Vector2i, z_level: int) -> Array[Vector2i]:
	var open: Array[Vector2i] = [start]
	var open_set := {start: true}
	var closed := {}
	var came_from := {}
	var g_score := {start: 0}
	var start_h: int = abs(start.x - target.x) + abs(start.y - target.y)
	var f_score := {start: start_h}
	var iterations := 0
	var max_iterations := 500
	var dirs_x: Array[int] =[1, -1, 0, 0]
	var dirs_y: Array[int] =[0, 0, 1, -1]
	var best_node := start
	var best_h: int = start_h
	while not open.is_empty():
		iterations += 1
		if iterations > max_iterations: return reconstruct_path(came_from, best_node)
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
		if current == target: return reconstruct_path(came_from, current)
		var last_node = open.pop_back()
		if current_idx < open.size(): open[current_idx] = last_node
		open_set.erase(current)
		closed[current] = true
		var current_g: int = g_score[current]
		var cx: int = current.x
		var cy: int = current.y
		for i in 4:
			var nx: int = cx + dirs_x[i]
			var ny: int = cy + dirs_y[i]
			var neighbor := Vector2i(nx, ny)
			if nx < 0 or nx >= world.GRID_WIDTH or ny < 0 or ny >= world.GRID_HEIGHT: continue
			if closed.has(neighbor): continue
			if neighbor != target and world.tiles.is_solid(neighbor, z_level): continue
			var tentative_g: int = current_g + 1
			if tentative_g < g_score.get(neighbor, 999999):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				var h: int = abs(nx - target.x) + abs(ny - target.y)
				f_score[neighbor] = tentative_g + h
				if h < best_h:
					best_h = h
					best_node = neighbor
				if not open_set.has(neighbor):
					open.append(neighbor)
					open_set[neighbor] = true
	return[]

func reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] =[]
	path.append(current)
	while came_from.has(current):
		current = came_from[current]
		path.append(current)
	path.reverse()
	if not path.is_empty(): path.remove_at(0)
	return path

func handle_rpc_request_update_laws(sender_id: int, new_laws: Array) -> void:
	if not world.multiplayer.is_server(): return
	var player = find_player_by_peer(sender_id)
	if player == null or player.get("character_class") != "king": return
	world.rpc_update_laws.rpc(new_laws)

func handle_rpc_update_laws(new_laws: Array) -> void:
	world.current_laws = new_laws
	if world.has_node("/root/Sidebar"):
		var sidebar = world.get_node("/root/Sidebar")
		if sidebar.has_method("refresh_laws_ui"): sidebar.refresh_laws_ui()

func handle_rpc_send_chat(sender_id: int, message: String) -> void:
	if not world.multiplayer.is_server(): return
	var sender := find_player_by_peer(sender_id)
	if sender == null: return
	world.rpc_broadcast_chat.rpc(sender_id, message, sender.get("tile_pos"), sender.get("z_level"))

func handle_rpc_broadcast_chat(sender_peer_id: int, message: String, sender_tile: Vector2i, sender_z: int) -> void:
	var local_player := get_local_player()
	if local_player == null: return
	if local_player.get("z_level") != sender_z: return
	var diff: Vector2i = local_player.get("tile_pos") - sender_tile
	if diff.length_squared() > 144: return
	var sender_node = find_player_by_peer(sender_peer_id)
	if sender_node == null: return
	if local_player.get("sleep_state") == 2:
		if world.has_node("/root/Sidebar"):
			world.get_node("/root/Sidebar").add_message("[color=#aaaaaa]you hear someone talking...[/color]")
		return
	if sender_node.has_method("_show_chat_message"): sender_node._show_chat_message(message)
	if local_player.has_method("_show_inspect_text"): local_player._show_inspect_text(sender_node.get("character_name") + " says: " + message, "")

func handle_rpc_broadcast_damage_log(attacker_name: String, target_name: String, amount: int, source_tile: Vector2i, source_z: int, blocked: bool, is_shove: bool, targeted_limb: String, block_type: String) -> void:
	var local_player := get_local_player()
	if local_player == null: return
	if local_player.get("z_level") != source_z: return
	var diff: Vector2i = local_player.get("tile_pos") - source_tile
	if diff.length_squared() > 144: return
	var Sidebar = world.get_node("/root/Sidebar") if world.has_node("/root/Sidebar") else null
	if Sidebar == null: return
	if local_player.get("sleep_state") == 2:
		if target_name == local_player.get("character_name"): Sidebar.add_message("[color=#ff0000][b]YOU FEEL PAIN!!![/b][/color]")
		else: Sidebar.add_message("[color=#aaaaaa]you hear a scuffle...[/color]")
		return
	var disp_attacker = "You" if attacker_name == local_player.get("character_name") else attacker_name
	var disp_target = "You" if target_name == local_player.get("character_name") else target_name
	var limb_str = targeted_limb
	match targeted_limb:
		"r_arm": limb_str = "right arm"
		"l_arm": limb_str = "left arm"
		"r_leg": limb_str = "right leg"
		"l_leg": limb_str = "left leg"
	var log_text = ""
	if is_shove: log_text = "[color=#ffcc00][font_size=14]" + disp_attacker + " shoved " + disp_target + "![/font_size][/color]"
	elif blocked: log_text = "[color=#aaaaaa][font_size=14]" + disp_target + " " + ("parried" if block_type == "parried" else "dodged") + " " + disp_attacker + "'s attack![/font_size][/color]"
	else:
		if limb_str != "": log_text = "[color=#ff4444][font_size=14]" + disp_attacker + " hit " + disp_target + " in the " + limb_str + " for " + str(amount) + " damage[/font_size][/color]"
		else: log_text = "[color=#ff4444][font_size=14]" + disp_attacker + " hit " + disp_target + " for " + str(amount) + " damage[/font_size][/color]"
	Sidebar.add_message(log_text)