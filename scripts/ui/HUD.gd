# res://scripts/ui/HUD.gd
extends CanvasLayer

var player: Node = null

const SLOT_NODE_NAMES: Dictionary = {
	"head": "HeadSlot",
	"cloak": "CloakSlot",
	"face": "FaceSlot",
	"backpack": "BackpackSlot",
	"gloves": "GlovesSlot",
	"armor": "ArmorSlot",
	"trousers": "TrousersSlot",
	"feet": "FeetSlot",
	"clothing": "ClothingSlot",
	"waist": "WaistSlot",
	"pocket_l": "PocketLSlot",
	"pocket_r": "PocketRSlot",
}

const HAND_NODE_NAMES: Array[String] = ["LeftHand", "RightHand"]
const LIMB_NODE_PREFIXES: Dictionary = {
	"head": "Head",
	"chest": "Chest",
	"r_arm": "RArm",
	"l_arm": "LArm",
	"r_leg": "RLeg",
	"l_leg": "LLeg",
}
const ALWAYS_VISIBLE_SLOTS: Array[String] = ["waist", "pocket_l", "pocket_r"]
const HUD_ICON_TEXTURE: Texture2D = preload("res://assets/HUDicon.jpg")
const RESIST_TEXTURE: Texture2D = preload("res://ui/resist.png")

var _clothing_visible: bool = false
@warning_ignore("unused_private_class_variable")
var _clothing_panel: Control = null

var _slot_boxes: Dictionary = {}
var _slot_icons: Dictionary = {}
var _slot_amt_labels: Dictionary = {}

var _hand_highlights: Array = []
var _hand_icons: Array = []
var _hand_labels: Array = []
var _hand_broken_labels: Array = []
var _hand_amt_labels: Array = []

var _release_ctrl: Control = null
var _resist_ctrl: Control = null

var _toggle_bg: ColorRect = null
var _toggle_tex: TextureRect = null
var _toggle_label: Label = null
var _intent_label: Label = null

var _health_bar: ColorRect = null
var _stamina_bar: ColorRect = null

var targeted_limb: String = "chest"
var _limb_highlights: Dictionary = {}
var _limb_broken_overlays: Dictionary = {}

var _stance_icon: TextureRect = null
var _sneak_icon: TextureRect = null

var _scene_cached: bool = false
var _signals_connected: bool = false

func _ready() -> void:
	_cache_scene_refs()
	_apply_clothing_visibility()
	_select_limb(targeted_limb)

func setup(p: Node) -> void:
	player = p
	layer = 10
	_cache_scene_refs()
	_apply_clothing_visibility()
	_select_limb(targeted_limb)

func _slot_label_text(slot_name: String) -> String:
	match slot_name:
		"clothing":
			return "clothing\n/torso"
		"pocket_l":
			return "L. Pocket"
		"pocket_r":
			return "R. Pocket"
		_:
			return slot_name

func _set_full_rect(ctrl: Control) -> void:
	ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _ensure_box_background(parent: Control) -> void:
	var bg := parent.get_node_or_null("Background") as TextureRect
	if bg != null:
		return
	bg = TextureRect.new()
	bg.name = "Background"
	_set_full_rect(bg)
	bg.texture = HUD_ICON_TEXTURE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	parent.move_child(bg, 0)

func _ensure_slot_widgets(slot_ctrl: Control, label_text: String) -> void:
	slot_ctrl.clip_contents = true
	_ensure_box_background(slot_ctrl)

	var lbl := slot_ctrl.get_node_or_null("Label") as Label
	if lbl == null:
		lbl = Label.new()
		lbl.name = "Label"
		_set_full_rect(lbl)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75, 0.5))
		lbl.add_theme_font_size_override("font_size", 9)
		slot_ctrl.add_child(lbl)
	lbl.text = label_text

	var icon := slot_ctrl.get_node_or_null("Icon") as Sprite2D
	if icon == null:
		icon = Sprite2D.new()
		icon.name = "Icon"
		icon.position = Vector2(24, 24)
		icon.scale = Vector2(UIDefs.HUD_ITEM_ICON_SCALE, UIDefs.HUD_ITEM_ICON_SCALE)
		icon.visible = false
		slot_ctrl.add_child(icon)

	var amt_lbl := slot_ctrl.get_node_or_null("AmountLabel") as Label
	if amt_lbl == null:
		amt_lbl = Label.new()
		amt_lbl.name = "AmountLabel"
		_set_full_rect(amt_lbl)
		amt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amt_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		amt_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		amt_lbl.visible = false
		amt_lbl.add_theme_color_override("font_color", Color.WHITE)
		amt_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		amt_lbl.add_theme_constant_override("outline_size", 3)
		amt_lbl.add_theme_font_size_override("font_size", 10)
		slot_ctrl.add_child(amt_lbl)

