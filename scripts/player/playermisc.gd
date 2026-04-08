# res://scripts/player/playermisc.gd
extends RefCounted

var player: Node2D

# --- LOOTING STATE ---
var loot_panel: Control = null
var loot_target: Node = null
var loot_slot_controls: Dictionary = {}
var active_loot_attempts: Array = []

func _init(p_player: Node2D) -> void:
	player = p_player

# ===========================================================================
# Lifecycle Updates
# ===========================================================================

func update(delta: float) -> void:
	if loot_panel != null and is_instance_valid(loot_target):
		var diff: Vector2i = (loot_target.tile_pos - player.tile_pos).abs()
		if diff.x > 1 or diff.y > 1 or loot_target.z_level != player.z_level:
			close_target_inventory()

	_update_loot_attempts(delta)

func on_tile_pos_changed() -> void:
	pass

func close_menus() -> void:
	if loot_panel != null:
		close_target_inventory()

# ===========================================================================
# Looting
# ===========================================================================

func open_target_inventory(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	if loot_panel != null:
		close_target_inventory()

	var diff: Vector2i = (target.tile_pos - player.tile_pos).abs()
	if diff.x > 1 or diff.y > 1 or target.z_level != player.z_level:
		return

	loot_target = target
	loot_slot_controls.clear()

	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(230, 240)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left   = -115
	panel.offset_right  = 115
	panel.offset_top    = -200 # Shifted higher to avoid overlapping the hotbar
	panel.offset_bottom = 160
	panel.mouse_filter  = Control.MOUSE_FILTER_STOP
	loot_panel = panel
	player._ui_root.add_child(panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.offset_left   = 6
	main_vbox.offset_right  = -6
	main_vbox.offset_top    = 6
	main_vbox.offset_bottom = -6
	main_vbox.add_theme_constant_override("separation", 4)
	panel.add_child(main_vbox)

	var title_row := HBoxContainer.new()
	main_vbox.add_child(title_row)

	var target_peer: int = target.get_multiplayer_authority()
	var target_name: String = target.character_name if "character_name" in target else "Player " + str(target_peer)
	var title := Label.new()
	title.text = target_name + ("[DEAD]" if target.dead else "")
	title.add_theme_color_override("font_color", Color(1, 0.6, 0.1))
	title.add_theme_font_size_override("font_size", 12)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(24, 20)
	close_btn.pressed.connect(close_target_inventory)
	title_row.add_child(close_btn)

	main_vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll)
	
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	var hands_lbl := Label.new()
	hands_lbl.text = "Hands"
	hands_lbl.add_theme_font_size_override("font_size", 11)
	hands_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(hands_lbl)

	for i in range(2):
		var hand_label: String = "Right hand" if i == 0 else "Left hand"
		var slot_key:   String = "hand_" + str(i)
		var row := _build_slot_row(vbox, hand_label, slot_key)
		loot_slot_controls[slot_key] = row

	vbox.add_child(HSeparator.new())

	var equip_lbl := Label.new()
	equip_lbl.text = "Equipment"
	equip_lbl.add_theme_font_size_override("font_size", 11)
	equip_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(equip_lbl)

	for es in Defs.SLOTS_ALL:
		var slot_key: String = "equip_" + es
		var row := _build_slot_row(vbox, Defs.SLOT_DISPLAY[es], slot_key)
		loot_slot_controls[slot_key] = row

	refresh_loot_panel()

func _build_slot_row(parent: Control, label_text: String, slot_key: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text + ":"
	lbl.custom_minimum_size.x = 72
	lbl.add_theme_font_size_override("font_size", 11)
	row.add_child(lbl)

	var btn := Button.new()
	btn.text                  = "empty"
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size.y = 26 # Reduced to compress the list size
	btn.add_theme_font_size_override("font_size", 10)
	btn.icon_alignment        = HORIZONTAL_ALIGNMENT_CENTER
	btn.expand_icon           = true
	btn.disabled              = true
	var sk := slot_key
	btn.pressed.connect(func(): _on_loot_slot_pressed(sk))
	row.add_child(btn)

	return {"btn": btn}

func refresh_loot_panel() -> void:
	if loot_target == null or not is_instance_valid(loot_target):
		close_target_inventory()
		return

	var item_registry = ItemRegistry

	for i in range(2):
		var sk: String = "hand_" + str(i)
		if not loot_slot_controls.has(sk):
			continue
		var ctrl = loot_slot_controls[sk]
		var btn: Button = ctrl["btn"]
		var obj: Node   = loot_target.hands[i]
		if obj != null and is_instance_valid(obj):
			var item_name = obj.get("item_type")
			if item_name == null: item_name = obj.name.get_slice("@", 0)
			var amt = obj.get("amount") if "amount" in obj else 1
			
			var icon_tex = null
			if item_registry != null and item_registry.has_method("get_item_icon"):
				icon_tex = item_registry.get_item_icon(item_name)
				
			if icon_tex != null:
				btn.text = str(amt) if amt > 1 else ""
				btn.icon = icon_tex
			else:
				btn.text = (str(amt) + "x " + item_name) if amt > 1 else item_name
				btn.icon = null

			btn.disabled = false
		else:
			btn.text     = "empty"
			btn.icon     = null
			btn.disabled = true

	for es in Defs.SLOTS_ALL:
		var sk: String = "equip_" + es
		if not loot_slot_controls.has(sk):
			continue
		var ctrl = loot_slot_controls[sk]
		var btn: Button  = ctrl["btn"]
		var item = loot_target.equipped.get(es, null)
		if item != null and item is String and item != "":
			var icon_tex = null

			# ── Special Case: COINS (Dynamic Stack Sprites) ──────────
			if item.ends_with("Coin"):
				var edata = loot_target.equipped_data.get(es)
				var amt = 1
				var mtype = 0
				if typeof(edata) == TYPE_DICTIONARY:
					# Pockets and hands usually store flat data
					amt = edata.get("amount", 1)
					mtype = edata.get("metal_type", 0)
				
				var suffix = ["copper", "silver", "gold"][mtype]
				var thresholds = [20, 15, 10, 5, 4, 3, 2, 1]
				for ta in thresholds:
					if amt >= ta:
						var p = "res://objects/coins/" + str(ta) + suffix + ".png"
						if ResourceLoader.exists(p):
							icon_tex = load(p)
							break
			# ── General Case: Standard Items ──────────────────────────
			elif item_registry != null and item_registry.has_method("get_item_icon"):
				icon_tex = item_registry.get_item_icon(item)

			if icon_tex != null:
				btn.text = ""
				btn.icon = icon_tex
			else:
				btn.text = item
				btn.icon = null

			btn.disabled = false
		else:
			btn.text     = "empty"
			btn.icon     = null
			btn.disabled = true

func close_target_inventory() -> void:
	loot_target = null
	loot_slot_controls.clear()
	if loot_panel != null and is_instance_valid(loot_panel):
		loot_panel.queue_free()
	loot_panel = null

func _on_loot_slot_pressed(slot_key: String) -> void:
	if loot_target == null or not is_instance_valid(loot_target):
		return

	for attempt in active_loot_attempts:
		if attempt["slot_key"] == slot_key:
			return

	var diff: Vector2i = (loot_target.tile_pos - player.tile_pos).abs()
	if diff.x > 1 or diff.y > 1 or loot_target.z_level != player.z_level:
		return

	var item_desc: String = ""
	var slot_type: String = ""
	var slot_index         = null

	if slot_key.begins_with("hand_"):
		var idx: int = slot_key.trim_prefix("hand_").to_int()
		var obj: Node = loot_target.hands[idx]
		if obj == null or not is_instance_valid(obj):
			return
		var iname = obj.get("item_type")
		if iname == null: iname = obj.name.get_slice("@", 0)
		item_desc  = iname
		slot_type  = "hand"
		slot_index = idx
	else:
		var equip_slot: String = slot_key.trim_prefix("equip_")
		var item = loot_target.equipped.get(equip_slot, null)
		if item == null or not (item is String) or item == "":
			return
		item_desc  = item
		slot_type  = "equip"
		slot_index = equip_slot

	var prog_lbl: Label = _create_loot_indicator(loot_target, slot_key)
	prog_lbl.text    = "."
	prog_lbl.visible = true

	var attempt := {
		"slot_key":      slot_key,
		"slot_type":     slot_type,
		"slot_index":    slot_index,
		"elapsed":       0.0,
		"blink_elapsed": 0.0,
		"prog_label":    prog_lbl,
		"item_desc":     item_desc,
		"target":        loot_target
	}
	active_loot_attempts.append(attempt)

	var my_peer_id: int = player.multiplayer.get_unique_id()
	var target_path: NodePath = loot_target.get_path()
	if player.multiplayer.is_server():
		World.rpc_notify_loot_warning(target_path, my_peer_id, item_desc)
	else:
		World.rpc_notify_loot_warning.rpc_id(1, target_path, my_peer_id, item_desc)

func _update_loot_attempts(delta: float) -> void:
	var completed_keys: Array = []
	var cancelled_keys: Array =[]

	for attempt in active_loot_attempts:
		var slot_key:   String = attempt["slot_key"]
		var slot_type:  String = attempt["slot_type"]
		var slot_index         = attempt["slot_index"]
		var prog_lbl:   Label  = attempt["prog_label"]
		var target:     Node   = attempt["target"]

		if not is_instance_valid(target):
			cancelled_keys.append(slot_key)
			continue

		var diff: Vector2i = (target.tile_pos - player.tile_pos).abs()
		if diff.x > 1 or diff.y > 1 or target.z_level != player.z_level:
			cancelled_keys.append(slot_key)
			continue

		var item_still_there: bool = false
		if slot_type == "hand":
			var obj: Node = target.hands[int(slot_index)]
			item_still_there = (obj != null and is_instance_valid(obj))
		else:
			var item = target.equipped.get(str(slot_index), null)
			item_still_there = (item != null and item is String and item != "")

		if not item_still_there:
			cancelled_keys.append(slot_key)
			continue

		attempt["elapsed"]       += delta
		attempt["blink_elapsed"] += delta

		var progress: float = clamp(attempt["elapsed"] / Defs.LOOT_DURATION, 0.0, 1.0)
		var dot_count: int = clamp(int(progress * 5.0) + 1, 1, 5)
		var dot_str: String = ""
		for _d in range(dot_count):
			dot_str += "."

		if attempt["blink_elapsed"] >= Defs.LOOT_BLINK_INTERVAL:
			attempt["blink_elapsed"] = 0.0
			prog_lbl.visible = not prog_lbl.visible

		if prog_lbl.visible:
			prog_lbl.text = dot_str

		if attempt["elapsed"] >= Defs.LOOT_DURATION:
			completed_keys.append(slot_key)

	for sk in completed_keys:
		_complete_loot_attempt(sk)

	var all_done := completed_keys + cancelled_keys
	for sk in all_done:
		for attempt in active_loot_attempts:
			if attempt["slot_key"] == sk:
				_remove_loot_indicator(attempt["target"], sk)
				break
				
	active_loot_attempts = active_loot_attempts.filter(
		func(a): return not (a["slot_key"] in all_done)
	)

	if loot_target != null:
		refresh_loot_panel()

func _create_loot_indicator(target: Node, slot_key: String) -> Label:
	var lbl := Label.new()
	lbl.name = "LootProg_" + slot_key
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.position = Vector2(-20, -64) # Above head
	target.add_child(lbl)
	return lbl

func _remove_loot_indicator(target: Node, slot_key: String) -> void:
	var lbl = target.get_node_or_null("LootProg_" + slot_key)
	if lbl != null:
		lbl.queue_free()

func _complete_loot_attempt(slot_key: String) -> void:
	var target: Node = null
	for attempt in active_loot_attempts:
		if attempt["slot_key"] == slot_key:
			target = attempt["target"]
			break
	if target == null or not is_instance_valid(target):
		return

	var target_path: NodePath = target.get_path()
	var my_peer_id:     int = player.multiplayer.get_unique_id()

	var slot_type:  String = ""
	var slot_index         = null

	if slot_key.begins_with("hand_"):
		slot_type  = "hand"
		slot_index = slot_key.trim_prefix("hand_").to_int()
	else:
		slot_type  = "equip"
		slot_index = slot_key.trim_prefix("equip_")

	if player.multiplayer.is_server():
		World.rpc_request_loot_item(target_path, my_peer_id, slot_type, slot_index)
	else:
		World.rpc_request_loot_item.rpc_id(1, target_path, my_peer_id, slot_type, slot_index)

func show_loot_warning(looter_peer_id: int, item_desc: String) -> void:
	if player.sleep_state == 2: # SleepState.ASLEEP
		Sidebar.add_message("[color=#aaaaaa]you hear something...[/color]")
	else:
		var looter = World._find_player_by_peer(looter_peer_id)
		var looter_name = looter.character_name if looter != null and "character_name" in looter else "Player " + str(looter_peer_id)
		var msg: String = "[color=#ff2222][b]WARNING:[/b] " + looter_name + " is attempting to remove your " + item_desc + "![/color]"
		Sidebar.add_message(msg)