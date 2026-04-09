# Full file: project/objects/furnace.gd
@tool
extends WorldObject

const SMELT_TIME: float = 20.0

var is_on: bool = false
var light_intensity: float = 0.7
var _coal_count: int = 0
var _ironore_count: int = 0
var _fuel_type: String = ""
var _smelting: bool = false

var blocks_fov: bool = false

func should_snap_to_tile() -> bool:
	return true

func should_register_entity() -> bool:
	return true

func get_runtime_groups() -> Array[String]:
	return [Defs.GROUP_INSPECTABLE]

func get_solid_tile_offsets() -> Array[Vector2i]:
	return [Vector2i.ZERO]

func get_description() -> String:
	if _smelting:
		return "a furnace, roaring hot - smelting in progress"
	var parts: Array = []
	if _coal_count > 0:
		parts.append("fuel loaded")
	if _ironore_count > 0:
		parts.append("iron ore loaded")
	if parts.is_empty():
		return "a furnace, cold and empty"
	return "a furnace containing: " + ", ".join(parts)

func _exit_tree() -> void:
	super._exit_tree()
	if Engine.is_editor_hint():
		return
	Lighting.unregister_lamp(self)

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if Engine.is_editor_hint():
		return

	var player: Node = World.get_local_player()
	if player == null or player.z_level != z_level:
		return
	if not Defs.is_within_tile_reach(player.tile_pos, get_anchor_tile()):
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.is_key_pressed(KEY_SHIFT):
			return
		get_viewport().set_input_as_handled()
		if _smelting:
			player._show_inspect_text("the furnace is already smelting!", "")
			return
		var held: Node = player.hands[player.active_hand]
		if held != null:
			var item_type: String = held.get("item_type") if held.get("item_type") != null else ""
			var furnace_id := World.get_entity_id(self)
			if held.get("is_fuel") == true:
				if _coal_count >= 1:
					player._show_inspect_text("already has fuel", "")
				else:
					if multiplayer.is_server():
						World.rpc_request_furnace_action(furnace_id, "insert_fuel:" + item_type, player.active_hand)
					else:
						World.rpc_request_furnace_action.rpc_id(1, furnace_id, "insert_fuel:" + item_type, player.active_hand)
			elif held.get("is_smeltable_ore") == true:
				if _ironore_count >= 1:
					player._show_inspect_text("already has ore", "")
				else:
					if multiplayer.is_server():
						World.rpc_request_furnace_action(furnace_id, "insert_ore", player.active_hand)
					else:
						World.rpc_request_furnace_action.rpc_id(1, furnace_id, "insert_ore", player.active_hand)
			else:
				player._show_inspect_text("that can't be added to the furnace", "")
		else:
			if _coal_count >= 1 and _ironore_count >= 1:
				var furnace_id := World.get_entity_id(self)
				if multiplayer.is_server():
					World.rpc_request_furnace_action(furnace_id, "start_smelt", player.active_hand)
				else:
					World.rpc_request_furnace_action.rpc_id(1, furnace_id, "start_smelt", player.active_hand)
			else:
				player._show_inspect_text("needs fuel and iron ore to start", "")

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		get_viewport().set_input_as_handled()
		if _smelting:
			player._show_inspect_text("can't empty a furnace mid-smelt!", "")
			return
		if _coal_count == 0 and _ironore_count == 0:
			player._show_inspect_text("the furnace is already empty", "")
			return
		var furnace_id := World.get_entity_id(self)
		if multiplayer.is_server():
			World.rpc_request_furnace_action(furnace_id, "eject", player.active_hand)
		else:
			World.rpc_request_furnace_action.rpc_id(1, furnace_id, "eject", player.active_hand)

func _perform_action(action: String, player: Node, hand_idx: int, generated_names: Array) -> void:
	if action.begins_with("insert_fuel:"):
		if _coal_count < 1:
			_coal_count += 1
			_fuel_type = action.get_slice(":", 1)
			_consume_held(player, hand_idx)
			if player != null and player._is_local_authority():
				player._show_inspect_text("fuel added to furnace", "")
	elif action == "insert_ore":
		if _ironore_count < 1:
			_ironore_count += 1
			_consume_held(player, hand_idx)
			if player != null and player._is_local_authority():
				player._show_inspect_text("iron ore added to furnace", "")
	elif action == "start_smelt":
		_start_smelting()
	elif action == "eject":
		_eject_contents(player, generated_names)
	elif action == "finish_smelt":
		_finish_smelting(generated_names)

func _consume_held(player: Node, hand_idx: int) -> void:
	if player == null:
		return
	var obj: Node = player.hands[hand_idx]
	if obj != null:
		player.hands[hand_idx] = null
		obj.queue_free()
		if player._is_local_authority():
			player._update_hands_ui()
			player._apply_action_cooldown(null)

func _eject_contents(player: Node, generated_ids: Array) -> void:
	var drop_offsets := [
		Vector2(-Defs.TILE_SIZE, 0),
		Vector2(Defs.TILE_SIZE, 0),
		Vector2(0, Defs.TILE_SIZE),
		Vector2(-Defs.TILE_SIZE, Defs.TILE_SIZE),
	]
	var slot := 0
	var name_idx := 0
	if _coal_count > 0 and name_idx < generated_ids.size():
		ObjectSpawnUtils.spawn_item_type(
			get_parent(),
			_fuel_type,
			generated_ids[name_idx],
			z_level,
			global_position + drop_offsets[slot % drop_offsets.size()],
			generated_ids[name_idx]
		)
		slot += 1
		name_idx += 1
	if _ironore_count > 0 and name_idx < generated_ids.size():
		ObjectSpawnUtils.spawn_item_type(
			get_parent(),
			"IronOre",
			generated_ids[name_idx],
			z_level,
			global_position + drop_offsets[slot % drop_offsets.size()],
			generated_ids[name_idx]
		)
		slot += 1
		name_idx += 1
	_coal_count = 0
	_ironore_count = 0
	_fuel_type = ""
	if player != null and player._is_local_authority():
		player._show_inspect_text("furnace emptied", "")

func _start_smelting() -> void:
	_smelting = true
	is_on = true
	_set_sprite(true)
	if multiplayer.is_server():
		get_tree().create_timer(SMELT_TIME).timeout.connect(_on_server_smelt_finished)

func _on_server_smelt_finished() -> void:
	var ingot_id = World._make_entity_id("ingot")
	World.rpc_confirm_furnace_action.rpc(1, World.get_entity_id(self), "finish_smelt", -1, [ingot_id])

func _finish_smelting(generated_names: Array) -> void:
	_smelting = false
	is_on = false
	if _coal_count > 0:
		_coal_count -= 1
	if _ironore_count > 0:
		_ironore_count -= 1
	if _coal_count == 0:
		_fuel_type = ""
	_set_sprite(false)
	if generated_names.size() > 0:
		ObjectSpawnUtils.spawn_item_type(
			get_parent(),
			"IronIngot",
			generated_names[0],
			z_level,
			global_position + Vector2(0, Defs.TILE_SIZE),
			generated_names[0]
		)

func _set_sprite(on: bool) -> void:
	var sprite: Sprite2D = get_node_or_null("Sprite2D")
	if sprite != null:
		sprite.region_rect = Rect2(512 if on else 448, 0, 64, 64)
	if on:
		Lighting.register_lamp(self)
	else:
		Lighting.unregister_lamp(self)
