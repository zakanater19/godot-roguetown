class_name CharacterCreator
extends Control

signal character_saved(appearance: Dictionary)
signal character_canceled

const FACING_LABELS: Array[String] = ["Front", "Back", "Right", "Left"]

var _draft: Dictionary = {}
var _facing: int = 0
var _content_width: float = 0.0

var _sex_option: OptionButton
var _hair_option: OptionButton
var _hair_color: ColorPickerButton
var _facial_label: Label
var _facial_option: OptionButton
var _facial_color_label: Label
var _facial_color: ColorPickerButton
var _body_sprite: Sprite2D
var _hair_sprite: Sprite2D
var _facial_sprite: Sprite2D
var _rotate_button: Button
var _saved_hint: Label


func _ready() -> void:
	_apply_content_bounds()
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 100
	_build_ui()
	visible = false


## Restricts the modal and its input-blocking shade to the left-side play area.
## A width of zero restores the full-parent layout used by the main menu.
func constrain_to_content_width(width: float) -> void:
	_content_width = maxf(width, 0.0)
	if is_node_ready():
		_apply_content_bounds()


func _apply_content_bounds() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0 if _content_width > 0.0 else 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = _content_width if _content_width > 0.0 else 0.0
	offset_bottom = 0.0


func open(appearance: Dictionary = {}) -> void:
	_draft = CharacterProfile.sanitize_appearance(
		CharacterProfile.get_appearance() if appearance.is_empty() else appearance
	)
	_facing = 0
	_load_controls_from_draft()
	_saved_hint.text = "Changes are kept for this application session."
	visible = true
	_sex_option.grab_focus()


func close_without_saving() -> void:
	visible = false
	character_canceled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_without_saving()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.025, 0.03, 0.92)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -410.0
	panel.offset_top = -310.0
	panel.offset_right = 410.0
	panel.offset_bottom = 310.0
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)

	var title := Label.new()
	title.text = "CHARACTER CREATOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	root.add_child(title)

	var divider := HSeparator.new()
	root.add_child(divider)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 32)
	root.add_child(columns)

	var preview_column := VBoxContainer.new()
	preview_column.custom_minimum_size = Vector2(300, 0)
	preview_column.add_theme_constant_override("separation", 10)
	columns.add_child(preview_column)

	var preview_title := Label.new()
	preview_title.text = "Preview"
	preview_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_title.add_theme_font_size_override("font_size", 21)
	preview_column.add_child(preview_title)

	var preview_frame := PanelContainer.new()
	preview_frame.custom_minimum_size = Vector2(300, 365)
	preview_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_column.add_child(preview_frame)

	var preview_canvas := Control.new()
	preview_canvas.clip_contents = true
	preview_frame.add_child(preview_canvas)

	var preview_anchor := Node2D.new()
	preview_anchor.position = Vector2(150, 205)
	preview_canvas.add_child(preview_anchor)

	_body_sprite = _make_preview_sprite(0)
	preview_anchor.add_child(_body_sprite)
	_hair_sprite = _make_preview_sprite(5)
	preview_anchor.add_child(_hair_sprite)
	_facial_sprite = _make_preview_sprite(6)
	preview_anchor.add_child(_facial_sprite)

	_rotate_button = Button.new()
	_rotate_button.custom_minimum_size.y = 42
	_rotate_button.pressed.connect(_on_rotate_pressed)
	preview_column.add_child(_rotate_button)

	var settings := VBoxContainer.new()
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_theme_constant_override("separation", 14)
	columns.add_child(settings)

	var settings_title := Label.new()
	settings_title.text = "Appearance"
	settings_title.add_theme_font_size_override("font_size", 21)
	settings.add_child(settings_title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 16)
	settings.add_child(grid)

	_sex_option = OptionButton.new()
	_sex_option.custom_minimum_size = Vector2(270, 44)
	_add_labeled_control(grid, "Sex", _sex_option)
	_sex_option.add_item("Male")
	_sex_option.set_item_metadata(0, CharacterProfile.SEX_MALE)
	_sex_option.add_item("Female")
	_sex_option.set_item_metadata(1, CharacterProfile.SEX_FEMALE)

	_hair_option = OptionButton.new()
	_hair_option.custom_minimum_size = Vector2(270, 44)
	_add_labeled_control(grid, "Hairstyle", _hair_option)

	_hair_color = ColorPickerButton.new()
	_hair_color.custom_minimum_size = Vector2(270, 44)
	_hair_color.edit_alpha = false
	_add_labeled_control(grid, "Hair colour", _hair_color)

	_facial_option = OptionButton.new()
	_facial_option.custom_minimum_size = Vector2(270, 44)
	_facial_label = _add_labeled_control(grid, "Facial hair", _facial_option)

	_facial_color = ColorPickerButton.new()
	_facial_color.custom_minimum_size = Vector2(270, 44)
	_facial_color.edit_alpha = false
	_facial_color_label = _add_labeled_control(grid, "Facial hair colour", _facial_color)

	_saved_hint = Label.new()
	_saved_hint.text = "Changes are kept for this application session."
	_saved_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_saved_hint.add_theme_color_override("font_color", Color(0.65, 0.68, 0.72))
	settings.add_child(_saved_hint)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings.add_child(spacer)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	settings.add_child(buttons)

	var cancel_button := Button.new()
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size = Vector2(120, 48)
	cancel_button.pressed.connect(close_without_saving)
	buttons.add_child(cancel_button)

	var save_button := Button.new()
	save_button.text = "Save Character"
	save_button.custom_minimum_size = Vector2(155, 48)
	save_button.pressed.connect(_on_save_pressed)
	buttons.add_child(save_button)

	_sex_option.item_selected.connect(_on_sex_selected)
	_hair_option.item_selected.connect(_on_hair_selected)
	_hair_color.color_changed.connect(_on_hair_color_changed)
	_facial_option.item_selected.connect(_on_facial_hair_selected)
	_facial_color.color_changed.connect(_on_facial_hair_color_changed)


