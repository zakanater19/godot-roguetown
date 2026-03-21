@tool
extends Node2D

# --- CONFIGURATION ---
# TILE_SIZE / GRID_WIDTH / GRID_HEIGHT live in world.gd (the World autoload).
# Reference them via World.TILE_SIZE etc. rather than defining duplicates here.

const SHOW_OUTLINES: bool  = true
const OUTLINE_COLOR: Color = Color(0.5, 0.5, 0.5, 0.5)
const OUTLINE_WIDTH: float = 1.0

const HIDE_OUTLINES_AT_RUNTIME: bool = true

var target_fps: int = 60

var _bg_material: ShaderMaterial = null


func _ready() -> void:
	_build_tileset()
	_build_background()

	if Engine.is_editor_hint():
		return

	Engine.max_fps = target_fps

	# Force windowed fullscreen (borderless) at runtime in case project setting
	# was not applied (e.g. when launched from the editor).
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)

	World.tilemap = $TileMapLayer


func shake_tile(tile_pos: Vector2i) -> void:
	var tile_origin := Vector2(tile_pos.x * World.TILE_SIZE, tile_pos.y * World.TILE_SIZE)
	var shaker := Node2D.new()
	shaker.position = tile_origin
	shaker.z_index  = 8
	var highlight := Polygon2D.new()
	highlight.polygon = PackedVector2Array([
		Vector2(2, 2),
		Vector2(World.TILE_SIZE - 2, 2),
		Vector2(World.TILE_SIZE - 2, World.TILE_SIZE - 2),
		Vector2(2, World.TILE_SIZE - 2)
	])
	highlight.color = Color(1.0, 1.0, 1.0, 0.18)
	shaker.add_child(highlight)
	add_child(shaker)
	var tween := create_tween()
	tween.tween_property(shaker, "position", tile_origin + Vector2(4, 0),  0.04)
	tween.tween_property(shaker, "position", tile_origin + Vector2(-4, 0), 0.04)
	tween.tween_property(shaker, "position", tile_origin + Vector2(2, 0),  0.03)
	tween.tween_property(shaker, "position", tile_origin,                  0.03)
	tween.tween_callback(shaker.queue_free)


func _build_background() -> void:
	var bg_texture: Texture2D = load("res://231.jpg")
	if bg_texture == null:
		push_warning("res://231.jpg not found")
		return
	var shader: Shader = load("res://background.gdshader")
	if shader == null:
		push_warning("res://background.gdshader not found")
		return
	_bg_material = ShaderMaterial.new()
	_bg_material.shader = shader
	_bg_material.set_shader_parameter("bg_texture",  bg_texture)
	_bg_material.set_shader_parameter("tile_size",   float(World.TILE_SIZE))
	_bg_material.set_shader_parameter("grid_width",  World.GRID_WIDTH)
	_bg_material.set_shader_parameter("grid_height", World.GRID_HEIGHT)
	_bg_material.set_shader_parameter("time",        0.0)
	var rect := ColorRect.new()
	rect.name         = "Background"
	rect.position     = Vector2.ZERO
	rect.size         = Vector2(World.GRID_WIDTH * World.TILE_SIZE, World.GRID_HEIGHT * World.TILE_SIZE)
	rect.color        = Color.WHITE
	rect.z_index      = -1
	rect.material     = _bg_material
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	move_child(rect, 0)


func _build_tileset() -> void:
	var tilemap: TileMapLayer = $TileMapLayer
	
	if OS.has_feature("editor"):
		# tiles.png layout (64x64 each, single row):
		#  col 0: grass          (floor)
		#  col 1: cobble-orig    (floor)
		#  col 2: dirt           (floor)
		#  col 3: rock wall      (solid, 3 hits to break)
		#  col 4: wood floor     (floor)
		#  col 5: cobblestone    (floor, also placed when stone wall breaks)
		#  col 6: stone wall     (solid, 10 hits to break)
		#  col 7: wooden wall    (solid, 5 hits to break, drops wood floor)
		#  col 8: greenblocks    (floor)
		var floor_atlas := TileSetAtlasSource.new()
		floor_atlas.resource_name = "Floor Tiles"
		floor_atlas.texture = load("res://tiles.png")
		floor_atlas.texture_region_size = Vector2i(World.TILE_SIZE, World.TILE_SIZE)
		floor_atlas.create_tile(Vector2i(0, 0))  # grass
		floor_atlas.create_tile(Vector2i(1, 0))  # cobble-orig
		floor_atlas.create_tile(Vector2i(2, 0))  # dirt
		floor_atlas.create_tile(Vector2i(4, 0))  # wood floor
		floor_atlas.create_tile(Vector2i(5, 0))  # cobblestone floor
		floor_atlas.create_tile(Vector2i(8, 0))  # greenblocks
		
		var solid_atlas := TileSetAtlasSource.new()
		solid_atlas.resource_name = "Solid Tiles"
		solid_atlas.texture = load("res://tiles.png")
		solid_atlas.texture_region_size = Vector2i(World.TILE_SIZE, World.TILE_SIZE)
		solid_atlas.create_tile(Vector2i(3, 0))  # rock wall
		solid_atlas.create_tile(Vector2i(6, 0))  # stone wall
		solid_atlas.create_tile(Vector2i(7, 0))  # wooden wall
		
		var ts := TileSet.new()
		ts.tile_size = Vector2i(World.TILE_SIZE, World.TILE_SIZE)
		ts.add_source(floor_atlas, 0)
		ts.add_source(solid_atlas, 1)
		
		# Water: res://animated/water_sheet.png — a 192x64 PNG sprite sheet (3 frames × 64x64)
		# Generated from water.gif frames scaled to 64x64.
		# Godot 4 animates this automatically via TileSetAtlasSource animation columns.
		var water_tex = load("res://animated/water_sheet.png")
		if water_tex != null:
			var water_atlas := TileSetAtlasSource.new()
			water_atlas.resource_name = "Water"
			water_atlas.texture = water_tex
			water_atlas.texture_region_size = Vector2i(World.TILE_SIZE, World.TILE_SIZE)
			water_atlas.create_tile(Vector2i(0, 0))
			water_atlas.set_tile_animation_columns(Vector2i(0, 0), 3)
			water_atlas.set_tile_animation_frames_count(Vector2i(0, 0), 3)
			water_atlas.set_tile_animation_speed(Vector2i(0, 0), 4.0)
			ts.add_source(water_atlas, 5)
		else:
			push_warning("res://animated/water_sheet.png not found — Water tile skipped.")
		
		tilemap.tile_set = ts
		ResourceSaver.save(ts, "res://tileset.tres")
	else:
		var cached_ts = load("res://tileset.tres") as TileSet
		if cached_ts != null:
			tilemap.tile_set = cached_ts
		else:
			push_error("Failed to load cached tileset.tres!")


func _process(_delta: float) -> void:
	if has_node("TileMapLayer"):
		$TileMapLayer.position = Vector2.ZERO
	if has_node("Overlay"):
		$Overlay.position = Vector2.ZERO
	if _bg_material != null:
		_bg_material.set_shader_parameter("time", Time.get_ticks_msec() / 1000.0)
