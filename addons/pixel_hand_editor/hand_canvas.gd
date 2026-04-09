@tool
extends Control

signal offset_changed(new_offset: Vector2)
signal clothing_offset_changed(new_offset: Vector2)

const CANVAS_SCALE: int = 3
const CANVAS_PX: int = 320
const CENTER: Vector2 = Vector2(160.0, 160.0)
const PLAYER_DISP: float = 192.0

var player_tex: Texture2D = null
var facing: int = 0

var item_preview: Dictionary = {}
var active_item_variant: String = "hand"
var other_item_variant: String = "hand"

var active_hand: int = 0
var offset: Vector2 = Vector2(20.0, 8.0)
var active_rotation: float = 0.0
var item_game_scale: float = 1.0

var other_offset: Vector2 = Vector2(-20.0, 8.0)
var other_rotation: float = 0.0
var other_scale: float = 1.0

var flipped: bool = false
var other_flipped: bool = false

var clothing_mode: bool = false
var clothing_tex: Texture2D = null
var clothing_offset: Vector2 = Vector2.ZERO
var clothing_scale: float = 1.0
var clothing_layer: int = 1

var _dragging: bool = false
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_start_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	custom_minimum_size = Vector2(CANVAS_PX, CANVAS_PX)
	clip_contents = true


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(CANVAS_PX, CANVAS_PX)), Color(0.10, 0.10, 0.10))

	for i in range(0, CANVAS_PX + 1, CANVAS_SCALE):
		draw_line(Vector2(i, 0), Vector2(i, CANVAS_PX), Color(1, 1, 1, 0.05))
		draw_line(Vector2(0, i), Vector2(CANVAS_PX, i), Color(1, 1, 1, 0.05))

	if clothing_mode:
		_draw_clothing_preview()
	else:
		_draw_item_preview()

	draw_line(Vector2(CENTER.x - 6, CENTER.y), Vector2(CENTER.x + 6, CENTER.y), Color(1, 0.2, 0.2, 0.7), 1.0)
	draw_line(Vector2(CENTER.x, CENTER.y - 6), Vector2(CENTER.x, CENTER.y + 6), Color(1, 0.2, 0.2, 0.7), 1.0)


func _draw_item_preview() -> void:
	var draw_behind_player := (facing == 1)
	if draw_behind_player:
		_draw_non_active_item()
		_draw_active_item()

	_draw_player()

	if not draw_behind_player:
		_draw_non_active_item()
		_draw_active_item()

	var font := ThemeDB.fallback_font
	var hand_label := "R" if active_hand == 0 else "L" if active_hand == 1 else "W"
	draw_string(
		font,
		Vector2(4, CANVAS_PX - 20),
		"%s: (%d, %d)%s [rot: %.1f]" % [hand_label, int(offset.x), int(offset.y), " [flipped]" if flipped else "", active_rotation],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		Color.YELLOW
	)


func _draw_clothing_preview() -> void:
	if clothing_layer < 0:
		_draw_clothing_sprite()

	_draw_player()

	if clothing_layer >= 0:
		_draw_clothing_sprite()

	var font := ThemeDB.fallback_font
	var dir_names := ["South", "North", "East", "West"]
	draw_string(
		font,
		Vector2(4, CANVAS_PX - 8),
		"Facing: %s | Offset: (%d, %d) | Layer: %d" % [dir_names[facing], int(clothing_offset.x), int(clothing_offset.y), clothing_layer],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color(0.9, 0.9, 0.9)
	)


func _draw_player() -> void:
	if player_tex == null:
		return
	var src := Rect2(facing * 32.0, 0.0, 32.0, 32.0)
	var dest := Rect2(CENTER.x - PLAYER_DISP * 0.5, CENTER.y - PLAYER_DISP * 0.5, PLAYER_DISP, PLAYER_DISP)
	draw_texture_rect_region(player_tex, dest, src)


func _draw_non_active_item() -> void:
	var tint := Color(0.40, 0.70, 1.00, 0.55)
	_draw_item(other_offset, other_rotation, tint, false, other_flipped, other_scale, other_item_variant)


func _draw_active_item() -> void:
	var tint := Color(1.00, 0.95, 0.35, 0.92)
	_draw_item(offset, active_rotation, tint, true, flipped, item_game_scale, active_item_variant)


