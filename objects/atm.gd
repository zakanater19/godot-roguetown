@tool
extends WorldObject

const ATM_TEXTURE: Texture2D = preload("res://objects/atm.png")
const ATM_SPRITE_OFFSET: Vector2 = Vector2(0, -40)
const ATM_SPRITE_SCALE: Vector2 = Vector2(2, 2)
const ATM_HITBOX_SIZE: Vector2 = Vector2(44, 18)
const ATM_POPUP_PADDING: Vector2i = Vector2i(20, 20)

var blocks_fov: bool = false
var is_atm_machine: bool = true

var _dialog: PopupPanel = null
var _dialog_content: Control = null
var _balance_label: Label = null
var _material_option: OptionButton = null
var _amount_spinbox: SpinBox = null
var _is_editor_snapping: bool = false

func _ready() -> void:
	set_notify_transform(true)
	super._ready()
	_sync_presentation()
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
	return "a wall-mounted ATM"

func get_z_offset() -> int:
	return 5

func should_snap_to_tile() -> bool:
	return true

func should_register_entity() -> bool:
	return true

func get_runtime_groups() -> Array[String]:
	return [Defs.GROUP_INSPECTABLE]

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
	var held: Node = player.hands[player.active_hand] if Defs.is_valid_hand_index(player.active_hand) else null
	if held != null:
		if player.body != null and player.body.is_arm_broken(player.active_hand):
			player._show_inspect_text("that arm is useless", "")
			return
		if held.get("is_coin_stack") != true:
			player._show_inspect_text("that can't be deposited in the ATM", "")
			return
		get_viewport().set_input_as_handled()
		var deposit_atm_id := World.get_entity_id(self)
		if multiplayer.is_server():
			World.rpc_request_atm_hand_deposit(deposit_atm_id, player.active_hand)
		else:
			World.rpc_request_atm_hand_deposit.rpc_id(1, deposit_atm_id, player.active_hand)
		return
	if not Defs.is_valid_hand_index(player.active_hand) or player.hands[player.active_hand] != null:
		player._show_inspect_text("you need an open hand to use the ATM", "")
		return
	if player.body != null and player.body.is_arm_broken(player.active_hand):
		player._show_inspect_text("that arm is useless", "")
		return

	get_viewport().set_input_as_handled()
	var atm_id := World.get_entity_id(self)
	if multiplayer.is_server():
		World.rpc_request_atm_open(atm_id)
	else:
		World.rpc_request_atm_open.rpc_id(1, atm_id)

func _show_atm_menu(balance: int) -> void:
	_ensure_ui()
	_update_atm_balance(balance)
	if _dialog != null and is_instance_valid(_dialog) and _dialog_content != null:
		var desired_size := _get_dialog_size()
		_dialog.popup_centered(desired_size)

func _update_atm_balance(balance: int) -> void:
	if _balance_label != null:
		_balance_label.text = "Balance: %d" % balance

func _ensure_ui() -> void:
	if _dialog != null and is_instance_valid(_dialog):
		return

	_dialog = PopupPanel.new()

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_dialog.add_child(margin)
	_dialog_content = margin

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)

	var title_label := Label.new()
	title_label.text = "ATM"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_label)

	var close_button := Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(28, 0)
	close_button.pressed.connect(_close_ui)
	title_row.add_child(close_button)

	_balance_label = Label.new()
	_balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_balance_label.text = "Balance: 0"
	vbox.add_child(_balance_label)

	var form := GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", 8)
	form.add_theme_constant_override("v_separation", 6)
	vbox.add_child(form)

	var material_label := Label.new()
	material_label.text = "Material"
	form.add_child(material_label)

	_material_option = OptionButton.new()
	_material_option.custom_minimum_size = Vector2(160, 0)
	_material_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_material_option.add_item("Copper (1)", 0)
	_material_option.add_item("Silver (5)", 1)
	_material_option.add_item("Gold (10)", 2)
	form.add_child(_material_option)

	var amount_label := Label.new()
	amount_label.text = "Amount"
	form.add_child(amount_label)

	_amount_spinbox = SpinBox.new()
	_amount_spinbox.min_value = 1
	_amount_spinbox.max_value = 99999
	_amount_spinbox.step = 1
	_amount_spinbox.rounded = true
	_amount_spinbox.value = 1
	_amount_spinbox.custom_minimum_size = Vector2(96, 0)
	form.add_child(_amount_spinbox)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	vbox.add_child(button_row)

	var withdraw_button := Button.new()
	withdraw_button.text = "Withdraw"
	withdraw_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	withdraw_button.pressed.connect(_request_withdraw)
	button_row.add_child(withdraw_button)

	var ui_parent: Node = get_tree().root
	var local_player := World.get_local_player()
	if local_player != null:
		var player_hud = local_player.get("_hud")
		if player_hud != null and is_instance_valid(player_hud):
			ui_parent = player_hud

	if ui_parent != null:
		ui_parent.add_child(_dialog)

func _close_ui() -> void:
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null
	_dialog_content = null
	_balance_label = null
	_material_option = null
	_amount_spinbox = null

func _request_withdraw() -> void:
	if _material_option == null or _amount_spinbox == null:
		return

	var atm_id := World.get_entity_id(self)
	var amount := int(_amount_spinbox.value)
	var metal_type := _material_option.get_selected_id()
	var preferred_hand := 0
	var local_player := World.get_local_player()
	if local_player != null and Defs.is_valid_hand_index(local_player.active_hand):
		preferred_hand = local_player.active_hand

	if multiplayer.is_server():
		World.rpc_request_atm_withdraw(atm_id, metal_type, amount, preferred_hand)
	else:
		World.rpc_request_atm_withdraw.rpc_id(1, atm_id, metal_type, amount, preferred_hand)

func _sync_presentation() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.texture = ATM_TEXTURE
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = ATM_SPRITE_OFFSET
		sprite.scale = ATM_SPRITE_SCALE

	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision != null:
		collision.position = ATM_SPRITE_OFFSET
		var rect := collision.shape as RectangleShape2D
		if rect != null:
			rect.size = ATM_HITBOX_SIZE

func _snap_to_editor_tile() -> void:
	if not Engine.is_editor_hint() or _is_editor_snapping:
		return
	var snapped_position := Defs.tile_to_pixel(Defs.world_to_tile(global_position))
	if global_position.is_equal_approx(snapped_position):
		return
	_is_editor_snapping = true
	global_position = snapped_position
	_is_editor_snapping = false

func _get_dialog_size() -> Vector2i:
	if _dialog_content == null:
		return Vector2i(0, 0)
	var desired_size := Vector2i(_dialog_content.get_combined_minimum_size().ceil())
	return desired_size + ATM_POPUP_PADDING
