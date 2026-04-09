@tool
class_name PickableWorldObject
extends WorldObject

func should_register_entity() -> bool:
	return true

func get_runtime_groups() -> Array[String]:
	if is_pickup_enabled():
		return [Defs.GROUP_PICKABLE]
	return []

func is_pickup_enabled() -> bool:
	return true

func can_local_player_pick_up(player: Node) -> bool:
	return (
		player != null
		and player.z_level == z_level
		and Defs.is_within_tile_reach(player.tile_pos, get_anchor_tile())
	)

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if Engine.is_editor_hint() or not is_pickup_enabled():
		return
	if event is not InputEventMouseButton:
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	if Input.is_key_pressed(KEY_SHIFT):
		return

	var player: Node = World.get_local_player()
	if not can_local_player_pick_up(player):
		return

	get_viewport().set_input_as_handled()
	if player.has_method("_on_object_picked_up"):
		player._on_object_picked_up(self)
