# res://objects/merchantvendor.gd
@tool
extends WorldObject

const VENDOR_POPUP_SIZE := Vector2i(480, 560)

var blocks_fov: bool = false
var is_merchant_vendor: bool = true
var stored_balance: int = 0

var _dialog: PopupPanel = null
var _balance_label: Label = null
var _withdraw_button: Button = null
var _catalog_list: VBoxContainer = null
var _item_buttons: Dictionary = {}
var _is_editor_snapping: bool = false

func _ready() -> void:
	set_notify_transform(true)
	super._ready()
	if Engine.is_editor_hint():
		call_deferred("_snap_to_editor_tile")

func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		call_deferred("_snap_to_editor_tile")

func _process(_delta: float) -> void:
	if _dialog == null or not is_instance_valid(_dialog) or not _dialog.visible:
		return
	if Engine.is_editor_hint():
		return

	var local_player: Node = World.get_local_player()
	if local_player == null:
		_close_ui()
		return
	if not Defs.is_within_tile_reach(local_player.tile_pos, get_anchor_tile()) or local_player.z_level != z_level:
		_close_ui()

func _exit_tree() -> void:
	_close_ui()
	super._exit_tree()

func get_description() -> String:
	return "a merchant vendor, ready to trade"

func get_z_offset() -> int:
	return 5

func should_snap_to_tile() -> bool:
	return true

func should_register_entity() -> bool:
	return true

func get_runtime_groups() -> Array[String]:
	return [Defs.GROUP_INSPECTABLE]

func get_solid_tile_offsets() -> Array[Vector2i]:
	return [Vector2i.ZERO]

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if Engine.is_editor_hint():
		return
	if event is not InputEventMouseButton:
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	if Input.is_key_pressed(KEY_SHIFT):
		return

	var player: Node = World.get_local_player()
	if player == null or player.z_level != z_level:
		return
	if not Defs.is_within_tile_reach(player.tile_pos, get_anchor_tile()):
		return

	var active_hand_valid := Defs.is_valid_hand_index(player.active_hand)
	var held: Node = player.hands[player.active_hand] if active_hand_valid else null
	if held != null:
		if player.body != null and player.body.is_arm_broken(player.active_hand):
			player._show_inspect_text("that arm is useless", "")
			return
		get_viewport().set_input_as_handled()
		var held_vendor_id := World.get_entity_id(self)
		if multiplayer.is_server():
			World.rpc_request_merchant_hand_interaction(held_vendor_id, player.active_hand)
		else:
			World.rpc_request_merchant_hand_interaction.rpc_id(1, held_vendor_id, player.active_hand)
		return

	if not active_hand_valid or player.hands[player.active_hand] != null:
		player._show_inspect_text("you need an open hand to use the merchant vendor", "")
		return
	if player.body != null and player.body.is_arm_broken(player.active_hand):
		player._show_inspect_text("that arm is useless", "")
		return

	get_viewport().set_input_as_handled()
	var vendor_id := World.get_entity_id(self)
	if multiplayer.is_server():
		World.rpc_request_merchant_open(vendor_id)
	else:
		World.rpc_request_merchant_open.rpc_id(1, vendor_id)

func _show_merchant_menu(balance: int) -> void:
	_ensure_ui()
	_update_merchant_balance(balance)
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.popup_centered(VENDOR_POPUP_SIZE)

func _update_merchant_balance(balance: int) -> void:
	stored_balance = balance
	if _balance_label != null:
		_balance_label.text = "Balance: %d" % stored_balance
	if _withdraw_button != null:
		_withdraw_button.disabled = stored_balance <= 0
	_refresh_item_buttons()

func _ensure_ui() -> void:
	if _dialog != null and is_instance_valid(_dialog):
		return

	_dialog = PopupPanel.new()

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_dialog.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)

	var title := Label.new()
	title.text = "Merchant Vendor"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	header.add_child(title)

	_balance_label = Label.new()
	_balance_label.text = "Balance: 0"
	header.add_child(_balance_label)

	_withdraw_button = Button.new()
	_withdraw_button.text = "Withdraw"
	_withdraw_button.pressed.connect(_request_withdraw)
	header.add_child(_withdraw_button)

	var close_button := Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(28, 0)
	close_button.pressed.connect(_close_ui)
	header.add_child(close_button)

	var section_label := Label.new()
	section_label.text = "Buyable"
	section_label.add_theme_font_size_override("font_size", 13)
	root.add_child(section_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 460)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_catalog_list = VBoxContainer.new()
	_catalog_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_catalog_list)

	_item_buttons.clear()
	for entry in Trade.get_buyable_catalog():
		_add_catalog_row(entry)

	var ui_parent: Node = get_tree().root
	var local_player := World.get_local_player()
	if local_player != null:
		var player_hud = local_player.get("_hud")
		if player_hud != null and is_instance_valid(player_hud):
			ui_parent = player_hud

	if ui_parent != null:
		ui_parent.add_child(_dialog)

func _add_catalog_row(entry: Dictionary) -> void:
	if _catalog_list == null:
		return

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_catalog_list.add_child(row)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = entry.get("icon", null)
	row.add_child(icon)

	var text_block := VBoxContainer.new()
	text_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_block)

	var item_label := Label.new()
	item_label.text = str(entry.get("item_type", ""))
	text_block.add_child(item_label)

	var desc_label := Label.new()
	desc_label.text = str(entry.get("description", ""))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 11)
	text_block.add_child(desc_label)

	var price_label := Label.new()
	price_label.text = "%d" % int(entry.get("price", 0))
	price_label.custom_minimum_size = Vector2(44, 0)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(price_label)

	var buy_button := Button.new()
	buy_button.text = "Buy"
	buy_button.pressed.connect(_request_purchase.bind(str(entry.get("item_type", ""))))
	row.add_child(buy_button)

	_item_buttons[str(entry.get("item_type", ""))] = {
		"button": buy_button,
		"price": int(entry.get("price", 0)),
	}

func _refresh_item_buttons() -> void:
	for item_type in _item_buttons.keys():
		var entry: Dictionary = _item_buttons[item_type]
		var buy_button := entry.get("button", null) as Button
		if buy_button != null and is_instance_valid(buy_button):
			buy_button.disabled = stored_balance < int(entry.get("price", 0))

func _request_purchase(item_type: String) -> void:
	if item_type.is_empty():
		return
	var vendor_id := World.get_entity_id(self)
	if multiplayer.is_server():
		World.rpc_request_merchant_purchase(vendor_id, item_type)
	else:
		World.rpc_request_merchant_purchase.rpc_id(1, vendor_id, item_type)

func _request_withdraw() -> void:
	var vendor_id := World.get_entity_id(self)
	if multiplayer.is_server():
		World.rpc_request_merchant_withdraw(vendor_id)
	else:
		World.rpc_request_merchant_withdraw.rpc_id(1, vendor_id)

func _close_ui() -> void:
	_item_buttons.clear()
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null
	_balance_label = null
	_withdraw_button = null
	_catalog_list = null

func _snap_to_editor_tile() -> void:
	if not Engine.is_editor_hint() or _is_editor_snapping:
		return
	var snapped_position := Defs.tile_to_pixel(Defs.world_to_tile(global_position))
	if global_position.is_equal_approx(snapped_position):
		return
	_is_editor_snapping = true
	global_position = snapped_position
	_is_editor_snapping = false
