# res://lighting.gd
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

func _ready() -> void:
	# 1. Setup the heightmap image tracking opaque blocks on the CPU
	# r channel = highest wall/opaque Z-level
	# g channel = highest floor/any tile Z-level
	roof_map_image = Image.create(1000, 1000, false, Image.FORMAT_RG8)
	roof_map_image.fill(Color(0, 0, 0, 1))

	# 2. Precalculate the 11x11 (5 tile radius) blur kernel for sun bleed on the surface
	for sy in range(-5, 6):
		for sx in range(-5, 6):
			var dist = Vector2(sx, sy).length()
			if dist <= 5.5:
				_blur_weights[Vector2i(sx, sy)] = 1.0 / (1.0 + dist * dist)

	# 3. Setup the drawing node for our CPU shadows
	_draw_node = LightDrawNode.new()
	_draw_node.name = "GlobalLightMap"
	_draw_node.position = Vector2.ZERO
	_draw_node.z_index = 3998
	add_child(_draw_node)

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
						if source_id == 1:
							if z > roof_data[idx]: roof_data[idx] = z
						# All non-stair tiles count as a roof for levels below them
						if z > roof_data[idx + 1]: roof_data[idx + 1] = z

	# 2. Iterate over solid_grid for dynamic opaque objects
	for z in range(1, 6):
		if World.solid_grid.has(z):
			for pos in World.solid_grid[z].keys():
				if pos.x >= 0 and pos.x < 1000 and pos.y >= 0 and pos.y < 1000:
					var is_op = false
					for obj in World.solid_grid[z][pos]:
						if obj.get("blocks_fov") == null or obj.get("blocks_fov") == true:
							is_op = true
							break
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

		# Any non-stair tile acts as a floor/roof
		if source_id != -1 and highest_floor_z == 0:
			highest_floor_z = z

		var is_opaque = false
		if source_id == 1:
			is_opaque = true
		elif World.solid_grid.has(z) and World.solid_grid[z].has(pos):
			for obj in World.solid_grid[z][pos]:
				if obj.get("blocks_fov") == null or obj.get("blocks_fov") == true:
					is_opaque = true
					break

		if is_opaque and highest_wall_z == 0:
			highest_wall_z = z
			# An opaque tile also implicitly acts as a roof/floor if we didn't find one yet
			if highest_floor_z == 0:
				highest_floor_z = z

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

# Robust grid traversal (Bresenham) to prevent corner snagging clipping the light
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
	var same_z_lamps: PackedVector2Array = PackedVector2Array()
	var other_z_lamps: Array[Dictionary] =[]

	for lamp in active_lamps:
		if is_instance_valid(lamp):
			valid_lamps.append(lamp)
			if lamp.is_on and local_player != null:
				if lamp.z_level == current_z:
					if same_z_lamps.size() < 30:
						same_z_lamps.append(lamp.global_position)
				else:
					if other_z_lamps.size() < 15:
						other_z_lamps.append({"pos": lamp.global_position, "z": lamp.z_level})
	active_lamps = valid_lamps

	# --- TILE GRID CPU LIGHTING ---
	var new_cache: Dictionary = {}
	var roof_data := roof_map_image.get_data()

	if player_tile != Vector2i(-9999, -9999):
		var ambient = 0.04

		var view_radius_x = 16
		var view_radius_y = 11

		var is_underground = current_z < 3
		var sun_open_positions: Array[Vector2i] =[]
		var valid_holes_for_lamps: Array =[]

		# Scan view radius for sunlight holes (roof_data)
		if is_underground and sun_weight > 0.001:
			for dy in range(-view_radius_y, view_radius_y + 1):
				for dx in range(-view_radius_x, view_radius_x + 1):
					var check = player_tile + Vector2i(dx, dy)
					if check.x < 0 or check.x >= 1000 or check.y < 0 or check.y >= 1000:
						continue
					var idx = (check.y * 1000 + check.x) * 2
					var wz = roof_data[idx]
					var fz = roof_data[idx + 1]
					# An open position has no ceiling above current_z and no wall blocking.
					# Stair tiles have fz == 0 and wz == 0, so they always pass this check.
					if fz <= current_z and wz < current_z:
						sun_open_positions.append(check)
						
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
										"d_lamp": d_lamp
									})

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
				var sunlight: float = 0.0
				var global_px = Vector2(tile.x * 64 + 32, tile.y * 64 + 32)

				if is_underground:
					# Underground: no kernel. Sunlight bleeds from holes.
					if not sun_open_positions.is_empty() and sun_weight > 0.001:
						var min_dist_sq = 999999.0
						var closest_op = Vector2i(-9999, -9999)
						for op in sun_open_positions:
							var ddx = tile.x - op.x
							var ddy = tile.y - op.y
							var dsq = float(ddx * ddx + ddy * ddy)
							if dsq < min_dist_sq:
								min_dist_sq = dsq
								closest_op = op
						var min_dist = sqrt(min_dist_sq)
						if min_dist < STAIR_BLEED_TILES:
							var op_px = Vector2(closest_op.x * 64 + 32, closest_op.y * 64 + 32)
							if not _is_line_blocked(global_px, op_px, current_z):
								sunlight = sun_weight * (1.0 - smoothstep(0.0, STAIR_BLEED_TILES, min_dist))
				else:
					# Surface lighting
					if not is_roofed:
						# Direct sunlight, skip blur
						sunlight = sun_weight
					elif sun_weight < 0.001:
						# Night — nothing to bleed
						sunlight = 0.0
					else:
						# Roofed surface tile — run blur kernel for soft shadow edges
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

							# Blocks horizontal light bleed if it's an opaque wall at/above current Z,
							# OR if it's a floor strictly above current Z (i.e. an indoor tile).
							# Stair positions have floor_z == 0 and will not block.
							var block = 1.0 if (c_wall_z >= current_z or c_floor_z > current_z) else 0.0
							var w = _blur_weights[offset]

							shadow += block * w
							total_weight += w

						shadow /= total_weight
						sunlight = (1.0 - shadow) * sun_weight

				# Lamp light distance calculation (Same Z)
				var lamplight = 0.0
				for l_pos in same_z_lamps:
					var d = global_px.distance_to(l_pos)
					if d < 450.0:
						if not _is_line_blocked(l_pos, global_px, current_z):
							var intensity = 1.0 - smoothstep(150.0, 450.0, d)
							lamplight = max(lamplight, intensity)

				# Lamp light filtering up/down from transit holes (Other Z-levels)
				for hole_info in valid_holes_for_lamps:
					var d_hole = hole_info.op_px.distance_to(global_px)
					var total_d = hole_info.d_lamp + d_hole
					if total_d < 450.0:
						if not _is_line_blocked(hole_info.op_px, global_px, current_z):
							var intensity = 1.0 - smoothstep(150.0, 450.0, total_d)
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