func _ensure_hand_widgets(hand_ctrl: Control, is_active: bool) -> void:
	_ensure_box_background(hand_ctrl)

	var highlight := hand_ctrl.get_node_or_null("Highlight") as ColorRect
	if highlight == null:
		highlight = ColorRect.new()
		highlight.name = "Highlight"
		_set_full_rect(highlight)
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hand_ctrl.add_child(highlight)
	highlight.color = Color(0.7, 0.7, 0.7, 0.25) if is_active else Color(0, 0, 0, 0)

	var icon := hand_ctrl.get_node_or_null("Icon") as Sprite2D
	if icon == null:
		icon = Sprite2D.new()
		icon.name = "Icon"
		icon.position = Vector2(24, 24)
		icon.scale = Vector2(UIDefs.HUD_HAND_ICON_SCALE, UIDefs.HUD_HAND_ICON_SCALE)
		icon.visible = false
		hand_ctrl.add_child(icon)

	var amt_lbl := hand_ctrl.get_node_or_null("AmountLabel") as Label
	if amt_lbl == null:
		amt_lbl = Label.new()
		amt_lbl.name = "AmountLabel"
		_set_full_rect(amt_lbl)
		amt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amt_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		amt_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		amt_lbl.visible = false
		amt_lbl.add_theme_color_override("font_color", Color.WHITE)
		amt_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		amt_lbl.add_theme_constant_override("outline_size", 3)
		amt_lbl.add_theme_font_size_override("font_size", 10)
		hand_ctrl.add_child(amt_lbl)

	var grab_lbl := hand_ctrl.get_node_or_null("GrabLabel") as Label
	if grab_lbl == null:
		grab_lbl = Label.new()
		grab_lbl.name = "GrabLabel"
		_set_full_rect(grab_lbl)
		grab_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grab_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grab_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grab_lbl.visible = false
		grab_lbl.text = "GRAB"
		grab_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.0))
		grab_lbl.add_theme_font_size_override("font_size", 12)
		hand_ctrl.add_child(grab_lbl)

	var broken_lbl := hand_ctrl.get_node_or_null("BrokenLabel") as Label
	if broken_lbl == null:
		broken_lbl = Label.new()
		broken_lbl.name = "BrokenLabel"
		_set_full_rect(broken_lbl)
		broken_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		broken_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		broken_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		broken_lbl.visible = false
		broken_lbl.text = "X"
		broken_lbl.add_theme_color_override("font_color", Color(0.9, 0.1, 0.1, 0.85))
		broken_lbl.add_theme_font_size_override("font_size", 40)
		hand_ctrl.add_child(broken_lbl)

func _ensure_text_button(ctrl: Control, label_name: String, text: String, font_size: int, font_color: Color = Color.WHITE) -> void:
	_ensure_box_background(ctrl)
	var lbl := ctrl.get_node_or_null(label_name) as Label
	if lbl == null:
		lbl = Label.new()
		lbl.name = label_name
		_set_full_rect(lbl)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ctrl.add_child(lbl)
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", font_color)

func _ensure_resist_button(ctrl: Control) -> void:
	_ensure_box_background(ctrl)

	var icon := ctrl.get_node_or_null("ResistIcon") as TextureRect
	if icon == null:
		icon = TextureRect.new()
		icon.name = "ResistIcon"
		_set_full_rect(icon)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ctrl.add_child(icon)
	icon.texture = RESIST_TEXTURE

	var lbl := ctrl.get_node_or_null("Label") as Label
	if lbl == null:
		lbl = Label.new()
		lbl.name = "Label"
		_set_full_rect(lbl)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ctrl.add_child(lbl)
	lbl.text = "[Z]"
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))

