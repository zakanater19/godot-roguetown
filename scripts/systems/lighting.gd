# res://scripts/systems/lighting.gd
# AutoLoad singleton — registered as "Lighting" in project.godot
# Handles the global day/night cycle, top-down z-level shadows, and lights.
extends Node

signal sun_weight_updated(weight: float)

var current_day: int = 1
var time_offset: float = 0.0
var time_multiplier: float = 1.0
var sun_weight: float = 1.0

# 20 min day (1200s) + 20 min night (1200s) = 2400s cycle
# Transition is 5 minutes (300s)
const CYCLE_DURATION: float = 2400.0
const TRANSITION_DURATION: float = 300.0

var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.25

var _last_sun_weight: float = -1.0
var _last_player_z: int = -1

# CPU Shadow mapping variables
var roof_map_image: Image
var active_lamps: Array[Node] =[]

# Precalculated kernel for CPU blur — surface only (z >= 3)
var _blur_weights: Dictionary = {}

# How many tiles stair light bleeds into the underground
const STAIR_BLEED_TILES: float = 5.0

# Node to handle drawing the CPU-calculated light blocks
class LightDrawNode extends Node2D:
	var light_cache: Dictionary = {}
	func _draw() -> void:
		for tile in light_cache:
			var light_level = light_cache[tile]
			var alpha = 1.0 - light_level
			if alpha > 0.0:
				draw_rect(Rect2(tile.x * 64, tile.y * 64, 64, 64), Color(0, 0, 0, alpha))

var _draw_node: LightDrawNode = null
# Light cache excluding the local player's personal vision radius (used for sneak checks)
var world_light_cache: Dictionary = {}

func _ready() -> void:
	# 1. Setup the heightmap image tracking opaque blocks on the CPU
	# r channel = highest wall/opaque Z-level
	# g channel = highest floor/any tile Z-level
	roof_map_image = Image.create(1000, 1000, false, Image.FORMAT_RG8)
	roof_map_image.fill(Color(0, 0, 0, 1))

	# 2. Precalculate the tight 7x7 (3 tile radius) blur kernel for soft local shadows (e.g., trees)
	for sy in range(-3, 4):
		for sx in range(-3, 4):
			var dist = Vector2(sx, sy).length()
			if dist <= 3.5:
				_blur_weights[Vector2i(sx, sy)] = 1.0 / (1.0 + dist * dist)

	# 3. Setup the drawing node for our CPU shadows
	_draw_node = LightDrawNode.new()
	_draw_node.name = "GlobalLightMap"
	_draw_node.position = Vector2.ZERO
	_draw_node.z_index = 3998
	add_child(_draw_node)

func get_tile_light(tile: Vector2i) -> float:
	if _draw_node == null: return 1.0
	return _draw_node.light_cache.get(tile, 1.0)

func get_tile_world_light(tile: Vector2i) -> float:
	return world_light_cache.get(tile, 1.0)

func register_lamp(lamp: Node) -> void:
	if not active_lamps.has(lamp): active_lamps.append(lamp)

func unregister_lamp(lamp: Node) -> void:
	active_lamps.erase(lamp)

func rebuild_roof_map() -> void:
	var roof_data = PackedByteArray()
	roof_data.resize(1000 * 1000 * 2)
	roof_data.fill(0)

	# 1. Iterate over used cells in TileMapLayers
	for z in range(1, 6):
		var tm = World.get_tilemap(z)
		if tm != null:
			var used_cells = tm.get_used_cells()
			for pos in used_cells:
				if pos.x >= 0 and pos.x < 1000 and pos.y >= 0 and pos.y < 1000:
					var source_id = tm.get_cell_source_id(pos)
					if source_id != -1:
						# Stair tiles (source_id == 2) are treated as air:
						# they do not block light or count as a roof for levels below.
						if source_id == 2:
							continue

						var idx = (pos.y * 1000 + pos.x) * 2
						var is_op = TileDefs.is_opaque(source_id, tm.get_cell_atlas_coords(pos))
						
						# Mark opacity if opaque
						if is_op:
							if z > roof_data[idx]: roof_data[idx] = z
							
						# All non-stair tiles count as a roof for levels below them
						if z > roof_data[idx + 1]: roof_data[idx + 1] = z

	# 2. Iterate over solid_grid for dynamic opaque objects
	for z in range(1, 6):
		if World.solid_grid.has(z):
			for pos in World.solid_grid[z].keys():
				if pos.x >= 0 and pos.x < 1000 and pos.y >= 0 and pos.y < 1000:
					var is_op = false
					var valid_objs: Array = []
					for obj in World.solid_grid[z][pos]:
						if not is_instance_valid(obj):
							continue
						valid_objs.append(obj)
						if obj.get("blocks_fov") == null or obj.get("blocks_fov") == true:
							is_op = true
							break
					World.solid_grid[z][pos] = valid_objs
					if is_op:
						var idx = (pos.y * 1000 + pos.x) * 2
						if z > roof_data[idx]: roof_data[idx] = z
						if z > roof_data[idx + 1]: roof_data[idx + 1] = z

	roof_map_image = Image.create_from_data(1000, 1000, false, Image.FORMAT_RG8, roof_data)

