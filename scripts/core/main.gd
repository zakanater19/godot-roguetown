# project/main.gd
@tool
extends Node2D

const SHOW_OUTLINES: bool  = true
const OUTLINE_COLOR: Color = Color(0.5, 0.5, 0.5, 0.5)
const OUTLINE_WIDTH: float = 1.0

const HIDE_OUTLINES_AT_RUNTIME: bool = true

## Column order 0..10 must match TileSet atlas coords (floor + solid share one row).
const TURF_TILE_PATHS: PackedStringArray = [
	"res://assets/tiles/tile_00_grass.png",
	"res://assets/tiles/tile_01_cobble_rough.png",
	"res://assets/tiles/tile_02_dirt.png",
	"res://assets/tiles/tile_03_wall_rock.png",
	"res://assets/tiles/tile_04_wood_planks.png",
	"res://assets/tiles/tile_05_cobble_floor.png",
	"res://assets/tiles/tile_06_wall_stone.png",
	"res://assets/tiles/tile_07_wall_wood.png",
	"res://assets/tiles/tile_08_greenblocks.png",
	"res://assets/tiles/tile_09_loose_rock.png",
	"res://assets/tiles/tile_10_wooden_window.png",
]

var target_fps: int = 60
var _last_z: int = -1

func _ready() -> void:
	get_viewport().physics_object_picking_sort = true
	_build_tileset()
	_build_background()

	if Engine.is_editor_hint():
		# Hide the depth darken effects while working in the editor
		for z in range(1, 6):
			var darken = get_node_or_null("Darken_Z" + str(z) + "_Z" + str(z+1))
			if darken and darken.visible:
				darken.visible = false
		return

	World.register_main(self)
	Engine.max_fps = target_fps
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	
	# Wait for grid to populate, then calculate global shadow mapping
	await get_tree().process_frame
	Lighting.rebuild_roof_map()

	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			# Server is fully loaded — hide the startup loading screen.
			LoadingScreen.hide_loading()
		else:
			# Flag the map as fully loaded; LateJoin will now start the version check.
			LateJoin.map_loaded = true
			LoadingScreen.update_status("Checking version...")

func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		World.unregister_main()

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

func _compose_turf_atlas_texture() -> ImageTexture:
	var w := TURF_TILE_PATHS.size() * World.TILE_SIZE
	var h := World.TILE_SIZE
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in TURF_TILE_PATHS.size():
		var tex_path: String = TURF_TILE_PATHS[i]
		var tex: Texture2D = load(tex_path) as Texture2D
		if tex == null:
			push_error("_compose_turf_atlas_texture: missing or invalid texture: %s" % tex_path)
			continue
		var sub: Image = tex.get_image()
		if sub == null:
			push_error("_compose_turf_atlas_texture: could not read image data: %s" % tex_path)
			continue
		if sub.get_width() != World.TILE_SIZE or sub.get_height() != World.TILE_SIZE:
			sub.resize(World.TILE_SIZE, World.TILE_SIZE, Image.INTERPOLATE_NEAREST)
		sub.convert(Image.FORMAT_RGBA8)
		img.blit_rect(sub, Rect2i(0, 0, World.TILE_SIZE, World.TILE_SIZE), Vector2i(i * World.TILE_SIZE, 0))
	return ImageTexture.create_from_image(img)


func _build_tileset() -> void:
	if Engine.is_editor_hint():
		var editor_ts := load("res://assets/tileset.tres") as TileSet
		if editor_ts:
			for z in range(1, 6):
				var tm = get_node_or_null("TileMapLayer_Z" + str(z))
				if tm != null:
					tm.tile_set = editor_ts
		return

	var tilemap: TileMapLayer = $TileMapLayer_Z3
	var turf_tex := _compose_turf_atlas_texture()

	var floor_atlas := TileSetAtlasSource.new()
	floor_atlas.resource_name = "Floor Tiles"
	floor_atlas.texture = turf_tex
	floor_atlas.texture_region_size = Vector2i(World.TILE_SIZE, World.TILE_SIZE)
	floor_atlas.create_tile(Vector2i(0, 0))
	floor_atlas.create_tile(Vector2i(1, 0))
	floor_atlas.create_tile(Vector2i(2, 0))
	floor_atlas.create_tile(Vector2i(4, 0))
	floor_atlas.create_tile(Vector2i(5, 0))
	floor_atlas.create_tile(Vector2i(8, 0))
	floor_atlas.create_tile(Vector2i(9, 0))

	var solid_atlas := TileSetAtlasSource.new()
	solid_atlas.resource_name = "Solid Tiles"
	solid_atlas.texture = turf_tex
	solid_atlas.texture_region_size = Vector2i(World.TILE_SIZE, World.TILE_SIZE)
	solid_atlas.create_tile(Vector2i(3, 0))
	solid_atlas.create_tile(Vector2i(6, 0))
	solid_atlas.create_tile(Vector2i(7, 0))
	solid_atlas.create_tile(Vector2i(10, 0))

	var ts := TileSet.new()
	ts.tile_size = Vector2i(World.TILE_SIZE, World.TILE_SIZE)
	ts.add_source(floor_atlas, 0)
	ts.add_source(solid_atlas, 1)

	var stairs_tex = load("res://doors/stairs.png")
	if stairs_tex != null:
		var stairs_atlas := TileSetAtlasSource.new()
		stairs_atlas.resource_name = "Stairs"
		stairs_atlas.texture = stairs_tex
		stairs_atlas.texture_region_size = Vector2i(64, 64)
		stairs_atlas.create_tile(Vector2i(0, 0))
		ts.add_source(stairs_atlas, 2)
	else:
		push_warning("res://doors/stairs.png not found — Stairs tile skipped.")

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

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	var local_player = World.get_local_player()
	var current_z = 3
	if local_player != null:
		current_z = local_player.get("view_z_level") if "view_z_level" in local_player else local_player.z_level

	# OPTIMIZATION: Only update map layers when the player's floor actively changes
	if current_z != _last_z:
		_last_z = current_z
		
		for z in range(1, 6):
			var tm = get_node_or_null("TileMapLayer_Z" + str(z))
			if tm:
				tm.visible = (z <= current_z)
				
			var darken = get_node_or_null("Darken_Z" + str(z) + "_Z" + str(z+1))
			if darken:
				# Darken everything below the current player level
				darken.visible = (z < current_z)
