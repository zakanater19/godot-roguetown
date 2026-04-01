# res://scripts/ui/hud_build.gd
# Builder helper — constructs all HUD panels and assigns refs back to the HUD node.
extends RefCounted

const BOX:  int = 48
const GAP:  int = 4
const STEP: int = BOX + GAP

const SLOT_LAYOUT: Array = [
	["head",      1, 0],
	["cloak",     0, 1], ["face",      1, 1], ["backpack",  2, 1],
	["gloves",    0, 2], ["armor",     1, 2], ["trousers",  2, 2],
	["feet",      0, 3], ["clothing",  1, 3],
	["waist",     0, 4], ["pocket_l",  1, 4],
	["pocket_r",  2, 4],
]

const LIMB_REGIONS: Dictionary = {
	"chest": [Vector2(4,  8),  Vector2(57, 35)],
	"r_arm": [Vector2(12, 25), Vector2(11, 23)],
	"l_arm": [Vector2(42, 25), Vector2(11, 23)],
	"r_leg": [Vector2(17, 39), Vector2(14, 25)],
	"l_leg": [Vector2(34, 39), Vector2(14, 25)],
	"head":  [Vector2(23, 9),  Vector2(19, 18)],
}

var hud: CanvasLayer

func _init(h: CanvasLayer) -> void:
	hud = h

func build_all(root: Control) -> void:
	build_clothing_panel(root)
	build_hand_boxes(root)
	build_limb_panel(root)
	build_stance_icon(root)
	build_sneak_button(root)

# ── Clothing panel ────────────────────────────────────────────────────────────

func build_clothing_panel(parent: Control) -> void:
	var panel_w: int = 3 * STEP
	var panel_h: int = 5 * STEP

	var panel := Control.new()
	panel.anchor_left   = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_top    = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left   = -(50 + 8 + panel_w) - 166
	panel.offset_right  = -(50 + 8) - 166
	panel.offset_bottom = -16
	panel.offset_top    = -16 - panel_h
	panel.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	hud._clothing_panel = panel

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
	ctrl.visible             = true if slot_name in ["waist", "pocket_l", "pocket_r"] else hud._clothing_visible
	hud._clothing_panel.add_child(ctrl)

	_add_bg(ctrl)

	var label_text := slot_name
	if slot_name == "clothing":  label_text = "clothing\n/torso"
	elif slot_name == "pocket_l": label_text = "L. Pocket"
	elif slot_name == "pocket_r": label_text = "R. Pocket"
	elif slot_name == "face":     label_text = "face"

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

	hud._slot_boxes[slot_name]      = ctrl
	hud._slot_icons[slot_name]      = icon
	hud._slot_amt_labels[slot_name] = amt_lbl
	ctrl.gui_input.connect(func(event: InputEvent): hud._on_slot_gui_input(event, slot_name))

func _create_toggle_box(col: int, row: int) -> void:
	var ctrl := Control.new()
	ctrl.position            = Vector2(col * STEP, row * STEP)
	ctrl.size                = Vector2(BOX, BOX)
	ctrl.custom_minimum_size = Vector2(BOX, BOX)
	ctrl.clip_contents       = true
	ctrl.mouse_filter        = Control.MOUSE_FILTER_STOP
	hud._clothing_panel.add_child(ctrl)

	var tex := TextureRect.new()
	tex.texture      = hud._hud_tex
	tex.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.size         = Vector2(BOX, BOX)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.visible      = true
	ctrl.add_child(tex)
	hud._toggle_tex = tex

	var bg := ColorRect.new()
	bg.color        = Color(0.25, 0.05, 0.05, 0.85)
	bg.size         = Vector2(BOX, BOX)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.visible      = false
	ctrl.add_child(bg)
	hud._toggle_bg = bg

	var lbl := Label.new()
	lbl.text = "↑"
	lbl.add_theme_color_override("font_color", Color(0.15, 0.9, 0.25))
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	ctrl.add_child(lbl)
	hud._toggle_label = lbl
	ctrl.gui_input.connect(hud._on_toggle_gui_input)

# ── Hand boxes, Intent & Bars ─────────────────────────────────────────────────

