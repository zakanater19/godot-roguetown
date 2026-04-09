@tool
extends BreakableWorldObject

const HITS_TO_BREAK: int = 3
const DEFAULT_MATERIAL: MaterialData = preload("res://materials/wood.tres")
const TRANSITION_DURATION: float = 0.4

enum DoorState { CLOSED, OPEN, DESTROYED, OPENING, CLOSING }

const STATE_TEXTURES: Dictionary = {
	DoorState.CLOSED: preload("res://doors/doorshut.png"),
	DoorState.OPEN: preload("res://doors/dooropen.png"),
	DoorState.OPENING: preload("res://doors/door-opening.png"),
	DoorState.CLOSING: preload("res://doors/door-closing.png"),
	DoorState.DESTROYED: preload("res://doors/doorbroken.png"),
}

var state: DoorState = DoorState.CLOSED
@export var material_data: MaterialData = DEFAULT_MATERIAL

@onready var sprite: Sprite2D = $Sprite2D

var _anim_timer: float = 0.0
var _is_animating: bool = false
var _anim_frames: int = 1
var _frame_size: int = 64

func get_z_offset() -> int:
	return 5

func should_snap_to_tile() -> bool:
	return true

func get_runtime_groups() -> Array[String]:
	return [Defs.GROUP_DOOR]

func get_solid_tile_offsets() -> Array[Vector2i]:
	if _is_solid_state(state):
		return [Vector2i.ZERO]
	return []

func _ready() -> void:
	super._ready()
	_update_sprite()

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _is_animating:
		return
	_anim_timer += delta
	var progress: float = clampf(_anim_timer / TRANSITION_DURATION, 0.0, 1.0)
	var current_frame: int = int(progress * _anim_frames)
	if current_frame >= _anim_frames:
		current_frame = _anim_frames - 1
	sprite.region_rect = Rect2(current_frame * _frame_size, 0, _frame_size, _frame_size)
	if progress >= 1.0:
		_is_animating = false

func _update_sprite() -> void:
	_is_animating = false
	sprite.region_enabled = false
	sprite.texture = STATE_TEXTURES.get(state, null)

	if state == DoorState.OPENING or state == DoorState.CLOSING:
		_start_animation()
		return

	if sprite.texture != null:
		var tex_h: int = sprite.texture.get_height()
		var scale_factor: float = 64.0 / float(tex_h)
		sprite.scale = Vector2(scale_factor, scale_factor)

func _start_animation() -> void:
	if sprite.texture == null:
		return
	sprite.region_enabled = true
	_frame_size = sprite.texture.get_height()
	_anim_frames = int(sprite.texture.get_width() / float(_frame_size))
	if _anim_frames < 1:
		_anim_frames = 1
	var scale_factor: float = 64.0 / float(_frame_size)
	sprite.scale = Vector2(scale_factor, scale_factor)
	_anim_timer = 0.0
	_is_animating = true
	sprite.region_rect = Rect2(0, 0, _frame_size, _frame_size)

func _is_solid_state(current_state: DoorState) -> bool:
	return current_state == DoorState.CLOSED or current_state == DoorState.CLOSING

func _update_solidity() -> void:
	set_solid_enabled(_is_solid_state(state))

func open_door() -> void:
	if state != DoorState.CLOSED:
		return
	state = DoorState.OPENING
	_update_sprite()
	_update_solidity()
	await get_tree().create_timer(TRANSITION_DURATION).timeout
	if state == DoorState.OPENING:
		state = DoorState.OPEN
		_update_sprite()

func close_door() -> void:
	if state != DoorState.OPEN:
		return
	state = DoorState.CLOSING
	_update_sprite()
	_update_solidity()
	await get_tree().create_timer(TRANSITION_DURATION).timeout
	if state == DoorState.CLOSING:
		state = DoorState.CLOSED
		_update_sprite()

func toggle_door() -> void:
	if state == DoorState.CLOSED:
		open_door()
	elif state == DoorState.OPEN:
		close_door()

func can_toggle() -> bool:
	return state != DoorState.DESTROYED

func toggle_structure() -> void:
	toggle_door()

func apply_structure_damage(amount: float) -> String:
	hits += amount
	if hits >= HITS_TO_BREAK * 2:
		return "remove"
	if hits >= HITS_TO_BREAK:
		return "destroy"
	return "hit"

func destroy_structure() -> void:
	state = DoorState.DESTROYED
	_update_sprite()
	set_solid_enabled(false)

func remove_structure() -> void:
	set_solid_enabled(false)
	queue_free()

func get_description() -> String:
	match state:
		DoorState.CLOSED: return "a closed wooden door"
		DoorState.OPEN: return "an open wooden door"
		DoorState.OPENING: return "a wooden door, opening"
		DoorState.CLOSING: return "a wooden door, closing"
		DoorState.DESTROYED: return "a destroyed door"
	return "a door"
