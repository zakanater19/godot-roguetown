extends Node

const FOV_RADIUS := 12
const SOURCE_OFFSETS: Array =[
	Vector2( 0.0,   0.0),
	Vector2( 0.3,   0.3),
	Vector2(-0.3,   0.3),
	Vector2( 0.3,  -0.3),
	Vector2(-0.3,  -0.3),
]
const STEP_SIZE := 0.3

var _visible_tiles: Dictionary = {}
var _player_tile: Vector2i = Vector2i(-9999, -9999)
var _player_z: int = 3
var _draw_node: Node2D = null
var _time_since_update: float = 0.0

var _solid_cache: Dictionary = {}
var _precomputed_los: Dictionary = {}

func _ready() -> void:
	_precompute_rays()
	await get_tree().process_frame
	_draw_node = load("res://fov_draw.gd").new()
	# FIX: Godot's maximum CanvasItem z_index is 4096.
	_draw_node.z_index = 4000
	_draw_node.name = "FOVDraw"
	get_tree().root.add_child(_draw_node)

func _process(delta: float) -> void:
	if _draw_node == null: return
	var player = World.get_local_player()
	if player == null: return
	
	_time_since_update += delta
	var tile = player.tile_pos
	
	if tile != _player_tile or player.z_level != _player_z or _time_since_update >= 0.5:
		_player_tile = tile
		_player_z = player.z_level
		_time_since_update = 0.0
		_compute_fov()
		_draw_node.queue_redraw()

func _is_turf_opaque(tile: Vector2i) -> bool:
	if _solid_cache.has(tile):
		return _solid_cache[tile]
	var opaque = World.is_opaque(tile, _player_z)
	_solid_cache[tile] = opaque
	return opaque

func _precompute_rays() -> void:
	var r2: int = FOV_RADIUS * FOV_RADIUS
	for dy in range(-FOV_RADIUS, FOV_RADIUS + 1):
		for dx in range(-FOV_RADIUS, FOV_RADIUS + 1):
			if dx * dx + dy * dy > r2: continue
			var dest = Vector2i(dx, dy)
			_precomputed_los[dest] = _generate_ray_paths(dest)

func _generate_ray_paths(dest: Vector2i) -> Array:
	var rays = []
	var base_targets =[Vector2(dest.x + 0.5, dest.y + 0.5)]
	var extra_targets =[
		Vector2(dest.x + 0.1, dest.y + 0.1),
		Vector2(dest.x + 0.9, dest.y + 0.1),
		Vector2(dest.x + 0.1, dest.y + 0.9),
		Vector2(dest.x + 0.9, dest.y + 0.9)
	]
	
	for is_extra in [false, true]:
		var targs = extra_targets if is_extra else base_targets
		for tc in targs:
			for off in SOURCE_OFFSETS:
				var fc = Vector2(0.5 + off.x, 0.5 + off.y)
				var cells_to_check =[]
				var delta: Vector2 = tc - fc
				var dist: float = delta.length()
				if dist >= 0.001:
					var norm: Vector2 = delta / dist
					var from_tile := Vector2i(0, 0)
					var to_tile   := dest
					var prev_tile := from_tile
					var t: float = STEP_SIZE
					while t < dist - STEP_SIZE:
						var p: Vector2 = fc + norm * t
						var tile := Vector2i(int(floor(p.x)), int(floor(p.y)))
						if tile != from_tile and tile != to_tile:
							if cells_to_check.is_empty():
								cells_to_check.append(tile)
							else:
								var last = cells_to_check.back()
								if typeof(last) == TYPE_DICTIONARY or last != tile:
									cells_to_check.append(tile)
						if tile != prev_tile:
							if tile.x != prev_tile.x and tile.y != prev_tile.y:
								cells_to_check.append({
									"diag1": Vector2i(tile.x, prev_tile.y),
									"diag2": Vector2i(prev_tile.x, tile.y)
								})
							prev_tile = tile
						t += STEP_SIZE
				rays.append({
					"is_extra": is_extra,
					"cells": cells_to_check
				})
	return rays

func _has_los(from_tile: Vector2i, to_tile: Vector2i) -> bool:
	var dest = to_tile - from_tile
	if not _precomputed_los.has(dest): return false
	var dest_opaque = _is_turf_opaque(to_tile)
	
	for ray in _precomputed_los[dest]:
		if ray.is_extra and not dest_opaque:
			continue
			
		var ray_clear = true
		for cell in ray.cells:
			if typeof(cell) == TYPE_DICTIONARY:
				if _is_turf_opaque(from_tile + cell.diag1) and _is_turf_opaque(from_tile + cell.diag2):
					ray_clear = false
					break
			else:
				if _is_turf_opaque(from_tile + cell):
					ray_clear = false
					break
		if ray_clear:
			return true
			
	return false

func _compute_fov() -> void:
	_solid_cache.clear()
	_visible_tiles.clear()
	var r2: int = FOV_RADIUS * FOV_RADIUS
	for dy in range(-FOV_RADIUS, FOV_RADIUS + 1):
		for dx in range(-FOV_RADIUS, FOV_RADIUS + 1):
			if dx * dx + dy * dy > r2: continue
			var tile := _player_tile + Vector2i(dx, dy)
			if _has_los(_player_tile, tile): _visible_tiles[tile] = true
	_visible_tiles[_player_tile] = true
	_apply_fov_hiding()

func _apply_fov_hiding() -> void:
	var local_player = World.get_local_player()
	
	# OPTIMIZATION: Only search ONE group, and do Z-Level visibility testing here to avoid conflicts.
	for ent in get_tree().get_nodes_in_group("z_entity"):
		if ent == local_player: continue
		
		var ez = ent.get("z_level")
		if ez == null: continue
		
		var is_visible = false
		if ez > _player_z:
			# Entites on floors above the player are completely hidden
			is_visible = false
		else:
			# Entities on current or below floors use FOV logic
			var ent_tile := Vector2i(int(ent.global_position.x / 64.0), int(ent.global_position.y / 64.0))
			is_visible = _visible_tiles.has(ent_tile)
			
		if ent.has_method("_set_fov_visibility"):
			ent._set_fov_visibility(is_visible)
		else:
			# Avoid triggering engine redraws unless visibility status actually changed
			if "visible" in ent and ent.visible != is_visible:
				ent.visible = is_visible
			if "input_pickable" in ent and ent.get("input_pickable") != is_visible:
				ent.input_pickable = is_visible