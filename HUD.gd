# res://HUD.gd
extends CanvasLayer

var player: Node = null

const BOX:  int = 48
const GAP:  int = 4
const STEP: int = BOX + GAP   

const SLOT_LAYOUT: Array =[["head",      1, 0],["cloak",     2, 0],["armor",     1, 1],["backpack",  2, 1],["gloves",    0, 2],["clothing",  1, 2],["trousers",  2, 2],["feet",      1, 3],["waist",     0, 3],
]

var _hud_tex:          Texture2D = null
var _clothing_visible: bool      = false
var _clothing_panel:   Control   = null

var _slot_boxes: Dictionary = {}
var _slot_icons: Dictionary = {}

var _hand_highlights:    Array =[]
var _hand_icons:         Array =[]
var _hand_labels:        Array =[]  # yellow "GRAB" labels, one per hand slot
var _hand_broken_labels: Array =[]  # red "X" for broken hands
var _hand_amt_labels:    Array =[]  # new label for stack amounts

var _release_ctrl: Control = null
var _resist_ctrl:  Control = null

var _toggle_bg:    ColorRect   = null
var _toggle_tex:   TextureRect = null
var _toggle_label: Label       = null
var _intent_label: Label       = null

# Vertical Bars
var _health_bar:  ColorRect = null
var _stamina_bar: ColorRect = null

# Limb targeting
var targeted_limb: String     = "chest"
var _limb_highlights: Dictionary = {}  # limb_name -> TextureRect
var _limb_broken_overlays: Dictionary = {} # limb_name -> TextureRect (Fishnet)

# Combat stance icon
var _stance_icon: TextureRect = null

const LIMB_REGIONS: Dictionary = {
	"chest":[Vector2(4,  8),  Vector2(57, 35)],
	"r_arm":[Vector2(12, 25), Vector2(11, 23)],
	"l_arm":[Vector2(42, 25), Vector2(11, 23)],
	"r_leg":[Vector2(17, 39), Vector2(14, 25)],
	"l_leg":[Vector2(34, 39), Vector2(14, 25)],
	"head":[Vector2(23, 9),  Vector2(19, 18)],
}

# ── Setup ─────────────────────────────────────────────────────────────────────

func setup(p: Node) -> void:
	player   = p
	layer    = 10
	_hud_tex = load("res://HUDicon.jpg") as Texture2D
	_build()

func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_clothing_panel(root)
	_build_hand_boxes(root)
	_build_limb_panel(root)
	_build_stance_icon(root)

# ── Clothing panel (shifted left: -140 to center in 1000px game area) ────────

func _build_clothing_panel(parent: Control) -> void:
	var panel_w: int = 3 * STEP
	var panel_h: int = 4 * STEP

	_clothing_panel = Control.new()
	_clothing_panel.anchor_left   = 0.5
	_clothing_panel.anchor_right  = 0.5
	_clothing_panel.anchor_top    = 1.0
	_clothing_panel.anchor_bottom = 1.0
	_clothing_panel.offset_left   = -(50 + 8 + panel_w) - 166
	_clothing_panel.offset_right  = -(50 + 8) - 166
	_clothing_panel.offset_bottom = -16
	_clothing_panel.offset_top    = -16 - panel_h
	_clothing_panel.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_clothing_panel)

	for slot_data in SLOT_LAYOUT:
		var slot_name: String = slot_data[0]
		var col:       int    = slot_data[1]
		var row:       int    = slot_data[2]
		_create_slot_box(slot_name, col, row)

	_create_toggle_box(2, 3)

