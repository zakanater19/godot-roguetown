@tool
extends Control

# ── Constants ─────────────────────────────────────────────────────────────────
const OFFSETS_PATH:          String = "res://objects/hand_offsets.json"
const CLOTHING_OFFSETS_PATH: String = "res://clothing/clothing_offsets.json"

const FACING_NAMES:  Array  =["south", "north", "east", "west"]
const FACING_LABELS: Array  =["S", "N", "E", "W"]

const HOLDABLE_ITEMS: Dictionary = {
	"Pickaxe":   {"col": 0, "game_scale": 0.75},
	"Pebble":    {"col": 2, "game_scale": 1.00},
	"Sword":     {"col": 3, "game_scale": 1.00},
	"Coal":      {"col": 4, "game_scale": 0.45},
	"IronOre":   {"col": 5, "game_scale": 0.45},
	"IronIngot": {"col": 6, "game_scale": 0.75},
	"Dirk":      {"col": -1, "game_scale": 1.00, "custom_tex": "res://objects/dirk.png"},
	"Lamp":      {"col": -1, "game_scale": 1.00, "custom_tex": "res://objects/lampoff.png"},
}

const CLOTHING_ITEMS: Dictionary = {
	"IronHelmet":      "res://clothing/ironhelmet.png",
	"IronChestplate":  "res://clothing/ironchestplate.png",
	"LeatherBoots":    "res://clothing/leatherboots.png",
	"LeatherTrousers": "res://clothing/leathertrousers.png",
	"Apothshirt":      "res://clothing/apothshirt.png",
	"Blackshirt":      "res://clothing/blackshirt.png",
	"Undershirt":      "res://clothing/undershirt.png",
	"Merchantrobe":    "res://clothing/merchantrobe.png",
	"Plate": "res://clothing/plate.png",
	"Satchel": "res://clothing/satchelonmob.png",
	"KingCloak": "res://clothing/king_cloak_onmob.png",
	"Crown": "res://clothing/crownonmob.png",
	"ChainGloves": "res://clothing/chainglovesonmob.png",
}

const DEFAULT_RIGHT: Dictionary = {
	"Pickaxe":   {"south":[20.0,  8.0], "north":[20.0, -10.0], "east":[16.0,  8.0], "west":[-16.0,  8.0]},
	"Pebble":    {"south":[20.0,  8.0], "north":[20.0, -10.0], "east":[16.0,  8.0], "west":[-16.0,  8.0]},
	"Sword":     {"south":[20.0, -2.0], "north":[20.0, -20.0], "east":[16.0, -2.0], "west":[-16.0, -2.0]},
	"Coal":      {"south":[20.0,  8.0], "north":[20.0, -10.0], "east":[16.0,  8.0], "west":[-16.0,  8.0]},
	"IronOre":   {"south":[20.0,  8.0], "north":[20.0, -10.0], "east":[16.0,  8.0], "west":[-16.0,  8.0]},
	"IronIngot": {"south":[20.0,  8.0], "north":[20.0, -10.0], "east":[16.0,  8.0], "west":[-16.0,  8.0]},
	"Lamp":      {"south":[20.0,  8.0], "north":[20.0, -10.0], "east":[16.0,  8.0], "west":[-16.0,  8.0]},
}

const DEFAULT_LEFT: Dictionary = {
	"Pickaxe":   {"south":[-20.0, 10.0], "north":[-20.0, -8.0], "east":[-16.0, 10.0], "west":[16.0, 10.0]},
	"Pebble":    {"south":[-20.0, 10.0], "north":[-20.0, -8.0], "east":[-16.0, 10.0], "west":[16.0, 10.0]},
	"Sword":     {"south":[-20.0,  0.0], "north":[-20.0,-18.0], "east":[-16.0,  0.0], "west":[16.0,  0.0]},
	"Coal":      {"south":[-20.0, 10.0], "north":[-20.0, -8.0], "east":[-16.0, 10.0], "west":[16.0, 10.0]},
	"IronOre":   {"south":[-20.0, 10.0], "north":[-20.0, -8.0], "east":[-16.0, 10.0], "west":[16.0, 10.0]},
	"IronIngot": {"south":[-20.0, 10.0], "north":[-20.0, -8.0], "east":[-16.0, 10.0], "west":[16.0, 10.0]},
	"Lamp":      {"south":[-20.0, 10.0], "north":[-20.0, -8.0], "east":[-16.0, 10.0], "west":[16.0, 10.0]},
}

