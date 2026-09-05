@tool
class_name WorldObject
extends Area2D

@export var z_level: int = 3

var _registered_solid_tiles: Array[Vector2i] = []
var _fov_visible: bool = true
var _render_distance_visible: bool = true

# Gameplay state that is allowed to cross the network boundary.  Keeping this
# list explicit prevents UI nodes, Resources, animation timers, and other
# client-only presentation details from accidentally becoming authoritative.
const AUTHORITATIVE_STATE_FIELDS: Array[String] = [
	"hits",
	"state",
	"is_on",
	"has_torch",
	"direction_rotation",
	"_coal_count",
	"_ironore_count",
	"_ore_item_type",
	"_fuel_type",
	"_smelting",
	"contents",
	"amount",
	"metal_type",
	"stored_balance",
	"items_picked",
	"key_id",
	"is_locked",
	"tree_id",
	"piece_kind",
	"support_segment_name",
	"hits_to_break",
	"drop_count",
	"atlas_index",
	"z_offset",
	"solid_piece",
	"blocks_fov",
	"decor_configs",
	"max_items",
	"loot_item_types",
]

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
	if World.main_scene != null and World.main_scene.has_method("register_render_distance_node"):
		World.main_scene.register_render_distance_node(self)

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return

	unregister_solid_tiles()
	if World.main_scene != null and World.main_scene.has_method("unregister_render_distance_node"):
		World.main_scene.unregister_render_distance_node(self)
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

func _set_fov_visibility(p_visible: bool) -> void:
	_fov_visible = p_visible
	_apply_combined_visibility()

func set_render_distance_visible(p_visible: bool) -> void:
	_render_distance_visible = p_visible
	_apply_combined_visibility()

func _apply_combined_visibility() -> void:
	var combined := bool(get_meta("fov_visible", _fov_visible)) and _render_distance_visible
	if visible != combined:
		visible = combined
	if input_pickable != combined:
		input_pickable = combined

func capture_authoritative_state() -> Dictionary:
	var state: Dictionary = {}
	for field_name in AUTHORITATIVE_STATE_FIELDS:
		if not (field_name in self):
			continue
		var value: Variant = get(field_name)
		if value is Array or value is Dictionary:
			state[field_name] = value.duplicate(true)
		else:
			state[field_name] = value
	return state

func apply_authoritative_state(state: Dictionary, refresh_presentation: bool = true) -> void:
	for field_name in AUTHORITATIVE_STATE_FIELDS:
		if not state.has(field_name) or not (field_name in self):
			continue
		var value: Variant = state[field_name]
		if value is Array or value is Dictionary:
			set(field_name, value.duplicate(true))
		else:
			set(field_name, value)

	if refresh_presentation and is_inside_tree():
		_refresh_from_authoritative_state(state)

func _refresh_from_authoritative_state(state: Dictionary) -> void:
	# These hooks update local presentation/caches from server-owned values.  In
	# particular, lighting rendering remains local even though is_on/blocks_fov
	# are authoritative gameplay inputs.
	if has_method("rebuild_decor") and state.has("decor_configs"):
		call("rebuild_decor")
	if has_method("_update_sprite"):
		call("_update_sprite")
	if has_method("_update_solidity"):
		call("_update_solidity")
	else:
		set_solid_enabled(starts_solid())
	if has_method("_set_sprite") and state.has("is_on"):
		call("_set_sprite", bool(state["is_on"]))
	if has_method("_apply_visual_state"):
		call("_apply_visual_state")
	if has_method("_update_merchant_balance") and state.has("stored_balance"):
		call("_update_merchant_balance", int(state["stored_balance"]))

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

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and not Engine.is_editor_hint() and is_inside_tree():
		WorldStream.update_node(self)