func _create_slot_box(slot_name: String, col: int, row: int) -> void:
	var ctrl := Control.new()
	ctrl.position            = Vector2(col * STEP, row * STEP)
	ctrl.size                = Vector2(BOX, BOX)
	ctrl.custom_minimum_size = Vector2(BOX, BOX)
	ctrl.clip_contents       = true
	ctrl.mouse_filter        = Control.MOUSE_FILTER_STOP
	ctrl.visible             = true if slot_name == "waist" else _clothing_visible
	_clothing_panel.add_child(ctrl)

	_add_bg(ctrl)

	var label_text := slot_name
	if slot_name == "clothing": label_text = "clothing\n/torso"
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75, 0.5))
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD
	lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	ctrl.add_child(lbl)

	var icon := Sprite2D.new()
	icon.position = Vector2(BOX / 2.0, BOX / 2.0)
	icon.scale    = Vector2(0.75, 0.75)
	icon.visible  = false
	ctrl.add_child(icon)

	_slot_boxes[slot_name] = ctrl
	_slot_icons[slot_name] = icon
	ctrl.gui_input.connect(func(event: InputEvent): _on_slot_gui_input(event, slot_name))

func _create_toggle_box(col: int, row: int) -> void:
	var ctrl := Control.new()
	ctrl.position            = Vector2(col * STEP, row * STEP)
	ctrl.size                = Vector2(BOX, BOX)
	ctrl.custom_minimum_size = Vector2(BOX, BOX)
	ctrl.clip_contents       = true
	ctrl.mouse_filter        = Control.MOUSE_FILTER_STOP
	_clothing_panel.add_child(ctrl)

	var tex := TextureRect.new()
	tex.texture      = _hud_tex
	tex.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.size         = Vector2(BOX, BOX)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.visible      = true
	ctrl.add_child(tex)
	_toggle_tex = tex

	var bg := ColorRect.new()
	bg.color        = Color(0.25, 0.05, 0.05, 0.85)
	bg.size         = Vector2(BOX, BOX)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.visible      = false
	ctrl.add_child(bg)
	_toggle_bg = bg

	var lbl := Label.new()
	lbl.text = "↑"
	lbl.add_theme_color_override("font_color", Color(0.15, 0.9, 0.25))
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	ctrl.add_child(lbl)
	_toggle_label = lbl
	ctrl.gui_input.connect(_on_toggle_gui_input)

# ── Hand boxes, Intent & Bars ─────────────────────