const DEFAULT_WAIST: Dictionary = {
	"Pickaxe":   {"south":[12.0, 4.0], "north":[-12.0, 4.0], "east":[0.0, 4.0], "west":[0.0, 4.0]},
	"Pebble":    {"south":[12.0, 4.0], "north":[-12.0, 4.0], "east":[0.0, 4.0], "west":[0.0, 4.0]},
	"Sword":     {"south":[12.0, 4.0], "north":[-12.0, 4.0], "east":[0.0, 4.0], "west":[0.0, 4.0]},
	"Coal":      {"south":[12.0, 4.0], "north":[-12.0, 4.0], "east":[0.0, 4.0], "west":[0.0, 4.0]},
	"IronOre":   {"south":[12.0, 4.0], "north":[-12.0, 4.0], "east":[0.0, 4.0], "west":[0.0, 4.0]},
	"IronIngot": {"south":[12.0, 4.0], "north":[-12.0, 4.0], "east":[0.0, 4.0], "west":[0.0, 4.0]},
	"Lamp":      {"south":[12.0, 4.0], "north":[-12.0, 4.0], "east":[0.0, 4.0], "west":[0.0, 4.0]},
}

# ── State ─────────────────────────────────────────────────────────────────────
var _offsets:          Dictionary = {}
var _clothing_offsets: Dictionary = {}

var _selected_item:    String = "Pickaxe"
var _selected_facing:  int    = 0
var _active_hand:      int    = 0 # 0=Right, 1=Left, 2=Waist

# 0 = Items mode, 1 = Clothing mode
var _mode: int = 0

# ── UI references ─────────────────────────────────────────────────────────────
var _canvas:            Control      = null
var _item_option:       OptionButton = null
var _clothing_option:   OptionButton = null
var _facing_btns:       Array[Button] =[]
var _hand_btns:         Array[Button] =[]

var _x_spin:            SpinBox      = null
var _y_spin:            SpinBox      = null
var _rot_spin:          SpinBox      = null
var _waist_scale_spin:  SpinBox      = null
var _flip_btn:          Button       = null

var _cloth_x_spin:      SpinBox      = null
var _cloth_y_spin:      SpinBox      = null
var _cloth_scale_spin:  SpinBox      = null

var _status_lbl:        Label        = null
var _mode_btns:         Array[Button] =[]

# Sections toggled by mode
var _items_section:    Control = null
var _clothing_section: Control = null
var _sidebar_items:    Control = null
var _sidebar_clothing: Control = null

var _updating_ui:  bool = false


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	custom_minimum_size = Vector2(620, 400)
	_build_ui()
	_load_offsets()
	_load_clothing_offsets()
	_refresh_canvas()

