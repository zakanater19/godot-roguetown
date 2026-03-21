# Full file: project/addons/pixel_hand_editor/hand_canvas.gd

@tool
extends Control

# Emitted when the user drag-moves the active hand's item.
signal offset_changed(new_offset: Vector2)

# Emitted when the user drag-moves a clothing item.
signal clothing_offset_changed(new_offset: Vector2)

# ── Display constants ─────────────────────────────────────────────────────────
const CANVAS_SCALE: int     = 3
const CANVAS_PX:    int     = 320
const CENTER:       Vector2 = Vector2(160.0, 160.0)
const PLAYER_DISP:  float   = 192.0   # 64 world-units * 3 screen-px-per-world-unit

# ── Properties set by the panel ───────────────────────────────────────────────
var player_tex:       Texture2D = null
var objects_tex:      Texture2D = null
var item_col:         int       = 0
var item_game_scale:  float     = 1.0
var facing:           int       = 0

# 0 = right hand active, 1 = left hand active, 2 = waist active
var active_hand:   int     = 0

# Offset/rotation of the active hand (world units)
var offset:          Vector2 = Vector2(20.0, 8.0)
var active_rotation: float   = 0.0

# Offset/rotation of the inactive hand -- shown as ghost
var other_offset:    Vector2 = Vector2(-20.0, 8.0)
var other_rotation:  float   = 0.0

# Flip state for each hand
var flipped:       bool    = false
var other_flipped: bool    = false

# ── Clothing preview mode ─────────────────────────────────────────────────────
# When true the canvas shows the player sprite + clothing overlay only.
var clothing_mode:   bool      = false
var clothing_tex:    Texture2D = null
var clothing_offset: Vector2   = Vector2.ZERO
var clothing_scale:  float     = 1.0

# ── Drag state ────────────────────────────────────────────────────────────────
var _dragging:          bool    = false
var _drag_start_mouse:  Vector2 = Vector2.ZERO
var _drag_start_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	custom_minimum_size = Vector2(CANVAS_PX, CANVAS_PX)
	clip_contents        = true


# ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	# Dark background
	draw_rect(Rect2(Vector2.ZERO, Vector2(CANVAS_PX, CANVAS_PX)), Color(0.10, 0.10, 0.10))

	# Subtle per-world-pixel grid
	for i in range(0, CANVAS_PX + 1, CANVAS_SCALE):
		draw_line(Vector2(i, 0),  Vector2(i, CANVAS_PX),  Color(1, 1, 1, 0.05))
		draw_line(Vector2(0, i),  Vector2(CANVAS_PX, i),  Color(1, 1, 1, 0.05))

	if clothing_mode:
		_draw_clothing_preview()
		return

	# Ghost hand (behind player)
	if objects_tex != null:
		# Ghost is not interactive/scale-mutable, keeping basic
		_draw_item(other_offset, other_rotation, Color(0.40, 0.70, 1.00, 0.55), false, other_flipped, 1.0)

	# Player sprite
	if player_tex != null:
		var src  := Rect2(facing * 32.0, 0.0, 32.0, 32.0)
		var dest := Rect2(
			CENTER.x - PLAYER_DISP * 0.5,
			CENTER.y - PLAYER_DISP * 0.5,
			PLAYER_DISP, PLAYER_DISP
		)
		draw_texture_rect_region(player_tex, dest, src)

	# Active hand item (over player)
	if objects_tex != null:
		_draw_item(offset, active_rotation, Color(1.00, 0.95, 0.35, 0.92), true, flipped, item_game_scale)

	# Player-centre crosshair
	draw_line(Vector2(CENTER.x - 6, CENTER.y), Vector2(CENTER.x + 6, CENTER.y),
			  Color(1, 0.2, 0.2, 0.7), 1.0)
	draw_line(Vector2(CENTER.x, CENTER.y - 6), Vector2(CENTER.x, CENTER.y + 6),
			  Color(1, 0.2, 0.2, 0.7), 1.0)

	# Coordinate readout
	var font       := ThemeDB.fallback_font
	var hand_label := "R" if active_hand == 0 else "L" if active_hand == 1 else "W"
	var other_lbl  := "L" if active_hand == 0 else "R"
	draw_string(font, Vector2(4, CANVAS_PX - 20),
				"%s: (%d, %d)%s [rot: %.1f] [scale: %.2f]" %[hand_label, int(offset.x), int(offset.y),
				"  [flipped]" if flipped else "", active_rotation, item_game_scale],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.YELLOW)
	draw_string(font, Vector2(4, CANVAS_PX - 6),
				"%s: (%d, %d)%s[rot: %.1f]" %[other_lbl, int(other_offset.x), int(other_offset.y),
				"  [flipped]" if other_flipped else "", other_rotation],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.75, 1.0))


