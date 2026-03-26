@tool
extends Area2D

const TILE_SIZE: int = 64
const HITS_TO_BREAK: int = 3

enum DoorState { CLOSED, OPEN, DESTROYED, OPENING, CLOSING }

var state: DoorState = DoorState.CLOSED
var hits: int = 0
@export var z_level: int = 3

@onready var sprite: Sprite2D = $Sprite2D

var _anim_timer: float = 0.0
var _is_animating: bool = false
var _anim_duration: float = 0.4
var _anim_frames: int = 1
var _frame_size: int = 64

func _ready() -> void:
	z_index = (z_level - 1) * 200 + z_index
	add_to_group("z_entity")
	if Engine.is_editor_hint(): return
	var tile_pos := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
	global_position = Vector2((tile_pos.x + 0.5) * TILE_SIZE, (tile_pos.y + 0.5) * TILE_SIZE)
	_update_sprite()
	if state == DoorState.CLOSED:
		World.register_solid(tile_pos, z_level, self)
	add_to_group("door")

func _exit_tree() -> void:
	if Engine.is_editor_hint(): return
	var tile_pos := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
	World.unregister_solid(tile_pos, z_level, self)

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _is_animating: return
	_anim_timer += delta
	var progress = clamp(_anim_timer / _anim_duration, 0.0, 1.0)
	var current_frame = int(progress * _anim_frames)
	if current_frame >= _anim_frames: current_frame = _anim_frames - 1
	sprite.region_rect = Rect2(current_frame * _frame_size, 0, _frame_size, _frame_size)
	if progress >= 1.0: _is_animating = false

func _update_sprite() -> void:
	_is_animating = false
	sprite.region_enabled = false
	match state:
		DoorState.CLOSED: sprite.texture = load("res://doors/doorshut.png")
		DoorState.OPEN: sprite.texture = load("res://doors/dooropen.png")
		DoorState.OPENING:
			sprite.texture = load("res://doors/door-opening.png")
			_start_animation()
			return
		DoorState.CLOSING:
			sprite.texture = load("res://doors/door-closing.png")
			_start_animation()
			return
		DoorState.DESTROYED: sprite.texture = load("res://doors/doorbroken.png")

	if sprite.texture != null:
		var tex_h = sprite.texture.get_height()
		var scale_factor = 64.0 / float(tex_h)
		sprite.scale = Vector2(scale_factor, scale_factor)

func _start_animation() -> void:
	if sprite.texture != null:
		sprite.region_enabled = true
		_frame_size = sprite.texture.get_height()
		_anim_frames = int(sprite.texture.get_width() / float(_frame_size))
		if _anim_frames < 1: _anim_frames = 1
		var scale_factor = 64.0 / float(_frame_size)
		sprite.scale = Vector2(scale_factor, scale_factor)
		_anim_timer = 0.0
		_is_animating = true
		sprite.region_rect = Rect2(0, 0, _frame_size, _frame_size)

func _update_solidity() -> void:
	var tile_pos := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
	if state == DoorState.CLOSED or state == DoorState.CLOSING: World.register_solid(tile_pos, z_level, self)
	else: World.unregister_solid(tile_pos, z_level, self)

func open_door() -> void:
	if state == DoorState.CLOSED:
		state = DoorState.OPENING
		_update_sprite()
		_update_solidity()
		await get_tree().create_timer(0.4).timeout
		if state == DoorState.OPENING:
			state = DoorState.OPEN
			_update_sprite()

func close_door() -> void:
	if state == DoorState.OPEN:
		state = DoorState.CLOSING
		_update_sprite()
		_update_solidity()
		await get_tree().create_timer(0.4).timeout
		if state == DoorState.CLOSING:
			state = DoorState.CLOSED
			_update_sprite()

func toggle_door() -> void:
	if state == DoorState.CLOSED: open_door()
	elif state == DoorState.OPEN: close_door()

func destroy_door() -> void:
	state = DoorState.DESTROYED
	_update_sprite()
	var tile_pos := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
	World.unregister_solid(tile_pos, z_level, self)

func remove_completely() -> void:
	var tile_pos := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
	World.unregister_solid(tile_pos, z_level, self)
	queue_free()

func perform_hit(_main_node: Node) -> void:
	if _main_node != null and _main_node.has_method("shake_tile"):
		var t := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
		_main_node.shake_tile(t, z_level)

func get_description() -> String:
	match state:
		DoorState.CLOSED: return "a closed wooden door"
		DoorState.OPEN: return "an open wooden door"
		DoorState.OPENING: return "a wooden door, opening"
		DoorState.CLOSING: return "a wooden door, closing"
		DoorState.DESTROYED: return "a destroyed door"
	return "a door"