func _draw_clothing_sprite() -> void:
	if clothing_tex == null:
		return
	var draw_scale := 2.0 * clothing_scale * float(CANVAS_SCALE)
	var size := 32.0 * draw_scale
	var center := CENTER + clothing_offset * float(CANVAS_SCALE)
	var cloth_dest := Rect2(center.x - size * 0.5, center.y - size * 0.5, size, size)
	var src := Rect2(facing * 32.0, 0.0, 32.0, 32.0)

	draw_texture_rect_region(clothing_tex, cloth_dest, src, Color(1, 1, 1, 0.95))
	draw_rect(cloth_dest, Color(0.6, 0.9, 1.0, 0.4), false, 1.0)


func _draw_item(item_offset: Vector2, rot: float, tint: Color, show_border: bool, flip_h: bool, extra_scale: float, variant: String) -> void:
	var draw_data := _get_variant_data(variant)
	var texture: Texture2D = draw_data.get("texture", null)
	if texture == null:
		return

	var source_size := _get_source_size(draw_data, texture)
	if source_size == Vector2.ZERO:
		return

	var scale: Vector2 = draw_data.get("scale", Vector2.ONE)
	var display_size := Vector2(
		source_size.x * scale.x * extra_scale * float(CANVAS_SCALE),
		source_size.y * scale.y * extra_scale * float(CANVAS_SCALE)
	)
	var center := CENTER + item_offset * float(CANVAS_SCALE)
	var dest := Rect2(-display_size.x * 0.5, -display_size.y * 0.5, display_size.x, display_size.y)

	var draw_flip := flip_h
	if facing == 3:
		draw_flip = not draw_flip

	draw_set_transform(center, deg_to_rad(rot), Vector2(-1.0 if draw_flip else 1.0, 1.0))
	if bool(draw_data.get("region_enabled", false)):
		draw_texture_rect_region(texture, dest, draw_data.get("region_rect", Rect2()), tint)
	else:
		draw_texture_rect(texture, dest, false, tint)
	if show_border:
		draw_rect(dest, Color(1.0, 1.0, 0.2, 0.5), false, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _get_variant_data(variant: String) -> Dictionary:
	return item_preview.get(variant, {})


func _get_source_size(draw_data: Dictionary, texture: Texture2D) -> Vector2:
	if bool(draw_data.get("region_enabled", false)):
		var region: Rect2 = draw_data.get("region_rect", Rect2())
		return region.size
	return texture.get_size()


func _get_active_hit_radius() -> float:
	if clothing_mode:
		return 0.0
	var draw_data := _get_variant_data(active_item_variant)
	var texture: Texture2D = draw_data.get("texture", null)
	if texture == null:
		return 0.0
	var source_size := _get_source_size(draw_data, texture)
	var scale: Vector2 = draw_data.get("scale", Vector2.ONE)
	return maxf(source_size.x * scale.x, source_size.y * scale.y) * item_game_scale * float(CANVAS_SCALE) * 0.5


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if clothing_mode:
				if clothing_tex != null:
					var draw_scale := 2.0 * clothing_scale * float(CANVAS_SCALE)
					var size := 32.0 * draw_scale
					var center := CENTER + clothing_offset * float(CANVAS_SCALE)
					var cloth_rect := Rect2(center.x - size * 0.5, center.y - size * 0.5, size, size)
					if cloth_rect.has_point(event.position):
						_dragging = true
						_drag_start_mouse = event.position
						_drag_start_offset = clothing_offset
						accept_event()
			else:
				var center := CENTER + offset * float(CANVAS_SCALE)
				if event.position.distance_to(center) <= _get_active_hit_radius():
					_dragging = true
					_drag_start_mouse = event.position
					_drag_start_offset = offset
					accept_event()
		else:
			_dragging = false

	elif event is InputEventMouseMotion and _dragging:
		var screen_delta: Vector2 = event.position - _drag_start_mouse
		var world_delta: Vector2 = screen_delta / float(CANVAS_SCALE)

		if clothing_mode:
			clothing_offset = Vector2(round(_drag_start_offset.x + world_delta.x), round(_drag_start_offset.y + world_delta.y))
			emit_signal("clothing_offset_changed", clothing_offset)
			queue_redraw()
			accept_event()
		else:
			offset = Vector2(round(_drag_start_offset.x + world_delta.x), round(_drag_start_offset.y + world_delta.y))
			emit_signal("offset_changed", offset)
			queue_redraw()
			accept_event()
