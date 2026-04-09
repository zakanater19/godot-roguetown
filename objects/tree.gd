# Full file: project/objects/tree.gd
@tool
extends BreakableWorldObject

const HITS_TO_BREAK: int = 5
const DEFAULT_MATERIAL: MaterialData = preload("res://materials/wood.tres")
const DROP_SPREAD: float = 14.0

@export var material_data: MaterialData = DEFAULT_MATERIAL

func get_description() -> String:
	return "a dark, bare tree"

func _ready() -> void:
	super._ready()

func should_snap_to_tile() -> bool:
	return true

func get_runtime_groups() -> Array[String]:
	return [Defs.GROUP_CHOPPABLE]

func get_solid_tile_offsets() -> Array[Vector2i]:
	return [Vector2i.ZERO]

func perform_break(log_names: Array) -> void:
	for log_name in log_names:
		ObjectSpawnUtils.spawn_drop_with_seed(
			get_parent(),
			"log",
			log_name,
			z_level,
			position,
			DROP_SPREAD
		)
	queue_free()