func _build_hand_boxes(parent: Control) -> void:
	var hands_ctrl := Control.new()
	hands_ctrl.anchor_left   = 0.5
	hands_ctrl.anchor_right  = 0.5
	hands_ctrl.anchor_top    = 1.0
	hands_ctrl.anchor_bottom = 1.0
	hands_ctrl.offset_left   = -166
	hands_ctrl.offset_right  = -166
	hands_ctrl.offset_top    = -(BOX + 16)
	hands_ctrl.offset_bottom = -16
	hands_ctrl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	parent.add_child(hands_ctrl)

	# --- Hand slots ---
	for i in range(2):
		var ctrl := Control.new()
		ctrl.position            = Vector2(-50 + i * STEP, 0)
		ctrl.size                = Vector2(BOX, BOX)
		ctrl.custom_minimum_size = Vector2(BOX, BOX)
		ctrl.mouse_filter        = Control.MOUSE_FILTER_STOP
		hands_ctrl.add_child(ctrl)
		_add_bg(ctrl)
		
		var highlight := ColorRect.new()
		highlight.size         = Vector2(BOX, BOX)
		highlight.color        = Color(0.7, 0.7, 0.7, 0.25) if i == 0 else Color(0, 0, 0, 0)
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ctrl.add_child(highlight)
		_hand_highlights.append(highlight)
		
		var icon := Sprite2D.new()
		icon.position = Vector2(BOX / 2.0, BOX / 2.0)
		icon.scale    = Vector2(0.6, 0.6)
		icon.visible  = false
		ctrl.add_child(icon)
		_hand_icons.append(icon)
		
		# Quantity label for stacks (bottom right)
		var amt_lbl := Label.new()
		amt_lbl.text = ""
		amt_lbl.add_theme_color_override("font_color", Color.WHITE)
		amt_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		amt_lbl.add_theme_constant_override("outline_size", 3)
		amt_lbl.add_theme_font_size_override("font_size", 10)
		amt_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		amt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amt_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
		amt_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
		amt_lbl.visible              = false
		ctrl.add_child(amt_lbl)
		_hand_amt_labels.append(amt_lbl)

		# Yellow "GRAB" label — visible only while this hand is holding a grab
		var grab_lbl := Label.new()
		grab_lbl.text = "GRAB"
		grab_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.0))
		grab_lbl.add_theme_font_size_override("font_size", 12)
		grab_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		grab_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grab_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		grab_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
		grab_lbl.visible              = false
		ctrl.add_child(grab_lbl)
		_hand_labels.append(grab_lbl)
		
		# Red "X" label for broken hands
		var broken_lbl := Label.new()
		broken_lbl.text = "X"
		broken_lbl.add_theme_color_override("font_color", Color(0.9, 0.1, 0.1, 0.85))
		broken_lbl.add_theme_font_size_override("font_size", 40)
		broken_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		broken_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		broken_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		broken_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
		broken_lbl.visible              = false
		ctrl.add_child(broken_lbl)
		_hand_broken_labels.append(broken_lbl)

		ctrl.gui_input.connect(_on_hand_gui_input.bind(i))

	# --- Release grab button (above hand slot 0 / right hand) ---
	# Visible only when the local player is currently grabbing something.
	_release_ctrl = Control.new()
	_release_ctrl.position            = Vector2(-50, -(BOX + GAP))
	_release_ctrl.size                = Vector2(BOX, BOX)
	_release_ctrl.custom_minimum_size = Vector2(BOX, BOX)
	_release_ctrl.mouse_filter        = Control.MOUSE_FILTER_STOP
	_release_ctrl.visible             = false
	hands_ctrl.add_child(_release_ctrl)
	_add_bg(_release_ctrl)
	var release_lbl := Label.new()
	release_lbl.text = "RELEASE\n[Q]"
	release_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1))
	release_lbl.add_theme_font_size_override("font_size", 8)
	release_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	release_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	release_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	release_lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD
	release_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_release_ctrl.add_child(release_lbl)
	_release_ctrl.gui_input.connect(_on_release_gui_input)

	# --- Resist indicator (above hand slot 1 / left hand) ---
	# Visible only when the local player is being grabbed by someone.
	_resist_ctrl = Control.new()
	_resist_ctrl.position            = Vector2(2, -(BOX + GAP))
	_resist_ctrl.size                = Vector2(BOX, BOX)
	_resist_ctrl.custom_minimum_size = Vector2(BOX, BOX)
	_resist_ctrl.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	_resist_ctrl.visible             = false
	hands_ctrl.add_child(_resist_ctrl)
	_add_bg(_resist_ctrl)
	var resist_tex_node := TextureRect.new()
	var resist_tex := load("res://ui/resist.png") as Texture2D
	if resist_tex != null:
		resist_tex_node.texture      = resist_tex
		resist_tex_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		resist_tex_node.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		resist_tex_node.size         = Vector2(BOX, BOX)
		resist_tex_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_resist_ctrl.add_child(resist_tex_node)
	var resist_lbl := Label.new()
	resist_lbl.text = "[Z]"
	resist_lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	resist_lbl.add_theme_font_size_override("font_size", 9)
	resist_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resist_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resist_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	resist_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_resist_ctrl.add_child(resist_lbl)

	# --- Intent ---
	var intent_ctrl := Control.new()
	intent_ctrl.position            = Vector2(54, 0)
	intent_ctrl.size                = Vector2(BOX, BOX)
	hands_ctrl.add_child(intent_ctrl)
	_add_bg(intent_ctrl)
	_intent_label = Label.new()
	_intent_label.text = "COMBAT\nMODE"
	_intent_label.add_theme_font_size_override("font_size", 9)
	_intent_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intent_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	intent_ctrl.add_child(_intent_label)
	intent_ctrl.gui_input.connect(_on_intent_gui_input)

	# --- Crafting ---
	var craft_ctrl := Control.new()
	craft_ctrl.position            = Vector2(106, 0)
	craft_ctrl.size                = Vector2(BOX, BOX)
	hands_ctrl.add_child(craft_ctrl)
	_add_bg(craft_ctrl)
	var craft_lbl := Label.new()
	craft_lbl.text = "CRAFT"
	craft_lbl.add_theme_font_size_override("font_size", 11)
	craft_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	craft_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	craft_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	craft_ctrl.add_child(craft_lbl)
	craft_ctrl.gui_input.connect(_on_craft_gui_input)

	# --- Stats/Skills ---
	var stats_ctrl := Control.new()
	stats_ctrl.position            = Vector2(158, 0)
	stats_ctrl.size                = Vector2(BOX, BOX)
	hands_ctrl.add_child(stats_ctrl)
	_add_bg(stats_ctrl)
	var stats_lbl := Label.new()
	stats_lbl.text = "STATS"
	stats_lbl.add_theme_font_size_override("font_size", 10)
	stats_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	stats_ctrl.add_child(stats_lbl)
	stats_ctrl.gui_input.connect(_on_stats_gui_input)

	# --- Sleep ---
	var sleep_ctrl := Control.new()
	sleep_ctrl.position            = Vector2(210, 0)
	sleep_ctrl.size                = Vector2(BOX, BOX)
	hands_ctrl.add_child(sleep_ctrl)
	_add_bg(sleep_ctrl)
	var sleep_lbl := Label.new()
	sleep_lbl.text = "SLEEP"
	sleep_lbl.add_theme_font_size_override("font_size", 10)
	sleep_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sleep_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sleep_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	sleep_ctrl.add_child(sleep_lbl)
	sleep_ctrl.gui_input.connect(_on_sleep_gui_input)

	# --- Vertical Bars ---
	var bar_container := HBoxContainer.new()
	bar_container.position = Vector2(264, -32)
	bar_container.add_theme_constant_override("separation", 6)
	hands_ctrl.add_child(bar_container)
	
	# Health Bar
	var hb_cont := Control.new()
	hb_cont.custom_minimum_size = Vector2(10, 80)
	bar_container.add_child(hb_cont)
	var hb_bg := ColorRect.new()
	hb_bg.color = Color(0.2, 0.2, 0.2)
	hb_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb_cont.add_child(hb_bg)
	_health_bar = ColorRect.new()
	_health_bar.color = Color(0.8, 0.1, 0.1)
	_health_bar.size = Vector2(10, 80)
	hb_cont.add_child(_health_bar)
	
	# Stamina Bar
	var sb_cont := Control.new()
	sb_cont.custom_minimum_size = Vector2(10, 80)
	bar_container.add_child(sb_cont)
	var sb_bg := ColorRect.new()
	sb_bg.color = Color(0.2, 0.2, 0.2)
	sb_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sb_cont.add_child(sb_bg)
	_stamina_bar = ColorRect.new()
	_stamina_bar.color = Color(0.1, 0.8, 0.1)
	_stamina_bar.size = Vector2(10, 80)
	sb_cont.add_child(_stamina_bar)

