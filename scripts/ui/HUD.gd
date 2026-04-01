# res://scripts/ui/HUD.gd
extends CanvasLayer

var player: Node = null

const BOX:  int = 48
const GAP:  int = 4
const STEP: int = BOX + GAP

var _hud_tex:          Texture2D = null
var _clothing_visible: bool      = false
@warning_ignore("unused_private_class_variable")
var _clothing_panel:   Control   = null

var _slot_boxes:      Dictionary = {}
var _slot_icons:      Dictionary = {}
var _slot_amt_labels: Dictionary = {}

var _hand_highlights:    Array = []
var _hand_icons:         Array = []
var _hand_labels:        Array = []
var _hand_broken_labels: Array = []
var _hand_amt_labels:    Array = []

var _release_ctrl: Control = null
var _resist_ctrl:  Control = null

var _toggle_bg:    ColorRect   = null
var _toggle_tex:   TextureRect = null
var _toggle_label: Label       = null
var _intent_label: Label       = null

var _health_bar:  ColorRect = null
var _stamina_bar: ColorRect = null

var targeted_limb: String     = "chest"
var _limb_highlights:       Dictionary = {}
var _limb_broken_overlays:  Dictionary = {}

var _stance_icon: TextureRect = null

# ── Setup ─────────────────────────────────────────────────────────────────────

func setup(p: Node) -> void:
	player   = p
	layer    = 10
	_hud_tex = load("res://assets/HUDicon.jpg") as Texture2D
	_build()

func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var builder = preload("res://scripts/ui/hud_build.gd").new(self)
	builder.build_all(root)

# ── Limb selection ────────────────────────────────────────────────────────────

func _select_limb(limb_name: String) -> void:
	targeted_limb = limb_name
	for limb_key in _limb_highlights:
		_limb_highlights[limb_key].visible = (limb_key == limb_name)

func _on_limb_gui_input(event: InputEvent, limb_name: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_select_limb(limb_name)

# ── Stats update ──────────────────────────────────────────────────────────────

func update_stats(health: int, stamina: float) -> void:
	if _health_bar:
		var h = (clamp(health, 0, 100) / 100.0) * 80.0
		_health_bar.size.y     = h
		_health_bar.position.y = 80 - h
	if _stamina_bar:
		var s = (clamp(stamina, 0, 100) / 100.0) * 80.0
		_stamina_bar.size.y     = s
		_stamina_bar.position.y = 80 - s

	if player != null and player.body != null:
		for limb_name in _limb_broken_overlays.keys():
			_limb_broken_overlays[limb_name].visible = player.body.limb_broken.get(limb_name, false)

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
	if _release_ctrl != null: _release_ctrl.visible = is_grabbing
	if _resist_ctrl  != null: _resist_ctrl.visible  = is_grabbed

func update_hands_display(hands: Array, active_hand: int) -> void:
	var grab_hand: int = -1
	if player != null:
		var ghi = player.get("grab_hand_idx")
		var gt  = player.get("grabbed_target")
		if ghi != null and ghi >= 0 and gt != null and is_instance_valid(gt):
			grab_hand = ghi

	for i in range(min(2, _hand_icons.size())):
		_hand_highlights[i].color = Color(0.7, 0.7, 0.7, 0.25) if i == active_hand else Color(0, 0, 0, 0)
		var icon:      Sprite2D = _hand_icons[i]
		var grab_lbl:  Label    = _hand_labels[i] if i < _hand_labels.size() else null
		var amt_lbl:   Label    = _hand_amt_labels[i] if i < _hand_amt_labels.size() else null

		var is_broken = false
		if player != null and player.body != null:
			is_broken = player.body.is_arm_broken(i)
		if i < _hand_broken_labels.size():
			_hand_broken_labels[i].visible = is_broken

		if i == grab_hand:
			icon.visible = false
			if grab_lbl != null: grab_lbl.visible = true
			if amt_lbl  != null: amt_lbl.visible  = false
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

				if amt_lbl != null: amt_lbl.visible = false
			else:
				icon.visible = false
				if amt_lbl != null: amt_lbl.visible = false

func update_clothing_display(equipped: Dictionary, equipped_data: Dictionary = {}) -> void:
	for slot_name in _slot_icons.keys():
		var icon:      Sprite2D = _slot_icons[slot_name]
		var amt_lbl:   Label    = _slot_amt_labels[slot_name]
		var item_name           = equipped.get(slot_name, null)
		var _idata = ItemRegistry.get_by_type(item_name) if item_name != null else null

		if _idata != null and _idata.hud_texture_path != "":
			if item_name == "Hood" and slot_name == "face":
				var face_data = equipped_data.get("face", null)
				var hood_up: bool = false
				if face_data is Dictionary:
					hood_up = face_data.get("hood_up", false)
				var hood_tex_path: String = "res://clothing/hoodup.png" if hood_up else _idata.hud_texture_path
				var hood_tex := load(hood_tex_path) as Texture2D
				if hood_tex != null:
					icon.texture        = hood_tex
					icon.region_enabled = true
					icon.region_rect    = Rect2(0, 0, hood_tex.get_width(), hood_tex.get_height())
					var max_dim = max(hood_tex.get_width(), hood_tex.get_height())
					icon.scale   = Vector2(32.0 / max_dim, 32.0 / max_dim) if max_dim > 0 else Vector2(1.0, 1.0)
					icon.visible = true
				else:
					icon.visible = false
				amt_lbl.visible = false
				continue

			var atlas: AtlasTexture = ItemRegistry.get_item_icon(item_name) as AtlasTexture
			if atlas != null:
				icon.texture        = atlas
				icon.region_enabled = false
				var max_dim: float  = max(atlas.region.size.x, atlas.region.size.y)
				icon.scale   = Vector2(32.0 / max_dim, 32.0 / max_dim) if max_dim > 0 else Vector2(1.0, 1.0)
				icon.visible = true
				var data = equipped_data.get(slot_name)
				if typeof(data) == TYPE_DICTIONARY and data.has("amount") and data["amount"] > 1:
					amt_lbl.text    = str(data["amount"])
					amt_lbl.visible = true
				else:
					amt_lbl.visible = false
				continue

		icon.visible    = false
		amt_lbl.visible = false

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
	spinbox.value     = 1
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
	if player == null: return
	if player.multiplayer.is_server():
		World.rpc_request_release_grab()
	else:
		World.rpc_request_release_grab.rpc_id(1)

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

func _on_stance_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if player != null and player.has_method("toggle_combat_stance"):
			player.toggle_combat_stance()

func _on_slot_gui_input(event: InputEvent, slot_name: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if slot_name == "face" and player != null:
			var face_item = player.equipped.get("face", null)
			if face_item == "Hood":
				if player.has_method("toggle_hood_state"):
					player.toggle_hood_state()
		return

	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed): return
	if player == null: return
	var held: Node         = player.hands[player.active_hand]
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
		if slot_name not in ["waist", "pocket_l", "pocket_r"]:
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
