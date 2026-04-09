@tool
extends BreakableWorldObject

const HITS_TO_BREAK: int = 4
const DEFAULT_MATERIAL: MaterialData = preload("res://materials/wood.tres")

@export var material_data: MaterialData = DEFAULT_MATERIAL

func get_description() -> String:
	return "a normal bed, looks somewhat comfortable"

func _ready() -> void:
	super._ready()

func should_snap_to_tile() -> bool:
	return true

func get_runtime_groups() -> Array[String]:
	return [Defs.GROUP_BREAKABLE, Defs.GROUP_BED]

func perform_break() -> void:
	queue_free()
