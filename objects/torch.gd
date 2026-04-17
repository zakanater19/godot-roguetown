@tool
extends PickableWorldObject

const OFF_TEXTURE: Texture2D = preload("res://objects/torch.png")
const ON_TEXTURE: Texture2D = preload("res://objects/torch_on_sheet.png")
const ON_FRAME_COUNT: int = 8
const ON_FPS: float = 10.0
const FRAME_SIZE: int = 32
const DISPLAY_SCALE: Vector2 = Vector2(1.5, 1.5)
const GROUND_EXTINGUISH_DELAY: float = 5.0

var item_type: String = "Torch"
var tool_type: String = ""
var material_data: MaterialData = preload("res://materials/wood.tres")
var weaponizable: bool = true
var force: int = 5
var too_large_for_satchel: bool = false
var slot: String = ""
var is_fuel: bool = false
var is_smeltable_ore: bool = false

@export var is_on: bool = false:
	set(value):
		is_on = value
		_anim_timer = 0.0
		_apply_visual_state()

@export var light_intensity: float = 1.0

var _anim_timer: float = 0.0
var _ground_burn_time: float = 0.0
var _auto_extinguish_requested: bool = false

func get_description() -> String:
	return "a torch, currently " + ("ON" if is_on else "OFF")

func get_use_delay() -> float:
	return 0.3

func is_torch_item() -> bool:
	return true

func _ready() -> void:
	super._ready()
	_apply_visual_state()

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_on:
		_ground_burn_time = 0.0
		_auto_extinguish_requested = false
		return
	_anim_timer += delta
	_update_animation_frame()
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if _is_held_by_any_player() or not _is_ground_drop():
		_ground_burn_time = 0.0
		_auto_extinguish_requested = false
		return
	if _is_in_water_tile():
		_request_auto_extinguish()
		return
	_ground_burn_time += delta
	if _ground_burn_time >= GROUND_EXTINGUISH_DELAY:
		_request_auto_extinguish()

func _exit_tree() -> void:
	super._exit_tree()
	if Engine.is_editor_hint():
		return
	Lighting.unregister_lamp(self)

func _set_fov_visibility(p_visible: bool) -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null and sprite.visible != p_visible:
		sprite.visible = p_visible

	if input_pickable != p_visible:
		input_pickable = p_visible

func _set_sprite(on: bool) -> void:
	is_on = on

func _extinguish_from_world() -> void:
	_set_sprite(false)
	_ground_burn_time = 0.0
	_auto_extinguish_requested = false

func interact_in_hand(player: Node) -> void:
	_set_sprite(not is_on)
	if player != null and player._is_local_authority():
		player._update_hands_ui()
		var state_str := "ON" if is_on else "OFF"
		player._show_inspect_text("You turn the torch " + state_str, "")

func _apply_visual_state() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.scale = DISPLAY_SCALE
		if is_on:
			sprite.texture = ON_TEXTURE
			sprite.region_enabled = true
			_update_animation_frame()
		else:
			sprite.texture = OFF_TEXTURE
			sprite.region_enabled = false
			sprite.region_rect = Rect2(0, 0, FRAME_SIZE, FRAME_SIZE)

	if Engine.is_editor_hint():
		return

	if is_on:
		Lighting.register_lamp(self)
	else:
		Lighting.unregister_lamp(self)

func _update_animation_frame() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return
	var frame := int(floor(_anim_timer * ON_FPS)) % ON_FRAME_COUNT
	sprite.region_rect = Rect2(frame * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)

func _is_held_by_any_player() -> bool:
	for player in get_tree().get_nodes_in_group(Defs.GROUP_PLAYER):
		if player == null or not is_instance_valid(player):
			continue
		var hands: Variant = player.get("hands")
		if not (hands is Array):
			continue
		for hand_item in hands:
			if hand_item == self:
				return true
	return false

func _is_ground_drop() -> bool:
	return z_index % Defs.Z_LAYER_SIZE == Defs.Z_OFFSET_ITEMS

func _is_in_water_tile() -> bool:
	var tilemap := World.get_tilemap(z_level)
	if tilemap == null:
		return false
	return tilemap.get_cell_source_id(get_anchor_tile()) == 5

func _request_auto_extinguish() -> void:
	if _auto_extinguish_requested:
		return
	_auto_extinguish_requested = true
	var torch_id := World.get_entity_id(self)
	if torch_id == "":
		_extinguish_from_world()
		return
	if multiplayer.has_multiplayer_peer():
		World.rpc_confirm_auto_extinguish_torch.rpc(torch_id)
	else:
		_extinguish_from_world()