# ── Limb targeting panel ──────────────────────────────────────────────────────

func _build_limb_panel(parent: Control) -> void:
	# Positioned to the left of the hand row.
	# Hand row left edge is at anchor_center - 166 + (-50) = center - 216.
	# We sit 8px further left, panel is 64x64.
	var panel := Control.new()
	panel.anchor_left   = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_top    = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_right  = -388          # 8px gap left of clothing panel (clothing panel left = center-380)
	panel.offset_left   = -388 - 64     # 64px wide
	panel.offset_bottom = -16
	panel.offset_top    = -16 - 64      # 64px tall
	panel.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)

	# Base gargoyle — always visible
	var base_tex := load("res://ui/m-zone_sel.png") as Texture2D
	if base_tex != null:
		var base := TextureRect.new()
		base.texture      = base_tex
		base.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		base.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		base.size         = Vector2(64, 64)
		base.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(base)

	# Shader for drawing fishnet lines on broken limbs
	var fishnet_shader = Shader.new()
	fishnet_shader.code = """
	shader_type canvas_item;
	void fragment() {
		vec4 tex = texture(TEXTURE, UV);
		float u = UV.x * 64.0;
		float v = UV.y * 64.0;
		if (tex.a > 0.1 && (mod(u + v, 5.0) < 1.0 || mod(u - v, 5.0) < 1.0)) {
			COLOR = vec4(0.9, 0.1, 0.1, 0.9);
		} else {
			COLOR = vec4(0.0, 0.0, 0.0, 0.0);
		}
	}
	"""

	# Highlight overlays — one per limb, blue modulate, only selected is visible
	var limb_tex_names := {
		"head":  "res://ui/m-head.png",
		"chest": "res://ui/m-chest.png",
		"r_arm": "res://ui/m-r_arm.png",
		"l_arm": "res://ui/m-l_arm.png",
		"r_leg": "res://ui/m-r_leg.png",
		"l_leg": "res://ui/m-l_leg.png",
	}
	for limb_name in limb_tex_names:
		var hl_tex := load(limb_tex_names[limb_name]) as Texture2D
		if hl_tex == null:
			continue
		var hl := TextureRect.new()
		hl.texture      = hl_tex
		hl.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hl.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		hl.size         = Vector2(64, 64)
		hl.modulate     = Color(1.0, 0.2, 0.2)
		hl.visible      = (limb_name == targeted_limb)
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(hl)
		_limb_highlights[limb_name] = hl
		
		# Broken overlays — fishnet shader
		var broken_hl := TextureRect.new()
		broken_hl.texture      = hl_tex
		broken_hl.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		broken_hl.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		broken_hl.size         = Vector2(64, 64)
		broken_hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		broken_hl.visible      = false
		
		var mat = ShaderMaterial.new()
		mat.shader = fishnet_shader
		broken_hl.material = mat
		
		panel.add_child(broken_hl)
		_limb_broken_overlays[limb_name] = broken_hl

	# Invisible click regions — each covers the limb's pixel bounding box
	for limb_name in LIMB_REGIONS:
		var region: Array = LIMB_REGIONS[limb_name]
		var click := Control.new()
		click.position   = region[0]
		click.size       = region[1]
		click.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.add_child(click)
		click.gui_input.connect(func(event: InputEvent): _on_limb_gui_input(event, limb_name))

	# Apply default selection
	_select_limb(targeted_limb)