func _ensure_toggle_box(ctrl: Control) -> void:
	var tex := ctrl.get_node_or_null("ToggleTexture") as TextureRect
	if tex == null:
		tex = TextureRect.new()
		tex.name = "ToggleTexture"
		_set_full_rect(tex)
		tex.texture = HUD_ICON_TEXTURE
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_SCALE
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ctrl.add_child(tex)

	var bg := ctrl.get_node_or_null("ToggleBackground") as ColorRect
	if bg == null:
		bg = ColorRect.new()
		bg.name = "ToggleBackground"
		_set_full_rect(bg)
		bg.color = Color(0.25, 0.05, 0.05, 0.85)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.visible = false
		ctrl.add_child(bg)

	var lbl := ctrl.get_node_or_null("ToggleLabel") as Label
	if lbl == null:
		lbl = Label.new()
		lbl.name = "ToggleLabel"
		_set_full_rect(lbl)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.add_theme_font_size_override("font_size", 22)
		ctrl.add_child(lbl)

func _cache_scene_refs() -> void:
	if _scene_cached:
		return

	_clothing_panel = get_node_or_null("SafeArea/ClothingPanel") as Control
	var toggle_box := get_node_or_null("SafeArea/ClothingPanel/ToggleBox") as Control
	if toggle_box != null:
		_ensure_toggle_box(toggle_box)
	_toggle_bg = get_node_or_null("SafeArea/ClothingPanel/ToggleBox/ToggleBackground") as ColorRect
	_toggle_tex = get_node_or_null("SafeArea/ClothingPanel/ToggleBox/ToggleTexture") as TextureRect
	_toggle_label = get_node_or_null("SafeArea/ClothingPanel/ToggleBox/ToggleLabel") as Label

	_slot_boxes.clear()
	_slot_icons.clear()
	_slot_amt_labels.clear()
	for slot_name in SLOT_NODE_NAMES.keys():
		var slot_ctrl := get_node_or_null("SafeArea/ClothingPanel/" + SLOT_NODE_NAMES[slot_name]) as Control
		if slot_ctrl == null:
			continue
		_ensure_slot_widgets(slot_ctrl, _slot_label_text(slot_name))
		_slot_boxes[slot_name] = slot_ctrl
		_slot_icons[slot_name] = slot_ctrl.get_node_or_null("Icon") as Sprite2D
		_slot_amt_labels[slot_name] = slot_ctrl.get_node_or_null("AmountLabel") as Label

	_hand_highlights.clear()
	_hand_icons.clear()
	_hand_labels.clear()
	_hand_broken_labels.clear()
	_hand_amt_labels.clear()
	for hand_idx in range(HAND_NODE_NAMES.size()):
		var hand_name := HAND_NODE_NAMES[hand_idx]
		var hand_ctrl := get_node_or_null("SafeArea/HandsPanel/" + hand_name) as Control
		if hand_ctrl == null:
			continue
		_ensure_hand_widgets(hand_ctrl, hand_idx == 0)
		_hand_highlights.append(hand_ctrl.get_node_or_null("Highlight") as ColorRect)
		_hand_icons.append(hand_ctrl.get_node_or_null("Icon") as Sprite2D)
		_hand_labels.append(hand_ctrl.get_node_or_null("GrabLabel") as Label)
		_hand_broken_labels.append(hand_ctrl.get_node_or_null("BrokenLabel") as Label)
		_hand_amt_labels.append(hand_ctrl.get_node_or_null("AmountLabel") as Label)

	_release_ctrl = get_node_or_null("SafeArea/HandsPanel/ReleaseButton") as Control
	_resist_ctrl = get_node_or_null("SafeArea/HandsPanel/ResistButton") as Control
	if _release_ctrl != null:
		_ensure_text_button(_release_ctrl, "Label", "RELEASE\n[Q]", 8, Color(1.0, 0.6, 0.1))
	if _resist_ctrl != null:
		_ensure_resist_button(_resist_ctrl)

	var intent_button := get_node_or_null("SafeArea/HandsPanel/IntentButton") as Control
	if intent_button != null:
		_ensure_text_button(intent_button, "IntentLabel", "COMBAT\nMODE", 9, Color(0.3, 0.3, 0.3))

	var craft_button := get_node_or_null("SafeArea/HandsPanel/CraftButton") as Control
	if craft_button != null:
		_ensure_text_button(craft_button, "Label", "CRAFT", 11)

	var stats_button := get_node_or_null("SafeArea/HandsPanel/StatsButton") as Control
	if stats_button != null:
		_ensure_text_button(stats_button, "Label", "STATS", 10)

	var sleep_button := get_node_or_null("SafeArea/HandsPanel/SleepButton") as Control
	if sleep_button != null:
		_ensure_text_button(sleep_button, "Label", "SLEEP", 10)

	_intent_label = get_node_or_null("SafeArea/HandsPanel/IntentButton/IntentLabel") as Label
	_health_bar = get_node_or_null("SafeArea/HandsPanel/BarContainer/HealthContainer/HealthBar") as ColorRect
	_stamina_bar = get_node_or_null("SafeArea/HandsPanel/BarContainer/StaminaContainer/StaminaBar") as ColorRect

	_limb_highlights.clear()
	_limb_broken_overlays.clear()
	for limb_name in LIMB_NODE_PREFIXES.keys():
		var limb_prefix: String = LIMB_NODE_PREFIXES[limb_name]
		_limb_highlights[limb_name] = get_node_or_null("SafeArea/LimbPanel/" + limb_prefix + "Highlight") as TextureRect
		_limb_broken_overlays[limb_name] = get_node_or_null("SafeArea/LimbPanel/" + limb_prefix + "Broken") as TextureRect

	_stance_icon = get_node_or_null("SafeArea/StancePanel/StanceIcon") as TextureRect
	_sneak_icon = get_node_or_null("SafeArea/SneakPanel/SneakIcon") as TextureRect

	_connect_scene_signals()
	_scene_cached = true

