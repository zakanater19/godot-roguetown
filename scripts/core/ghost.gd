extends Node2D

const MOVE_TIME: float = PlayerDefs.MOVE_TIME
const GHOST_MOVE_TIME: float = MOVE_TIME * 0.5
const GHOST_Z_OFFSET: int = Defs.Z_OFFSET_PLAYERS + 1

enum SleepState { AWAKE, FALLING_ASLEEP, ASLEEP, WAKING_UP }

var is_ghost: bool = true
var is_possessed: bool = true

@export var character_name: String = "ghost"
@export var character_class: String = "peasant"
@export var z_level: int = 3
var view_z_level: int = 3

var tile_pos: Vector2i = Vector2i.ZERO:
	set(val):
		var diff: Vector2i = (val - tile_pos).abs()
		tile_pos = val
		if diff.x > 1 or diff.y > 1:
			pixel_pos = World.tile_to_pixel(val)
			position = pixel_pos

var pixel_pos: Vector2 = Vector2.ZERO
var moving: bool = false
var move_elapsed: float = 0.0
var move_from: Vector2 = Vector2.ZERO
var move_to: Vector2 = Vector2.ZERO
var current_move_duration: float = GHOST_MOVE_TIME
var _awaiting_move_confirm: bool = false
var buffered_dir: Vector2i = Vector2i.ZERO
var facing: int = 0
var is_sprinting: bool = false
var camera: Camera2D = null

var dead: bool = false
var sleep_state: SleepState = SleepState.AWAKE
var is_lying_down: bool = false
var is_sneaking: bool = false
var sneak_alpha: float = 1.0
var health: int = 1
var stamina: float = 0.0
var exhausted: bool = false
var body = null
var hands: Array[Node] = [null, null]
var active_hand: int = 0
var throwing_mode: bool = false
var action_cooldown: float = 0.0
var intent: String = "observe"
var combat_mode: bool = false
var grabbed_target: Node = null
var grabbed_by: Node = null
var grab_hand_idx: int = -1
var prices_shown: bool = false
var stats: Dictionary = {"strength": 10, "agility": 10}
var skills: Dictionary = {}
var equipped: Dictionary = {
	"head": null, "face": null, "cloak": null, "armor": null,
	"backpack": null, "waist": null, "clothing": null, "trousers": null,
	"feet": null, "gloves": null, "pocket_l": null, "pocket_r": null
}
var equipped_data: Dictionary = {
	"head": null, "face": null, "cloak": null, "armor": null,
	"backpack": null, "waist": null, "clothing": null, "trousers": null,
	"feet": null, "gloves": null, "pocket_l": null, "pocket_r": null
}

var inspect = null

var _canvas_layer: CanvasLayer = null
var _ui_root: Control = null
var _chat_input: LineEdit = null
var _inspect_label: Label = null
var _z_label: Label = null
var _up_button: Button = null
var _down_button: Button = null
var _active_chat_messages: Array[Node2D] = []

func _enter_tree() -> void:
	if name.begins_with("Ghost_"):
		var parts = name.split("_")
		if parts.size() > 1:
			set_multiplayer_authority(parts[1].to_int())

func _ready() -> void:
	view_z_level = z_level
	z_index = Defs.get_z_index(z_level, GHOST_Z_OFFSET)
	current_move_duration = GHOST_MOVE_TIME
	add_to_group("player")
	add_to_group("z_entity")
	World.register_entity(self, "player:%s" % name)
	visible = _is_local_authority()

	if tile_pos == Vector2i.ZERO and position != Vector2.ZERO:
		tile_pos = Defs.world_to_tile(position)

	pixel_pos = World.tile_to_pixel(tile_pos)
	position = pixel_pos
	inspect = preload("res://scripts/player/playerinspect.gd").new(self)

	if _is_local_authority():
		camera = get_parent().get_node_or_null("Camera2D")
		_build_ui()
		_refresh_local_view()

func _exit_tree() -> void:
	World.unregister_entity(self)