# ── UI construction ───────────────────────────────────────────────────────────

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

	var mode_labels :=["Hand Items", "Clothing"]
	for i in range(2):
		var btn := Button.new()
		btn.text           = mode_labels[i]
		btn.toggle_mode    = true
		btn.button_pressed = (i == 0)
		var ci := i
		btn.toggled.connect(func(pressed: bool): _on_mode_toggled(ci, pressed))
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
	_item_option.custom_minimum_size.x = 110
	for key in HOLDABLE_ITEMS.keys():
		_item_option.add_item(key)
	_item_option.item_selected.connect(_on_item_selected)
	_items_section.add_child(_item_option)

	var sep_hand := Control.new()
	sep_hand.custom_minimum_size.x = 8
	_items_section.add_child(sep_hand)

	var hand_lbl := Label.new()
	hand_lbl.text = "Hand:"
	_items_section.add_child(hand_lbl)

	var hand_labels :=["Right", "Left", "Waist"]
	for i in range(3):
		var btn := Button.new()
		btn.text           = hand_labels[i]
		btn.toggle_mode    = true
		btn.button_pressed = (i == 0)
		var ci := i
		btn.toggled.connect(func(pressed: bool): _on_hand_toggled(ci, pressed))
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
	_clothing_option.custom_minimum_size.x = 140
	for key in CLOTHING_ITEMS.keys():
		_clothing_option.add_item(key)
	_clothing_option.item_selected.connect(_on_clothing_selected)
	_clothing_section.add_child(_clothing_option)

	var sep1 := Control.new()
	sep1.custom_minimum_size.x = 8
	toolbar.add_child(sep1)

	var facing_lbl := Label.new()
	facing_lbl.text = "Facing:"
	toolbar.add_child(facing_lbl)

	for i in range(4):
		var btn := Button.new()
		btn.text           = FACING_LABELS[i]
		btn.toggle_mode    = true
		btn.button_pressed = (i == 0)
		btn.custom_minimum_size = Vector2(28, 0)
		var ci := i
		btn.toggled.connect(func(pressed: bool): _on_facing_toggled(ci, pressed))
		toolbar.add_child(btn)
		_facing_btns.append(btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	var save_btn := Button.new()
	save_btn.text = "Save Offsets"
	save_btn.pressed.connect(_on_save_pressed)
	toolbar.add_child(save_btn)

	_status_lbl = Label.new()
	_status_lbl.text = ""
	_status_lbl.custom_minimum_size.x = 180
	toolbar.add_child(_status_lbl)

	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 10)
	root.add_child(hbox)

	_canvas = Control.new()
	_canvas.set_script(load("res://addons/pixel_hand_editor/hand_canvas.gd"))
	_canvas.player_tex  = load("res://player.png")
	_canvas.objects_tex = load("res://objects/objects.png")
	_canvas.offset_changed.connect(_on_canvas_offset_changed)
	_canvas.clothing_offset_changed.connect(_on_canvas_clothing_offset_changed)
	hbox.add_child(_canvas)

	_sidebar_items = VBoxContainer.new()
	_sidebar_items.custom_minimum_size.x = 160
	_sidebar_items.add_theme_constant_override("separation", 6)
	hbox.add_child(_sidebar_items)

	var offset_hdr := Label.new()
	offset_hdr.text = "Active Hand Offset"
	offset_hdr.add_theme_color_override("font_color", Color(1.0, 0.95, 0.35))
	_sidebar_items.add_child(offset_hdr)

	var x_row := HBoxContainer.new()
	_sidebar_items.add_child(x_row)
	var xl := Label.new()
	xl.text = "X:"; xl.custom_minimum_size.x = 20
	x_row.add_child(xl)
	_x_spin = SpinBox.new()
	_x_spin.min_value = -128; _x_spin.max_value = 128; _x_spin.step = 1
	_x_spin.custom_minimum_size.x = 80
	_x_spin.value_changed.connect(_on_spin_changed)
	x_row.add_child(_x_spin)

	var y_row := HBoxContainer.new()
	_sidebar_items.add_child(y_row)
	var yl := Label.new()
	yl.text = "Y:"; yl.custom_minimum_size.x = 20
	y_row.add_child(yl)
	_y_spin = SpinBox.new()
	_y_spin.min_value = -128; _y_spin.max_value = 128; _y_spin.step = 1
	_y_spin.custom_minimum_size.x = 80
	_y_spin.value_changed.connect(_on_spin_changed)
	y_row.add_child(_y_spin)

	var rot_row := HBoxContainer.new()
	_sidebar_items.add_child(rot_row)
	var rotl := Label.new()
	rotl.text = "Rot:"; rotl.custom_minimum_size.x = 30
	rot_row.add_child(rotl)
	_rot_spin = SpinBox.new()
	_rot_spin.min_value = -360; _rot_spin.max_value = 360; _rot_spin.step = 1
	_rot_spin.custom_minimum_size.x = 70
	_rot_spin.value_changed.connect(_on_spin_changed)
	rot_row.add_child(_rot_spin)

	var scale_row := HBoxContainer.new()
	_sidebar_items.add_child(scale_row)
	var scalel := Label.new()
	scalel.text = "W.Scale:"; scalel.custom_minimum_size.x = 50
	scale_row.add_child(scalel)
	_waist_scale_spin = SpinBox.new()
	_waist_scale_spin.min_value = 0.1; _waist_scale_spin.max_value = 5.0; _waist_scale_spin.step = 0.05
	_waist_scale_spin.custom_minimum_size.x = 70
	_waist_scale_spin.value_changed.connect(_on_spin_changed)
	scale_row.add_child(_waist_scale_spin)

	_sidebar_items.add_child(HSeparator.new())

	_flip_btn = Button.new()
	_flip_btn.text        = "Flip Horizontal"
	_flip_btn.toggle_mode = true
	_flip_btn.pressed.connect(_on_flip_pressed)
	_sidebar_items.add_child(_flip_btn)

	_sidebar_items.add_child(HSeparator.new())

	var hint := Label.new()
	hint.text = "Yellow = active hand.\nBlue ghost = other hand.\nDrag yellow item to move.\nFlip mirrors the sprite.\nSave writes hand_offsets.json"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	_sidebar_items.add_child(hint)

	_sidebar_clothing = VBoxContainer.new()
	_sidebar_clothing.custom_minimum_size.x = 160
	_sidebar_clothing.add_theme_constant_override("separation", 6)
	_sidebar_clothing.visible = false
	hbox.add_child(_sidebar_clothing)

	var cloth_hdr := Label.new()
	cloth_hdr.text = "Clothing Transform"
	cloth_hdr.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	_sidebar_clothing.add_child(cloth_hdr)

	var cx_row := HBoxContainer.new()
	_sidebar_clothing.add_child(cx_row)
	var cxl := Label.new()
	cxl.text = "X:"; cxl.custom_minimum_size.x = 20
	cx_row.add_child(cxl)
	_cloth_x_spin = SpinBox.new()
	_cloth_x_spin.min_value = -128; _cloth_x_spin.max_value = 128; _cloth_x_spin.step = 1
	_cloth_x_spin.custom_minimum_size.x = 80
	_cloth_x_spin.value_changed.connect(_on_clothing_spin_changed)
	cx_row.add_child(_cloth_x_spin)

	var cy_row := HBoxContainer.new()
	_sidebar_clothing.add_child(cy_row)
	var cyl := Label.new()
	cyl.text = "Y:"; cyl.custom_minimum_size.x = 20
	cy_row.add_child(cyl)
	_cloth_y_spin = SpinBox.new()
	_cloth_y_spin.min_value = -128; _cloth_y_spin.max_value = 128; _cloth_y_spin.step = 1
	_cloth_y_spin.custom_minimum_size.x = 80
	_cloth_y_spin.value_changed.connect(_on_clothing_spin_changed)
	cy_row.add_child(_cloth_y_spin)

	var cs_row := HBoxContainer.new()
	_sidebar_clothing.add_child(cs_row)
	var csl := Label.new()
	csl.text = "Scale:"; csl.custom_minimum_size.x = 40
	cs_row.add_child(csl)
	_cloth_scale_spin = SpinBox.new()
	_cloth_scale_spin.min_value = 0.1; _cloth_scale_spin.max_value = 5.0; _cloth_scale_spin.step = 0.05
	_cloth_scale_spin.custom_minimum_size.x = 60
	_cloth_scale_spin.value_changed.connect(_on_clothing_spin_changed)
	cs_row.add_child(_cloth_scale_spin)

	_sidebar_clothing.add_child(HSeparator.new())

	var cloth_hint := Label.new()
	cloth_hint.text = "Drag the clothing item to move it.\nUse Facing buttons to check all directions.\nSave writes clothing_offsets.json"
	cloth_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cloth_hint.add_theme_font_size_override("font_size", 10)
	_sidebar_clothing.add_child(cloth_hint)

