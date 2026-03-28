# Full file: project/objects/furnace.gd
@tool
extends Area2D

const TILE_SIZE:   int   = 64
const SMELT_TIME:  float = 4.0

var is_on:         bool  = false
var _coal_count:   int   = 0
var _ironore_count: int  = 0
var _fuel_type:    String = "" 
var _smelting:     bool  = false

@export var z_level: int = 3
var blocks_fov: bool = false

func get_description() -> String:
	if _smelting: return "a furnace, roaring hot — smelting in progress"
	var parts: Array =[]
	if _coal_count > 0: parts.append("fuel loaded")
	if _ironore_count > 0: parts.append("iron ore loaded")
	if parts.is_empty(): return "a furnace, cold and empty"
	return "a furnace containing: " + ", ".join(parts)

func _ready() -> void:
	z_index = (z_level - 1) * 200 + 2
	add_to_group("z_entity")
	if Engine.is_editor_hint():
		return
	var tile_pos := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
	global_position = Vector2((tile_pos.x + 0.5) * TILE_SIZE, (tile_pos.y + 0.5) * TILE_SIZE)
	World.register_solid(tile_pos, z_level, self)
	add_to_group("inspectable")

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	var tile_pos := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
	World.unregister_solid(tile_pos, z_level, self)

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if Engine.is_editor_hint():
		return

	var player: Node = World.get_local_player()
	if player == null or player.z_level != z_level:
		return

	var my_tile  := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
	var diff: Vector2i = (my_tile - player.tile_pos).abs()
	if diff.x > 1 or diff.y > 1:
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
			var itype: String = held.get("item_type") if held.get("item_type") != null else ""
			if held.get("is_fuel") == true:
				if _coal_count >= 1: player._show_inspect_text("already has fuel", "")
				else:
					if multiplayer.is_server(): World.rpc_request_furnace_action(get_path(), "insert_fuel:" + itype, player.active_hand)
					else: World.rpc_request_furnace_action.rpc_id(1, get_path(), "insert_fuel:" + itype, player.active_hand)
			elif held.get("is_smeltable_ore") == true:
				if _ironore_count >= 1: player._show_inspect_text("already has ore", "")
				else:
					if multiplayer.is_server(): World.rpc_request_furnace_action(get_path(), "insert_ore", player.active_hand)
					else: World.rpc_request_furnace_action.rpc_id(1, get_path(), "insert_ore", player.active_hand)
			else: player._show_inspect_text("that can't be added to the furnace", "")
		else:
			if _coal_count >= 1 and _ironore_count >= 1:
				if multiplayer.is_server(): World.rpc_request_furnace_action(get_path(), "start_smelt", player.active_hand)
				else: World.rpc_request_furnace_action.rpc_id(1, get_path(), "start_smelt", player.active_hand)
			else: player._show_inspect_text("needs fuel and iron ore to start", "")

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		get_viewport().set_input_as_handled()
		if _smelting:
			player._show_inspect_text("can't empty a furnace mid-smelt!", "")
			return
		if _coal_count == 0 and _ironore_count == 0:
			player._show_inspect_text("the furnace is already empty", "")
			return
		if multiplayer.is_server(): World.rpc_request_furnace_action(get_path(), "eject", player.active_hand)
		else: World.rpc_request_furnace_action.rpc_id(1, get_path(), "eject", player.active_hand)

func _perform_action(action: String, player: Node, hand_idx: int, generated_names: Array) -> void:
	if action.begins_with("insert_fuel:"):
		if _coal_count < 1:
			_coal_count += 1
			_fuel_type = action.get_slice(":", 1)
			_consume_held(player, hand_idx)
			if player != null and player._is_local_authority(): player._show_inspect_text("fuel added to furnace", "")
	elif action == "insert_ore":
		if _ironore_count < 1:
			_ironore_count += 1
			_consume_held(player, hand_idx)
			if player != null and player._is_local_authority(): player._show_inspect_text("iron ore added to furnace", "")
	elif action == "start_smelt": _start_smelting()
	elif action == "eject": _eject_contents(player, generated_names)
	elif action == "finish_smelt": _finish_smelting(generated_names)

func _consume_held(player: Node, hand_idx: int) -> void:
	if player == null: return
	var obj: Node = player.hands[hand_idx]
	if obj != null:
		player.hands[hand_idx] = null
		obj.queue_free()
		if player._is_local_authority():
			player._update_hands_ui()
			player._apply_action_cooldown(null)

func _eject_contents(player: Node, generated_names: Array) -> void:
	var drop_offsets :=[Vector2(-TILE_SIZE, 0), Vector2(TILE_SIZE, 0), Vector2(0, TILE_SIZE), Vector2(-TILE_SIZE, TILE_SIZE)]
	var slot := 0
	var name_idx := 0
	if _coal_count > 0:
		var scene_path: String = ItemRegistry.get_scene_path(_fuel_type)
		if scene_path != "":
			var s := load(scene_path) as PackedScene
			if s != null and name_idx < generated_names.size():
				_spawn_item(s, drop_offsets[slot % drop_offsets.size()], player, generated_names[name_idx])
				slot += 1
				name_idx += 1
	if _ironore_count > 0:
		var ironore_scene := load("res://objects/ironore.tscn") as PackedScene
		if ironore_scene != null and name_idx < generated_names.size():
			_spawn_item(ironore_scene, drop_offsets[slot % drop_offsets.size()], player, generated_names[name_idx])
			slot += 1
			name_idx += 1
	_coal_count    = 0
	_ironore_count = 0
	_fuel_type     = ""
	if player != null and player._is_local_authority(): player._show_inspect_text("furnace emptied", "")

func _spawn_item(scene: PackedScene, offset: Vector2, _player: Node, node_name: String = "") -> void:
	var obj: Node2D = scene.instantiate()
	if node_name != "": obj.name = node_name
	obj.global_position = global_position + offset
	# Ensure the spawned item is on the same Z as the furnace
	if obj.has_method("set"): obj.set("z_level", z_level)
	get_parent().add_child(obj)

func _start_smelting() -> void:
	_smelting = true
	is_on     = true
	_set_sprite(true)
	if multiplayer.is_server():
		get_tree().create_timer(SMELT_TIME).timeout.connect(_on_server_smelt_finished)

func _on_server_smelt_finished() -> void:
	var ingot_name = "Ingot_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000)
	World.rpc_confirm_furnace_action.rpc(1, get_path(), "finish_smelt", -1,[ingot_name])

func _finish_smelting(generated_names: Array) -> void:
	_smelting      = false
	is_on          = false
	if _coal_count > 0: _coal_count -= 1
	if _ironore_count > 0: _ironore_count -= 1
	if _coal_count == 0: _fuel_type = ""
	_set_sprite(false)
	var ingot_scene := load("res://objects/ironingot.tscn") as PackedScene
	if ingot_scene != null and generated_names.size() > 0:
		_spawn_item(ingot_scene, Vector2(0, TILE_SIZE), null, generated_names[0])

func _set_sprite(on: bool) -> void:
	var sprite: Sprite2D = get_node_or_null("Sprite2D")
	if sprite != null: sprite.region_rect = Rect2(512 if on else 448, 0, 64, 64)