# project/main.gd
@tool
extends Node2D

const SHOW_OUTLINES: bool  = true
const OUTLINE_COLOR: Color = Color(0.5, 0.5, 0.5, 0.5)
const OUTLINE_WIDTH: float = 1.0
const BUSH_SCENE: PackedScene = preload("res://objects/bush.tscn")

const HIDE_OUTLINES_AT_RUNTIME: bool = true

## Each category is packed into its own atlas so the TileMap palette only shows
## tiles that can actually be painted from that source.
const FLOOR_TILE_PATHS: PackedStringArray =[
	"res://assets/tiles/tile_00_grass.png",
	"res://assets/tiles/tile_01_cobble_rough.png",
	"res://assets/tiles/tile_02_dirt.png",
	"res://assets/tiles/tile_04_wood_planks.png",
	"res://assets/tiles/tile_05_cobble_floor.png",
	"res://assets/tiles/tile_08_greenblocks.png",
	"res://assets/tiles/tile_09_loose_rock.png",
]

const SOLID_TILE_PATHS: PackedStringArray =[
	"res://assets/tiles/tile_03_wall_rock.png",
	"res://assets/tiles/tile_06_wall_stone.png",
	"res://assets/tiles/tile_07_wall_wood.png",
	"res://assets/tiles/tile_10_wooden_window.png",
]

const GRASS_DECOR_TILE_PATHS: PackedStringArray =[
	"res://assets/foliage/grass1.png",
	"res://assets/foliage/grass2.png",
	"res://assets/foliage/grass3.png",
	"res://assets/foliage/grass4.png",
	"res://assets/foliage/grass5.png",
	"res://assets/foliage/grass6.png",
	"res://assets/foliage/grass7.png",
	"res://assets/foliage/grass8.png",
]
const GRASS_FLOOR_ATLAS_COORDS: Vector2i = Vector2i(0, 0)
const GRASS_DECOR_SPAWN_CHANCE: float = 0.1
const BUSH_SPAWN_CHANCE: float = 0.025
const GRASS_DECOR_Z_OFFSET: int = 1
const FOLIAGE_LAYOUT_SEED: int = 734287

var target_fps: int = 60
var _last_z: int = -1
var _grass_decor_layers: Dictionary = {}

var _fps_label: Label = null

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

	# Region maps are editor-only metadata, like SS13 areas. Their overlay never
	# renders to players; gameplay behavior can be attached later.
	for z in range(1, 6):
		var region_map := get_node_or_null("RegionMapLayer_Z" + str(z)) as TileMapLayer
		if region_map != null:
			region_map.visible = false

	# Tree spawners also build their runtime pieces deferred. Queue foliage after
	# them so their full ground footprint is part of the occupied-tile check.
	call_deferred("_spawn_runtime_foliage")

	# Add FPS Counter
	var fps_layer := CanvasLayer.new()
	fps_layer.layer = 128
	_fps_label = Label.new()
	_fps_label.name = "FPSLabel"
	_fps_label.position = Vector2(10, 10)
	_fps_label.add_theme_font_size_override("font_size", 24)
	_fps_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
	_fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_fps_label.add_theme_constant_override("outline_size", 3)
	fps_layer.add_child(_fps_label)
	add_child(fps_layer)

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

func _compose_atlas_texture(tile_paths: PackedStringArray) -> ImageTexture:
	var w := tile_paths.size() * World.TILE_SIZE
	var h := World.TILE_SIZE
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in tile_paths.size():
		var tex_path: String = tile_paths[i]
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
	var floor_tex := _compose_atlas_texture(FLOOR_TILE_PATHS)
	var solid_tex := _compose_atlas_texture(SOLID_TILE_PATHS)

	var floor_atlas := TileSetAtlasSource.new()
	floor_atlas.resource_name = "Floor Tiles"
	floor_atlas.texture = floor_tex
	floor_atlas.texture_region_size = Vector2i(World.TILE_SIZE, World.TILE_SIZE)
	for i in FLOOR_TILE_PATHS.size():
		floor_atlas.create_tile(Vector2i(i, 0))

	var solid_atlas := TileSetAtlasSource.new()
	solid_atlas.resource_name = "Solid Tiles"
	solid_atlas.texture = solid_tex
	solid_atlas.texture_region_size = Vector2i(World.TILE_SIZE, World.TILE_SIZE)
	for i in SOLID_TILE_PATHS.size():
		solid_atlas.create_tile(Vector2i(i, 0))

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