func _get_hand_key() -> String:
	if _active_hand == 0: return "right"
	if _active_hand == 1: return "left"
	return "waist"

# ── Mode switching ────────────────────────────────────────────────────────────

func _on_mode_toggled(idx: int, pressed: bool) -> void:
	if not pressed:
		_mode_btns[idx].set_pressed_no_signal(true)
		return
	_mode = idx
	for i in range(2):
		if i != idx:
			_mode_btns[i].set_pressed_no_signal(false)

	var is_items    := (_mode == 0)
	var is_clothing := (_mode == 1)

	_items_section.visible    = is_items
	_sidebar_items.visible    = is_items
	_clothing_section.visible = is_clothing
	_sidebar_clothing.visible = is_clothing

	if _canvas != null:
		_canvas.clothing_mode = is_clothing
		if is_clothing:
			_refresh_clothing_canvas()
		else:
			_refresh_canvas()

# ── Event handlers ────────────────────────────────────────────────────────────

func _on_item_selected(index: int) -> void:
	_selected_item = HOLDABLE_ITEMS.keys()[index]
	_refresh_canvas()

func _on_clothing_selected(_index: int) -> void:
	_refresh_clothing_canvas()

func _on_facing_toggled(idx: int, pressed: bool) -> void:
	if not pressed:
		_facing_btns[idx].set_pressed_no_signal(true)
		return
	_selected_facing = idx
	for i in range(4):
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
	for i in range(3):
		if i != idx:
			_hand_btns[i].set_pressed_no_signal(false)
	_refresh_canvas()

