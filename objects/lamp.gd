@tool
extends Area2D

const TILE_SIZE: int = 64
var item_type: String = "Lamp"

var weaponizable: bool = true
var force: int = 5
var too_large_for_satchel: bool = false
var slot: String = ""

var is_on: bool = false

func get_description() -> String:
	return "a portable lamp, currently " + ("ON" if is_on else "OFF")

func get_use_delay() -> float:
	return 0.3

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group("pickable")
	_set_sprite(is_on)

# --- Added _process to dynamically control light based on sun_weight ---
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var light = get_node_or_null("PointLight2D")
	if light:
		# Brighter at night (low sun_weight), off/dim during the day
		light.energy = 1.2 * (1.0 - Lighting.sun_weight)
		# Disable light if it's too bright outside (sun_weight > 0.8)
		light.enabled = (Lighting.sun_weight < 0.8) and is_on

func _set_sprite(on: bool) -> void:
	is_on = on
	var sprite = get_node_or_null("Sprite2D")
	# REMOVED: if light: light.enabled = is_on (Handled in _process now)
	if sprite:
		sprite.texture = load("res://objects/lampon.png") if is_on else load("res://objects/lampoff.png")

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
		if player == null:
			return
		var my_tile := Vector2i(int(global_position.x / TILE_SIZE), int(global_position.y / TILE_SIZE))
		var diff: Vector2i = (my_tile - player.tile_pos).abs()
		if diff.x <= 1 and diff.y <= 1:
			get_viewport().set_input_as_handled()
			if player.has_method("_on_object_picked_up"):
				player._on_object_picked_up(self)
				
