@tool
extends Area2D

const TILE_SIZE: int = 64
const HITS_TO_BREAK: int = 5
const SPRITE_SCALE: float = 2.0
const DEFAULT_MATERIAL: MaterialData = preload("res://materials/metal.tres")

enum GateState { CLOSED, OPEN, DESTROYED, OPENING, CLOSING }

var state: GateState = GateState.CLOSED
var hits: float = 0.0
var blocks_fov: bool = false  # Solid but lets light/FOV through like windows
@export var z_level: int = 3
@export var material_data: MaterialData = DEFAULT_MATERIAL

@onready var sprite: Sprite2D = $Sprite2D

var _anim_timer: float = 0.0
var _is_animating: bool = false
var _anim_duration: float = 0.4
var _anim_frames: int = 1
var _frame_width: int = 96
var _frame_height: int = 32

# Gate spans 3 tiles horizontally (192px = 3 * 64)
var _tile_positions: Array[Vector2i] = []

func _ready() -> void:
	z_index = (z_level - 1) * 200 + 5
	add_to_group("z_entity")
	add_to_group("gate")
	if Engine.is_editor_hint(): return
	
	# Snap to tile grid like doors do
	var tile_pos := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
	# Center the gate on 3 tiles (tile_pos is middle tile)
	global_position = Vector2((tile_pos.x + 0.5) * TILE_SIZE, (tile_pos.y + 0.5) * TILE_SIZE)
	
	# Gate spans 3 tiles: left, center, right
	_tile_positions = [tile_pos - Vector2i(1, 0), tile_pos, tile_pos + Vector2i(1, 0)]
	
	_update_sprite()
	if state == GateState.CLOSED:
		for t_pos in _tile_positions:
			World.register_solid(t_pos, z_level, self)

func _exit_tree() -> void:
	if Engine.is_editor_hint(): return
	for t_pos in _tile_positions:
		World.unregister_solid(t_pos, z_level, self)

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _is_animating: return
	_anim_timer += delta
	var progress = clamp(_anim_timer / _anim_duration, 0.0, 1.0)
	var current_frame = int(progress * _anim_frames)
	if current_frame >= _anim_frames: current_frame = _anim_frames - 1
	sprite.region_rect = Rect2(current_frame * _frame_width, 0, _frame_width, _frame_height)
	if progress >= 1.0: _is_animating = false

func _update_sprite() -> void:
	_is_animating = false
	sprite.region_enabled = false
	sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	match state:
		GateState.CLOSED: sprite.texture = load("res://doors/gateclosed.png")
		GateState.OPEN: sprite.texture = load("res://doors/gateopen.png")
		GateState.OPENING:
			sprite.texture = load("res://doors/gate-opening.png")
			_start_animation()
			return
		GateState.CLOSING:
			sprite.texture = load("res://doors/gate-closing.png")
			_start_animation()
			return
		GateState.DESTROYED: sprite.texture = load("res://doors/gateclosed.png")

func _start_animation() -> void:
	if sprite.texture != null:
		sprite.region_enabled = true
		_frame_width = 96
		_frame_height = 32
		_anim_frames = int(sprite.texture.get_width() / float(_frame_width))
		if _anim_frames < 1: _anim_frames = 1
		sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
		_anim_timer = 0.0
		_is_animating = true
		sprite.region_rect = Rect2(0, 0, _frame_width, _frame_height)

func _update_solidity() -> void:
	# Keep collision while opening (3 seconds), only allow passage when fully open
	var is_solid = (state == GateState.CLOSED or state == GateState.CLOSING or state == GateState.OPENING)
	for tile_pos in _tile_positions:
		if is_solid:
			World.register_solid(tile_pos, z_level, self)
		else:
			World.unregister_solid(tile_pos, z_level, self)

func open_gate() -> void:
	if state == GateState.CLOSED:
		state = GateState.OPENING
		_anim_duration = 3.0  # Opening takes 3 seconds
		_update_sprite()
		_update_solidity()
		await get_tree().create_timer(3.0).timeout
		if state == GateState.OPENING:
			state = GateState.OPEN
			_update_solidity()
			_update_sprite()

func close_gate() -> void:
	if state == GateState.OPEN:
		state = GateState.CLOSING
		_anim_duration = 0.4  # Closing is fast
		_update_sprite()
		_update_solidity()
		await get_tree().create_timer(0.4).timeout
		if state == GateState.CLOSING:
			state = GateState.CLOSED
			_update_sprite()

func toggle_gate() -> void:
	if state == GateState.CLOSED: open_gate()
	elif state == GateState.OPEN: close_gate()

func destroy_gate() -> void:
	state = GateState.DESTROYED
	_update_sprite()
	for tile_pos in _tile_positions:
		World.unregister_solid(tile_pos, z_level, self)

func remove_completely() -> void:
	for tile_pos in _tile_positions:
		World.unregister_solid(tile_pos, z_level, self)
	queue_free()

func perform_hit(_main_node: Node) -> void:
	if _main_node != null and _main_node.has_method("shake_tile"):
		for tile_pos in _tile_positions:
			_main_node.shake_tile(tile_pos, z_level)

func get_description() -> String:
	match state:
		GateState.CLOSED: return "a closed iron gate"
		GateState.OPEN: return "an open iron gate"
		GateState.OPENING: return "an iron gate, opening"
		GateState.CLOSING: return "an iron gate, closing"
		GateState.DESTROYED: return "a destroyed gate"
	return "a gate"