func _on_canvas_offset_changed(new_offset: Vector2) -> void:
	var hand_key = _get_hand_key()
	_store_field(_selected_item, FACING_NAMES[_selected_facing], hand_key, new_offset, _rot_spin.value, _waist_scale_spin.value)
	_updating_ui = true
	if _x_spin != null: _x_spin.value = new_offset.x
	if _y_spin != null: _y_spin.value = new_offset.y
	_updating_ui = false

func _on_spin_changed(_v: float) -> void:
	if _updating_ui or _x_spin == null or _y_spin == null or _rot_spin == null or _waist_scale_spin == null:
		return
	var new_offset := Vector2(_x_spin.value, _y_spin.value)
	var new_rot    := _rot_spin.value
	var new_scale  := _waist_scale_spin.value
	var hand_key   = _get_hand_key()
	_store_field(_selected_item, FACING_NAMES[_selected_facing], hand_key, new_offset, new_rot, new_scale)
	if _canvas != null:
		_canvas.offset = new_offset
		_canvas.active_rotation = new_rot
		if hand_key == "waist":
			_canvas.item_game_scale = new_scale
		_canvas.queue_redraw()

func _on_canvas_clothing_offset_changed(new_offset: Vector2) -> void:
	var clothing_name: String = CLOTHING_ITEMS.keys()[_clothing_option.selected]
	var facing_name: String   = FACING_NAMES[_selected_facing]
	var current_scale: float  = _cloth_scale_spin.value
	
	_store_clothing_field(clothing_name, facing_name, new_offset, current_scale)
	
	_updating_ui = true
	if _cloth_x_spin != null: _cloth_x_spin.value = new_offset.x
	if _cloth_y_spin != null: _cloth_y_spin.value = new_offset.y
	_updating_ui = false

