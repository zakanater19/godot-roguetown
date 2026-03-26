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

func _ready() -> void:
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

func _is_turf_solid(tile: Vector2i) -> bool:
	if _solid_cache.has(tile):
		return _solid_cache[tile]
	var solid = World.is_solid(tile, _player_z)
	_solid_cache[tile] = solid
	return solid

func _ray_clear(from: Vector2, to: Vector2) -> bool:
	var delta: Vector2 = to - from
	var dist: float = delta.length()
	if dist < 0.001: return true
	var norm: Vector2 = delta / dist
	var from_tile := Vector2i(int(floor(from.x)), int(floor(from.y)))
	var to_tile   := Vector2i(int(floor(to.x)),   int(floor(to.y)))
	var prev_tile := from_tile
	var t: float = STEP_SIZE
	while t < dist - STEP_SIZE:
		var p: Vector2 = from + norm * t
		var tile := Vector2i(int(floor(p.x)), int(floor(p.y)))
		if tile != from_tile and tile != to_tile:
			if _is_turf_solid(tile): return false
		if tile != prev_tile:
			if tile.x != prev_tile.x and tile.y != prev_tile.y:
				if _is_turf_solid(Vector2i(tile.x, prev_tile.y)) and _is_turf_solid(Vector2i(prev_tile.x, tile.y)):
					return false
			prev_tile = tile
		t += STEP_SIZE
	return true

func _has_los(from_tile: Vector2i, to_tile: Vector2i) -> bool:
	var targets: Array =[Vector2(to_tile.x + 0.5, to_tile.y + 0.5)]
	if _is_turf_solid(to_tile):
		targets.append(Vector2(to_tile.x + 0.1, to_tile.y + 0.1))
		targets.append(Vector2(to_tile.x + 0.9, to_tile.y + 0.1))
		targets.append(Vector2(to_tile.x + 0.1, to_tile.y + 0.9))
		targets.append(Vector2(to_tile.x + 0.9, to_tile.y + 0.9))
	for tc in targets:
		for off in SOURCE_OFFSETS:
			var fc := Vector2(from_tile.x + 0.5 + off.x, from_tile.y + 0.5 + off.y)
			if _ray_clear(fc, tc): return true
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
	var target_groups =["player", "npc", "pickable", "minable_object", "choppable_object", "door", "breakable_object", "inspectable", "bed"]
	var local_player = World.get_local_player()
	
	for g in target_groups:
		for ent in get_tree().get_nodes_in_group(g):
			if ent == local_player: continue
			# Don't try to hide objects outside our Z layer via FOV (Main.gd handles macro visibility)
			if ent.get("z_level") != null and ent.z_level != _player_z: continue
			var ent_tile := Vector2i(int(ent.global_position.x / 64.0), int(ent.global_position.y / 64.0))
			var is_visible = _visible_tiles.has(ent_tile)
			if "visible" in ent: ent.visible = is_visible
			if "input_pickable" in ent: ent.input_pickable = is_visible