func build_hand_boxes(parent: Control) -> void:
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
		hud._hand_highlights.append(highlight)

		var icon := Sprite2D.new()
		icon.position = Vector2(BOX / 2.0, BOX / 2.0)
		icon.scale    = Vector2(0.6, 0.6)
		icon.visible  = false
		ctrl.add_child(icon)
		hud._hand_icons.append(icon)

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
		hud._hand_amt_labels.append(amt_lbl)

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
		hud._hand_labels.append(grab_lbl)

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
		hud._hand_broken_labels.append(broken_lbl)

		ctrl.gui_input.connect(hud._on_hand_gui_input.bind(i))

	# Release grab button
	hud._release_ctrl = Control.new()
	hud._release_ctrl.position            = Vector2(-50, -(BOX + GAP))
	hud._release_ctrl.size                = Vector2(BOX, BOX)
	hud._release_ctrl.custom_minimum_size = Vector2(BOX, BOX)
	hud._release_ctrl.mouse_filter        = Control.MOUSE_FILTER_STOP
	hud._release_ctrl.visible             = false
	hands_ctrl.add_child(hud._release_ctrl)
	_add_bg(hud._release_ctrl)
	var release_lbl := Label.new()
	release_lbl.text = "RELEASE\n[Q]"
	release_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1))
	release_lbl.add_theme_font_size_override("font_size", 8)
	release_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	release_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	release_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	release_lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD
	release_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	hud._release_ctrl.add_child(release_lbl)
	hud._release_ctrl.gui_input.connect(hud._on_release_gui_input)

	# Resist grab button
	hud._resist_ctrl = Control.new()
	hud._resist_ctrl.position            = Vector2(2, -(BOX + GAP))
	hud._resist_ctrl.size                = Vector2(BOX, BOX)
	hud._resist_ctrl.custom_minimum_size = Vector2(BOX, BOX)
	hud._resist_ctrl.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	hud._resist_ctrl.visible             = false
	hands_ctrl.add_child(hud._resist_ctrl)
	_add_bg(hud._resist_ctrl)
	var resist_tex_node := TextureRect.new()
	var resist_tex := load("res://ui/resist.png") as Texture2D
	if resist_tex != null:
		resist_tex_node.texture      = resist_tex
		resist_tex_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		resist_tex_node.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		resist_tex_node.size         = Vector2(BOX, BOX)
		resist_tex_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud._resist_ctrl.add_child(resist_tex_node)
	var resist_lbl := Label.new()
	resist_lbl.text = "[Z]"
	resist_lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	resist_lbl.add_theme_font_size_override("font_size", 9)
	resist_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resist_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resist_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	resist_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	hud._resist_ctrl.add_child(resist_lbl)

	# Intent button
	var intent_ctrl := Control.new()
	intent_ctrl.position = Vector2(54, 0)
	intent_ctrl.size     = Vector2(BOX, BOX)
	hands_ctrl.add_child(intent_ctrl)
	_add_bg(intent_ctrl)
	hud._intent_label = Label.new()
	hud._intent_label.text = "COMBAT\nMODE"
	hud._intent_label.add_theme_font_size_override("font_size", 9)
	hud._intent_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud._intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud._intent_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	intent_ctrl.add_child(hud._intent_label)
	intent_ctrl.gui_input.connect(hud._on_intent_gui_input)

	# Crafting button
	var craft_ctrl := Control.new()
	craft_ctrl.position = Vector2(106, 0)
	craft_ctrl.size     = Vector2(BOX, BOX)
	hands_ctrl.add_child(craft_ctrl)
	_add_bg(craft_ctrl)
	var craft_lbl := Label.new()
	craft_lbl.text = "CRAFT"
	craft_lbl.add_theme_font_size_override("font_size", 11)
	craft_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	craft_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	craft_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	craft_ctrl.add_child(craft_lbl)
	craft_ctrl.gui_input.connect(hud._on_craft_gui_input)

	# Stats button
	var stats_ctrl := Control.new()
	stats_ctrl.position = Vector2(158, 0)
	stats_ctrl.size     = Vector2(BOX, BOX)
	hands_ctrl.add_child(stats_ctrl)
	_add_bg(stats_ctrl)
	var stats_lbl := Label.new()
	stats_lbl.text = "STATS"
	stats_lbl.add_theme_font_size_override("font_size", 10)
	stats_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	stats_ctrl.add_child(stats_lbl)
	stats_ctrl.gui_input.connect(hud._on_stats_gui_input)

	# Sleep button
	var sleep_ctrl := Control.new()
	sleep_ctrl.position = Vector2(210, 0)
	sleep_ctrl.size     = Vector2(BOX, BOX)
	hands_ctrl.add_child(sleep_ctrl)
	_add_bg(sleep_ctrl)
	var sleep_lbl := Label.new()
	sleep_lbl.text = "SLEEP"
	sleep_lbl.add_theme_font_size_override("font_size", 10)
	sleep_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sleep_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sleep_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	sleep_ctrl.add_child(sleep_lbl)
	sleep_ctrl.gui_input.connect(hud._on_sleep_gui_input)

	# Vertical bars
	var bar_container := HBoxContainer.new()
	bar_container.position = Vector2(264, -32)
	bar_container.add_theme_constant_override("separation", 6)
	hands_ctrl.add_child(bar_container)

	var hb_cont := Control.new()
	hb_cont.custom_minimum_size = Vector2(10, 80)
	bar_container.add_child(hb_cont)
	var hb_bg := ColorRect.new()
	hb_bg.color = Color(0.2, 0.2, 0.2)
	hb_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb_cont.add_child(hb_bg)
	hud._health_bar = ColorRect.new()
	hud._health_bar.color = Color(0.8, 0.1, 0.1)
	hud._health_bar.size  = Vector2(10, 80)
	hb_cont.add_child(hud._health_bar)

	var sb_cont := Control.new()
	sb_cont.custom_minimum_size = Vector2(10, 80)
	bar_container.add_child(sb_cont)
	var sb_bg := ColorRect.new()
	sb_bg.color = Color(0.2, 0.2, 0.2)
	sb_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sb_cont.add_child(sb_bg)
	hud._stamina_bar = ColorRect.new()
	hud._stamina_bar.color = Color(0.1, 0.8, 0.1)
	hud._stamina_bar.size  = Vector2(10, 80)
	sb_cont.add_child(hud._stamina_bar)

