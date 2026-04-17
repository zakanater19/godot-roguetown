@tool
extends WorldObject

const TORCH_SCENE: PackedScene = preload("res://objects/torch.tscn")
const TORCH_SCENE_PATH: String = "res://objects/torch.tscn"
const TORCH_SCRIPT_PATH: String = "res://objects/torch.gd"
const FRAME_SIZE: int = 32
const ON_FRAME_COUNT: int = 3
const ON_FPS: float = 5.0

const EMPTY_TEXTURES: Dictionary = {
	1: preload("res://objects/torchwall_empty_dir1.png"),
	2: preload("res://objects/torchwall_empty_dir2.png"),
	3: preload("res://objects/torchwall_empty_dir3.png"),
	4: preload("res://objects/torchwall_empty_dir4.png"),
}

const OFF_TEXTURES: Dictionary = {
	1: preload("res://objects/torchwall_off_dir1.png"),
	2: preload("res://objects/torchwall_off_dir2.png"),
	3: preload("res://objects/torchwall_off_dir3.png"),
	4: preload("res://objects/torchwall_off_dir4.png"),
}

const ON_TEXTURES: Dictionary = {
	1: preload("res://objects/torchwall_on_dir1.png"),
	2: preload("res://objects/torchwall_on_dir2.png"),
	3: preload("res://objects/torchwall_on_dir3.png"),
	4: preload("res://objects/torchwall_on_dir4.png"),
}

const SPRITE_OFFSETS: Dictionary = {
	1: Vector2(0, -64),
	2: Vector2.ZERO,
	3: Vector2.ZERO,
	4: Vector2.ZERO,
}

const HITBOX_OFFSETS: Dictionary = {
	1: Vector2(-1, -64),
	2: Vector2(0, 11),
	3: Vector2(-18, -8),
	4: Vector2(16, -8),
}

const HITBOX_SIZES: Dictionary = {
	1: Vector2(20, 50),
	2: Vector2(18, 40),
	3: Vector2(30, 50),
	4: Vector2(30, 50),
}

@export_range(1, 4, 1) var direction_rotation: int = 1:
	set(value):
		direction_rotation = clampi(value, 1, 4)
		_anim_timer = 0.0
		_apply_visual_state()

@export var has_torch: bool = true:
	set(value):
		has_torch = value
		if not has_torch:
			is_on = false
		_apply_visual_state()

@export var is_on: bool = true:
	set(value):
		is_on = value if has_torch else false
		_anim_timer = 0.0
		_apply_visual_state()

@export var light_intensity: float = 1.0

var blocks_fov: bool = false
var _anim_timer: float = 0.0
var _is_editor_snapping: bool = false

func get_description() -> String:
	if not has_torch:
		return "an empty wall torch mount"
	return "a wall torch mount holding a " + ("lit torch" if is_on else "torch")

func get_z_offset() -> int:
	return 5

func should_snap_to_tile() -> bool:
	return true

func should_register_entity() -> bool:
	return true

func get_runtime_groups() -> Array[String]:
	return[Defs.GROUP_INSPECTABLE]

func _ready() -> void:
	set_notify_transform(true)
	super._ready()
	_apply_visual_state()
	if Engine.is_editor_hint():
		call_deferred("_snap_to_editor_tile")

func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		call_deferred("_snap_to_editor_tile")

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not has_torch or not is_on:
		return
	_anim_timer += delta
	_update_animation_frame()

func _exit_tree() -> void:
	super._exit_tree()
	if Engine.is_editor_hint():
		return
	Lighting.unregister_lamp(self)

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
	if player.body != null and player.body.is_arm_broken(player.active_hand):
		player._show_inspect_text("that arm is useless", "")
		return

	var held: Node = player.hands[player.active_hand]
	if _is_torch_item(held):
		if has_torch:
			player._show_inspect_text("there's already a torch in the wall mount", "")
			return
		get_viewport().set_input_as_handled()
		_request_action("insert", player.active_hand)
		return

	if held != null:
		player._show_inspect_text("only a torch fits in the wall mount", "")
		return

	get_viewport().set_input_as_handled()
	if has_torch:
		_request_action("extract", player.active_hand)
	else:
		player._show_inspect_text("the wall mount is empty", "")

func _request_action(action: String, hand_idx: int) -> void:
	var torchwall_id := World.get_entity_id(self)
	if multiplayer.is_server():
		World.rpc_request_torchwall_action(torchwall_id, action, hand_idx)
	else:
		World.rpc_request_torchwall_action.rpc_id(1, torchwall_id, action, hand_idx)

