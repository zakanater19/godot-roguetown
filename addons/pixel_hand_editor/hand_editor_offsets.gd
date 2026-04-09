@tool
extends RefCounted

const OFFSETS_PATH: String = "res://objects/hand_offsets.json"
const CLOTHING_OFFSETS_PATH: String = "res://clothing/clothing_offsets.json"

var panel: Control


func _init(p: Control) -> void:
	panel = p


func ensure_entry(item: String, facing: String) -> void:
	if not panel._offsets.has(item):
		panel._offsets[item] = {}
	if not panel._offsets[item].has(facing):
		panel._offsets[item][facing] = {}


func store_field(item: String, facing: String, key: String, value: Vector2, rot: float, scale: float) -> void:
	ensure_entry(item, facing)
	panel._offsets[item][facing][key] = [value.x, value.y]
	panel._offsets[item][facing][key + "_rotation"] = rot
	if key == "waist":
		panel._offsets[item][facing][key + "_scale"] = scale


func store_clothing_field(item: String, facing: String, offset: Vector2, scale: float, layer: int) -> void:
	if not panel._clothing_offsets.has(item):
		panel._clothing_offsets[item] = {}
	if not panel._clothing_offsets[item].has(facing):
		panel._clothing_offsets[item][facing] = {}
	panel._clothing_offsets[item][facing]["offset"] = [offset.x, offset.y]
	panel._clothing_offsets[item][facing]["scale"] = scale
	panel._clothing_offsets[item][facing]["layer"] = layer


func read_offset(item: String, facing: String, hand_key: String) -> Vector2:
	if panel._offsets.has(item) and panel._offsets[item].has(facing):
		var entry: Dictionary = panel._offsets[item][facing]
		if entry.has(hand_key):
			var arr = entry[hand_key]
			return Vector2(float(arr[0]), float(arr[1]))
	return default_offset(item, facing, hand_key)


func read_flipped(item: String, facing: String, flip_key: String) -> bool:
	if panel._offsets.has(item) and panel._offsets[item].has(facing):
		return bool(panel._offsets[item][facing].get(flip_key, false))
	return false


func read_rotation(item: String, facing: String, rot_key: String) -> float:
	if panel._offsets.has(item) and panel._offsets[item].has(facing):
		return float(panel._offsets[item][facing].get(rot_key, default_rotation(item, rot_key.get_slice("_", 0))))
	return default_rotation(item, rot_key.get_slice("_", 0))


func read_scale(item: String, facing: String, scale_key: String, default: float) -> float:
	if panel._offsets.has(item) and panel._offsets[item].has(facing):
		return float(panel._offsets[item][facing].get(scale_key, default))
	return default


func read_clothing_data(item: String, facing: String) -> Dictionary:
	var default_layer := default_clothing_layer(item)
	if panel._clothing_offsets.has(item) and panel._clothing_offsets[item].has(facing):
		var entry: Dictionary = panel._clothing_offsets[item][facing]
		var raw_offset = entry.get("offset", [0, 0])
		return {
			"offset": Vector2(float(raw_offset[0]), float(raw_offset[1])),
			"scale": float(entry.get("scale", 1.0)),
			"layer": int(entry.get("layer", default_layer)),
		}
	return {"offset": Vector2.ZERO, "scale": 1.0, "layer": default_layer}


func default_offset(item: String, facing: String, hand_key: String) -> Vector2:
	var item_data: ItemData = panel._item_data_by_type.get(item, null)
	var base_y := item_data.hand_offset_y if item_data != null else 0.0

	match hand_key:
		"right":
			match facing:
				"south":
					return Vector2(20.0, 8.0 + base_y)
				"north":
					return Vector2(20.0, -10.0 + base_y)
				"east":
					return Vector2(16.0, 8.0 + base_y)
				"west":
					return Vector2(-16.0, 8.0 + base_y)
		"left":
			match facing:
				"south":
					return Vector2(-20.0, 10.0 + base_y)
				"north":
					return Vector2(-20.0, -8.0 + base_y)
				"east":
					return Vector2(-16.0, 10.0 + base_y)
				"west":
					return Vector2(16.0, 10.0 + base_y)
		"waist":
			match facing:
				"south":
					return Vector2(12.0, 4.0)
				"north":
					return Vector2(-12.0, 4.0)
				"east":
					return Vector2(0.0, 4.0)
				"west":
					return Vector2(0.0, 4.0)

	return Vector2.ZERO


func default_rotation(item: String, hand_key: String) -> float:
	if hand_key != "waist":
		return 0.0
	var item_data: ItemData = panel._item_data_by_type.get(item, null)
	return item_data.waist_rotation if item_data != null else 0.0


func default_clothing_layer(item: String) -> int:
	var item_data: ItemData = panel._item_data_by_type.get(item, null)
	if item_data == null:
		return 1
	return PlayerVisualDefs.get_default_clothing_layer_for_slot(item_data.slot)


func load_offsets() -> void:
	if not FileAccess.file_exists(OFFSETS_PATH):
		set_status("No saved hand offsets, using defaults.")
		return
	var file := FileAccess.open(OFFSETS_PATH, FileAccess.READ)
	if file == null:
		set_status("Could not read " + OFFSETS_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		set_status("Hand offset JSON parse error, using defaults.")
		return
	panel._offsets = parsed
	set_status("Offsets loaded.")


func write_offsets() -> void:
	var file := FileAccess.open(OFFSETS_PATH, FileAccess.WRITE)
	if file == null:
		set_status("ERROR: cannot write " + OFFSETS_PATH)
		return
	file.store_string(JSON.stringify(panel._offsets, "\t"))
	file.close()
	set_status("Saved.")


func load_clothing_offsets() -> void:
	if not FileAccess.file_exists(CLOTHING_OFFSETS_PATH):
		return
	var file := FileAccess.open(CLOTHING_OFFSETS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		panel._clothing_offsets = parsed


func write_clothing_offsets() -> void:
	var dir := DirAccess.open("res://")
	if dir != null and not dir.dir_exists("clothing"):
		dir.make_dir("clothing")
	var file := FileAccess.open(CLOTHING_OFFSETS_PATH, FileAccess.WRITE)
	if file == null:
		set_status("ERROR: cannot write " + CLOTHING_OFFSETS_PATH)
		return
	file.store_string(JSON.stringify(panel._clothing_offsets, "\t"))
	file.close()
	set_status("Clothing offsets saved.")


func set_status(msg: String) -> void:
	if panel._status_lbl != null:
		panel._status_lbl.text = msg
