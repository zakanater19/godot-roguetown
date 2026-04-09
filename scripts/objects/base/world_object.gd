@tool
class_name WorldObject
extends Area2D

@export var z_level: int = 3

var _registered_solid_tiles: Array[Vector2i] = []

func _ready() -> void:
	z_index = Defs.get_z_index(z_level, get_z_offset())
	add_to_group(Defs.GROUP_Z_ENTITY)
	if Engine.is_editor_hint():
		return

	if should_snap_to_tile():
		snap_to_tile_center()
	if should_register_entity():
		World.register_entity(self)

	for group_name in get_runtime_groups():
		add_to_group(group_name)

	if starts_solid():
		register_solid_tiles()

	_on_world_object_ready()

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return

	unregister_solid_tiles()
	if should_register_entity():
		World.unregister_entity(self)
	_on_world_object_exit()

func get_z_offset() -> int:
	return Defs.Z_OFFSET_ITEMS

func should_snap_to_tile() -> bool:
	return false

func should_register_entity() -> bool:
	return false

func get_runtime_groups() -> Array[String]:
	return []

func get_solid_tile_offsets() -> Array[Vector2i]:
	return []

func starts_solid() -> bool:
	return not get_solid_tile_offsets().is_empty()

func get_anchor_tile() -> Vector2i:
	return Defs.world_to_tile(global_position)

func snap_to_tile_center() -> void:
	global_position = Defs.tile_to_pixel(get_anchor_tile())

func get_solid_tiles() -> Array[Vector2i]:
	var anchor_tile := get_anchor_tile()
	var tiles: Array[Vector2i] = []
	for offset in get_solid_tile_offsets():
		tiles.append(anchor_tile + offset)
	return tiles

func register_solid_tiles() -> void:
	unregister_solid_tiles()
	for tile_pos in get_solid_tiles():
		World.register_solid(tile_pos, z_level, self)
		_registered_solid_tiles.append(tile_pos)

func unregister_solid_tiles() -> void:
	for tile_pos in _registered_solid_tiles:
		World.unregister_solid(tile_pos, z_level, self)
	_registered_solid_tiles.clear()

func set_solid_enabled(enabled: bool) -> void:
	if enabled:
		register_solid_tiles()
	else:
		unregister_solid_tiles()

func get_shake_tiles() -> Array[Vector2i]:
	var tiles := get_solid_tiles()
	if tiles.is_empty():
		tiles.append(get_anchor_tile())
	return tiles

func shake(main_node: Node = null) -> void:
	if main_node == null:
		main_node = World.main_scene
	if main_node == null or not main_node.has_method("shake_tile"):
		return
	for tile_pos in get_shake_tiles():
		main_node.shake_tile(tile_pos, z_level)

func _on_world_object_ready() -> void:
	pass

func _on_world_object_exit() -> void:
	pass