func _perform_action(action: String, player: Node, hand_idx: int, generated_ids: Array) -> void:
	match action:
		"insert":
			_insert_torch_from_hand(player, hand_idx)
		"extract":
			_extract_torch_to_hand(player, hand_idx, generated_ids)

func _set_sprite(on: bool) -> void:
	is_on = on if has_torch else false

func _apply_visual_state() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.scale = Vector2(2.0, 2.0)
		sprite.position = SPRITE_OFFSETS.get(direction_rotation, Vector2.ZERO)
		if not has_torch:
			sprite.texture = EMPTY_TEXTURES.get(direction_rotation, EMPTY_TEXTURES[1])
			sprite.region_enabled = false
			sprite.region_rect = Rect2(0, 0, FRAME_SIZE, FRAME_SIZE)
		elif is_on:
			sprite.texture = ON_TEXTURES.get(direction_rotation, ON_TEXTURES[1])
			sprite.region_enabled = true
			_update_animation_frame()
		else:
			sprite.texture = OFF_TEXTURES.get(direction_rotation, OFF_TEXTURES[1])
			sprite.region_enabled = false
			sprite.region_rect = Rect2(0, 0, FRAME_SIZE, FRAME_SIZE)
	_sync_interaction_area()

	if Engine.is_editor_hint():
		return

	if has_torch and is_on:
		Lighting.register_lamp(self)
	else:
		Lighting.unregister_lamp(self)

func _update_animation_frame() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return
	var frame := int(floor(_anim_timer * ON_FPS)) % ON_FRAME_COUNT
	sprite.region_rect = Rect2(frame * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)

func _sync_interaction_area() -> void:
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null:
		return
	collision.position = HITBOX_OFFSETS.get(direction_rotation, Vector2.ZERO)
	var rect := collision.shape as RectangleShape2D
	if rect != null:
		rect.size = HITBOX_SIZES.get(direction_rotation, Vector2(20, 50))

func _is_torch_item(item: Node) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if item.has_method("is_torch_item") and item.is_torch_item():
		return true
	if str(item.get("item_type")) == "Torch":
		return true
	if item.scene_file_path == TORCH_SCENE_PATH:
		return true
	var script := item.get_script() as Script
	return script != null and script.resource_path == TORCH_SCRIPT_PATH

func _insert_torch_from_hand(player: Node, hand_idx: int) -> void:
	if player == null or not Defs.is_valid_hand_index(hand_idx):
		return
	var held_item: Node = player.hands[hand_idx]
	if not _is_torch_item(held_item):
		return
	if has_torch:
		return

	var torch_lit: bool = held_item.get("is_on") == true
	player.hands[hand_idx] = null
	World.unregister_entity(held_item)
	held_item.queue_free()

	has_torch = true
	is_on = torch_lit

	if player._is_local_authority():
		player._update_hands_ui()
		player._show_inspect_text("You place the torch into the wall mount", "")

func _extract_torch_to_hand(player: Node, hand_idx: int, generated_ids: Array) -> void:
	if player == null or not Defs.is_valid_hand_index(hand_idx):
		return
	if player.hands[hand_idx] != null or not has_torch:
		return

	var torch := TORCH_SCENE.instantiate() as Node2D
	if torch == null:
		return

	torch.position = player.pixel_pos
	torch.set("z_level", player.z_level)

	# Set the ID and name BEFORE adding to the tree so _ready() uses the synced ID
	var entity_id: String = str(generated_ids[0]) if not generated_ids.is_empty() else World._make_entity_id("torch_extract")
	torch.name = Defs.make_runtime_name("Torch")
	torch.set_meta("entity_id", entity_id)

	player.get_parent().add_child(torch)
	World.register_entity(torch, entity_id)
	
	torch.call("_set_sprite", is_on)
	for child in torch.get_children():
		if child is CollisionShape2D:
			child.disabled = true

	player.hands[hand_idx] = torch
	has_torch = false
	is_on = false

	if player._is_local_authority():
		player._update_hands_ui()
		player._show_inspect_text("You take the torch from the wall mount", "")

func _snap_to_editor_tile() -> void:
	if not Engine.is_editor_hint() or _is_editor_snapping:
		return
	var snapped_position := Defs.tile_to_pixel(Defs.world_to_tile(global_position))
	if global_position.is_equal_approx(snapped_position):
		return
	_is_editor_snapping = true
	global_position = snapped_position
	_is_editor_snapping = false