func update_roof_map_at(pos: Vector2i) -> void:
	if pos.x < 0 or pos.x >= 1000 or pos.y < 0 or pos.y >= 1000: return
	var highest_wall_z = 0
	var highest_floor_z = 0

	for z in range(5, 0, -1):
		var tm = World.get_tilemap(z)
		var source_id = -1 if tm == null else tm.get_cell_source_id(pos)

		# Stair tiles (source_id == 2) are treated as air — skip them entirely
		if source_id == 2:
			continue

		var atlas_coords := Vector2i(-1, -1) if tm == null else tm.get_cell_atlas_coords(pos)
		var is_opaque = false
		if source_id == 1:
			if TileDefs.is_opaque(source_id, atlas_coords):
				is_opaque = true
		elif World.solid_grid.has(z) and World.solid_grid[z].has(pos):
			var valid_objs: Array = []
			for obj in World.solid_grid[z][pos]:
				if not is_instance_valid(obj):
					continue
				valid_objs.append(obj)
				if obj.get("blocks_fov") == null or obj.get("blocks_fov") == true:
					is_opaque = true
					break
			World.solid_grid[z][pos] = valid_objs

		# Any non-stair tile acts as a floor, but only opaque tiles act as roofs
		if source_id != -1 and highest_floor_z == 0:
			highest_floor_z = z

		if is_opaque and highest_wall_z == 0:
			highest_wall_z = z
			if highest_floor_z == 0: highest_floor_z = z

		if highest_wall_z > 0 and highest_floor_z > 0:
			break

	var new_col = Color(highest_wall_z / 255.0, highest_floor_z / 255.0, 0, 1)
	if roof_map_image.get_pixel(pos.x, pos.y) != new_col:
		roof_map_image.set_pixel(pos.x, pos.y, new_col)

# Helper function to see if light can travel vertically between two Z levels at a specific tile
func _can_light_pass_z(pos: Vector2i, z1: int, z2: int) -> bool:
	var z_min = min(z1, z2)
	var z_max = max(z1, z2)
	
	# Check all levels between the bottom and the top
	for z in range(z_min + 1, z_max + 1):
		var tm = World.get_tilemap(z)
		if tm != null:
			var src = tm.get_cell_source_id(pos)
			# 2 is stairs, -1 is air. Any other floor blocks vertical light.
			if src != -1 and src != 2: 
				return false
				
		# Also check if there's a solid/opaque object blocking the hole
		if World.is_opaque(pos, z):
			return false
			
	return true

# Robust grid traversal (Bresenham) to prevent corner snagging clipping point lights
func _is_line_blocked(start_px: Vector2, end_px: Vector2, check_z: int) -> bool:
	var x0 = int(floor(start_px.x / 64.0))
	var y0 = int(floor(start_px.y / 64.0))
	var x1 = int(floor(end_px.x / 64.0))
	var y1 = int(floor(end_px.y / 64.0))
	
	if x0 == x1 and y0 == y1:
		return false
		
	var dx = abs(x1 - x0)
	var dy = -abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx + dy
	
	var start_x = x0
	var start_y = y0
	
	while true:
		if x0 == x1 and y0 == y1:
			break
			
		# Do not check the origin tile so dropped lamps don't cast shadows on themselves
		if x0 != start_x or y0 != start_y:
			if World.is_opaque(Vector2i(x0, y0), check_z):
				return true
				
		var e2 = 2 * err
		if e2 >= dy:
			if x0 == x1: break
			err += dy
			x0 += sx
		if e2 <= dx:
			if y0 == y1: break
			err += dx
			y0 += sy
			
	return false

