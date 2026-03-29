@tool
extends Area2D

const TILE_SIZE: int = 64
var item_type: String = "Lamp"

var weaponizable: bool = true
var force: int = 5
var too_large_for_satchel: bool = false
var slot: String = ""

var is_on: bool = false
@export var z_level: int = 3

func get_description() -> String:
	return "a portable lamp, currently " + ("ON" if is_on else "OFF")

func get_use_delay() -> float:
	return 0.3

func _ready() -> void:
	# Standardized to floor base + 2 (below players at +10)
	z_index = (z_level - 1) * 200 + 2
	add_to_group("z_entity")
	if Engine.is_editor_hint():
		return
	add_to_group("pickable")
	
	# Eliminate the old PointLight2D entirely, the shader handles everything
	var light = get_node_or_null("PointLight2D")
	if light:
		light.queue_free()
		
	_set_sprite(is_on)

func _exit_tree() -> void:
	Lighting.unregister_lamp(self)

func _set_fov_visibility(p_visible: bool) -> void:
	var sprite = get_node_or_null("Sprite2D")
	if sprite != null and sprite.visible != p_visible:
		sprite.visible = p_visible
		
	if input_pickable != p_visible:
		input_pickable = p_visible

func _set_sprite(on: bool) -> void:
	is_on = on
	var sprite = get_node_or_null("Sprite2D")
	if sprite:
		sprite.texture = load("res://objects/lampon.png") if is_on else load("res://objects/lampoff.png")
		
	if is_on:
		Lighting.register_lamp(self)
	else:
		Lighting.unregister_lamp(self)

func interact_in_hand(player: Node) -> void:
	_set_sprite(not is_on)
	if player != null and player._is_local_authority():
		player._update_hands_ui()
		var state_str = "ON" if is_on else "OFF"
		player._show_inspect_text("You turn the lamp " + state_str, "")

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.is_key_pressed(KEY_SHIFT):
			return
		var player: Node = World.get_local_player()
		if player == null or player.z_level != z_level:
			return
		var my_tile := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
		var diff: Vector2i = (my_tile - player.tile_pos).abs()
		if diff.x <= 1 and diff.y <= 1:
			get_viewport().set_input_as_handled()
			if player.has_method("_on_object_picked_up"):
				player._on_object_picked_up(self)
