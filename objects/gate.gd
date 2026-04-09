@tool
extends BreakableWorldObject

const HITS_TO_BREAK: int = 5
const SPRITE_SCALE: float = 2.0
const DEFAULT_MATERIAL: MaterialData = preload("res://materials/metal.tres")
const OPEN_DURATION: float = 3.0
const CLOSE_DURATION: float = 0.4

enum GateState { CLOSED, OPEN, DESTROYED, OPENING, CLOSING }

const STATE_TEXTURES: Dictionary = {
	GateState.CLOSED: preload("res://doors/gateclosed.png"),
	GateState.OPEN: preload("res://doors/gateopen.png"),
	GateState.OPENING: preload("res://doors/gate-opening.png"),
	GateState.CLOSING: preload("res://doors/gate-closing.png"),
	GateState.DESTROYED: preload("res://doors/gateclosed.png"),
}

var state: GateState = GateState.CLOSED
var blocks_fov: bool = false
@export var material_data: MaterialData = DEFAULT_MATERIAL

@onready var sprite: Sprite2D = $Sprite2D

var _anim_timer: float = 0.0
var _is_animating: bool = false
var _anim_duration: float = CLOSE_DURATION
var _anim_frames: int = 1
var _frame_width: int = 96
var _frame_height: int = 32

func get_z_offset() -> int:
	return 5

func should_snap_to_tile() -> bool:
	return true

func get_runtime_groups() -> Array[String]:
	return [Defs.GROUP_GATE]

func get_solid_tile_offsets() -> Array[Vector2i]:
	if _is_solid_state(state):
		return [Vector2i(-1, 0), Vector2i.ZERO, Vector2i(1, 0)]
	return []

func get_shake_tiles() -> Array[Vector2i]:
	var anchor_tile := get_anchor_tile()
	return [anchor_tile - Vector2i(1, 0), anchor_tile, anchor_tile + Vector2i(1, 0)]

func _ready() -> void:
	super._ready()
	_update_sprite()

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _is_animating:
		return
	_anim_timer += delta
	var progress: float = clampf(_anim_timer / _anim_duration, 0.0, 1.0)
	var current_frame: int = int(progress * _anim_frames)
	if current_frame >= _anim_frames:
		current_frame = _anim_frames - 1
	sprite.region_rect = Rect2(current_frame * _frame_width, 0, _frame_width, _frame_height)
	if progress >= 1.0:
		_is_animating = false

func _update_sprite() -> void:
	_is_animating = false
	sprite.region_enabled = false
	sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	sprite.texture = STATE_TEXTURES.get(state, null)

	if state == GateState.OPENING or state == GateState.CLOSING:
		_start_animation()

func _start_animation() -> void:
	if sprite.texture == null:
		return
	sprite.region_enabled = true
	_frame_width = 96
	_frame_height = 32
	_anim_frames = int(sprite.texture.get_width() / float(_frame_width))
	if _anim_frames < 1:
		_anim_frames = 1
	sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	_anim_timer = 0.0
	_is_animating = true
	sprite.region_rect = Rect2(0, 0, _frame_width, _frame_height)

func _is_solid_state(current_state: GateState) -> bool:
	return current_state == GateState.CLOSED or current_state == GateState.CLOSING or current_state == GateState.OPENING

func _update_solidity() -> void:
	set_solid_enabled(_is_solid_state(state))

func open_gate() -> void:
	if state != GateState.CLOSED:
		return
	state = GateState.OPENING
	_anim_duration = OPEN_DURATION
	_update_sprite()
	_update_solidity()
	await get_tree().create_timer(OPEN_DURATION).timeout
	if state == GateState.OPENING:
		state = GateState.OPEN
		_update_solidity()
		_update_sprite()

func close_gate() -> void:
	if state != GateState.OPEN:
		return
	state = GateState.CLOSING
	_anim_duration = CLOSE_DURATION
	_update_sprite()
	_update_solidity()
	await get_tree().create_timer(CLOSE_DURATION).timeout
	if state == GateState.CLOSING:
		state = GateState.CLOSED
		_update_sprite()

func toggle_gate() -> void:
	if state == GateState.CLOSED:
		open_gate()
	elif state == GateState.OPEN:
		close_gate()

func can_toggle() -> bool:
	return state != GateState.DESTROYED

func toggle_structure() -> void:
	toggle_gate()

func apply_structure_damage(amount: float) -> String:
	hits += amount
	if hits >= HITS_TO_BREAK * 2:
		return "remove"
	if hits >= HITS_TO_BREAK:
		return "destroy"
	return "hit"

func destroy_structure() -> void:
	state = GateState.DESTROYED
	_update_sprite()
	set_solid_enabled(false)

func remove_structure() -> void:
	set_solid_enabled(false)
	queue_free()

func get_description() -> String:
	match state:
		GateState.CLOSED: return "a closed iron gate"
		GateState.OPEN: return "an open iron gate"
		GateState.OPENING: return "an iron gate, opening"
		GateState.CLOSING: return "an iron gate, closing"
		GateState.DESTROYED: return "a destroyed gate"
	return "a gate"
