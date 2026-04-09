@tool
extends Control

const FACING_NAMES: Array[String] = ["south", "north", "east", "west"]
const FACING_LABELS: Array[String] = ["S", "N", "E", "W"]

var _offsets: Dictionary = {}
var _clothing_offsets: Dictionary = {}
var _item_data_by_type: Dictionary = {}
var _preview_data_by_type: Dictionary = {}
var _hand_item_names: Array[String] = []
var _clothing_item_names: Array[String] = []

var _selected_item: String = ""
var _selected_facing: int = 0
var _active_hand: int = 0
var _mode: int = 0

var _canvas: Control = null
var _item_option: OptionButton = null
var _clothing_option: OptionButton = null
var _facing_btns: Array[Button] = []
var _hand_btns: Array[Button] = []

var _x_spin: SpinBox = null
var _y_spin: SpinBox = null
var _rot_spin: SpinBox = null
var _waist_scale_spin: SpinBox = null
var _flip_btn: Button = null

var _cloth_x_spin: SpinBox = null
var _cloth_y_spin: SpinBox = null
var _cloth_scale_spin: SpinBox = null
var _cloth_layer_spin: SpinBox = null
var _cloth_slot_lbl: Label = null

var _status_lbl: Label = null
var _mode_btns: Array[Button] = []

var _items_section: Control = null
var _clothing_section: Control = null
var _sidebar_items: Control = null
var _sidebar_clothing: Control = null

var _updating_ui: bool = false

var _offsets_helper = null
var _catalog_helper = null


