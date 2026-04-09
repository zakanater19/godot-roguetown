# Full file: project/objects/coin.gd
@tool
extends PickableWorldObject

enum MetalType { COPPER, SILVER, GOLD }

@export var metal_type: MetalType = MetalType.COPPER :
	set(value):
		metal_type = value
		_set_item_type()
		_update_sprite()

@export var amount: int = 1 : set = set_amount

var item_type: String = ""
var is_coin_stack: bool = true

func set_amount(val: int) -> void:
	if val > 0:
		amount = clamp(val, 1, 99) 
	else:
		amount = val  
	if not Engine.is_editor_hint() and is_inside_tree():
		_update_sprite()

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return

	_set_item_type()
	_update_sprite()

func _set_item_type() -> void:
	match metal_type:
		MetalType.COPPER: item_type = "CopperCoin"
		MetalType.SILVER: item_type = "SilverCoin"
		MetalType.GOLD: item_type = "GoldCoin"

func get_description() -> String:
	var metal_name = ["copper", "silver", "gold"][metal_type]
	return str(amount) + "x " + metal_name + " coin"

func get_use_delay() -> float:
	return 0.2

func _update_sprite() -> void:
	if amount <= 0:
		return
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return

	if amount > 2:
		sprite.scale = Vector2(1.0, 1.0)
	else:
		sprite.scale = Vector2(0.5, 0.5)

	var tex_path := Defs.get_coin_icon_path(amount, metal_type)
	if not tex_path.is_empty():
		sprite.texture = load(tex_path)
	sprite.region_enabled = false