func _on_clothing_spin_changed(_v: float) -> void:
	if _updating_ui or _cloth_x_spin == null or _cloth_y_spin == null or _cloth_scale_spin == null:
		return
	var new_offset := Vector2(_cloth_x_spin.value, _cloth_y_spin.value)
	var new_scale  := _cloth_scale_spin.value
	var clothing_name: String = CLOTHING_ITEMS.keys()[_clothing_option.selected]
	var facing_name: String   = FACING_NAMES[_selected_facing]
	
	_store_clothing_field(clothing_name, facing_name, new_offset, new_scale)
	
	if _canvas != null:
		_canvas.clothing_offset = new_offset
		_canvas.clothing_scale  = new_scale
		_canvas.queue_redraw()

func _on_flip_pressed() -> void:
	var hand_key             = _get_hand_key()
	var flip_key             = hand_key + "_flipped"
	var facing_name: String  = FACING_NAMES[_selected_facing]
	_ensure_entry(_selected_item, facing_name)
	var current_flip: bool   = _offsets[_selected_item][facing_name].get(flip_key, false)
	var new_flip: bool       = not current_flip
	_offsets[_selected_item][facing_name][flip_key] = new_flip
	if _canvas != null:
		_canvas.flipped = new_flip
		_canvas.queue_redraw()
	if _flip_btn != null:
		_flip_btn.set_pressed_no_signal(new_flip)

func _on_save_pressed() -> void:
	if _mode == 0:
		_on_spin_changed(0.0)
		for item_name in HOLDABLE_ITEMS.keys():
			for facing_name in FACING_NAMES:
				_ensure_entry(item_name, facing_name)
				var entry: Dictionary = _offsets[item_name][facing_name]
				
				if not entry.has("right"):
					var d = _default_offset(item_name, facing_name, "right")
					entry["right"] =[d.x, d.y]
				if not entry.has("left"):
					var d = _default_offset(item_name, facing_name, "left")
					entry["left"] =[d.x, d.y]
				if not entry.has("waist"):
					var d = _default_offset(item_name, facing_name, "waist")
					entry["waist"] =[d.x, d.y]
					
				if not entry.has("right_flipped"): entry["right_flipped"] = false
				if not entry.has("left_flipped"):  entry["left_flipped"] = false
				if not entry.has("waist_flipped"): entry["waist_flipped"] = false
				
				if not entry.has("right_rotation"): entry["right_rotation"] = 0.0
				if not entry.has("left_rotation"):  entry["left_rotation"] = 0.0
				if not entry.has("waist_rotation"): entry["waist_rotation"] = 45.0 if item_name == "Sword" else 0.0
				
				if not entry.has("waist_scale"): entry["waist_scale"] = 1.0
		_write_offsets()
	else:
		_on_clothing_spin_changed(0.0)
		for item_name in CLOTHING_ITEMS.keys():
			for facing_name in FACING_NAMES:
				if not _clothing_offsets.has(item_name):
					_clothing_offsets[item_name] = {}
				if not _clothing_offsets[item_name].has(facing_name):
					_clothing_offsets[item_name][facing_name] = {"offset": [0.0, 0.0], "scale": 1.0}
		_write_clothing_offsets()

# ── Canvas refresh ────────────────────────────────────────────────────────────

