# res://scripts/ui/loading_screen.gd
# Autoload: LoadingScreen
#
# Persistent full-screen overlay shown during:
#   • Scene transition (connecting / starting server)
#   • Version check & resource diff download
#   • World-state sync from server
#
# Sits at CanvasLayer 100 so it covers every other UI layer.

extends CanvasLayer

signal primary_action_pressed
signal secondary_action_pressed

var _status_label:   RichTextLabel
var _progress_bar:   ProgressBar
var _detail_label:   Label
var _primary_button: Button
var _secondary_button: Button
var _action_row: HBoxContainer

func _ready() -> void:
	layer = 100
	_build_ui()
	hide()


func _build_ui() -> void:
	# Dark translucent backdrop
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.07, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Centred panel
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(440, 210)
	panel.set_anchor(SIDE_LEFT,   0.5)
	panel.set_anchor(SIDE_TOP,    0.5)
	panel.set_anchor(SIDE_RIGHT,  0.5)
	panel.set_anchor(SIDE_BOTTOM, 0.5)
	panel.offset_left   = -220
	panel.offset_top    = -105
	panel.offset_right  =  220
	panel.offset_bottom =  105
	add_child(panel)

	# Margin inside panel
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(edge, 28)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Loading"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	_status_label = RichTextLabel.new()
	_status_label.bbcode_enabled       = true
	_status_label.fit_content          = true
	_status_label.scroll_active        = false
	_status_label.custom_minimum_size  = Vector2(380, 0)
	_status_label.text = "Please wait..."
	vbox.add_child(_status_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value            = 0.0
	_progress_bar.max_value            = 1.0
	_progress_bar.value                = 0.0
	_progress_bar.custom_minimum_size.y = 18
	_progress_bar.visible              = false
	vbox.add_child(_progress_bar)

	_detail_label = Label.new()
	_detail_label.text = ""
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	_detail_label.visible = false
	vbox.add_child(_detail_label)

	_action_row = HBoxContainer.new()
	_action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_action_row.add_theme_constant_override("separation", 12)
	_action_row.visible = false
	vbox.add_child(_action_row)

	_primary_button = Button.new()
	_primary_button.text = "Retry"
	_primary_button.custom_minimum_size = Vector2(120, 38)
	_primary_button.pressed.connect(func() -> void:
		primary_action_pressed.emit()
	)
	_action_row.add_child(_primary_button)

	_secondary_button = Button.new()
	_secondary_button.text = "Server List"
	_secondary_button.custom_minimum_size = Vector2(120, 38)
	_secondary_button.pressed.connect(func() -> void:
		secondary_action_pressed.emit()
	)
	_action_row.add_child(_secondary_button)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Show the overlay with an initial status message.
func show_loading(status: String) -> void:
	_status_label.text     = status
	_progress_bar.visible  = false
	_detail_label.visible  = false
	_action_row.visible    = false
	show()


## Update the status text and optionally display a progress bar.
## Pass progress < 0 to hide the bar.  Pass detail = "" to hide the sub-label.
func update_status(status: String, progress: float = -1.0, detail: String = "") -> void:
	_status_label.text = status
	if progress >= 0.0:
		_progress_bar.value   = progress
		_progress_bar.visible = true
	else:
		_progress_bar.visible = false
	_detail_label.text    = detail
	_detail_label.visible = detail != ""


func show_action_prompt(
	status: String,
	detail: String = "",
	primary_text: String = "Retry",
	secondary_text: String = "Server List"
) -> void:
	show_loading(status)
	update_status(status, -1.0, detail)
	_primary_button.text = primary_text
	_secondary_button.text = secondary_text
	_action_row.visible = true


## Hide the overlay.  Safe to call even when already hidden.
func hide_loading() -> void:
	_action_row.visible = false
	hide()
