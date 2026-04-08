@tool
extends Area2D

const TILE_SIZE: int  = 64
const MAX_SLOTS: int  = 10
const DRAG_THRESHOLD: float = 10.0

var item_type: String = "Satchel"
var slot: String = "backpack"
var too_large_for_satchel: bool = true

var contents: Array =[]
var _ui_layer:  CanvasLayer = null
var _slot_btns: Array       =[]

var _drag_started:      bool    = false
var _drag_press_screen: Vector2 = Vector2.ZERO

@export var z_level: int = 3

func get_description() -> String:
	return "a leather satchel, useful for carrying things"

func get_use_delay() -> float:
	return 0.3

func _ready() -> void:
	# Standardized to floor base + 2 (below players at +10)
	z_index = (z_level - 1) * 200 + 2
	add_to_group("z_entity")
	if Engine.is_editor_hint():
		return
	World.register_entity(self)
	add_to_group("pickable")
	if contents.size() != MAX_SLOTS:
		contents.resize(MAX_SLOTS)
		for i in MAX_SLOTS:
			contents[i] = null

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var col := get_node_or_null("CollisionShape2D")
	if col != null and col.disabled:
		col.disabled = false

	if _ui_layer != null and is_instance_valid(_ui_layer):
		var player: Node = World.get_local_player()
		if player != null:
			if player.z_level != z_level:
				_close_ui()
				return
			var my_tile := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y  / TILE_SIZE))
			var diff: Vector2i = (my_tile - player.tile_pos).abs()
			if diff.x > 1 or diff.y > 1:
				_close_ui()

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	World.unregister_entity(self)
	_close_ui()

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not _drag_started:
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed):
		return

	_drag_started = false
	var player: Node = World.get_local_player()
	if player == null or player.z_level != z_level:
		return

	if player.hands[0] == self or player.hands[1] == self: return
	if player.hands[player.active_hand] != null: return

	var drag_dist: float = event.position.distance_to(_drag_press_screen)
	if drag_dist <= DRAG_THRESHOLD: return

	var my_tile := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
	var diff: Vector2i = (my_tile - player.tile_pos).abs()
	if diff.x > 1 or diff.y > 1: return

	var mw := get_global_mouse_position()
	if mw.distance_to(player.pixel_pos) >= float(TILE_SIZE) * 0.6: return

	get_viewport().set_input_as_handled()
	if _ui_layer != null and is_instance_valid(_ui_layer): _close_ui()
	else: _open_ui()

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if Engine.is_editor_hint(): return
		
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.is_key_pressed(KEY_SHIFT): return
		get_viewport().set_input_as_handled()

		if event.pressed:
			_drag_started      = true
			_drag_press_screen = event.position
			return

		if not event.pressed:
			_drag_started = false
			var player: Node = World.get_local_player()
			if player == null or player.z_level != z_level: return

			var my_tile := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
			var diff: Vector2i = (my_tile - player.tile_pos).abs()
			if diff.x > 1 or diff.y > 1: return

			var active_held: Node  = player.hands[player.active_hand]
			var other_hand:  int   = 1 - player.active_hand
			var in_other_hand: bool = (player.hands[other_hand] == self)
			var in_active_hand: bool = (active_held == self)

			if active_held != null and not in_active_hand:
				if active_held.get("too_large_for_satchel") == true:
					var item_label: String = active_held.get("item_type") if active_held.get("item_type") != null else active_held.name
					Sidebar.add_message("[color=#ffaaaa]" + item_label + " is too large to fit in the satchel.[/color]")
					return

				var satchel_id := World.get_entity_id(self)
				if multiplayer.is_server(): World.rpc_request_satchel_insert(satchel_id, player.active_hand)
				else: World.rpc_request_satchel_insert.rpc_id(1, satchel_id, player.active_hand)

			elif in_other_hand or in_active_hand:
				if _ui_layer != null and is_instance_valid(_ui_layer): _close_ui()
				else: _open_ui()

			else:
				if player.has_method("_on_object_picked_up"):
					player._on_object_picked_up(self)

func _open_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 20
	get_tree().root.add_child(_ui_layer)

	var panel := PanelContainer.new()
	panel.anchor_left   = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -120
	panel.offset_right  = 120
	panel.offset_top    = -190
	panel.offset_bottom = 190
	_ui_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)

	var title_lbl := Label.new()
	title_lbl.text                  = "Satchel"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_row.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text                = "X"
	close_btn.custom_minimum_size = Vector2(24, 20)
	close_btn.pressed.connect(_close_ui)
	title_row.add_child(close_btn)

	vbox.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(grid)

	_slot_btns.clear()
	for i in MAX_SLOTS:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(100, 40)
		btn.add_theme_font_size_override("font_size", 10)
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.expand_icon = true
		
		var si: int = i
		btn.pressed.connect(func(): _on_slot_pressed(si))
		grid.add_child(btn)
		_slot_btns.append(btn)

	_refresh_ui()

func _refresh_ui() -> void:
	var item_registry = ItemRegistry
	for i in _slot_btns.size():
		var btn: Button     = _slot_btns[i]
		var slot_entry      = contents[i] if i < contents.size() else null
		if slot_entry != null:
			var itype = slot_entry.get("item_type", "?")
			var amt = slot_entry.get("state", {}).get("amount", 1)
			
			var icon_tex = null
			
			# Check if item is a coin to load the correct stack sprite
			if itype.ends_with("Coin") and slot_entry.has("state"):
				var state = slot_entry.get("state", {})
				var metal_type = state.get("metal_type", 0)
				var amount = state.get("amount", 1)
				
				var suffix = ["copper", "silver", "gold"][metal_type]
				var thresholds = [20, 15, 10, 5, 4, 3, 2, 1]
				for ta in thresholds:
					if amount >= ta:
						var path = "res://objects/coins/" + str(ta) + suffix + ".png"
						if ResourceLoader.exists(path):
							icon_tex = load(path)
							break
			elif item_registry != null and item_registry.has_method("get_item_icon"):
				icon_tex = item_registry.get_item_icon(itype)
				
			if icon_tex != null:
				btn.text = str(amt) if amt > 1 else ""
				btn.icon = icon_tex
			else:
				btn.text = (str(amt) + "x " + itype) if amt > 1 else itype
				btn.icon = null
				
			btn.disabled = false
		else:
			btn.text     = "[empty]"
			btn.icon     = null
			btn.disabled = true

func _close_ui() -> void:
	_slot_btns.clear()
	if _ui_layer != null and is_instance_valid(_ui_layer):
		_ui_layer.queue_free()
	_ui_layer = null

func _on_slot_pressed(slot_index: int) -> void:
	var player: Node = World.get_local_player()
	if player == null: return

	var my_tile := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
	var diff: Vector2i = (my_tile - player.tile_pos).abs()
	if diff.x > 1 or diff.y > 1 or player.z_level != z_level:
		_close_ui()
		return

	if player.hands[player.active_hand] != null: return

	if player.body != null and player.body.is_arm_broken(player.active_hand):
		Sidebar.add_message("[color=#ffaaaa]That arm is useless![/color]")
		return

	var satchel_id := World.get_entity_id(self)
	if multiplayer.is_server(): World.rpc_request_satchel_extract(satchel_id, slot_index, player.active_hand)
	else: World.rpc_request_satchel_extract.rpc_id(1, satchel_id, slot_index, player.active_hand)
