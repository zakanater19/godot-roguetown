@tool
extends ObjectItem

@export var key_id: int = 1

func has_key_id(target_key_id: int) -> bool:
	return key_id > 0 and key_id == target_key_id

func get_description() -> String:
	if key_id > 0:
		return Defs.get_key_description(key_id)
	return "a key"
