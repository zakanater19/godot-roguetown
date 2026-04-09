@tool
extends PickableWorldObject

const OFF_TEXTURE: Texture2D = preload("res://objects/lampoff.png")
const ON_TEXTURE: Texture2D = preload("res://objects/lampon.png")

var item_type: String = "Lamp"

var weaponizable: bool = true
var force: int = 5
var too_large_for_satchel: bool = false
var slot: String = ""

var is_on: bool = false
var light_intensity: float = 1.0

func get_description() -> String:
	return "a portable lamp, currently " + ("ON" if is_on else "OFF")

func get_use_delay() -> float:
	return 0.3

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return

	var light := get_node_or_null("PointLight2D")
	if light:
		light.queue_free()

	_set_sprite(is_on)

func _exit_tree() -> void:
	super._exit_tree()
	if Engine.is_editor_hint():
		return
	if Lighting == null or not Lighting.has_method("unregister_lamp"):
		return
	Lighting.unregister_lamp(self)

func _set_fov_visibility(p_visible: bool) -> void:
	var sprite = get_node_or_null("Sprite2D")
	if sprite != null and sprite.visible != p_visible:
		sprite.visible = p_visible
		
	if input_pickable != p_visible:
		input_pickable = p_visible

func _set_sprite(on: bool) -> void:
	is_on = on
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		sprite.texture = ON_TEXTURE if is_on else OFF_TEXTURE

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
