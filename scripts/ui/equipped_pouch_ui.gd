extends CanvasLayer

var player: Node = null
var pocket_slot: String = ""
var _slot_buttons: Array[Button] = []

func setup(p_player: Node, p_pocket_slot: String) -> void:
	player = p_player
	pocket_slot = p_pocket_slot
	layer = 20
	_build_ui()
	refresh()

func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player) or player.equipped.get(pocket_slot) != "Pouch":
		close()

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -120
	panel.offset_right = 120
	panel.offset_top = -105
	panel.offset_bottom = 105
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)

	var title_label := Label.new()
	title_label.text = "Pouch"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 13)
	title_row.add_child(title_label)

	var close_button := Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(24, 20)
	close_button.pressed.connect(close)
	title_row.add_child(close_button)

	vbox.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(grid)

	for slot_index in Defs.POUCH_SLOT_COUNT:
		var button := Button.new()
		button.custom_minimum_size = Vector2(100, 64)
		button.add_theme_font_size_override("font_size", 10)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.expand_icon = true
		button.pressed.connect(_on_slot_pressed.bind(slot_index))
		grid.add_child(button)
		_slot_buttons.append(button)

func refresh() -> void:
	if player == null or not is_instance_valid(player):
		return
	var pouch_data = player.equipped_data.get(pocket_slot, {})
	var contents: Array = pouch_data.get("contents", []) if pouch_data is Dictionary else []

	for slot_index in range(_slot_buttons.size()):
		var button := _slot_buttons[slot_index]
		var entry = contents[slot_index] if slot_index < contents.size() else null
		if entry == null:
			button.text = "[empty]"
			button.icon = null
			button.disabled = true
			continue

		var item_type := str(entry.get("item_type", "?"))
		var state: Dictionary = entry.get("state", {})
		var amount := int(state.get("amount", 1))
		var icon: Texture2D = null
		if item_type.ends_with("Coin"):
			var icon_path := Defs.get_coin_icon_path(amount, int(state.get("metal_type", 0)))
			if icon_path != "":
				icon = load(icon_path) as Texture2D
		else:
			icon = ItemRegistry.get_item_icon(item_type)

		button.icon = icon
		button.text = str(amount) if icon != null and amount > 1 else (item_type if amount <= 1 else "%dx %s" % [amount, item_type])
		button.disabled = false

func _on_slot_pressed(slot_index: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	var hand_index := int(player.active_hand)
	if not Defs.is_valid_hand_index(hand_index) or player.hands[hand_index] != null:
		return
	if player.body != null and player.body.is_arm_broken(hand_index):
		Sidebar.add_message("[color=#ffaaaa]That arm is useless![/color]")
		return
	World.rpc_request_equipped_pouch_extract.rpc_id(1, pocket_slot, slot_index, hand_index)

func close() -> void:
	if not is_queued_for_deletion():
		queue_free()