func _connect_scene_signals() -> void:
	if _signals_connected:
		return

	for slot_name in SLOT_NODE_NAMES.keys():
		var slot_ctrl: Control = _slot_boxes.get(slot_name, null)
		if slot_ctrl != null:
			slot_ctrl.gui_input.connect(_on_slot_gui_input.bind(slot_name))

	for i in range(HAND_NODE_NAMES.size()):
		var hand_ctrl := get_node_or_null("SafeArea/HandsPanel/" + HAND_NODE_NAMES[i]) as Control
		if hand_ctrl != null:
			hand_ctrl.gui_input.connect(_on_hand_gui_input.bind(i))

	if _release_ctrl != null:
		_release_ctrl.gui_input.connect(_on_release_gui_input)

	var intent_button := get_node_or_null("SafeArea/HandsPanel/IntentButton") as Control
	if intent_button != null:
		intent_button.gui_input.connect(_on_intent_gui_input)

	var craft_button := get_node_or_null("SafeArea/HandsPanel/CraftButton") as Control
	if craft_button != null:
		craft_button.gui_input.connect(_on_craft_gui_input)

	var stats_button := get_node_or_null("SafeArea/HandsPanel/StatsButton") as Control
	if stats_button != null:
		stats_button.gui_input.connect(_on_stats_gui_input)

	var sleep_button := get_node_or_null("SafeArea/HandsPanel/SleepButton") as Control
	if sleep_button != null:
		sleep_button.gui_input.connect(_on_sleep_gui_input)

	var toggle_button := get_node_or_null("SafeArea/ClothingPanel/ToggleBox") as Control
	if toggle_button != null:
		toggle_button.gui_input.connect(_on_toggle_gui_input)

	for limb_name in LIMB_NODE_PREFIXES.keys():
		var limb_prefix: String = LIMB_NODE_PREFIXES[limb_name]
		var click_ctrl := get_node_or_null("SafeArea/LimbPanel/" + limb_prefix + "Click") as Control
		if click_ctrl != null:
			click_ctrl.gui_input.connect(_on_limb_gui_input.bind(limb_name))

	var stance_panel := get_node_or_null("SafeArea/StancePanel") as Control
	if stance_panel != null:
		stance_panel.gui_input.connect(_on_stance_gui_input)

	var sneak_panel := get_node_or_null("SafeArea/SneakPanel") as Control
	if sneak_panel != null:
		sneak_panel.gui_input.connect(_on_sneak_gui_input)

	_signals_connected = true

func _apply_clothing_visibility() -> void:
	for slot_name in _slot_boxes.keys():
		var slot_ctrl: Control = _slot_boxes[slot_name]
		slot_ctrl.visible = slot_name in ALWAYS_VISIBLE_SLOTS or _clothing_visible

	if _toggle_bg != null:
		_toggle_bg.visible = _clothing_visible
	if _toggle_tex != null:
		_toggle_tex.visible = not _clothing_visible
	if _toggle_label != null:
		_toggle_label.text = "X" if _clothing_visible else "^"
		var label_color := Color(0.9, 0.15, 0.15) if _clothing_visible else Color(0.15, 0.9, 0.25)
		_toggle_label.add_theme_color_override("font_color", label_color)

