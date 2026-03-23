# res://sidebar.gd
# AutoLoad singleton — registered as "Sidebar" in project.godot.
# Manages the right-side log panel.
extends Node

const MAX_MESSAGES:  int   = 100

var _canvas:   CanvasLayer  = null
var _rtl:      RichTextLabel = null
var _messages: Array[String] =[]

# Stats & Laws Menu Variables
var _stats_time_label: Label = null
var _stats_day_label: Label = null
var _stats_view: VBoxContainer = null

var _laws_view: VBoxContainer = null
var _laws_list_vbox: VBoxContainer = null
var _edit_laws_btn: Button = null

var _edit_laws_view: VBoxContainer = null
var _edit_list_vbox: VBoxContainer = null

var _debug_view: VBoxContainer = null


func _ready() -> void:
	_build()


func _process(_delta: float) -> void:
	if _stats_time_label == null:
		return
		
	if Lobby.game_started:
		# Format into Hours and Minutes
		var hours := int(Lobby.round_time / 3600.0)
		var minutes := int(Lobby.round_time / 60.0) % 60
		_stats_time_label.text = "round time: %02d:%02d" %[hours, minutes]
	else:
		# Keep it zeroed out while in the Lobby
		_stats_time_label.text = "round time: 00:00"
		
	if _stats_day_label != null:
		_stats_day_label.text = "day: " + str(Lighting.current_day)


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

	# Setup the tab buttons
	var tabs_hbox := HBoxContainer.new()
	stats_inner.add_child(tabs_hbox)

	var btn_stats := Button.new()
	btn_stats.text = "STATS"
	btn_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_stats.pressed.connect(_on_tab_stats_pressed)
	tabs_hbox.add_child(btn_stats)

	var btn_laws := Button.new()
	btn_laws.text = "LAWS"
	btn_laws.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_laws.pressed.connect(_on_tab_laws_pressed)
	tabs_hbox.add_child(btn_laws)
	
	var btn_debug := Button.new()
	btn_debug.text = "DEBUG"
	btn_debug.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_debug.pressed.connect(_on_tab_debug_pressed)
	tabs_hbox.add_child(btn_debug)

	# --- View Containers ---
	
	# 1. Stats View
	_stats_view = VBoxContainer.new()
	_stats_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_inner.add_child(_stats_view)

	_stats_time_label = Label.new()
	_stats_time_label.text = "round time: 00:00"
	_stats_time_label.add_theme_font_size_override("font_size", 14)
	_stats_time_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	_stats_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_view.add_child(_stats_time_label)

	_stats_day_label = Label.new()
	_stats_day_label.text = "day: 1"
	_stats_day_label.add_theme_font_size_override("font_size", 12)
	_stats_day_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_stats_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_view.add_child(_stats_day_label)

	# 2. Laws View (Read Only)
	_laws_view = VBoxContainer.new()
	_laws_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_laws_view.visible = false
	stats_inner.add_child(_laws_view)

	var laws_scroll := ScrollContainer.new()
	laws_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_laws_view.add_child(laws_scroll)

	_laws_list_vbox = VBoxContainer.new()
	_laws_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	laws_scroll.add_child(_laws_list_vbox)

	_edit_laws_btn = Button.new()
	_edit_laws_btn.text = "Edit Laws"
	_edit_laws_btn.visible = false
	_edit_laws_btn.pressed.connect(_on_edit_laws_pressed)
	_laws_view.add_child(_edit_laws_btn)

	# 3. Edit Laws View
	_edit_laws_view = VBoxContainer.new()
	_edit_laws_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_edit_laws_view.visible = false
	stats_inner.add_child(_edit_laws_view)

	var edit_scroll := ScrollContainer.new()
	edit_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_edit_laws_view.add_child(edit_scroll)

	_edit_list_vbox = VBoxContainer.new()
	_edit_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_scroll.add_child(_edit_list_vbox)

	var edit_actions_hbox := HBoxContainer.new()
	_edit_laws_view.add_child(edit_actions_hbox)

	var add_law_btn := Button.new()
	add_law_btn.text = "Add Law"
	add_law_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_law_btn.pressed.connect(_on_add_law_pressed)
	edit_actions_hbox.add_child(add_law_btn)

	var save_laws_btn := Button.new()
	save_laws_btn.text = "Save"
	save_laws_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_laws_btn.pressed.connect(_on_save_laws_pressed)
	edit_actions_hbox.add_child(save_laws_btn)

	var cancel_laws_btn := Button.new()
	cancel_laws_btn.text = "Cancel"
	cancel_laws_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_laws_btn.pressed.connect(_on_cancel_laws_pressed)
	edit_actions_hbox.add_child(cancel_laws_btn)
	
	# 4. Debug View
	_debug_view = VBoxContainer.new()
	_debug_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_debug_view.visible = false
	stats_inner.add_child(_debug_view)

	# Lighting Toggle Button
	var btn_time_toggle := Button.new()
	btn_time_toggle.text = "Toggle Midnight/Midday"
	btn_time_toggle.pressed.connect(_on_toggle_time_pressed)
	_debug_view.add_child(btn_time_toggle)

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

