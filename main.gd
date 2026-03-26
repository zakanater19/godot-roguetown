# res://main.gd
@tool
extends Node2D

const SHOW_OUTLINES: bool  = true
const OUTLINE_COLOR: Color = Color(0.5, 0.5, 0.5, 0.5)
const OUTLINE_WIDTH: float = 1.0

const HIDE_OUTLINES_AT_RUNTIME: bool = true

var target_fps: int = 60

func _ready() -> void:
	_build_tileset()
	_build_background()

	if Engine.is_editor_hint():
		return

	Engine.max_fps = target_fps
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)

func shake_tile(tile_pos: Vector2i, z_level: int = 3) -> void:
	var tile_origin := Vector2(tile_pos.x * World.TILE_SIZE, tile_pos.y * World.TILE_SIZE)
	var shaker := Node2D.new()
	shaker.position = tile_origin
	shaker.z_index  = (z_level - 1) * 200 + 8
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
	var rect := ColorRect.new()
	rect.name         = "Background"
	rect.position     = Vector2.ZERO
	rect.size         = Vector2(World.GRID_WIDTH * World.TILE_SIZE, World.GRID_HEIGHT * World.TILE_SIZE)
	rect.color        = Color.BLACK
	rect.z_index      = -1
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	move_child(rect, 0)

func _build_tileset() -> void:
	var tilemap: TileMapLayer = $TileMapLayer_Z3
	
	if OS.has_feature("editor"):
		var floor_atlas := TileSetAtlasSource.new()
		floor_atlas.resource_name = "Floor Tiles"
		floor_atlas.texture = load("res://tiles.png")
		floor_atlas.texture_region_size = Vector2i(World.TILE_SIZE, World.TILE_SIZE)
		floor_atlas.create_tile(Vector2i(0, 0)) 
		floor_atlas.create_tile(Vector2i(1, 0))  
		floor_atlas.create_tile(Vector2i(2, 0))  
		floor_atlas.create_tile(Vector2i(4, 0))  
		floor_atlas.create_tile(Vector2i(5, 0))  
		floor_atlas.create_tile(Vector2i(8, 0))  
		
		var solid_atlas := TileSetAtlasSource.new()
		solid_atlas.resource_name = "Solid Tiles"
		solid_atlas.texture = load("res://tiles.png")
		solid_atlas.texture_region_size = Vector2i(World.TILE_SIZE, World.TILE_SIZE)
		solid_atlas.create_tile(Vector2i(3, 0))  
		solid_atlas.create_tile(Vector2i(6, 0))  
		solid_atlas.create_tile(Vector2i(7, 0))  
		
		var ts := TileSet.new()
		ts.tile_size = Vector2i(World.TILE_SIZE, World.TILE_SIZE)
		ts.add_source(floor_atlas, 0)
		ts.add_source(solid_atlas, 1)
		
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
		
		for z in range(1, 6):
			var tm = get_node_or_null("TileMapLayer_Z" + str(z))
			if tm != null:
				tm.tile_set = ts

		ResourceSaver.save(ts, "res://tileset.tres")
	else:
		var cached_ts = load("res://tileset.tres") as TileSet
		if cached_ts != null:
			for z in range(1, 6):
				var tm = get_node_or_null("TileMapLayer_Z" + str(z))
				if tm != null:
					tm.tile_set = cached_ts
		else:
			push_error("Failed to load cached tileset.tres!")

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		# Hide the depth darken effects while working in the editor
		for z in range(1, 6):
			var darken = get_node_or_null("Darken_Z" + str(z) + "_Z" + str(z+1))
			if darken and darken.visible:
				darken.visible = false
		return

	var local_player = World.get_local_player()
	var current_z = 3
	if local_player != null:
		current_z = local_player.z_level

	for z in range(1, 6):
		var tm = get_node_or_null("TileMapLayer_Z" + str(z))
		if tm:
			tm.visible = (z <= current_z)
			
		var darken = get_node_or_null("Darken_Z" + str(z) + "_Z" + str(z+1))
		if darken:
			# Darken everything below the current player level
			darken.visible = (z < current_z)

	for ent in get_tree().get_nodes_in_group("z_entity"):
		var ez = ent.get("z_level")
		if ez != null:
			if ez > current_z:
				ent.visible = false
			else:
				ent.visible = true