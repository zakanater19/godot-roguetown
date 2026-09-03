# Full file: project/objects/tree.gd
@tool
extends BreakableWorldObject

const HITS_TO_BREAK: int = 5
const DEFAULT_MATERIAL: MaterialData = preload("res://materials/wood.tres")
const TREE_TEXTURE: Texture2D = preload("res://objects/tree.png")
const STUMP_TEXTURES: Array[Texture2D] = [
	preload("res://assets/foliage/t1stump.png"),
	preload("res://assets/foliage/t2stump.png"),
	preload("res://assets/foliage/t3stump.png"),
	preload("res://assets/foliage/t4stump.png"),
]
const TREE_SCALE: Vector2 = Vector2(1.5, 1.5)
const STUMP_SCALE: Vector2 = Vector2(2, 2)
const STUMP_FRAME_SIZE: Vector2 = Vector2(64, 96)
const STUMP_SPRITE_OFFSET: Vector2 = Vector2(0, -64)
const STUMP_Z_OFFSET: int = Defs.Z_OFFSET_ITEMS - 1
const FELLED_TREE_LOG_MIN: int = 4
const FELLED_TREE_LOG_MAX: int = 5
const STUMP_SLOW_MULTIPLIER: float = 1.5
const DROP_SPREAD: float = 14.0

@export var material_data: MaterialData = DEFAULT_MATERIAL
@export var state: String = "tree"
@export var blocks_fov: bool = true

@onready var sprite: Sprite2D = $Sprite2D

func get_description() -> String:
	if state == "stump":
		return "a tree stump"
	return "a dark, bare tree"

func _ready() -> void:
	_update_sprite()
	super._ready()

func should_snap_to_tile() -> bool:
	return true

func get_runtime_groups() -> Array[String]:
	return [Defs.GROUP_CHOPPABLE]

func get_solid_tile_offsets() -> Array[Vector2i]:
	if state == "stump":
		return []
	return [Vector2i.ZERO]

func get_drop_spread() -> float:
	return DROP_SPREAD

func get_movement_slow_multiplier() -> float:
	if state == "stump":
		return STUMP_SLOW_MULTIPLIER
	return 1.0

func _update_solidity() -> void:
	set_solid_enabled(state != "stump")

func build_break_payload() -> Dictionary:
	var tree_path := str(get_path())
	var drop_count := 1 if state == "stump" else randi_range(FELLED_TREE_LOG_MIN, FELLED_TREE_LOG_MAX)
	var drop_names: Array[String] = []
	for _i in range(drop_count):
		drop_names.append(Defs.make_runtime_name("Log"))
	return {
		"broken_paths": [tree_path],
		"drop_names": {
			tree_path: drop_names,
		},
	}

func perform_break(log_names: Array, drop_positions: Array = [], land_z_override: int = -1) -> void:
	var land_z := land_z_override if land_z_override >= 1 else z_level
	for index in range(log_names.size()):
		var log_name := String(log_names[index])
		if index < drop_positions.size():
			ObjectSpawnUtils.spawn_drop_at(get_parent(), "log", log_name, land_z, Vector2(drop_positions[index]))
		else:
			ObjectSpawnUtils.spawn_drop_with_seed(get_parent(), "log", log_name, land_z, position, DROP_SPREAD)

	if state != "stump":
		state = "stump"
		hits = 0.0
		blocks_fov = false
		_update_sprite()
		return

	queue_free()

func _update_sprite() -> void:
	if sprite == null:
		return

	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if state == "stump":
		sprite.texture = STUMP_TEXTURES[posmod(name.hash(), STUMP_TEXTURES.size())]
		sprite.region_enabled = true
		sprite.region_rect = Rect2(Vector2.ZERO, STUMP_FRAME_SIZE)
		sprite.position = STUMP_SPRITE_OFFSET
		sprite.scale = STUMP_SCALE
		sprite.z_as_relative = false
		sprite.z_index = Defs.get_z_index(z_level, STUMP_Z_OFFSET)
		return

	sprite.texture = TREE_TEXTURE
	sprite.region_enabled = false
	sprite.position = Vector2.ZERO
	sprite.scale = TREE_SCALE
	sprite.z_as_relative = true
	sprite.z_index = 0