func _is_local_authority() -> bool:
	if not is_possessed:
		return false
	if not is_inside_tree():
		return false
	if not multiplayer.has_multiplayer_peer():
		return false
	if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return false
	return multiplayer.get_unique_id() == get_multiplayer_authority()

func _build_ui() -> void:
	if _canvas_layer != null:
		return

	var cl: CanvasLayer = CanvasLayer.new()
	cl.layer = 10
	_canvas_layer = cl
	add_child(cl)

	var safe_area: Control = Control.new()
	safe_area.name = "GhostUI"
	safe_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe_area.mouse_filter = Control.MOUSE_FILTER_PASS
	cl.add_child(safe_area)
	_ui_root = safe_area

	var controls: VBoxContainer = VBoxContainer.new()
	controls.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	controls.offset_left = 12
	controls.offset_top = -92
	controls.offset_right = 132
	controls.offset_bottom = 92
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	safe_area.add_child(controls)

	var ghost_icon: TextureRect = TextureRect.new()
	ghost_icon.texture = load("res://npcs/ghost.png")
	ghost_icon.custom_minimum_size = Vector2(32, 32)
	ghost_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	ghost_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost_icon.modulate = Color(0.85, 0.95, 1.0, 0.95)
	controls.add_child(ghost_icon)

	_z_label = Label.new()
	_z_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_z_label.add_theme_color_override("font_color", Color(0.78, 0.9, 1.0))
	_z_label.add_theme_font_size_override("font_size", 12)
	controls.add_child(_z_label)

	_up_button = Button.new()
	_up_button.text = "Up"
	_up_button.add_theme_font_size_override("font_size", 12)
	_up_button.custom_minimum_size = Vector2(80, 22)
	_up_button.pressed.connect(_on_up_pressed)
	controls.add_child(_up_button)

	_down_button = Button.new()
	_down_button.text = "Down"
	_down_button.add_theme_font_size_override("font_size", 12)
	_down_button.custom_minimum_size = Vector2(80, 22)
	_down_button.pressed.connect(_on_down_pressed)
	controls.add_child(_down_button)

	var respawn_button: Button = Button.new()
	respawn_button.text = "Respawn"
	respawn_button.add_theme_font_size_override("font_size", 12)
	respawn_button.custom_minimum_size = Vector2(80, 22)
	respawn_button.pressed.connect(_on_respawn_pressed)
	controls.add_child(respawn_button)

	_inspect_label = Label.new()
	_inspect_label.text = "INSPECTING"
	_inspect_label.add_theme_color_override("font_color", Color(0.78, 0.9, 1.0))
	_inspect_label.add_theme_font_size_override("font_size", 14)
	_inspect_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_inspect_label.offset_left = 12
	_inspect_label.offset_top = 10
	_inspect_label.offset_right = 140
	_inspect_label.offset_bottom = 30
	_inspect_label.visible = false
	safe_area.add_child(_inspect_label)

	_chat_input = LineEdit.new()
	_chat_input.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_input.offset_left = 12
	_chat_input.offset_top = -40
	_chat_input.offset_right = 312
	_chat_input.offset_bottom = -10
	_chat_input.placeholder_text = "Deadchat..."
	_chat_input.visible = false
	_chat_input.text_submitted.connect(_on_chat_submitted)
	safe_area.add_child(_chat_input)

	_update_z_controls()

func _update_z_controls() -> void:
	if _z_label != null:
		_z_label.text = "Z %d" % z_level
	if _up_button != null:
		_up_button.disabled = z_level >= 5
	if _down_button != null:
		_down_button.disabled = z_level <= 1

func _refresh_local_view() -> void:
	if not _is_local_authority():
		return
	if camera != null:
		camera.position = pixel_pos
		camera.offset = PlayerDefs.get_camera_offset(get_viewport_rect().size)
	Lighting.refresh_local_lighting()
	if FOV != null and FOV.has_method("refresh_local_fov"):
		FOV.refresh_local_fov()