func _select_limb(limb_name: String) -> void:
	targeted_limb = limb_name
	for limb_key in _limb_highlights:
		_limb_highlights[limb_key].visible = (limb_key == limb_name)

func _on_limb_gui_input(event: InputEvent, limb_name: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_select_limb(limb_name)

# ── Combat stance icon ────────────────────────────────────────────────────────

func _build_stance_icon(parent: Control) -> void:
	# Sits immediately to the left of the limb panel.
	# Limb panel: offset_right = -388, offset_left = -452.
	# We place this panel 8px to the left of that: offset_right = -460, offset_left = -524.
	var panel := Control.new()
	panel.anchor_left   = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_top    = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_right  = -460
	panel.offset_left   = -524          # 64px wide
	panel.offset_bottom = -16
	panel.offset_top    = -16 - 64      # 64px tall
	panel.mouse_filter  = Control.MOUSE_FILTER_STOP
	parent.add_child(panel)

	# Dark background
	var bg := ColorRect.new()
	bg.color        = Color(0.1, 0.1, 0.1, 0.7)
	bg.size         = Vector2(64, 64)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bg)

	# Stance icon — default dodge
	var dodge_tex := load("res://ui/dodge.png") as Texture2D
	_stance_icon = TextureRect.new()
	_stance_icon.texture      = dodge_tex
	_stance_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_stance_icon.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_stance_icon.size         = Vector2(64, 64)
	_stance_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_stance_icon)

	panel.gui_input.connect(_on_stance_gui_input)

func _on_stance_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if player != null and player.has_method("toggle_combat_stance"):
			player.toggle_combat_stance()

# ── Stats Update ─────────────────────────────────────────────────────────────

