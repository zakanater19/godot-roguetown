@tool
class_name TreeSegment
extends BreakableWorldObject

const DEFAULT_MATERIAL: MaterialData = preload("res://materials/wood.tres")
const TREE_TEXTURE: Texture2D = preload("res://assets/tree_sheet.png")
const TREE_DECOR_SCRIPT = preload("res://objects/tree_decor.gd")
const CELL_SIZE: int = 32
const SHEET_COLUMNS: int = 5
const WORLD_SCALE: float = 2.0
const DROP_SPREAD: float = 12.0
const BRANCH_SLOW_MULTIPLIER: float = 1.2

@export var tree_id: String = ""
@export var piece_kind: String = "trunk"
@export var support_segment_name: String = ""
@export var hits_to_break: float = 5.0
@export var drop_count: int = 0
@export var atlas_index: int = 18
@export var z_offset: int = Defs.Z_OFFSET_ITEMS
@export var solid_piece: bool = true
@export var blocks_fov: bool = true
@export var material_data: MaterialData = DEFAULT_MATERIAL

var decor_configs: Array = []

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	_update_sprite()
	super._ready()
	rebuild_decor()

func get_hits_to_break() -> float:
	return hits_to_break

func get_z_offset() -> int:
	return z_offset

func should_snap_to_tile() -> bool:
	return true

func get_runtime_groups() -> Array[String]:
	return [Defs.GROUP_CHOPPABLE]

func get_solid_tile_offsets() -> Array[Vector2i]:
	if solid_piece:
		return [Vector2i.ZERO]
	return []

func get_description() -> String:
	match piece_kind:
		"branch":
			return "a tree branch"
		_:
			return "a tree trunk"

func get_movement_slow_multiplier() -> float:
	if piece_kind == "branch":
		return BRANCH_SLOW_MULTIPLIER
	return 1.0

func build_break_payload() -> Dictionary:
	var broken_paths: Array[String] = []
	var drop_names: Dictionary = {}
	var pending: Array = [self]
	var seen: Dictionary = {}

	while not pending.is_empty():
		var current = pending.pop_front()
		if current == null or not is_instance_valid(current):
			continue

		var current_path: String = str(current.get_path())
		if seen.has(current_path):
			continue

		seen[current_path] = true
		broken_paths.append(current_path)

		if current.drop_count > 0:
			var names: Array[String] = []
			for _i in range(current.drop_count):
				names.append(Defs.make_runtime_name("Log"))
			drop_names[current_path] = names

		if current.piece_kind == "trunk":
			for dependent in current.get_supported_segments():
				pending.append(dependent)

	return {
		"broken_paths": broken_paths,
		"drop_names": drop_names,
	}

func get_supported_segments() -> Array:
	var results: Array = []
	var parent_node: Node = get_parent()
	if parent_node == null:
		return results

	for child in parent_node.get_children():
		if child == self:
			continue
		if not (child is TreeSegment):
			continue
		if child.tree_id != tree_id:
			continue
		if child.support_segment_name != name:
			continue
		results.append(child)

	return results

func perform_break(log_names: Array) -> void:
	set_solid_enabled(false)
	var drop_tile: Vector2i = get_anchor_tile()
	var drop_center: Vector2 = Defs.tile_to_pixel(drop_tile)
	var land_z: int = World.calculate_gravity_z(drop_tile, z_level)
	for log_name in log_names:
		ObjectSpawnUtils.spawn_drop_with_seed(
			get_parent(),
			"log",
			String(log_name),
			land_z,
			drop_center,
			DROP_SPREAD
		)
	queue_free()

func rebuild_decor() -> void:
	for child in get_children():
		if child is TreeDecor:
			remove_child(child)
			child.queue_free()

	for config in decor_configs:
		var decor: TreeDecor = TREE_DECOR_SCRIPT.new() as TreeDecor
		var tile_offset: Vector2i = config.get("tile_offset", Vector2i.ZERO)
		decor.name = "%s_leaf_%s" % [name, str(get_child_count())]
		decor.z_level = int(config.get("z_level", z_level))
		decor.atlas_index = int(config.get("atlas_index", 0))
		decor.z_offset = int(config.get("z_offset", z_offset + 2))
		decor.blocks_fov = bool(config.get("blocks_fov", false))
		decor.position = Vector2(
			tile_offset.x * Defs.TILE_SIZE,
			tile_offset.y * Defs.TILE_SIZE
		)
		add_child(decor)

func _update_sprite() -> void:
	if sprite == null:
		return

	sprite.texture = TREE_TEXTURE
	sprite.centered = true
	sprite.region_enabled = true
	sprite.region_rect = _get_region_rect(atlas_index)
	sprite.scale = Vector2.ONE * WORLD_SCALE
	sprite.z_as_relative = false
	sprite.z_index = Defs.get_z_index(z_level, z_offset + 1)

func _get_region_rect(cell_index: int) -> Rect2:
	var x: int = (cell_index % SHEET_COLUMNS) * CELL_SIZE
	var y: int = floori(float(cell_index) / float(SHEET_COLUMNS)) * CELL_SIZE
	return Rect2(x, y, CELL_SIZE, CELL_SIZE)