func _on_up_pressed() -> void:
	_request_z_change(z_level + 1)

func _on_down_pressed() -> void:
	_request_z_change(z_level - 1)

func _request_z_change(new_z: int) -> void:
	var target_z: int = clampi(new_z, 1, 5)
	if target_z == z_level:
		return
	if multiplayer.is_server():
		World.rpc_request_ghost_z_change(target_z)
	else:
		World.rpc_request_ghost_z_change.rpc_id(1, target_z)

func _on_respawn_pressed() -> void:
	if multiplayer.is_server():
		World.rpc_request_respawn.rpc(multiplayer.get_unique_id())
	else:
		World.rpc_request_respawn.rpc_id(1, multiplayer.get_unique_id())

func _on_chat_submitted(text: String) -> void:
	if _chat_input == null:
		return
	_chat_input.visible = false
	_chat_input.clear()
	_chat_input.release_focus()
	if text.strip_edges() == "":
		return
	if multiplayer.is_server():
		World.rpc_send_chat(text)
	else:
		World.rpc_send_chat.rpc_id(1, text)

func _unhandled_input(event: InputEvent) -> void:
	if not _is_local_authority():
		return

	if _chat_input != null and _chat_input.has_focus():
		if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed and not event.echo:
			_chat_input.visible = false
			_chat_input.clear()
			_chat_input.release_focus()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.keycode == KEY_T and event.pressed and not event.echo:
		if _chat_input != null and not _chat_input.visible:
			_chat_input.visible = true
			_chat_input.grab_focus()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and Input.is_key_pressed(KEY_SHIFT):
		var mouse_world: Vector2 = get_global_mouse_position()
		var target_tile: Vector2i = Defs.world_to_tile(mouse_world)
		if not FOV._visible_tiles.has(target_tile):
			return
		inspect_at(mouse_world)
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	var is_local: bool = _is_local_authority()

	if moving:
		move_elapsed += delta
		var t: float = clamp(move_elapsed / current_move_duration, 0.0, 1.0)
		pixel_pos = move_from.lerp(move_to, t)
		position = pixel_pos
		if t >= 1.0:
			moving = false
			pixel_pos = move_to
			position = pixel_pos

	if is_local:
		if _chat_input == null or not _chat_input.has_focus():
			buffered_dir = Vector2i.ZERO
			if Input.is_key_pressed(KEY_W):
				buffered_dir.y -= 1
			elif Input.is_key_pressed(KEY_S):
				buffered_dir.y += 1
			elif Input.is_key_pressed(KEY_A):
				buffered_dir.x -= 1
			elif Input.is_key_pressed(KEY_D):
				buffered_dir.x += 1
			if not moving and buffered_dir != Vector2i.ZERO:
				_try_move(buffered_dir)
		else:
			buffered_dir = Vector2i.ZERO

		if camera != null:
			camera.position = pixel_pos
			camera.offset = PlayerDefs.get_camera_offset(get_viewport_rect().size)

		if _inspect_label != null:
			_inspect_label.visible = Input.is_key_pressed(KEY_SHIFT)

func _try_move(dir: Vector2i) -> void:
	if dir == Vector2i.ZERO or _awaiting_move_confirm:
		return
	_awaiting_move_confirm = true
	if multiplayer.is_server():
		World.rpc_try_move(dir, false)
	else:
		World.rpc_try_move.rpc_id(1, dir, false)

func _start_move_lerp() -> void:
	_awaiting_move_confirm = false
	var new_pixel: Vector2 = World.tile_to_pixel(tile_pos)
	if new_pixel == pixel_pos:
		return
	current_move_duration = GHOST_MOVE_TIME
	move_from = pixel_pos
	move_to = new_pixel
	move_elapsed = 0.0
	moving = true