func update_stats(health: int, stamina: float) -> void:
	if _health_bar:
		var h = (clamp(health, 0, 100) / 100.0) * 80.0
		_health_bar.size.y = h
		_health_bar.position.y = 80 - h
	if _stamina_bar:
		var s = (clamp(stamina, 0, 100) / 100.0) * 80.0
		_stamina_bar.size.y = s
		_stamina_bar.position.y = 80 - s
		
	# Update broken limbs indicators on the doll targeting UI
	if player != null and player.body != null:
		for limb_name in _limb_broken_overlays.keys():
			_limb_broken_overlays[limb_name].visible = player.body.limb_broken.get(limb_name, false)

# ── Helper ──────────────────────────────────────────────────────────────────

func _add_bg(ctrl: Control) -> void:
	if _hud_tex != null:
		var tex := TextureRect.new()
		tex.texture      = _hud_tex
		tex.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_SCALE
		tex.size         = Vector2(BOX, BOX)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ctrl.add_child(tex)
	else:
		var bg := ColorRect.new()
		bg.color        = Color(0.15, 0.15, 0.15, 0.75)
		bg.size         = Vector2(BOX, BOX)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ctrl.add_child(bg)

# ── Public update API ─────────────────────────────────────────────────────────

func update_combat_display(is_combat: bool) -> void:
	if _intent_label == null: return
	if is_combat: _intent_label.add_theme_color_override("font_color", Color(0.9, 0.15, 0.15))
	else:         _intent_label.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3))

func update_stance_display(stance: String) -> void:
	if _stance_icon == null:
		return
	var tex_path: String = "res://ui/dodge.png" if stance == "dodge" else "res://ui/parry.png"
	var tex := load(tex_path) as Texture2D
	if tex != null:
		_stance_icon.texture = tex

func update_grab_display(is_grabbing: bool, is_grabbed: bool) -> void:
	if _release_ctrl != null:
		_release_ctrl.visible = is_grabbing
	if _resist_ctrl != null:
		_resist_ctrl.visible = is_grabbed

func _on_release_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	if player == null:
		return
	if player.multiplayer.is_server():
		World.rpc_request_release_grab()
	else:
		World.rpc_request_release_grab.rpc_id(1)

func update_hands_display(hands: Array, active_hand: int) -> void:
	# Determine which hand (if any) is currently performing a grab
	var grab_hand: int = -1
	if player != null:
		var ghi = player.get("grab_hand_idx")
		var gt  = player.get("grabbed_target")
		if ghi != null and ghi >= 0 and gt != null and is_instance_valid(gt):
			grab_hand = ghi

	for i in range(min(2, _hand_icons.size())):
		_hand_highlights[i].color = Color(0.7, 0.7, 0.7, 0.25) if i == active_hand else Color(0, 0, 0, 0)
		var icon: Sprite2D = _hand_icons[i]
		var grab_lbl: Label = _hand_labels[i] if i < _hand_labels.size() else null
		var amt_lbl: Label = _hand_amt_labels[i] if i < _hand_amt_labels.size() else null
		
		# Check if the hand is broken and display the 'X'
		var is_broken = false
		if player != null and player.body != null:
			is_broken = player.body.is_arm_broken(i)
		if i < _hand_broken_labels.size():
			_hand_broken_labels[i].visible = is_broken

		if i == grab_hand:
			# This hand is occupied by a grab — show GRAB label, hide item icon
			icon.visible = false
			if grab_lbl != null: grab_lbl.visible = true
			if amt_lbl != null: amt_lbl.visible = false
		else:
			if grab_lbl != null: grab_lbl.visible = false
			
			if hands[i] != null:
				var obj_sprite: Sprite2D = hands[i].get_node_or_null("Sprite2D")
				if obj_sprite != null:
					icon.texture        = obj_sprite.texture
					icon.region_enabled = obj_sprite.region_enabled
					icon.region_rect    = obj_sprite.region_rect
					icon.visible        = true
				else: 
					icon.visible = false
					
				# Removed logic that set amt_lbl.visible = true
				if amt_lbl != null:
					amt_lbl.visible = false
			else: 
				icon.visible = false
				if amt_lbl != null: amt_lbl.visible = false