# --- Tab Logic ---

func _on_toggle_time_pressed() -> void:
	Lighting.toggle_time_of_day()

func _on_tab_stats_pressed() -> void:
	if _stats_view == null: return
	_stats_view.visible = true
	_laws_view.visible = false
	_edit_laws_view.visible = false
	if _debug_view: _debug_view.visible = false

func _on_tab_laws_pressed() -> void:
	if _laws_view == null: return
	_stats_view.visible = false
	_laws_view.visible = true
	_edit_laws_view.visible = false
	if _debug_view: _debug_view.visible = false
	refresh_laws_ui()

func _on_tab_debug_pressed() -> void:
	if _debug_view == null: return
	_stats_view.visible = false
	_laws_view.visible = false
	_edit_laws_view.visible = false
	_debug_view.visible = true

func refresh_laws_ui() -> void:
	if _laws_list_vbox == null: return
	
	for child in _laws_list_vbox.get_children():
		child.queue_free()
		
	var laws = World.current_laws
	if laws.is_empty():
		var lbl = Label.new()
		lbl.text = "No laws set."
		lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_laws_list_vbox.add_child(lbl)
	else:
		for i in range(laws.size()):
			var lbl = Label.new()
			lbl.text = laws[i]
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.add_theme_font_size_override("font_size", 12)
			_laws_list_vbox.add_child(lbl)
			
	_edit_laws_btn.visible = false
	var player = World.get_local_player()
	if player != null and player.character_class == "king":
		_edit_laws_btn.visible = true

func _on_edit_laws_pressed() -> void:
	if _edit_laws_view == null: return
	_laws_view.visible = false
	_edit_laws_view.visible = true
	_build_edit_laws_list()

func _build_edit_laws_list() -> void:
	for child in _edit_list_vbox.get_children():
		child.queue_free()
		
	var laws = World.current_laws
	for i in range(laws.size()):
		var law_text = laws[i]
		var prefix = "LAW " + str(i + 1) + ": "
		if law_text.begins_with(prefix):
			law_text = law_text.substr(prefix.length())
			
		_add_edit_law_row(law_text)

func _add_edit_law_row(text: String = "") -> void:
	var hbox = HBoxContainer.new()
	hbox.name = "LawRow"
	var le = LineEdit.new()
	le.name = "LawInput"
	le.text = text
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var del_btn = Button.new()
	del_btn.text = "X"
	del_btn.pressed.connect(func(): hbox.queue_free())
	hbox.add_child(le)
	hbox.add_child(del_btn)
	_edit_list_vbox.add_child(hbox)

func _on_add_law_pressed() -> void:
	_add_edit_law_row()

func _on_save_laws_pressed() -> void:
	var new_laws: Array =[]
	for child in _edit_list_vbox.get_children():
		var le = child.get_node_or_null("LawInput")
		if le and le.text.strip_edges() != "":
			new_laws.append(le.text.strip_edges())
	
	var formatted_laws =[]
	for i in range(new_laws.size()):
		formatted_laws.append("LAW " + str(i + 1) + ": " + new_laws[i])
		
	var player = World.get_local_player()
	if player != null and player.multiplayer.is_server():
		World.rpc_request_update_laws(formatted_laws)
	elif player != null:
		World.rpc_request_update_laws.rpc_id(1, formatted_laws)
		
	_on_tab_laws_pressed()

func _on_cancel_laws_pressed() -> void:
	_on_tab_laws_pressed()

func add_message(text: String) -> void:
	if _rtl == null:
		return

	_messages.append(text)

	# Trim oldest when over the cap
	while _messages.size() > MAX_MESSAGES:
		_messages.pop_front()

	# Rebuild the full text
	_rtl.text = "\n".join(_messages)
	