@rpc("any_peer", "call_local", "reliable")
func rpc_sync_ghost_state(p_name: String, p_class: String, spawn_tile: Vector2i, new_z: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != 1:
		return
	character_name = p_name
	character_class = p_class
	z_level = new_z
	view_z_level = new_z
	tile_pos = spawn_tile
	pixel_pos = World.tile_to_pixel(tile_pos)
	position = pixel_pos
	z_index = Defs.get_z_index(z_level, GHOST_Z_OFFSET)
	visible = _is_local_authority()
	_update_z_controls()
	if _is_local_authority():
		_refresh_local_view()

@rpc("any_peer", "call_local", "reliable")
func rpc_sync_z_level(new_z: int) -> void:
	z_level = new_z
	view_z_level = new_z
	z_index = Defs.get_z_index(z_level, GHOST_Z_OFFSET)
	if _is_local_authority():
		_refresh_local_view()
	_update_z_controls()

@rpc("any_peer", "call_remote", "reliable")
func rpc_set_spawn_position(spawn_pos: Vector2) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	position = spawn_pos
	tile_pos = Defs.world_to_tile(position)
	pixel_pos = World.tile_to_pixel(tile_pos)
	if _is_local_authority() and camera != null:
		camera.position = pixel_pos
		camera.offset = PlayerDefs.get_camera_offset(get_viewport_rect().size)

func _on_authority_changed() -> void:
	if _is_local_authority():
		visible = true
		if camera == null:
			camera = get_parent().get_node_or_null("Camera2D")
		if _canvas_layer == null:
			_build_ui()
		_refresh_local_view()
		_update_z_controls()

func _on_reconnection_confirmed() -> void:
	_on_authority_changed()
	if _is_local_authority():
		Sidebar.add_message("[color=#9fd7ff]You have reconnected to your ghost.[/color]")

func inspect_at(world_pos: Vector2) -> void:
	var target_tile: Vector2i = Defs.world_to_tile(world_pos)
	if target_tile == tile_pos:
		show_inspect_text(get_description(), get_detailed_description())
		return
	if inspect != null:
		inspect.inspect_at(world_pos)

func show_inspect_text(text: String, detailed_desc: String) -> void:
	if inspect != null:
		inspect.show_inspect_text(text, detailed_desc)

func _show_inspect_text(text: String, detailed_desc: String) -> void:
	show_inspect_text(text, detailed_desc)

func get_description() -> String:
	return character_name + "'s ghost"

func get_detailed_description() -> String:
	return "[color=#bfe6ff][b]" + character_name + "'s ghost[/b][/color]\na cold, translucent spirit drifting free of the body."

func get_inspect_color() -> Color:
	return Color(0.75, 0.9, 1.0)

func get_inspect_font_size() -> int:
	return 12

func show_remote_chat(sender_name: String, message: String) -> void:
	Sidebar.add_message("[color=#9fd7ff][b]" + sender_name + "[/b] deadchat: " + message + "[/color]")
	show_chat_bubble(message)

func show_chat_bubble(text: String) -> void:
	_active_chat_messages = _active_chat_messages.filter(func(n): return is_instance_valid(n))
	const STEP: float = 22.0
	for msg in _active_chat_messages:
		msg.position.y -= STEP

	var container: Node2D = Node2D.new()
	container.position = Vector2(0, -40)
	container.z_index = Defs.get_z_index(z_level, GHOST_Z_OFFSET + 20)
	add_child(container)

	var label: Label = Label.new()
	label.text = "\"" + text + "\""
	label.add_theme_color_override("font_color", Color(0.8, 0.93, 1.0))
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 3)
	label.custom_minimum_size = Vector2(400, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	label.position = Vector2(-200, 0)
	container.add_child(label)

	_active_chat_messages.append(container)
	get_tree().create_timer(5.0).timeout.connect(func():
		if is_instance_valid(container):
			_active_chat_messages.erase(container)
			container.queue_free()
	)

func sync_hands(_hand_ids: Array) -> void:
	pass

func _set_fov_visibility(p_is_visible: bool) -> void:
	visible = p_is_visible