func update_clothing_display(equipped: Dictionary) -> void:
	for slot_name in _slot_icons.keys():
		var icon: Sprite2D = _slot_icons[slot_name]
		var item_name      = equipped.get(slot_name, null)
		if item_name != null and ItemRegistry.HUD_TEXTURES.has(item_name):
			var tex := load(ItemRegistry.HUD_TEXTURES[item_name]) as Texture2D
			if tex != null:
				icon.texture        = tex
				icon.region_enabled = true
				
				var region_set = false
				var scene_path = ItemRegistry.get_scene_path(item_name)
				if scene_path != "":
					var scene = load(scene_path) as PackedScene
					if scene != null:
						var state = scene.get_state()
						for i in range(state.get_node_count()):
							if state.get_node_name(i) == "Sprite2D":
								for j in range(state.get_node_property_count(i)):
									if state.get_node_property_name(i, j) == "region_rect":
										icon.region_rect = state.get_node_property_value(i, j)
										region_set = true
										break
								if region_set:
									break
				
				if not region_set:
					icon.region_rect = Rect2(0, 0, 32, 32)
					
				icon.scale          = Vector2(1.0, 1.0)
				icon.visible        = true
				continue
		icon.visible = false

# ── Input handlers ────────────────────────────────────────────────────────────

func _on_hand_gui_input(event: InputEvent, hand_idx: int) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed): return
	if player == null: return

	var clicked_item: Node = player.hands[hand_idx]

	if Input.is_key_pressed(KEY_SHIFT):
		if clicked_item == null: return
		var desc = ""
		if clicked_item.has_method("get_description"):
			desc = clicked_item.get_description()
		else:
			desc = clicked_item.get("item_type") if clicked_item.get("item_type") != null else clicked_item.name.get_slice("@", 0)
		
		player._show_inspect_text(desc, "")
		return

	# If the clicked hand has a satchel and the active hand holds an item, insert into satchel
	if hand_idx != player.active_hand and clicked_item != null and player.hands[player.active_hand] != null:
		var itype = clicked_item.get("item_type")
		if itype == "Satchel":
			var active_held: Node = player.hands[player.active_hand]
			if active_held.get("too_large_for_satchel") == true:
				var label = active_held.get("item_type") if active_held.get("item_type") != null else active_held.name
				Sidebar.add_message("[color=#ffaaaa]" + label + " is too large to fit in the satchel.[/color]")
				return
			if player.multiplayer.is_server():
				World.rpc_request_satchel_insert(clicked_item.get_path(), player.active_hand)
			else:
				World.rpc_request_satchel_insert.rpc_id(1, clicked_item.get_path(), player.active_hand)
			return

	# Combine coins in hands
	if hand_idx != player.active_hand and clicked_item != null and player.hands[player.active_hand] != null:
		var active_held: Node = player.hands[player.active_hand]
		if active_held.get("is_coin_stack") and clicked_item.get("is_coin_stack"):
			if active_held.get("item_type") == clicked_item.get("item_type"):
				if player.multiplayer.is_server():
					World.rpc_request_combine_hand_coins(player.active_hand, hand_idx)
				else:
					World.rpc_request_combine_hand_coins.rpc_id(1, player.active_hand, hand_idx)
				return

	# If the clicked hand has an item and the active hand is empty, handle transfer or storage open
	if hand_idx != player.active_hand and clicked_item != null and player.hands[player.active_hand] == null:
		# Split coin stack
		if clicked_item.get("is_coin_stack"):
			if clicked_item.get("amount") > 1:
				_show_coin_split_dialog(hand_idx, player.active_hand, clicked_item.get("amount"))
			else:
				# Only 1 coin, just transfer it normally
				if player.multiplayer.has_multiplayer_peer():
					if player.multiplayer.is_server():
						player.rpc_transfer_to_hand(hand_idx, player.active_hand)
					else:
						player.rpc_transfer_to_hand.rpc_id(1, hand_idx, player.active_hand)
			return

		# Storage items (e.g. satchel) open their inventory instead of transferring to active hand
		if clicked_item.has_method("_open_ui"):
			if clicked_item.get("_ui_layer") != null and is_instance_valid(clicked_item.get("_ui_layer")):
				clicked_item._close_ui()
			else:
				clicked_item._open_ui()
			return
            
		if player.body != null and player.body.is_arm_broken(player.active_hand):
			Sidebar.add_message("[color=#ffaaaa]That arm is useless![/color]")
			return
            
		if player.multiplayer.has_multiplayer_peer():
			if player.multiplayer.is_server():
				player.rpc_transfer_to_hand(hand_idx, player.active_hand)
			else:
				player.rpc_transfer_to_hand.rpc_id(1, hand_idx, player.active_hand)
		return

	# Switch active hand to the clicked hand
	if player.active_hand != hand_idx:
		player.active_hand = hand_idx
		player._update_hands_ui()
		if player.multiplayer.has_multiplayer_peer():
			if player.multiplayer.is_server():
				player.rpc("_sync_active_hand", hand_idx)
			else:
				player.rpc_id(1, "_sync_active_hand", hand_idx)

