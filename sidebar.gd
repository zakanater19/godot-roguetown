# res://sidebar.gd
# AutoLoad singleton — registered as "Sidebar" in project.godot.
# Manages the right-side log panel.
extends Node

const MAX_MESSAGES:  int   = 100

var _canvas:   CanvasLayer  = null
var _rtl:      RichTextLabel = null
var _messages: Array[String] =[]

# NEW (for the requested stats menu only)
var _stats_time_label: Label = null


func _ready() -> void:
	_build()


func _process(_delta: float) -> void:
	if _stats_time_label == null:
		return
		
	if Lobby.game_started:
		# Format into Hours and Minutes
		var hours := int(Lobby.round_time / 3600.0)
		var minutes := int(Lobby.round_time / 60.0) % 60
		_stats_time_label.text = "round time: %02d:%02d" % [hours, minutes]
	else:
		# Keep it zeroed out while in the Lobby
		_stats_time_label.text = "round time: 00:00"


func set_visible(is_visible: bool) -> void:
	if _canvas:
		_canvas.visible = is_visible


func _build() -> void:
	_canvas       = CanvasLayer.new()
	_canvas.layer = 20
	add_child(_canvas)

	# Root control filling the whole viewport
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(root)

	# Mask for bottom area to enforce exactly 720px vertical view height
	var bottom_mask := ColorRect.new()
	bottom_mask.color = Color(0.0, 0.0, 0.0, 1.0)
	bottom_mask.anchor_left = 0.0
	bottom_mask.anchor_right = 1.0
	bottom_mask.anchor_top = 0.0
	bottom_mask.anchor_bottom = 1.0
	bottom_mask.offset_left = 0.0
	bottom_mask.offset_right = 0.0
	bottom_mask.offset_top = 720.0
	bottom_mask.offset_bottom = 0.0
	bottom_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom_mask)

	# Dark grey panel stretching from x=1000 to the right edge
	var panel := Panel.new()
	panel.anchor_left   = 0.0
	panel.anchor_right  = 1.0
	panel.anchor_top    = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left   = 1000.0
	panel.offset_right  = 0.0
	panel.offset_top    = 0.0
	panel.offset_bottom = 0.0

	# Override panel style to be dark grey
	var style := StyleBoxFlat.new()
	style.bg_color        = Color(0.10, 0.10, 0.10, 1.0)
	style.border_width_left = 2
	style.border_color    = Color(0.30, 0.30, 0.30, 1.0)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(panel)

	# === TOP FOURTH STATS MENU ===
	var content_vbox := VBoxContainer.new()
	content_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_vbox.add_theme_constant_override("separation", 0)
	panel.add_child(content_vbox)

	# Top stats area (top fourth = 180 px)
	var stats_panel := Panel.new()
	stats_panel.custom_minimum_size = Vector2(0, 180)
	stats_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var stats_style := StyleBoxFlat.new()
	stats_style.bg_color = Color(0.10, 0.10, 0.10, 1.0)
	stats_style.border_width_left = 2
	stats_style.border_color = Color(0.30, 0.30, 0.30, 1.0)
	stats_panel.add_theme_stylebox_override("panel", stats_style)
	stats_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	content_vbox.add_child(stats_panel)

	var stats_inner := VBoxContainer.new()
	stats_inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stats_inner.offset_left = 6
	stats_inner.offset_right = -6
	stats_inner.offset_top = 6
	stats_inner.offset_bottom = -6
	stats_inner.add_theme_constant_override("separation", 8)
	stats_panel.add_child(stats_inner)

	var tab_lbl := Label.new()
	tab_lbl.text = "STATS"
	tab_lbl.add_theme_font_size_override("font_size", 18)
	tab_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	tab_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_inner.add_child(tab_lbl)

	_stats_time_label = Label.new()
	_stats_time_label.text = "round time: 00:00"
	_stats_time_label.add_theme_font_size_override("font_size", 14)
	_stats_time_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	_stats_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_inner.add_child(_stats_time_label)

	# === NEW: Thin separator line at the bottom of the top section ===
	var separator := HSeparator.new()
	separator.custom_minimum_size = Vector2(0, 2)
	content_vbox.add_child(separator)

	# === ORIGINAL LOG SECTION (unchanged, now fills the bottom three-quarters) ===
	var log_container := Control.new()
	log_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_vbox.add_child(log_container)

	# RichTextLabel (Log) fills the remaining space
	_rtl = RichTextLabel.new()
	_rtl.bbcode_enabled   = true
	_rtl.scroll_following = true
	_rtl.selection_enabled = false
	_rtl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rtl.offset_left   = 6.0
	_rtl.offset_right  = -4.0
	_rtl.offset_top    = 6.0
	_rtl.offset_bottom = -6.0
	_rtl.add_theme_color_override("default_color",      Color(1.0, 1.0, 1.0))
	_rtl.add_theme_color_override("font_shadow_color",  Color(0.0, 0.0, 0.0, 0.5))
	_rtl.add_theme_constant_override("shadow_offset_x", 1)
	_rtl.add_theme_constant_override("shadow_offset_y", 1)
	_rtl.add_theme_font_size_override("normal_font_size", 12)
	_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_container.add_child(_rtl)


func add_message(text: String) -> void:
	if _rtl == null:
		return

	_messages.append(text)

	# Trim oldest when over the cap
	while _messages.size() > MAX_MESSAGES:
		_messages.pop_front()

	# Rebuild the full text
	_rtl.text = "\n".join(_messages)
	
