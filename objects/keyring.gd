@tool
extends ObjectItem

var contents: Array = []

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	super._ready()
	_normalize_contents()
	_update_sprite()

func can_accept_key_item(item: Node) -> bool:
	return item != null and item != self and item.has_method("has_key_id")

func validate_key_insert(item: Node) -> Dictionary:
	if not can_accept_key_item(item):
		return {"ok": false, "message": "[color=#ffaaaa]That won't fit on the keyring.[/color]"}

	_normalize_contents()
	if contents.size() >= Defs.KEYRING_MAX_KEYS:
		return {"ok": false, "message": "[color=#ffaaaa]The keyring is full.[/color]"}

	var inserted_key_id: int = int(item.get("key_id")) if "key_id" in item else 0
	if inserted_key_id <= 0:
		return {"ok": false, "message": "[color=#ffaaaa]That key doesn't match any lock.[/color]"}

	var item_name = item.get("item_type")
	if item_name == null or item_name == "":
		item_name = "BrownKey"

	return {
		"ok": true,
		"key_state": {
			"item_type": str(item_name),
			"key_id": inserted_key_id,
		}
	}

func insert_key_state(key_state: Dictionary) -> void:
	_normalize_contents()
	contents.append({
		"item_type": str(key_state.get("item_type", "BrownKey")),
		"key_id": int(key_state.get("key_id", 0)),
	})
	_update_sprite()

func can_extract_key() -> bool:
	_normalize_contents()
	return not contents.is_empty()

func get_random_key_roll() -> Dictionary:
	_normalize_contents()
	if contents.is_empty():
		return {}

	var index := randi_range(0, contents.size() - 1)
	return {
		"index": index,
		"key_state": contents[index].duplicate(true),
	}

func remove_key_at(index: int) -> Dictionary:
	_normalize_contents()
	if index < 0 or index >= contents.size():
		return {}

	var removed_key: Dictionary = contents[index].duplicate(true)
	contents.remove_at(index)
	_update_sprite()
	return removed_key

func has_key_id(target_key_id: int) -> bool:
	_normalize_contents()
	for entry in contents:
		if int(entry.get("key_id", 0)) == target_key_id:
			return true
	return false

func get_description() -> String:
	_normalize_contents()
	if contents.is_empty():
		return "an empty keyring"

	var lines: PackedStringArray = ["a keyring"]
	for i in range(contents.size()):
		var entry: Dictionary = contents[i]
		var key_desc := Defs.get_key_description(int(entry.get("key_id", 0)))
		lines.append("%d; %s" % [i + 1, key_desc])
	return "\n".join(lines)

func _update_sprite() -> void:
	if sprite == null:
		return

	_normalize_contents()
	var tex_path := Defs.get_keyring_icon_path(contents.size())
	var tex := load(tex_path) as Texture2D if tex_path != "" else null
	if tex != null:
		sprite.texture = tex

func _input_event(viewport: Viewport, event: InputEvent, shape_idx: int) -> void:
	if Engine.is_editor_hint():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.is_key_pressed(KEY_SHIFT):
			return

		var player: Node = World.get_local_player()
		if player != null and player.z_level == z_level and Defs.is_within_tile_reach(player.tile_pos, get_anchor_tile()):
			var held_item: Node = player.hands[player.active_hand]
			if can_accept_key_item(held_item):
				get_viewport().set_input_as_handled()
				var keyring_id := World.get_entity_id(self)
				if multiplayer.is_server():
					World.rpc_request_keyring_insert(keyring_id, player.active_hand)
				else:
					World.rpc_request_keyring_insert.rpc_id(1, keyring_id, player.active_hand)
				return

	super._input_event(viewport, event, shape_idx)

func _normalize_contents() -> void:
	if contents == null:
		contents = []
		return

	var normalized: Array = []
	for entry in contents:
		if entry is Dictionary and entry.has("key_id"):
			normalized.append({
				"item_type": str(entry.get("item_type", "BrownKey")),
				"key_id": int(entry.get("key_id", 0)),
			})
		elif entry is int:
			normalized.append({
				"item_type": "BrownKey",
				"key_id": int(entry),
			})
	contents = normalized
