# res://objects/merchantvendor.gd
@tool
extends WorldObject

var blocks_fov: bool = false

func get_description() -> String:
	return "a merchant vendor, ready to trade"

func get_z_offset() -> int:
	return 5

func should_snap_to_tile() -> bool:
	return true

func get_runtime_groups() -> Array[String]:
	return [Defs.GROUP_INSPECTABLE]

func get_solid_tile_offsets() -> Array[Vector2i]:
	return [Vector2i.ZERO]
