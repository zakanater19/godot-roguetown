@tool
extends Marker2D

var spawn_type: String = "peasant"
@export var z_level: int = 3

func _get_property_list() -> Array[Dictionary]:
	var options := Classes.get_spawn_options()
	
	return[{
		"name": "spawn_type",
		"type": TYPE_STRING,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": ",".join(options)
	}]

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group("spawners")