func _select_limb(limb_name: String) -> void:
	targeted_limb = limb_name
	for limb_key in _limb_highlights:
		var highlight: TextureRect = _limb_highlights[limb_key]
		if highlight != null:
			highlight.visible = (limb_key == limb_name)

func _on_limb_gui_input(event: InputEvent, limb_name: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_select_limb(limb_name)

func update_stats(health: int, stamina: float) -> void:
	if _health_bar:
		var h = (clamp(health, 0, PlayerDefs.DEFAULT_HEALTH) / float(PlayerDefs.DEFAULT_HEALTH)) * UIDefs.HUD_BAR_SIZE.y
		_health_bar.size.y = h
		_health_bar.position.y = UIDefs.HUD_BAR_SIZE.y - h
	if _stamina_bar:
		var s = (clamp(stamina, 0, 100) / 100.0) * UIDefs.HUD_BAR_SIZE.y
		_stamina_bar.size.y = s
		_stamina_bar.position.y = UIDefs.HUD_BAR_SIZE.y - s

	if player != null and player.body != null:
		for limb_name in _limb_broken_overlays.keys():
			var broken_overlay: TextureRect = _limb_broken_overlays[limb_name]
			if broken_overlay != null:
				broken_overlay.visible = player.body.limb_broken.get(limb_name, false)

func update_combat_display(is_combat: bool) -> void:
	if _intent_label == null:
		return
	if is_combat:
		_intent_label.add_theme_color_override("font_color", Color(0.9, 0.15, 0.15))
	else:
		_intent_label.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3))

func update_stance_display(stance: String) -> void:
	if _stance_icon == null:
		return
	var tex_path: String = "res://ui/dodge.png" if stance == "dodge" else "res://ui/parry.png"
	var tex := load(tex_path) as Texture2D
	if tex != null:
		_stance_icon.texture = tex

func update_sneak_display(sneaking: bool) -> void:
	if _sneak_icon == null:
		return
	var tex_path: String = "res://ui/sneakon.png" if sneaking else "res://ui/sneakoff.png"
	var tex := load(tex_path) as Texture2D
	if tex != null:
		_sneak_icon.texture = tex

func update_grab_display(is_grabbing: bool, is_grabbed: bool) -> void:
	if _release_ctrl != null:
		_release_ctrl.visible = is_grabbing
	if _resist_ctrl != null:
		_resist_ctrl.visible = is_grabbed

func update_hands_display(hands: Array, active_hand: int) -> void:
	var grab_hand: int = -1
	if player != null:
		var ghi = player.get("grab_hand_idx")
		var gt = player.get("grabbed_target")
		if ghi != null and ghi >= 0 and gt != null and is_instance_valid(gt):
			grab_hand = ghi

	for i in range(min(2, _hand_icons.size())):
		_hand_highlights[i].color = Color(0.7, 0.7, 0.7, 0.25) if i == active_hand else Color(0, 0, 0, 0)
		var icon: Sprite2D = _hand_icons[i]
		var grab_lbl: Label = _hand_labels[i] if i < _hand_labels.size() else null
		var amt_lbl: Label = _hand_amt_labels[i] if i < _hand_amt_labels.size() else null

		var is_broken := false
		if player != null and player.body != null:
			is_broken = player.body.is_arm_broken(i)
		if i < _hand_broken_labels.size():
			_hand_broken_labels[i].visible = is_broken

		if i == grab_hand:
			icon.visible = false
			if grab_lbl != null:
				grab_lbl.visible = true
			if amt_lbl != null:
				amt_lbl.visible = false
		else:
			if grab_lbl != null:
				grab_lbl.visible = false

			if hands[i] != null:
				var obj_sprite: Sprite2D = hands[i].get_node_or_null("Sprite2D")
				if obj_sprite != null:
					icon.texture = obj_sprite.texture
					icon.region_enabled = obj_sprite.region_enabled
					icon.region_rect = obj_sprite.region_rect
					icon.visible = true
				else:
					icon.visible = false

				if amt_lbl != null:
					amt_lbl.visible = false
			else:
				icon.visible = false
				if amt_lbl != null:
					amt_lbl.visible = false