# ── Limb targeting panel ──────────────────────────────────────────────────────

func build_limb_panel(parent: Control) -> void:
	var panel := Control.new()
	panel.anchor_left   = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_top    = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_right  = -388
	panel.offset_left   = -388 - 64
	panel.offset_bottom = -16
	panel.offset_top    = -16 - 64
	panel.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)

	var base_tex := load("res://ui/m-zone_sel.png") as Texture2D
	if base_tex != null:
		var base := TextureRect.new()
		base.texture      = base_tex
		base.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		base.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		base.size         = Vector2(64, 64)
		base.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(base)

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
		hl.visible      = (limb_name == hud.targeted_limb)
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(hl)
		hud._limb_highlights[limb_name] = hl

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
		hud._limb_broken_overlays[limb_name] = broken_hl

	for limb_name in LIMB_REGIONS:
		var region: Array = LIMB_REGIONS[limb_name]
		var click := Control.new()
		click.position   = region[0]
		click.size       = region[1]
		click.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.add_child(click)
		click.gui_input.connect(func(event: InputEvent): hud._on_limb_gui_input(event, limb_name))

	hud._select_limb(hud.targeted_limb)

# ── Combat stance icon ────────────────────────────────────────────────────────

func build_stance_icon(parent: Control) -> void:
	var panel := Control.new()
	panel.anchor_left   = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_top    = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_right  = -460
	panel.offset_left   = -524
	panel.offset_bottom = -16
	panel.offset_top    = -16 - 64
	panel.mouse_filter  = Control.MOUSE_FILTER_STOP
	parent.add_child(panel)

	var bg := ColorRect.new()
	bg.color        = Color(0.1, 0.1, 0.1, 0.7)
	bg.size         = Vector2(64, 64)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bg)

	var dodge_tex := load("res://ui/dodge.png") as Texture2D
	hud._stance_icon = TextureRect.new()
	hud._stance_icon.texture      = dodge_tex
	hud._stance_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hud._stance_icon.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	hud._stance_icon.size         = Vector2(64, 64)
	hud._stance_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hud._stance_icon)

	panel.gui_input.connect(hud._on_stance_gui_input)

# ── Sneak button (bottom-left of stance panel) ───────────────────────────────

func build_sneak_button(parent: Control) -> void:
	# Same size and style as the stance icon (64x64 with dark background),
	# placed directly to the left of it, touching, no gap.
	# Stance icon: offset_left=-524, offset_right=-460, offset_top=-80, offset_bottom=-16
	const SNEAK_SIZE: int = 64
	var panel := Control.new()
	panel.anchor_left   = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_top    = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_right  = -524
	panel.offset_left   = -524 - SNEAK_SIZE
	panel.offset_bottom = -16
	panel.offset_top    = -16 - SNEAK_SIZE
	panel.mouse_filter  = Control.MOUSE_FILTER_STOP
	parent.add_child(panel)

	var sneak_off_tex := load("res://ui/sneakoff.png") as Texture2D
	hud._sneak_icon = TextureRect.new()
	hud._sneak_icon.texture      = sneak_off_tex
	hud._sneak_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hud._sneak_icon.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	hud._sneak_icon.size         = Vector2(SNEAK_SIZE, SNEAK_SIZE)
	hud._sneak_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hud._sneak_icon)

	panel.gui_input.connect(hud._on_sneak_gui_input)

# ── Shared helper ─────────────────────────────────────────────────────────────

func _add_bg(ctrl: Control) -> void:
	if hud._hud_tex != null:
		var tex := TextureRect.new()
		tex.texture      = hud._hud_tex
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