func _refresh_canvas() -> void:
	if _canvas == null:
		return
	_canvas.clothing_mode = false
	var info: Dictionary = HOLDABLE_ITEMS[_selected_item]
	_canvas.item_col        = info["col"]
	
	if info.has("custom_tex"):
		_canvas.item_custom_tex = load(info["custom_tex"])
	else:
		_canvas.item_custom_tex = null

	_canvas.facing          = _selected_facing
	_canvas.active_hand     = _active_hand

	var facing_name: String = FACING_NAMES[_selected_facing]
	var ah_key              = _get_hand_key()
	var ah_flip_key         = ah_key + "_flipped"
	var ah_rot_key          = ah_key + "_rotation"
	var ah_scale_key        = ah_key + "_scale"

	var active_off   = _read_offset(_selected_item, facing_name, ah_key)
	var active_flip  = _read_flipped(_selected_item, facing_name, ah_flip_key)
	var active_rot   = _read_rotation(_selected_item, facing_name, ah_rot_key)
	
	var active_scale = info.get("game_scale", 1.0)
	if ah_key == "waist":
		active_scale = _read_scale(_selected_item, facing_name, ah_scale_key, active_scale)

	_canvas.offset          = active_off
	_canvas.flipped         = active_flip
	_canvas.active_rotation = active_rot
	_canvas.item_game_scale = active_scale

	var oh_key       = "left" if _active_hand == 0 else "right"
	var oh_flip_key  = oh_key + "_flipped"
	var oh_rot_key   = oh_key + "_rotation"
	
	var other_off    = _read_offset(_selected_item, facing_name, oh_key)
	var other_flip   = _read_flipped(_selected_item, facing_name, oh_flip_key)
	var other_rot    = _read_rotation(_selected_item, facing_name, oh_rot_key)
	
	var other_scale  = info.get("game_scale", 1.0)
	if oh_key == "waist":
		other_scale  = _read_scale(_selected_item, facing_name, oh_key + "_scale", other_scale)

	_canvas.other_offset   = other_off
	_canvas.other_flipped  = other_flip
	_canvas.other_rotation = other_rot
	_canvas.other_scale    = other_scale

	_updating_ui = true
	if _x_spin != null: _x_spin.value = active_off.x
	if _y_spin != null: _y_spin.value = active_off.y
	if _rot_spin != null: _rot_spin.value = active_rot
	if _waist_scale_spin != null: 
		_waist_scale_spin.editable = (ah_key == "waist")
		if ah_key == "waist":
			_waist_scale_spin.value = active_scale
	if _flip_btn != null: _flip_btn.set_pressed_no_signal(active_flip)
	_updating_ui = false

	_canvas.queue_redraw()

func _refresh_clothing_canvas() -> void:
	if _canvas == null or _clothing_option == null:
		return
	_canvas.clothing_mode = true
	_canvas.facing        = _selected_facing

	var keys: Array = CLOTHING_ITEMS.keys()
	var idx: int = _clothing_option.selected
	if idx >= 0 and idx < keys.size():
		var cloth_name: String = keys[idx]
		var tex_path: String = CLOTHING_ITEMS[cloth_name]
		_canvas.clothing_tex = load(tex_path)
		
		var facing_name: String = FACING_NAMES[_selected_facing]
		var data: Dictionary = _read_clothing_data(cloth_name, facing_name)
		
		_canvas.clothing_offset = data.offset
		_canvas.clothing_scale  = data.scale
		
		_updating_ui = true
		if _cloth_x_spin != null: _cloth_x_spin.value = data.offset.x
		if _cloth_y_spin != null: _cloth_y_spin.value = data.offset.y
		if _cloth_scale_spin != null: _cloth_scale_spin.value = data.scale
		_updating_ui = false
	else:
		_canvas.clothing_tex = null

	_canvas.queue_redraw()

# ── Offset helpers ────────────────────────────────────────────────────────────

func _ensure_entry(item: String, facing: String) -> void:
	if not _offsets.has(item):
		_offsets[item] = {}
	if not _offsets[item].has(facing):
		_offsets[item][facing] = {}

func _read_offset(item: String, facing: String, hand_key: String) -> Vector2:
	if _offsets.has(item) and _offsets[item].has(facing):
		var entry = _offsets[item][facing]
		if entry.has(hand_key):
			var arr = entry[hand_key]
			return Vector2(float(arr[0]), float(arr[1]))
	return _default_offset(item, facing, hand_key)

func _read_flipped(item: String, facing: String, flip_key: String) -> bool:
	if _offsets.has(item) and _offsets[item].has(facing):
		return _offsets[item][facing].get(flip_key, false)
	return false