func _make_preview_sprite(layer: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.centered = true
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, 32, 32)
	sprite.scale = Vector2(6.0, 6.0)
	sprite.z_index = layer
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return sprite


func _add_labeled_control(grid: GridContainer, text: String, control: Control) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	grid.add_child(label)
	grid.add_child(control)
	return label


func _load_controls_from_draft() -> void:
	_select_option_by_id(_sex_option, str(_draft["sex"]))
	_populate_hair_options(str(_draft["hair_style"]))
	_populate_facial_hair_options(str(_draft["facial_hair"]))
	_hair_color.color = CharacterProfile.color_from_storage(_draft["hair_color"], Color(0.29, 0.19, 0.15))
	_facial_color.color = CharacterProfile.color_from_storage(_draft["facial_hair_color"], Color(0.23, 0.15, 0.12))
	_update_facial_controls()
	_update_preview()


func _populate_hair_options(selected_id: String) -> void:
	_hair_option.clear()
	for option in CharacterProfile.get_hair_options(str(_draft["sex"])):
		_hair_option.add_item(str(option["label"]))
		_hair_option.set_item_metadata(_hair_option.item_count - 1, str(option["id"]))
	_select_option_by_id(_hair_option, selected_id)
	_draft["hair_style"] = str(_hair_option.get_item_metadata(_hair_option.selected))


func _populate_facial_hair_options(selected_id: String) -> void:
	_facial_option.clear()
	for option in CharacterProfile.get_facial_hair_options():
		_facial_option.add_item(str(option["label"]))
		_facial_option.set_item_metadata(_facial_option.item_count - 1, str(option["id"]))
	_select_option_by_id(_facial_option, selected_id)
	_draft["facial_hair"] = str(_facial_option.get_item_metadata(_facial_option.selected))


func _select_option_by_id(option_button: OptionButton, wanted_id: String) -> void:
	for index in range(option_button.item_count):
		if str(option_button.get_item_metadata(index)) == wanted_id:
			option_button.select(index)
			return
	if option_button.item_count > 0:
		option_button.select(0)


func _on_sex_selected(index: int) -> void:
	_draft["sex"] = str(_sex_option.get_item_metadata(index))
	_draft = CharacterProfile.sanitize_appearance(_draft)
	_populate_hair_options(str(_draft["hair_style"]))
	_populate_facial_hair_options(str(_draft["facial_hair"]))
	_update_facial_controls()
	_update_preview()


func _on_hair_selected(index: int) -> void:
	_draft["hair_style"] = str(_hair_option.get_item_metadata(index))
	_update_preview()


func _on_hair_color_changed(color: Color) -> void:
	_draft["hair_color"] = CharacterProfile.color_to_storage(color)
	_update_preview()


func _on_facial_hair_selected(index: int) -> void:
	_draft["facial_hair"] = str(_facial_option.get_item_metadata(index))
	_update_preview()


func _on_facial_hair_color_changed(color: Color) -> void:
	_draft["facial_hair_color"] = CharacterProfile.color_to_storage(color)
	_update_preview()


func _on_rotate_pressed() -> void:
	_facing = (_facing + 1) % FACING_LABELS.size()
	_update_preview()


func _on_save_pressed() -> void:
	var saved := CharacterProfile.set_appearance(_draft)
	visible = false
	character_saved.emit(saved)


func _update_facial_controls() -> void:
	var enabled := str(_draft["sex"]) == CharacterProfile.SEX_MALE
	_facial_label.visible = enabled
	_facial_option.visible = enabled
	_facial_color_label.visible = enabled
	_facial_color.visible = enabled


func _update_preview() -> void:
	_rotate_button.text = "Facing: %s  (turn)" % FACING_LABELS[_facing]
	_body_sprite.texture = load(CharacterProfile.get_body_texture_path(str(_draft["sex"])))
	_body_sprite.region_rect = Rect2(_facing * 32, 0, 32, 32)

	var hair_row := CharacterProfile.get_hair_row(str(_draft["hair_style"]))
	_hair_sprite.visible = hair_row >= 0
	if hair_row >= 0:
		_hair_sprite.position = Vector2(
			0.0,
			CharacterProfile.get_hair_vertical_offset(str(_draft["sex"])) * absf(_hair_sprite.scale.y)
		)
		_hair_sprite.texture = load(CharacterProfile.HAIR_TEXTURE)
		_hair_sprite.region_rect = Rect2(_facing * 32, hair_row * 32, 32, 32)
		_hair_sprite.modulate = CharacterProfile.color_from_storage(_draft["hair_color"], Color.WHITE)

	var facial_row := CharacterProfile.get_facial_hair_row(str(_draft["facial_hair"]))
	_facial_sprite.visible = str(_draft["sex"]) == CharacterProfile.SEX_MALE and facial_row >= 0
	if _facial_sprite.visible:
		_facial_sprite.position = Vector2(
			0.0,
			CharacterProfile.get_facial_hair_vertical_offset() * absf(_facial_sprite.scale.y)
		)
		_facial_sprite.texture = load(CharacterProfile.FACIAL_HAIR_TEXTURE)
		_facial_sprite.region_rect = Rect2(_facing * 32, facial_row * 32, 32, 32)
		_facial_sprite.modulate = CharacterProfile.color_from_storage(_draft["facial_hair_color"], Color.WHITE)
