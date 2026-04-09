@tool
class_name TreeDecor
extends Sprite2D

const TREE_TEXTURE: Texture2D = preload("res://assets/tree_sheet.png")
const CELL_SIZE: int = 32
const SHEET_COLUMNS: int = 5
const WORLD_SCALE: float = 2.0

@export var z_level: int = 3
@export var atlas_index: int = 0
@export var z_offset: int = 6
@export var blocks_fov: bool = false

func _ready() -> void:
	texture = TREE_TEXTURE
	centered = true
	region_enabled = true
	region_rect = _get_region_rect(atlas_index)
	scale = Vector2.ONE * WORLD_SCALE
	z_as_relative = false
	z_index = Defs.get_z_index(z_level, z_offset)

	if not is_in_group(Defs.GROUP_Z_ENTITY):
		add_to_group(Defs.GROUP_Z_ENTITY)

func _get_region_rect(cell_index: int) -> Rect2:
	var x: int = (cell_index % SHEET_COLUMNS) * CELL_SIZE
	var y: int = floori(float(cell_index) / float(SHEET_COLUMNS)) * CELL_SIZE
	return Rect2(x, y, CELL_SIZE, CELL_SIZE)