func _read_rotation(item: String, facing: String, rot_key: String) -> float:
	if _offsets.has(item) and _offsets[item].has(facing):
		return float(_offsets[item][facing].get(rot_key, 45.0 if item == "Sword" and rot_key.begins_with("waist") else 0.0))
	return 45.0 if item == "Sword" and rot_key.begins_with("waist") else 0.0

func _read_scale(item: String, facing: String, scale_key: String, default: float) -> float:
	if _offsets.has(item) and _offsets[item].has(facing):
		return float(_offsets[item][facing].get(scale_key, default))
	return default

func _read_clothing_data(item: String, facing: String) -> Dictionary:
	if _clothing_offsets.has(item) and _clothing_offsets[item].has(facing):
		var entry = _clothing_offsets[item][facing]
		return {
			"offset": Vector2(float(entry.get("offset",[0, 0])[0]), float(entry.get("offset",[0, 0])[1])),
			"scale": float(entry.get("scale", 1.0))
		}
	return {"offset": Vector2.ZERO, "scale": 1.0}

func _store_field(item: String, facing: String, key: String, value: Vector2, rot: float, scale: float) -> void:
	_ensure_entry(item, facing)
	_offsets[item][facing][key] =[value.x, value.y]
	_offsets[item][facing][key + "_rotation"] = rot
	
	# ONLY ever save scale data for the waist! Hands do not support overridden scaling inside the engine logic.
	if key == "waist":
		_offsets[item][facing][key + "_scale"] = scale

func _store_clothing_field(item: String, facing: String, offset: Vector2, scale: float) -> void:
	if not _clothing_offsets.has(item):
		_clothing_offsets[item] = {}
	if not _clothing_offsets[item].has(facing):
		_clothing_offsets[item][facing] = {}
	_clothing_offsets[item][facing]["offset"] =[offset.x, offset.y]
	_clothing_offsets[item][facing]["scale"] = scale

func _default_offset(item: String, facing: String, hand_key: String) -> Vector2:
	var table := DEFAULT_RIGHT if hand_key == "right" else DEFAULT_LEFT if hand_key == "left" else DEFAULT_WAIST
	if table.has(item) and table[item].has(facing):
		var arr = table[item][facing]
		return Vector2(float(arr[0]), float(arr[1]))
	return Vector2.ZERO

# ── Save / Load ───────────────────────────────────────────────────────────────

func _load_offsets() -> void:
	if not FileAccess.file_exists(OFFSETS_PATH):
		_set_status("No saved offsets — using defaults.")
		return
	var file := FileAccess.open(OFFSETS_PATH, FileAccess.READ)
	if file == null:
		_set_status("Could not read " + OFFSETS_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		_set_status("JSON parse error — using defaults.")
		return
	_offsets = parsed
	_set_status("Offsets loaded.")

func _write_offsets() -> void:
	var file := FileAccess.open(OFFSETS_PATH, FileAccess.WRITE)
	if file == null:
		_set_status("ERROR: cannot write " + OFFSETS_PATH)
		return
	file.store_string(JSON.stringify(_offsets, "\t"))
	file.close()
	_set_status("Saved.")

func _load_clothing_offsets() -> void:
	if not FileAccess.file_exists(CLOTHING_OFFSETS_PATH):
		return
	var file := FileAccess.open(CLOTHING_OFFSETS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_clothing_offsets = parsed

func _write_clothing_offsets() -> void:
	var dir := DirAccess.open("res://")
	if not dir.dir_exists("clothing"):
		dir.make_dir("clothing")
	var file := FileAccess.open(CLOTHING_OFFSETS_PATH, FileAccess.WRITE)
	if file == null:
		_set_status("ERROR: cannot write " + CLOTHING_OFFSETS_PATH)
		return
	file.store_string(JSON.stringify(_clothing_offsets, "\t"))
	file.close()
	_set_status("Clothing offsets saved.")

func _set_status(msg: String) -> void:
	if _status_lbl != null:
		_status_lbl.text = msg