func _ready() -> void:
	custom_minimum_size = Vector2(700, 420)
	_build_ui()
	_offsets_helper = preload("res://addons/pixel_hand_editor/hand_editor_offsets.gd").new(self)
	_catalog_helper = preload("res://addons/pixel_hand_editor/hand_editor_catalog.gd").new()
	_reload_catalog()
	_load_offsets()
	_load_clothing_offsets()
	if _mode == 1:
		_refresh_clothing_canvas()
	else:
		_refresh_canvas()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 4)
	root.add_child(mode_row)

	var mode_lbl := Label.new()
	mode_lbl.text = "Mode:"
	mode_row.add_child(mode_lbl)

	var mode_labels := ["Hand Items", "Clothing"]
	for i in range(2):
		var btn := Button.new()
		btn.text = mode_labels[i]
		btn.toggle_mode = true
		btn.button_pressed = (i == 0)
		var mode_index := i
		btn.toggled.connect(func(pressed: bool): _on_mode_toggled(mode_index, pressed))
		mode_row.add_child(btn)
		_mode_btns.append(btn)

	root.add_child(HSeparator.new())

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	root.add_child(toolbar)

	_items_section = HBoxContainer.new()
	_items_section.add_theme_constant_override("separation", 6)
	toolbar.add_child(_items_section)

	var item_lbl := Label.new()
	item_lbl.text = "Item:"
	_items_section.add_child(item_lbl)

	_item_option = OptionButton.new()
	_item_option.custom_minimum_size.x = 160
	_item_option.item_selected.connect(_on_item_selected)
	_items_section.add_child(_item_option)

	var hand_gap := Control.new()
	hand_gap.custom_minimum_size.x = 8
	_items_section.add_child(hand_gap)

	var hand_lbl := Label.new()
	hand_lbl.text = "Hand:"
	_items_section.add_child(hand_lbl)

	for hand_name in ["Right", "Left", "Waist"]:
		var btn := Button.new()
		btn.text = hand_name
		btn.toggle_mode = true
		btn.button_pressed = (_hand_btns.is_empty())
		var hand_index := _hand_btns.size()
		btn.toggled.connect(func(pressed: bool): _on_hand_toggled(hand_index, pressed))
		_items_section.add_child(btn)
		_hand_btns.append(btn)

	_clothing_section = HBoxContainer.new()
	_clothing_section.add_theme_constant_override("separation", 6)
	_clothing_section.visible = false
	toolbar.add_child(_clothing_section)

	var cloth_lbl := Label.new()
	cloth_lbl.text = "Clothing:"
	_clothing_section.add_child(cloth_lbl)

	_clothing_option = OptionButton.new()
	_clothing_option.custom_minimum_size.x = 180
	_clothing_option.item_selected.connect(_on_clothing_selected)
	_clothing_section.add_child(_clothing_option)

	var facing_gap := Control.new()
	facing_gap.custom_minimum_size.x = 8
	toolbar.add_child(facing_gap)

	var facing_lbl := Label.new()
	facing_lbl.text = "Facing:"
	toolbar.add_child(facing_lbl)

	for i in range(FACING_LABELS.size()):
		var btn := Button.new()
		btn.text = FACING_LABELS[i]
		btn.toggle_mode = true
		btn.button_pressed = (i == 0)
		btn.custom_minimum_size = Vector2(28, 0)
		var facing_index := i
		btn.toggled.connect(func(pressed: bool): _on_facing_toggled(facing_index, pressed))
		toolbar.add_child(btn)
		_facing_btns.append(btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	var reload_btn := Button.new()
	reload_btn.text = "Reload Items"
	reload_btn.pressed.connect(_reload_catalog)
	toolbar.add_child(reload_btn)

	var save_btn := Button.new()
	save_btn.text = "Save Offsets"
	save_btn.pressed.connect(_on_save_pressed)
	toolbar.add_child(save_btn)

	_status_lbl = Label.new()
	_status_lbl.custom_minimum_size.x = 220
	toolbar.add_child(_status_lbl)

	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	root.add_child(content)

	_canvas = Control.new()
	_canvas.set_script(load("res://addons/pixel_hand_editor/hand_canvas.gd"))
	_canvas.player_tex = load("res://assets/player.png")
	_canvas.offset_changed.connect(_on_canvas_offset_changed)
	_canvas.clothing_offset_changed.connect(_on_canvas_clothing_offset_changed)
	content.add_child(_canvas)

	_sidebar_items = VBoxContainer.new()
	_sidebar_items.custom_minimum_size.x = 190
	_sidebar_items.add_theme_constant_override("separation", 6)
	content.add_child(_sidebar_items)

	var offset_hdr := Label.new()
	offset_hdr.text = "Active Transform"
	offset_hdr.add_theme_color_override("font_color", Color(1.0, 0.95, 0.35))
	_sidebar_items.add_child(offset_hdr)

	var x_row := HBoxContainer.new()
	_sidebar_items.add_child(x_row)
	var xl := Label.new()
	xl.text = "X:"
	xl.custom_minimum_size.x = 20
	x_row.add_child(xl)
	_x_spin = SpinBox.new()
	_x_spin.min_value = -128
	_x_spin.max_value = 128
	_x_spin.step = 1
	_x_spin.custom_minimum_size.x = 80
	_x_spin.value_changed.connect(_on_spin_changed)
	x_row.add_child(_x_spin)

	var y_row := HBoxContainer.new()
	_sidebar_items.add_child(y_row)
	var yl := Label.new()
	yl.text = "Y:"
	yl.custom_minimum_size.x = 20
	y_row.add_child(yl)
	_y_spin = SpinBox.new()
	_y_spin.min_value = -128
	_y_spin.max_value = 128
	_y_spin.step = 1
	_y_spin.custom_minimum_size.x = 80
	_y_spin.value_changed.connect(_on_spin_changed)
	y_row.add_child(_y_spin)

	var rot_row := HBoxContainer.new()
	_sidebar_items.add_child(rot_row)
	var rot_lbl := Label.new()
	rot_lbl.text = "Rot:"
	rot_lbl.custom_minimum_size.x = 30
	rot_row.add_child(rot_lbl)
	_rot_spin = SpinBox.new()
	_rot_spin.min_value = -360
	_rot_spin.max_value = 360
	_rot_spin.step = 1
	_rot_spin.custom_minimum_size.x = 80
	_rot_spin.value_changed.connect(_on_spin_changed)
	rot_row.add_child(_rot_spin)

	var scale_row := HBoxContainer.new()
	_sidebar_items.add_child(scale_row)
	var scale_lbl := Label.new()
	scale_lbl.text = "W.Scale:"
	scale_lbl.custom_minimum_size.x = 52
	scale_row.add_child(scale_lbl)
	_waist_scale_spin = SpinBox.new()
	_waist_scale_spin.min_value = 0.1
	_waist_scale_spin.max_value = 5.0
	_waist_scale_spin.step = 0.05
	_waist_scale_spin.custom_minimum_size.x = 80
	_waist_scale_spin.value_changed.connect(_on_spin_changed)
	scale_row.add_child(_waist_scale_spin)

	_sidebar_items.add_child(HSeparator.new())

	_flip_btn = Button.new()
	_flip_btn.text = "Flip Horizontal"
	_flip_btn.toggle_mode = true
	_flip_btn.pressed.connect(_on_flip_pressed)
	_sidebar_items.add_child(_flip_btn)

	_sidebar_items.add_child(HSeparator.new())

	var item_hint := Label.new()
	item_hint.text = "The preview now uses each item's real scene crop and sprite scale.\nDrag the highlighted sprite to move it.\nWaist scale is the extra multiplier saved in hand_offsets.json."
	item_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item_hint.add_theme_font_size_override("font_size", 10)
	_sidebar_items.add_child(item_hint)

	_sidebar_clothing = VBoxContainer.new()
	_sidebar_clothing.custom_minimum_size.x = 220
	_sidebar_clothing.add_theme_constant_override("separation", 6)
	_sidebar_clothing.visible = false
	content.add_child(_sidebar_clothing)

	var cloth_hdr := Label.new()
	cloth_hdr.text = "Clothing Transform"
	cloth_hdr.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	_sidebar_clothing.add_child(cloth_hdr)

	_cloth_slot_lbl = Label.new()
	_cloth_slot_lbl.text = "Slot: -"
	_cloth_slot_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sidebar_clothing.add_child(_cloth_slot_lbl)

	var cx_row := HBoxContainer.new()
	_sidebar_clothing.add_child(cx_row)
	var cxl := Label.new()
	cxl.text = "X:"
	cxl.custom_minimum_size.x = 20
	cx_row.add_child(cxl)
	_cloth_x_spin = SpinBox.new()
	_cloth_x_spin.min_value = -128
	_cloth_x_spin.max_value = 128
	_cloth_x_spin.step = 1
	_cloth_x_spin.custom_minimum_size.x = 80
	_cloth_x_spin.value_changed.connect(_on_clothing_spin_changed)
	cx_row.add_child(_cloth_x_spin)

	var cy_row := HBoxContainer.new()
	_sidebar_clothing.add_child(cy_row)
	var cyl := Label.new()
	cyl.text = "Y:"
	cyl.custom_minimum_size.x = 20
	cy_row.add_child(cyl)
	_cloth_y_spin = SpinBox.new()
	_cloth_y_spin.min_value = -128
	_cloth_y_spin.max_value = 128
	_cloth_y_spin.step = 1
	_cloth_y_spin.custom_minimum_size.x = 80
	_cloth_y_spin.value_changed.connect(_on_clothing_spin_changed)
	cy_row.add_child(_cloth_y_spin)

	var cs_row := HBoxContainer.new()
	_sidebar_clothing.add_child(cs_row)
	var csl := Label.new()
	csl.text = "Scale:"
	csl.custom_minimum_size.x = 42
	cs_row.add_child(csl)
	_cloth_scale_spin = SpinBox.new()
	_cloth_scale_spin.min_value = 0.1
	_cloth_scale_spin.max_value = 5.0
	_cloth_scale_spin.step = 0.05
	_cloth_scale_spin.custom_minimum_size.x = 80
	_cloth_scale_spin.value_changed.connect(_on_clothing_spin_changed)
	cs_row.add_child(_cloth_scale_spin)

	var layer_row := HBoxContainer.new()
	_sidebar_clothing.add_child(layer_row)
	var layer_lbl := Label.new()
	layer_lbl.text = "Layer:"
	layer_lbl.custom_minimum_size.x = 42
	layer_row.add_child(layer_lbl)
	_cloth_layer_spin = SpinBox.new()
	_cloth_layer_spin.min_value = -10
	_cloth_layer_spin.max_value = 20
	_cloth_layer_spin.step = 1
	_cloth_layer_spin.custom_minimum_size.x = 80
	_cloth_layer_spin.value_changed.connect(_on_clothing_spin_changed)
	layer_row.add_child(_cloth_layer_spin)

	_sidebar_clothing.add_child(HSeparator.new())

	var cloth_hint := Label.new()
	cloth_hint.text = "Drag the clothing sprite to move it.\nLayer maps straight to the worn sprite's z_index in-game.\nNegative values draw behind the base body sprite."
	cloth_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cloth_hint.add_theme_font_size_override("font_size", 10)
	_sidebar_clothing.add_child(cloth_hint)


func _get_hand_key() -> String:
	if _active_hand == 0:
		return "right"
	if _active_hand == 1:
		return "left"
	return "waist"


func _get_selected_clothing_name() -> String:
	var idx := _clothing_option.selected if _clothing_option != null else -1
	if idx < 0 or idx >= _clothing_item_names.size():
		return ""
	return _clothing_item_names[idx]


func _reload_catalog() -> void:
	if _catalog_helper == null:
		return

	var previous_item := _selected_item
	var previous_clothing := _get_selected_clothing_name()

	var catalog: Dictionary = _catalog_helper.load_catalog()
	_item_data_by_type = catalog.get("items_by_type", {})
	_preview_data_by_type = catalog.get("preview_data_by_type", {})
	_hand_item_names = _to_string_array(catalog.get("hand_items", []))
	_clothing_item_names = _to_string_array(catalog.get("clothing_items", []))

	_item_option.clear()
	for item_name in _hand_item_names:
		_item_option.add_item(item_name)
	_selected_item = _restore_selection(_item_option, _hand_item_names, previous_item)

	_clothing_option.clear()
	for item_name in _clothing_item_names:
		_clothing_option.add_item(item_name)
	_restore_selection(_clothing_option, _clothing_item_names, previous_clothing)

	_set_status("Loaded %d hand items and %d clothing items." % [_hand_item_names.size(), _clothing_item_names.size()])

	if _mode == 1:
		_refresh_clothing_canvas()
	else:
		_refresh_canvas()


func _restore_selection(option: OptionButton, names: Array[String], preferred_name: String) -> String:
	if names.is_empty():
		return ""
	var index := names.find(preferred_name)
	if index == -1:
		index = 0
	option.select(index)
	return names[index]


func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry in value:
			result.append(String(entry))
	return result


func _on_mode_toggled(idx: int, pressed: bool) -> void:
	if not pressed:
		_mode_btns[idx].set_pressed_no_signal(true)
		return

	_mode = idx
	for i in range(_mode_btns.size()):
		if i != idx:
			_mode_btns[i].set_pressed_no_signal(false)

	var is_items := (_mode == 0)
	_items_section.visible = is_items
	_sidebar_items.visible = is_items
	_clothing_section.visible = not is_items
	_sidebar_clothing.visible = not is_items

	if _canvas != null:
		_canvas.clothing_mode = not is_items

	if is_items:
		_refresh_canvas()
	else:
		_refresh_clothing_canvas()


func _on_item_selected(index: int) -> void:
	if index < 0 or index >= _hand_item_names.size():
		return
	_selected_item = _hand_item_names[index]
	_refresh_canvas()


func _on_clothing_selected(index: int) -> void:
	if index < 0 or index >= _clothing_item_names.size():
		return
	_clothing_option.select(index)
	_refresh_clothing_canvas()


func _on_facing_toggled(idx: int, pressed: bool) -> void:
	if not pressed:
		_facing_btns[idx].set_pressed_no_signal(true)
		return

	_selected_facing = idx
	for i in range(_facing_btns.size()):
		if i != idx:
			_facing_btns[i].set_pressed_no_signal(false)

	if _mode == 1:
		_refresh_clothing_canvas()
	else:
		_refresh_canvas()


func _on_hand_toggled(idx: int, pressed: bool) -> void:
	if not pressed:
		_hand_btns[idx].set_pressed_no_signal(true)
		return

	_active_hand = idx
	for i in range(_hand_btns.size()):
		if i != idx:
			_hand_btns[i].set_pressed_no_signal(false)
	_refresh_canvas()


func _on_canvas_offset_changed(new_offset: Vector2) -> void:
	if _selected_item == "":
		return

	var hand_key := _get_hand_key()
	var extra_scale := _waist_scale_spin.value if hand_key == "waist" else 1.0
	_store_field(_selected_item, FACING_NAMES[_selected_facing], hand_key, new_offset, _rot_spin.value, extra_scale)

	_updating_ui = true
	_x_spin.value = new_offset.x
	_y_spin.value = new_offset.y
	_updating_ui = false


func _on_spin_changed(_value: float) -> void:
	if _updating_ui or _selected_item == "":
		return

	var hand_key := _get_hand_key()
	var new_offset := Vector2(_x_spin.value, _y_spin.value)
	var new_rotation := _rot_spin.value
	var extra_scale := _waist_scale_spin.value if hand_key == "waist" else 1.0

	_store_field(_selected_item, FACING_NAMES[_selected_facing], hand_key, new_offset, new_rotation, extra_scale)

	if _canvas != null:
		_canvas.offset = new_offset
		_canvas.active_rotation = new_rotation
		_canvas.item_game_scale = extra_scale
		_canvas.queue_redraw()


func _on_canvas_clothing_offset_changed(new_offset: Vector2) -> void:
	var clothing_name := _get_selected_clothing_name()
	if clothing_name == "":
		return

	_store_clothing_field(
		clothing_name,
		FACING_NAMES[_selected_facing],
		new_offset,
		_cloth_scale_spin.value,
		int(_cloth_layer_spin.value)
	)

	_updating_ui = true
	_cloth_x_spin.value = new_offset.x
	_cloth_y_spin.value = new_offset.y
	_updating_ui = false


func _on_clothing_spin_changed(_value: float) -> void:
	if _updating_ui:
		return

	var clothing_name := _get_selected_clothing_name()
	if clothing_name == "":
		return

	var new_offset := Vector2(_cloth_x_spin.value, _cloth_y_spin.value)
	var new_scale := _cloth_scale_spin.value
	var new_layer := int(_cloth_layer_spin.value)

	_store_clothing_field(clothing_name, FACING_NAMES[_selected_facing], new_offset, new_scale, new_layer)

	if _canvas != null:
		_canvas.clothing_offset = new_offset
		_canvas.clothing_scale = new_scale
		_canvas.clothing_layer = new_layer
		_canvas.queue_redraw()


func _on_flip_pressed() -> void:
	if _selected_item == "":
		return

	var hand_key := _get_hand_key()
	var flip_key := hand_key + "_flipped"
	var facing_name := FACING_NAMES[_selected_facing]
	_ensure_entry(_selected_item, facing_name)

	var current_flip: bool = bool(_offsets[_selected_item][facing_name].get(flip_key, false))
	var new_flip := not current_flip
	_offsets[_selected_item][facing_name][flip_key] = new_flip

	if _canvas != null:
		_canvas.flipped = new_flip
		_canvas.queue_redraw()
	_flip_btn.set_pressed_no_signal(new_flip)


func _on_save_pressed() -> void:
	if _mode == 0:
		_on_spin_changed(0.0)
		for item_name in _hand_item_names:
			for facing_name in FACING_NAMES:
				_ensure_entry(item_name, facing_name)
				var entry: Dictionary = _offsets[item_name][facing_name]

				if not entry.has("right"):
					var right_default := _default_offset(item_name, facing_name, "right")
					entry["right"] = [right_default.x, right_default.y]
				if not entry.has("left"):
					var left_default := _default_offset(item_name, facing_name, "left")
					entry["left"] = [left_default.x, left_default.y]
				if not entry.has("waist"):
					var waist_default := _default_offset(item_name, facing_name, "waist")
					entry["waist"] = [waist_default.x, waist_default.y]

				if not entry.has("right_flipped"):
					entry["right_flipped"] = false
				if not entry.has("left_flipped"):
					entry["left_flipped"] = false
				if not entry.has("waist_flipped"):
					entry["waist_flipped"] = false

				if not entry.has("right_rotation"):
					entry["right_rotation"] = _default_rotation(item_name, "right")
				if not entry.has("left_rotation"):
					entry["left_rotation"] = _default_rotation(item_name, "left")
				if not entry.has("waist_rotation"):
					entry["waist_rotation"] = _default_rotation(item_name, "waist")

				if not entry.has("waist_scale"):
					entry["waist_scale"] = 1.0
		_write_offsets()
	else:
		_on_clothing_spin_changed(0.0)
		for item_name in _clothing_item_names:
			var default_layer := _default_clothing_layer(item_name)
			if not _clothing_offsets.has(item_name):
				_clothing_offsets[item_name] = {}
			for facing_name in FACING_NAMES:
				if not _clothing_offsets[item_name].has(facing_name):
					_clothing_offsets[item_name][facing_name] = {
						"offset": [0.0, 0.0],
						"scale": 1.0,
						"layer": default_layer,
					}
				else:
					var entry: Dictionary = _clothing_offsets[item_name][facing_name]
					if not entry.has("offset"):
						entry["offset"] = [0.0, 0.0]
					if not entry.has("scale"):
						entry["scale"] = 1.0
					if not entry.has("layer"):
						entry["layer"] = default_layer
		_write_clothing_offsets()


func _refresh_canvas() -> void:
	if _canvas == null:
		return

	_canvas.clothing_mode = false
	_canvas.facing = _selected_facing
	_canvas.active_hand = _active_hand

	if _selected_item == "":
		_canvas.item_preview = {}
		_canvas.queue_redraw()
		return

	var preview: Dictionary = _preview_data_by_type.get(_selected_item, {})
	_canvas.item_preview = preview

	var facing_name := FACING_NAMES[_selected_facing]
	var active_key := _get_hand_key()
	var active_flip_key := active_key + "_flipped"
	var active_rot_key := active_key + "_rotation"

	var active_offset := _read_offset(_selected_item, facing_name, active_key)
	var active_flip := _read_flipped(_selected_item, facing_name, active_flip_key)
	var active_rotation := _read_rotation(_selected_item, facing_name, active_rot_key)
	var active_scale := _read_scale(_selected_item, facing_name, active_key + "_scale", 1.0) if active_key == "waist" else 1.0

	_canvas.active_item_variant = "waist" if active_key == "waist" else "hand"
	_canvas.offset = active_offset
	_canvas.flipped = active_flip
	_canvas.active_rotation = active_rotation
	_canvas.item_game_scale = active_scale

	var other_key := "left" if _active_hand == 0 else "right"
	var other_flip_key := other_key + "_flipped"
	var other_rot_key := other_key + "_rotation"
	var other_offset := _read_offset(_selected_item, facing_name, other_key)
	var other_flip := _read_flipped(_selected_item, facing_name, other_flip_key)
	var other_rotation := _read_rotation(_selected_item, facing_name, other_rot_key)

	_canvas.other_item_variant = "waist" if other_key == "waist" else "hand"
	_canvas.other_offset = other_offset
	_canvas.other_flipped = other_flip
	_canvas.other_rotation = other_rotation
	_canvas.other_scale = 1.0

	_updating_ui = true
	_x_spin.value = active_offset.x
	_y_spin.value = active_offset.y
	_rot_spin.value = active_rotation
	_waist_scale_spin.editable = (active_key == "waist")
	_waist_scale_spin.value = active_scale
	_flip_btn.set_pressed_no_signal(active_flip)
	_updating_ui = false

	_canvas.queue_redraw()


func _refresh_clothing_canvas() -> void:
	if _canvas == null:
		return

	_canvas.clothing_mode = true
	_canvas.facing = _selected_facing

	var clothing_name := _get_selected_clothing_name()
	if clothing_name == "":
		_canvas.clothing_tex = null
		_cloth_slot_lbl.text = "Slot: -"
		_canvas.queue_redraw()
		return

	var preview: Dictionary = _preview_data_by_type.get(clothing_name, {})
	var clothing_preview: Dictionary = preview.get("clothing", {})
	var facing_name := FACING_NAMES[_selected_facing]
	var data: Dictionary = _read_clothing_data(clothing_name, facing_name)

	_canvas.clothing_tex = clothing_preview.get("texture", null)
	_canvas.clothing_offset = data["offset"]
	_canvas.clothing_scale = data["scale"]
	_canvas.clothing_layer = int(data["layer"])

	var item_data: ItemData = _item_data_by_type.get(clothing_name, null)
	var slot_name := item_data.slot if item_data != null else "-"
	_cloth_slot_lbl.text = "Slot: %s | Default layer: %d" % [slot_name, _default_clothing_layer(clothing_name)]

	_updating_ui = true
	_cloth_x_spin.value = data["offset"].x
	_cloth_y_spin.value = data["offset"].y
	_cloth_scale_spin.value = data["scale"]
	_cloth_layer_spin.value = int(data["layer"])
	_updating_ui = false

	_canvas.queue_redraw()


func _ensure_entry(item: String, facing: String) -> void:
	_offsets_helper.ensure_entry(item, facing)


func _read_offset(item: String, facing: String, hand_key: String) -> Vector2:
	return _offsets_helper.read_offset(item, facing, hand_key)


func _read_flipped(item: String, facing: String, flip_key: String) -> bool:
	return _offsets_helper.read_flipped(item, facing, flip_key)


func _read_rotation(item: String, facing: String, rot_key: String) -> float:
	return _offsets_helper.read_rotation(item, facing, rot_key)


func _read_scale(item: String, facing: String, scale_key: String, default_value: float) -> float:
	return _offsets_helper.read_scale(item, facing, scale_key, default_value)


func _read_clothing_data(item: String, facing: String) -> Dictionary:
	return _offsets_helper.read_clothing_data(item, facing)


func _store_field(item: String, facing: String, key: String, value: Vector2, rotation: float, scale: float) -> void:
	_offsets_helper.store_field(item, facing, key, value, rotation, scale)


func _store_clothing_field(item: String, facing: String, offset: Vector2, scale: float, layer: int) -> void:
	_offsets_helper.store_clothing_field(item, facing, offset, scale, layer)


func _load_offsets() -> void:
	_offsets_helper.load_offsets()


func _write_offsets() -> void:
	_offsets_helper.write_offsets()


func _load_clothing_offsets() -> void:
	_offsets_helper.load_clothing_offsets()


func _write_clothing_offsets() -> void:
	_offsets_helper.write_clothing_offsets()


func _set_status(msg: String) -> void:
	_offsets_helper.set_status(msg)


func _default_offset(item: String, facing: String, hand_key: String) -> Vector2:
	return _offsets_helper.default_offset(item, facing, hand_key)


func _default_rotation(item: String, hand_key: String) -> float:
	return _offsets_helper.default_rotation(item, hand_key)


func _default_clothing_layer(item: String) -> int:
	return _offsets_helper.default_clothing_layer(item)
