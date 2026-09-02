extends SceneTree

const TILE_SIZE := 64

const FLOOR_TILE_PATHS: PackedStringArray = [
	"res://assets/tiles/tile_00_grass.png",
	"res://assets/tiles/tile_01_cobble_rough.png",
	"res://assets/tiles/tile_02_dirt.png",
	"res://assets/tiles/tile_04_wood_planks.png",
	"res://assets/tiles/tile_05_cobble_floor.png",
	"res://assets/tiles/tile_08_greenblocks.png",
	"res://assets/tiles/tile_09_loose_rock.png",
]

const SOLID_TILE_PATHS: PackedStringArray = [
	"res://assets/tiles/tile_03_wall_rock.png",
	"res://assets/tiles/tile_06_wall_stone.png",
	"res://assets/tiles/tile_07_wall_wood.png",
	"res://assets/tiles/tile_10_wooden_window.png",
]

func _initialize() -> void:
	var error := _write_atlas(FLOOR_TILE_PATHS, "res://assets/tiles/floor_tiles_sheet.png")
	if error == OK:
		error = _write_atlas(SOLID_TILE_PATHS, "res://assets/tiles/solid_tiles_sheet.png")
	quit(error)

func _write_atlas(tile_paths: PackedStringArray, output_path: String) -> Error:
	var atlas := Image.create(tile_paths.size() * TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))

	for index in tile_paths.size():
		var tile := Image.load_from_file(ProjectSettings.globalize_path(tile_paths[index]))
		if tile == null or tile.is_empty():
			push_error("Could not load tile image: %s" % tile_paths[index])
			return ERR_FILE_CANT_READ
		if tile.get_width() != TILE_SIZE or tile.get_height() != TILE_SIZE:
			tile.resize(TILE_SIZE, TILE_SIZE, Image.INTERPOLATE_NEAREST)
		tile.convert(Image.FORMAT_RGBA8)
		atlas.blit_rect(tile, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(index * TILE_SIZE, 0))

	var error := atlas.save_png(ProjectSettings.globalize_path(output_path))
	if error != OK:
		push_error("Could not save tile atlas: %s" % output_path)
	return error