func update_clothing_display(equipped: Dictionary, equipped_data: Dictionary = {}) -> void:
	for slot_name in _slot_icons.keys():
		var icon: Sprite2D = _slot_icons[slot_name]
		var amt_lbl: Label = _slot_amt_labels[slot_name]
		var item_name = equipped.get(slot_name, null)
		var item_data = ItemRegistry.get_by_type(item_name) if item_name != null else null

		if item_data != null and item_data.hud_texture_path != "":
			if item_name == "Hood" and slot_name == "face":
				var face_data = equipped_data.get("face", null)
				var hood_up := false
				if face_data is Dictionary:
					hood_up = face_data.get("hood_up", false)
				var hood_tex_path: String = "res://clothing/hoodup.png" if hood_up else item_data.hud_texture_path
				var hood_tex := load(hood_tex_path) as Texture2D
				if hood_tex != null:
					icon.texture = hood_tex
					icon.region_enabled = true
					icon.region_rect = Rect2(0, 0, hood_tex.get_width(), hood_tex.get_height())
					var max_dim = max(hood_tex.get_width(), hood_tex.get_height())
					icon.scale = Vector2(UIDefs.HUD_ITEM_ICON_TARGET_SIZE / max_dim, UIDefs.HUD_ITEM_ICON_TARGET_SIZE / max_dim) if max_dim > 0 else Vector2.ONE
					icon.visible = true
				else:
					icon.visible = false
				amt_lbl.visible = false
				continue
			elif item_name.ends_with("Coin"):
				var edata = equipped_data.get(slot_name)
				var amt := 1
				var mtype := 0
				if typeof(edata) == TYPE_DICTIONARY:
					if edata.has("state"):
						var state = edata["state"]
						amt = state.get("amount", 1)
						mtype = state.get("metal_type", 0)
					else:
						amt = edata.get("amount", 1)
						mtype = edata.get("metal_type", 0)

				var icon_path := Defs.get_coin_icon_path(amt, mtype)
				if icon_path != "":
					var tex = load(icon_path)
					if tex != null:
						icon.texture = tex
						icon.region_enabled = false
						var max_dim = max(tex.get_width(), tex.get_height())
						icon.scale = Vector2(UIDefs.HUD_ITEM_ICON_TARGET_SIZE / max_dim, UIDefs.HUD_ITEM_ICON_TARGET_SIZE / max_dim) if max_dim > 0 else Vector2.ONE
						icon.visible = true
						amt_lbl.visible = false
						continue

			var atlas: AtlasTexture = ItemRegistry.get_item_icon(item_name) as AtlasTexture
			if atlas != null:
				icon.texture = atlas
				icon.region_enabled = false
				var atlas_max_dim: float = max(atlas.region.size.x, atlas.region.size.y)
				icon.scale = Vector2(UIDefs.HUD_ITEM_ICON_TARGET_SIZE / atlas_max_dim, UIDefs.HUD_ITEM_ICON_TARGET_SIZE / atlas_max_dim) if atlas_max_dim > 0 else Vector2.ONE
				icon.visible = true
				var data = equipped_data.get(slot_name)
				if typeof(data) == TYPE_DICTIONARY and data.has("amount") and data["amount"] > 1:
					amt_lbl.text = str(data["amount"])
					amt_lbl.visible = true
				else:
					amt_lbl.visible = false
				continue

		icon.visible = false
		amt_lbl.visible = false

