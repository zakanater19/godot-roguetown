@tool
extends PickableWorldObject

const OFF_TEXTURE: Texture2D = preload("res://objects/torch.png")
const ON_TEXTURE: Texture2D = preload("res://objects/torch_on_sheet.png")
const ON_FRAME_COUNT: int = 8
const ON_FPS: float = 10.0
const FRAME_SIZE: int = 32
const DISPLAY_SCALE: Vector2 = Vector2(1.5, 1.5)

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
		return
	_anim_timer += delta
	_update_animation_frame()

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