func invalidate_local_lighting() -> void:
	_last_player_z = -1
	_update_timer = UPDATE_INTERVAL

func refresh_local_lighting() -> void:
	invalidate_local_lighting()
	_rebuild_local_light_cache()

func _process(delta: float) -> void:
	# --- TIME CYCLE LOGIC ---
	var total_time = Lobby.round_time + time_offset
	current_day = 1 + int(total_time / CYCLE_DURATION)
	var cycle_time = fmod(total_time, CYCLE_DURATION)

	var new_sun_weight: float = 1.0
	if cycle_time >= 900.0 and cycle_time < 1200.0:
		new_sun_weight = 1.0 - ((cycle_time - 900.0) / TRANSITION_DURATION)
	elif cycle_time >= 1200.0 and cycle_time < 2100.0:
		new_sun_weight = 0.0
	elif cycle_time >= 2100.0:
		new_sun_weight = (cycle_time - 2100.0) / TRANSITION_DURATION

	if abs(new_sun_weight - _last_sun_weight) > 0.0005:
		sun_weight = new_sun_weight
		_last_sun_weight = new_sun_weight
		sun_weight_updated.emit(sun_weight)

	# --- CPU LIGHTING CALCULATION THROTTLE ---
	_update_timer += delta
	if _update_timer < UPDATE_INTERVAL:
		return
	_update_timer = 0.0

	_rebuild_local_light_cache()