func _on_hand_gui_input(event: InputEvent, hand_idx: int) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	if player == null:
		return

	var clicked_item: Node = player.hands[hand_idx]

	if Input.is_key_pressed(KEY_SHIFT):
		if clicked_item == null:
			return
		var desc := ""
		if clicked_item.has_method("get_description"):
			desc = clicked_item.get_description()
		else:
			desc = clicked_item.get("item_type") if clicked_item.get("item_type") != null else clicked_item.name.get_slice("@", 0)
		player._show_inspect_text(desc, "")
		return

	if hand_idx != player.active_hand and clicked_item != null and player.hands[player.active_hand] != null:
		var itype = clicked_item.get("item_type")
		if itype == "Satchel":
			var active_held: Node = player.hands[player.active_hand]
			if active_held.get("too_large_for_satchel") == true:
				var label = active_held.get("item_type") if active_held.get("item_type") != null else active_held.name
				Sidebar.add_message("[color=#ffaaaa]" + label + " is too large to fit in the satchel.[/color]")
				return
			var clicked_item_id := World.get_entity_id(clicked_item)
			if player.multiplayer.is_server():
				World.rpc_request_satchel_insert(clicked_item_id, player.active_hand)
			else:
				World.rpc_request_satchel_insert.rpc_id(1, clicked_item_id, player.active_hand)
			return

	if hand_idx != player.active_hand and clicked_item != null and player.hands[player.active_hand] != null:
		var active_held: Node = player.hands[player.active_hand]
		if active_held.get("is_coin_stack") and clicked_item.get("is_coin_stack"):
			if active_held.get("item_type") == clicked_item.get("item_type"):
				if player.multiplayer.is_server():
					World.rpc_request_combine_hand_coins(player.active_hand, hand_idx)
				else:
					World.rpc_request_combine_hand_coins.rpc_id(1, player.active_hand, hand_idx)
				return

	if hand_idx != player.active_hand and clicked_item != null and player.hands[player.active_hand] == null:
		if clicked_item.get("is_coin_stack"):
			if clicked_item.get("amount") > 1:
				_show_coin_split_dialog(hand_idx, player.active_hand, clicked_item.get("amount"))
			else:
				if player.multiplayer.has_multiplayer_peer():
					if player.multiplayer.is_server():
						player.rpc_transfer_to_hand(hand_idx, player.active_hand)
					else:
						player.rpc_transfer_to_hand.rpc_id(1, hand_idx, player.active_hand)
			return

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

	if player.active_hand != hand_idx:
		player.active_hand = hand_idx
		player._update_hands_ui()
		if player.multiplayer.has_multiplayer_peer():
			if player.multiplayer.is_server():
				player.rpc("_sync_active_hand", hand_idx)
			else:
				player.rpc_id(1, "_sync_active_hand", hand_idx)

func _show_coin_split_dialog(from_idx: int, to_idx: int, max_amount: int) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Split Coins"

	var vbox := VBoxContainer.new()
	dialog.add_child(vbox)

	var label := Label.new()
	label.text = "Amount to split (Max: " + str(max_amount - 1) + "):"
	vbox.add_child(label)

	var spinbox := SpinBox.new()
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

func _on_release_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	if player == null:
		return
	if player.multiplayer.is_server():
		World.rpc_request_release_grab()
	else:
		World.rpc_request_release_grab.rpc_id(1)

func _on_intent_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	if player != null and player.has_method("toggle_combat_mode"):
		player.toggle_combat_mode()

func _on_craft_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	if player != null and player.has_method("toggle_crafting_menu"):
		player.toggle_crafting_menu()

func _on_stats_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	if player != null and player.has_method("show_stats_skills"):
		player.show_stats_skills()

func _on_sleep_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	if player != null and player.has_method("toggle_sleep"):
		player.toggle_sleep()

func _on_stance_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if player != null and player.has_method("toggle_combat_stance"):
			player.toggle_combat_stance()

func _on_sneak_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if player != null and player.has_method("toggle_sneak_mode"):
			player.toggle_sneak_mode()

func _on_slot_gui_input(event: InputEvent, slot_name: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if slot_name == "face" and player != null:
			var face_item = player.equipped.get("face", null)
			if face_item == "Hood" and player.has_method("toggle_hood_state"):
				player.toggle_hood_state()
		return

	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	if player == null:
		return
	var held: Node = player.hands[player.active_hand]
	var currently_equipped = player.equipped.get(slot_name, null)

	if Input.is_key_pressed(KEY_SHIFT):
		if currently_equipped != null and currently_equipped != "":
			player._show_inspect_text(slot_name + ": " + currently_equipped, "")
		return

	if held != null:
		if slot_name in ["pocket_l", "pocket_r"]:
			if held.get("too_large_for_satchel") == true:
				var item_label = held.get("item_type") if held.get("item_type") != null else held.name
				Sidebar.add_message("[color=#ffaaaa]" + item_label + " is too large to fit in your pocket.[/color]")
				return
			if currently_equipped == null:
				player._equip_clothing_to_slot(held, slot_name)
		else:
			var item_slot = held.get("slot")
			if item_slot == slot_name and currently_equipped == null:
				player._equip_clothing_to_slot(held, slot_name)
	elif held == null and currently_equipped != null:
		if player.body != null and player.body.is_arm_broken(player.active_hand):
			Sidebar.add_message("[color=#ffaaaa]That arm is useless![/color]")
			return
		player._unequip_clothing_from_slot(slot_name)

func _on_toggle_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	_clothing_visible = not _clothing_visible
	_apply_clothing_visibility()