func _show_coin_split_dialog(from_idx: int, to_idx: int, max_amount: int) -> void:
	var dialog = ConfirmationDialog.new()
	dialog.title = "Split Coins"
	
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	
	var label = Label.new()
	label.text = "Amount to split (Max: " + str(max_amount - 1) + "):"
	vbox.add_child(label)
	
	var spinbox = SpinBox.new()
	spinbox.min_value = 1
	spinbox.max_value = max_amount - 1
	spinbox.value = 1
	vbox.add_child(spinbox)
	
	dialog.confirmed.connect(func():
		var split_amt = int(spinbox.value)
		if player != null and player.multiplayer.has_multiplayer_peer():
			if player.multiplayer.is_server():
				World.rpc_request_split_coins(from_idx, to_idx, split_amt)
			else:
				World.rpc_request_split_coins.rpc_id(1, from_idx, to_idx, split_amt)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	
	add_child(dialog)
	dialog.popup_centered()

func _on_intent_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed): return
	if player != null and player.has_method("toggle_combat_mode"): player.toggle_combat_mode()

func _on_craft_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed): return
	if player != null and player.has_method("toggle_crafting_menu"): player.toggle_crafting_menu()

func _on_stats_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed): return
	if player != null and player.has_method("show_stats_skills"): player.show_stats_skills()

func _on_sleep_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed): return
	if player != null and player.has_method("toggle_sleep"): player.toggle_sleep()

func _on_slot_gui_input(event: InputEvent, slot_name: String) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed): return
	if player == null: return
	var held: Node         = player.hands[player.active_hand]
	var currently_equipped = player.equipped.get(slot_name, null)

	if Input.is_key_pressed(KEY_SHIFT):
		if currently_equipped != null and currently_equipped != "":
			player._show_inspect_text(slot_name + ": " + currently_equipped, "")
		return

	if held != null:
		var item_slot = held.get("slot")
		if item_slot == slot_name and currently_equipped == null: player._equip_clothing_to_slot(held, slot_name)
	elif held == null and currently_equipped != null: 
		if player.body != null and player.body.is_arm_broken(player.active_hand):
			Sidebar.add_message("[color=#ffaaaa]That arm is useless![/color]")
			return
		player._unequip_clothing_from_slot(slot_name)

func _on_toggle_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed): return
	_clothing_visible = not _clothing_visible
	for slot_name in _slot_boxes.keys():
		if slot_name != "waist":
			_slot_boxes[slot_name].visible = _clothing_visible
	if _clothing_visible:
		if _toggle_bg    != null: _toggle_bg.visible    = true
		if _toggle_tex   != null: _toggle_tex.visible   = false
		if _toggle_label != null:
			_toggle_label.text = "X"
			_toggle_label.add_theme_color_override("font_color", Color(0.9, 0.15, 0.15))
	else:
		if _toggle_bg    != null: _toggle_bg.visible    = false
		if _toggle_tex   != null: _toggle_tex.visible   = true
		if _toggle_label != null:
			_toggle_label.text = "↑"
			_toggle_label.add_theme_color_override("font_color", Color(0.15, 0.9, 0.25))