func _spawn_runtime_foliage() -> void:
	if not _grass_decor_layers.is_empty():
		return

	var decor_tileset := TileSet.new()
	decor_tileset.tile_size = Vector2i(World.TILE_SIZE, World.TILE_SIZE)

	var decor_atlas := TileSetAtlasSource.new()
	decor_atlas.resource_name = "Runtime Grass Decorations"
	decor_atlas.texture = _compose_atlas_texture(GRASS_DECOR_TILE_PATHS)
	decor_atlas.texture_region_size = Vector2i(World.TILE_SIZE, World.TILE_SIZE)
	for i in GRASS_DECOR_TILE_PATHS.size():
		decor_atlas.create_tile(Vector2i(i, 0))
	decor_tileset.add_source(decor_atlas, 0)

	var occupied_tiles := _collect_runtime_occupied_tiles()

	for z in range(1, 6):
		var world_layer := get_node_or_null("TileMapLayer_Z" + str(z)) as TileMapLayer
		if world_layer == null:
			continue

		var decor_layer := TileMapLayer.new()
		decor_layer.name = "RuntimeGrassDecor_Z" + str(z)
		decor_layer.tile_set = decor_tileset
		decor_layer.z_as_relative = false
		decor_layer.z_index = Defs.get_z_index(z, GRASS_DECOR_Z_OFFSET)
		decor_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(decor_layer)
		_grass_decor_layers[z] = decor_layer

		for cell in world_layer.get_used_cells_by_id(0, GRASS_FLOOR_ATLAS_COORDS):
			if occupied_tiles[z].has(cell):
				continue
			var bush_roll := posmod(_get_foliage_hash(cell, z, 2), 10000)
			if (
				Regions.allows_bushes_at(self, cell, z)
				and bush_roll < int(BUSH_SPAWN_CHANCE * 10000.0)
			):
				_spawn_runtime_bush(cell, z)
				occupied_tiles[z][cell] = true
				continue
			if not Regions.allows_grass_decor_at(self, cell, z):
				continue
			var spawn_roll := posmod(_get_foliage_hash(cell, z, 0), 10000)
			if spawn_roll >= int(GRASS_DECOR_SPAWN_CHANCE * 10000.0):
				continue
			var variant := posmod(_get_foliage_hash(cell, z, 1), GRASS_DECOR_TILE_PATHS.size())
			decor_layer.set_cell(cell, 0, Vector2i(variant, 0))

func _spawn_runtime_bush(cell: Vector2i, z_level: int) -> void:
	var bush := BUSH_SCENE.instantiate() as Node2D
	if bush == null:
		push_error("Could not instantiate the runtime bush scene.")
		return
	bush.name = "RuntimeBush_Z%d_X%d_Y%d" % [z_level, cell.x, cell.y]
	bush.position = Defs.tile_to_pixel(cell)
	bush.set("z_level", z_level)
	add_child(bush)

func _collect_runtime_occupied_tiles() -> Dictionary:
	var occupied: Dictionary = {1: {}, 2: {}, 3: {}, 4: {}, 5: {}}
	for child in get_children():
		if not (child is Node2D):
			continue
		var z_value = child.get("z_level")
		if z_value == null:
			continue
		var z := clampi(int(z_value), 1, 5)
		var anchor_tile := Defs.world_to_tile(child.global_position)
		occupied[z][anchor_tile] = true
		if child.has_method("get_solid_tiles"):
			for solid_tile in child.call("get_solid_tiles"):
				occupied[z][Vector2i(solid_tile)] = true
	return occupied

func _get_foliage_hash(cell: Vector2i, z: int, salt: int) -> int:
	return ("%d:%d:%d:%d:%d" % [FOLIAGE_LAYOUT_SEED, cell.x, cell.y, z, salt]).hash()

func has_runtime_grass_decor_at(tile_pos: Vector2i, z_level: int) -> bool:
	var decor_layer := _grass_decor_layers.get(z_level) as TileMapLayer
	return decor_layer != null and decor_layer.get_cell_source_id(tile_pos) != -1

func remove_runtime_grass_decor(tile_pos: Vector2i, z_level: int) -> void:
	var decor_layer := _grass_decor_layers.get(z_level) as TileMapLayer
	if decor_layer != null:
		decor_layer.erase_cell(tile_pos)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if _fps_label != null:
		_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

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

			var grass_decor := _grass_decor_layers.get(z) as TileMapLayer
			if grass_decor:
				grass_decor.visible = (z <= current_z)
				
			var darken = get_node_or_null("Darken_Z" + str(z) + "_Z" + str(z+1))
			if darken:
				# Darken everything below the current player level
				darken.visible = (z < current_z)
