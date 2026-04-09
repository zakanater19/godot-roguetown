# Full file: project/objects/rock.gd
@tool
extends BreakableWorldObject

const HITS_TO_BREAK: int = 2
const DEFAULT_MATERIAL: MaterialData = preload("res://materials/coarse_rock.tres")
const DROP_SPREAD: float = 14.0

@export var material_data: MaterialData = DEFAULT_MATERIAL

func get_description() -> String:
	return "a rock, solid and heavy"

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return

func get_runtime_groups() -> Array[String]:
	return [Defs.GROUP_MINABLE]

func perform_break(drops_data: Array) -> void:
	var center: Vector2 = position
	for data in drops_data:
		ObjectSpawnUtils.spawn_drop_with_seed(
			get_parent(),
			String(data.type),
			String(data.name),
			z_level,
			center,
			DROP_SPREAD
		)
	queue_free()