func _draw_clothing_preview() -> void:
	var dest := Rect2(
		CENTER.x - PLAYER_DISP * 0.5,
		CENTER.y - PLAYER_DISP * 0.5,
		PLAYER_DISP, PLAYER_DISP
	)
	if player_tex != null:
		var src := Rect2(facing * 32.0, 0.0, 32.0, 32.0)
		draw_texture_rect_region(player_tex, dest, src)

	if clothing_tex != null:
		var draw_scale := 2.0 * clothing_scale * float(CANVAS_SCALE)
		var size       := 32.0 * draw_scale
		var center     := CENTER + clothing_offset * float(CANVAS_SCALE)
		var cloth_dest := Rect2(center.x - size * 0.5, center.y - size * 0.5, size, size)
		var src        := Rect2(facing * 32.0, 0.0, 32.0, 32.0)
		
		draw_texture_rect_region(clothing_tex, cloth_dest, src, Color(1, 1, 1, 0.95))
		draw_rect(cloth_dest, Color(0.6, 0.9, 1.0, 0.4), false, 1.0)

	draw_line(Vector2(CENTER.x - 6, CENTER.y), Vector2(CENTER.x + 6, CENTER.y),
			  Color(1, 0.2, 0.2, 0.7), 1.0)
	draw_line(Vector2(CENTER.x, CENTER.y - 6), Vector2(CENTER.x, CENTER.y + 6),
			  Color(1, 0.2, 0.2, 0.7), 1.0)

	var dir_names :=["South", "North", "East", "West"]
	var font      := ThemeDB.fallback_font
	draw_string(font, Vector2(4, CANVAS_PX - 8),
				"Facing: " + dir_names[facing] + " | Offset: (" + str(int(clothing_offset.x)) + ", " + str(int(clothing_offset.y)) + ")",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.9, 0.9))


func _draw_item(item_offset: Vector2, rot: float, tint: Color, show_border: bool, flip_h: bool, scale_val: float) -> void:
	if objects_tex == null:
		return
	
	var draw_flip = flip_h
	if facing == 3:
		draw_flip = not draw_flip
		
	var center       := CENTER + item_offset * float(CANVAS_SCALE)
	var display_size := 64.0 * scale_val * float(CANVAS_SCALE)
	var half         := display_size * 0.5

	var src  := Rect2(item_col * 64.0, 0.0, 64.0, 64.0)
	var dest := Rect2(-half, -half, display_size, display_size)

	if draw_flip:
		draw_set_transform(center, deg_to_rad(rot), Vector2(-1.0, 1.0))
	else:
		draw_set_transform(center, deg_to_rad(rot), Vector2.ONE)
		
	draw_texture_rect_region(objects_tex, dest, src, tint)
	
	if show_border:
		draw_rect(dest, Color(1.0, 1.0, 0.2, 0.5), false, 1.0)
		
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ── Mouse input ───────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if clothing_mode:
				if clothing_tex != null:
					var draw_scale := 2.0 * clothing_scale * float(CANVAS_SCALE)
					var size       := 32.0 * draw_scale
					var center     := CENTER + clothing_offset * float(CANVAS_SCALE)
					var cloth_rect := Rect2(center.x - size * 0.5, center.y - size * 0.5, size, size)
					
					if cloth_rect.has_point(event.position):
						_dragging          = true
						_drag_start_mouse  = event.position
						_drag_start_offset = clothing_offset
						accept_event()
			else:
				var center       := CENTER + offset * float(CANVAS_SCALE)
				var display_size := 64.0 * item_game_scale * float(CANVAS_SCALE)
				var half         := display_size * 0.5
				var item_rect    := Rect2(center.x - half, center.y - half, display_size, display_size)
				
				if item_rect.has_point(event.position):
					_dragging          = true
					_drag_start_mouse  = event.position
					_drag_start_offset = offset
					accept_event()
		else:
			_dragging = false

	elif event is InputEventMouseMotion and _dragging:
		var screen_delta: Vector2 = event.position - _drag_start_mouse
		var world_delta:  Vector2 = screen_delta / float(CANVAS_SCALE)
		
		if clothing_mode:
			clothing_offset = Vector2(
				round(_drag_start_offset.x + world_delta.x),
				round(_drag_start_offset.y + world_delta.y)
			)
			emit_signal("clothing_offset_changed", clothing_offset)
			queue_redraw()
			accept_event()
		else:
			offset = Vector2(
				round(_drag_start_offset.x + world_delta.x),
				round(_drag_start_offset.y + world_delta.y)
			)
			emit_signal("offset_changed", offset)
			queue_redraw()
			accept_event()
			