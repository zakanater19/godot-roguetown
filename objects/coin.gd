# res://objects/coin.gd
@tool
extends Area2D

const TILE_SIZE: int = 64

enum MetalType { COPPER, SILVER, GOLD }

@export var metal_type: MetalType = MetalType.COPPER :
	set(value):
		metal_type = value
		_set_item_type()
		_update_sprite()

@export var amount: int = 1 : set = set_amount

# These are derived from metal_type and used for combining/descriptions
var item_type: String = ""
var is_coin_stack: bool = true

func set_amount(val: int) -> void:
	if val > 0:
		amount = clamp(val, 1, 99) # Increased limit to 99 for standard logic
	else:
		amount = val  # allow 0 for deletion
	if not Engine.is_editor_hint() and is_inside_tree():
		_update_sprite()

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	# Set item_type based on metal_type
	_set_item_type()

	add_to_group("pickable")
	_update_sprite()

func _set_item_type() -> void:
	match metal_type:
		MetalType.COPPER:
			item_type = "CopperCoin"
		MetalType.SILVER:
			item_type = "SilverCoin"
		MetalType.GOLD:
			item_type = "GoldCoin"

func get_description() -> String:
	var metal_name = ["copper", "silver", "gold"][metal_type]
	return str(amount) + "x " + metal_name + " coin"

func get_use_delay() -> float:
	return 0.2

func _update_sprite() -> void:
	if amount <= 0:
		return
	var sprite = get_node_or_null("Sprite2D")
	if sprite == null:
		return

	var suffix = ["copper", "silver", "gold"][metal_type]
	
	# Fallback logic: Find highest amount <= current amount that has an image
	var thresholds = [20, 15, 10, 5, 4, 3, 2, 1]
	var target_amount = 1
	for amt in thresholds:
		if amount >= amt:
			# Verify the file actually exists
			var path = "res://objects/coins/" + str(amt) + suffix + ".png"
			if ResourceLoader.exists(path):
				target_amount = amt
				break
	
	var tex_path = "res://objects/coins/" + str(target_amount) + suffix + ".png"

	if ResourceLoader.exists(tex_path):
		sprite.texture = load(tex_path)

	# Disable region as these are individual files, not a sheet
	sprite.region_enabled = false

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
				