func _rebuild_local_light_cache() -> void:
	if _draw_node == null:
		return

	var local_player = World.get_local_player()
	var current_z = 3
	var player_pos = Vector2(-9999, -9999)
	var player_tile = Vector2i(-9999, -9999)

	if local_player != null:
		current_z = local_player.z_level
		player_pos = local_player.global_position
		player_tile = local_player.tile_pos
		_last_player_z = current_z

	# Gather active lamps and categorize them by Z-level
	var valid_lamps: Array[Node] =[]
	var same_z_lamps: Array[Dictionary] =[]
	var other_z_lamps: Array[Dictionary] =[]

	for lamp in active_lamps:
		if is_instance_valid(lamp):
			valid_lamps.append(lamp)
			if lamp.is_on and local_player != null:
				var li: float = lamp.get("light_intensity") if lamp.get("light_intensity") != null else 1.0
				if lamp.z_level == current_z:
					if same_z_lamps.size() < 30:
						same_z_lamps.append({"pos": lamp.global_position, "intensity": li})
				else:
					if other_z_lamps.size() < 15:
						other_z_lamps.append({"pos": lamp.global_position, "z": lamp.z_level, "intensity": li})
	active_lamps = valid_lamps

	# --- TILE GRID CPU LIGHTING ---
	var new_cache: Dictionary = {}
	var roof_data := roof_map_image.get_data()

	if player_tile != Vector2i(-9999, -9999):
		var ambient = 0.0

		var view_radius_x = 16
		var view_radius_y = 11

		var is_underground = current_z < 3
		var valid_holes_for_lamps: Array =[]
		var sunlight_dist: Dictionary = {}

		# Flood Fill (BFS) to softly scatter daylight around corners and through windows
		if sun_weight > 0.001:
			var ext_rx = 20
			var ext_ry = 15
			var queue =[]
			
			# 1. Identify light sources (Unroofed tiles, windows, doors)
			for dy in range(-ext_ry, ext_ry + 1):
				for dx in range(-ext_rx, ext_rx + 1):
					var t = player_tile + Vector2i(dx, dy)
					if t.x < 0 or t.x >= 1000 or t.y < 0 or t.y >= 1000:
						continue
						
					var idx = (t.y * 1000 + t.x) * 2
					var wz = roof_data[idx]
					var fz = roof_data[idx + 1]
					
					var is_roofed = false
					# Solid walls don't emit scattered light. Only air/windows/doors.
					if is_underground:
						is_roofed = (fz > current_z or wz >= current_z)
					else:
						is_roofed = (wz >= current_z or fz > current_z)
					
					var tm = World.get_tilemap(current_z)
					var is_window = (tm != null and tm.get_cell_source_id(t) == 1 and tm.get_cell_atlas_coords(t) == Vector2i(10, 0))
					if is_window: is_roofed = false
					
					if not is_roofed:
						sunlight_dist[t] = 0.0
						queue.append(t)
						
			# 2. Propagate the light outward like a fluid
			var dirs =[
				Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
			]
			var dists =[1.0, 1.0, 1.0, 1.0, 1.414, 1.414, 1.414, 1.414]
			
			var head = 0
			while head < queue.size():
				var curr = queue[head]
				head += 1
				var d = sunlight_dist[curr]
				
				# Max light propagation distance (optimization)
				if d > 12.0: continue
				
				for i in range(8):
					var n = curr + dirs[i]
					if n.x < 0 or n.x >= 1000 or n.y < 0 or n.y >= 1000: continue
					if abs(n.x - player_tile.x) > ext_rx or abs(n.y - player_tile.y) > ext_ry: continue
					
					# Avoid light leaking diagonally through tight solid corners
					if i >= 4:
						var w1 = curr + Vector2i(dirs[i].x, 0)
						var w2 = curr + Vector2i(0, dirs[i].y)
						var tm = World.get_tilemap(current_z)
						var w1_op = false
						var w2_op = false
						if tm != null:
							if tm.get_cell_source_id(w1) == 1 and TileDefs.is_opaque(1, tm.get_cell_atlas_coords(w1)): w1_op = true
							if tm.get_cell_source_id(w2) == 1 and TileDefs.is_opaque(1, tm.get_cell_atlas_coords(w2)): w2_op = true
						if w1_op and w2_op:
							continue
					
					var nd = d + dists[i]
					if not sunlight_dist.has(n) or nd < sunlight_dist[n]:
						sunlight_dist[n] = nd
						
						# Check opacity to see if light can keep traveling through this tile
						var tm = World.get_tilemap(current_z)
						var src = -1 if tm == null else tm.get_cell_source_id(n)
						var coords = Vector2i(-1, -1) if tm == null else tm.get_cell_atlas_coords(n)
						
						var n_is_window = (src == 1 and coords == Vector2i(10, 0))
						var n_is_opaque = false
						if src == 1:
							if TileDefs.is_opaque(src, coords): n_is_opaque = true
						elif World.solid_grid.has(current_z) and World.solid_grid[current_z].has(n):
							var valid_objs: Array = []
							for obj in World.solid_grid[current_z][n]:
								if not is_instance_valid(obj):
									continue
								valid_objs.append(obj)
								if obj.get("blocks_fov") == null or obj.get("blocks_fov") == true:
									n_is_opaque = true
									break
							World.solid_grid[current_z][n] = valid_objs
									
						if not n_is_opaque or n_is_window:
							queue.append(n)
						
		# Scan view radius for lamp transit holes
		if not other_z_lamps.is_empty():
			for dy in range(-view_radius_y, view_radius_y + 1):
				for dx in range(-view_radius_x, view_radius_x + 1):
					var check = player_tile + Vector2i(dx, dy)
					if check.x < 0 or check.x >= 1000 or check.y < 0 or check.y >= 1000:
						continue
					
					var check_px = Vector2(check.x * 64 + 32, check.y * 64 + 32)
					for l_info in other_z_lamps:
						var d_lamp = l_info.pos.distance_to(check_px)
						if d_lamp < 450.0:
							if _can_light_pass_z(check, current_z, l_info.z):
								if not _is_line_blocked(l_info.pos, check_px, l_info.z):
									valid_holes_for_lamps.append({
										"op_px": check_px,
										"lamp_pos": l_info.pos,
										"d_lamp": d_lamp,
										"intensity": l_info.intensity
									})

		# Main rendering loop
		for dy in range(-view_radius_y, view_radius_y + 1):
			for dx in range(-view_radius_x, view_radius_x + 1):
				var tile = player_tile + Vector2i(dx, dy)

				# Out of bounds check
				if tile.x < 0 or tile.x >= 1000 or tile.y < 0 or tile.y >= 1000:
					new_cache[tile] = ambient
					continue

				var idx = (tile.y * 1000 + tile.x) * 2
				var wall_z = roof_data[idx]
				var floor_z = roof_data[idx + 1]

				var is_roofed = (wall_z > current_z) or (floor_z > current_z)
				
				# Check for window transparency directly
				var tm = World.get_tilemap(current_z)
				var is_window = (tm != null and tm.get_cell_source_id(tile) == 1 and tm.get_cell_atlas_coords(tile) == Vector2i(10, 0))
				if is_window: is_roofed = false

				var sunlight: float = 0.0
				var global_px = Vector2(tile.x * 64 + 32, tile.y * 64 + 32)

				if is_underground:
					var dist = sunlight_dist.get(tile, 9999.0)
					sunlight = sun_weight * (1.0 - smoothstep(0.0, STAIR_BLEED_TILES, dist))
				else:
					# Surface lighting
					if not is_roofed:
						sunlight = sun_weight
					elif sun_weight < 0.001:
						sunlight = 0.0
					else:
						# 1. Soft local shadows (e.g. for trees)
						var shadow: float = 0.0
						var total_weight: float = 0.0

						for offset in _blur_weights:
							var cx = tile.x + offset.x
							var cy = tile.y + offset.y

							if cx < 0 or cx >= 1000 or cy < 0 or cy >= 1000:
								continue

							var c_idx = (cy * 1000 + cx) * 2
							var c_wall_z = roof_data[c_idx]
							var c_floor_z = roof_data[c_idx + 1]

							# Blocks light bleed if it's an opaque wall/roof
							var is_c_roofed = (c_wall_z >= current_z or c_floor_z > current_z)
							
							# Override for transparent windows
							var c_tm = World.get_tilemap(current_z)
							var is_c_window = (c_tm != null and c_tm.get_cell_source_id(Vector2i(cx, cy)) == 1 and c_tm.get_cell_atlas_coords(Vector2i(cx, cy)) == Vector2i(10, 0))
							if is_c_window: is_c_roofed = false
							
							var block = 1.0 if is_c_roofed else 0.0
							var w = _blur_weights[offset]

							shadow += block * w
							total_weight += w

						shadow /= total_weight
						
						# 2. Add BFS scattered sunlight. 
						# Full light out to 3.5 tiles, beautifully fading out to shadow at 8.5 tiles.
						var dist = sunlight_dist.get(tile, 9999.0)
						var bleed = 1.0 - smoothstep(3.5, 8.5, dist)
						
						# Softly blend the shadow away based on how much light bleeds in
						shadow = lerp(shadow, 0.0, bleed)
						
						sunlight = (1.0 - shadow) * sun_weight

				# Lamp light distance calculation (Same Z)
				var lamplight = 0.0
				for l_data in same_z_lamps:
					var d = global_px.distance_to(l_data.pos)
					if d < 450.0:
						if not _is_line_blocked(l_data.pos, global_px, current_z):
							var intensity = (1.0 - smoothstep(150.0, 450.0, d)) * l_data.intensity
							lamplight = max(lamplight, intensity)

				# Lamp light filtering up/down from transit holes (Other Z-levels)
				for hole_info in valid_holes_for_lamps:
					var d_hole = hole_info.op_px.distance_to(global_px)
					var total_d = hole_info.d_lamp + d_hole
					if total_d < 450.0:
						if not _is_line_blocked(hole_info.op_px, global_px, current_z):
							var intensity = (1.0 - smoothstep(150.0, 450.0, total_d)) * hole_info.intensity
							lamplight = max(lamplight, intensity)

				# Personal player light
				var player_light = 0.0
				var pd = global_px.distance_to(player_pos)
				if pd < 192.0:
					if not _is_line_blocked(player_pos, global_px, current_z):
						player_light = 0.30 * (1.0 - smoothstep(32.0, 192.0, pd))

				var combined_light = max(sunlight, max(lamplight, player_light))
				var final_light = clamp(ambient + combined_light, 0.0, 1.0)

				new_cache[tile] = final_light

				# World light: same but without personal player vision light
				var world_combined = max(sunlight, lamplight)
				new_cache[tile] = final_light
				world_light_cache[tile] = clamp(ambient + world_combined, 0.0, 1.0)

	# Submit to draw node
	_draw_node.light_cache = new_cache
	_draw_node.queue_redraw()

# Called by the UI button
func toggle_time_of_day() -> void:
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			rpc_add_time_offset.rpc(1200.0)
		else:
			request_toggle_time.rpc_id(1)
	else:
		time_offset += 1200.0

@rpc("any_peer", "call_local", "reliable")
func request_toggle_time() -> void:
	if multiplayer.is_server():
		rpc_add_time_offset.rpc(1200.0)

@rpc("authority", "call_local", "reliable")
func rpc_add_time_offset(amount: float) -> void:
	time_offset += amount

@rpc("authority", "call_local", "reliable")
func sync_time_multiplier(val: float) -> void:
	time_multiplier = val
