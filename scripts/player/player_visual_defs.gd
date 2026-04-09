class_name PlayerVisualDefs
extends RefCounted

const CLOTHING_SPRITE_SPECS: Array[Dictionary] = [
	{"node_name": "TrousersSprite", "slot": "trousers", "default_layer": 1},
	{"node_name": "ClothingSprite", "slot": "clothing", "default_layer": 2},
	{"node_name": "ChestSprite", "slot": "armor", "default_layer": 3},
	{"node_name": "GlovesSprite", "slot": "gloves", "default_layer": 4},
	{"node_name": "BackpackSprite", "slot": "backpack", "default_layer": 4},
	{"node_name": "WaistSprite", "slot": "waist", "default_layer": 5},
	{"node_name": "BootsSprite", "slot": "feet", "default_layer": 5},
	{"node_name": "HelmetSprite", "slot": "head", "default_layer": 6},
	{"node_name": "FaceSprite", "slot": "face", "default_layer": 6},
	{"node_name": "CloakSprite", "slot": "cloak", "default_layer": 7},
]


static func get_clothing_sprite_specs() -> Array[Dictionary]:
	return CLOTHING_SPRITE_SPECS.duplicate(true)


static func get_default_clothing_layer_for_slot(slot_name: String) -> int:
	for spec in CLOTHING_SPRITE_SPECS:
		if String(spec.get("slot", "")) == slot_name:
			return int(spec.get("default_layer", 1))
	return 1
