@tool
# res://addons/pixel_hand_editor/hand_editor_offsets.gd
# Offset read/write/load/save helpers extracted from hand_editor_panel.gd.
extends RefCounted

const OFFSETS_PATH:          String = "res://objects/hand_offsets.json"
const CLOTHING_OFFSETS_PATH: String = "res://clothing/clothing_offsets.json"

const DEFAULT_RIGHT: Dictionary = {
	"Pickaxe":   {"south":[20.0,  8.0], "north":[20.0, -10.0], "east":[16.0,  8.0], "west":[-16.0,  8.0]},
	"Pebble":    {"south":[20.0,  8.0], "north":[20.0, -10.0], "east":[16.0,  8.0], "west":[-16.0,  8.0]},
	"Sword":     {"south":[20.0, -2.0], "north":[20.0, -20.0], "east":[16.0, -2.0], "west":[-16.0, -2.0]},
	"Coal":      {"south":[20.0,  8.0], "north":[20.0, -10.0], "east":[16.0,  8.0], "west":[-16.0,  8.0]},
	"IronOre":   {"south":[20.0,  8.0], "north":[20.0, -10.0], "east":[16.0,  8.0], "west":[-16.0,  8.0]},
	"IronIngot": {"south":[20.0,  8.0], "north":[20.0, -10.0], "east":[16.0,  8.0], "west":[-16.0,  8.0]},
	"Lamp":      {"south":[20.0,  8.0], "north":[20.0, -10.0], "east":[16.0,  8.0], "west":[-16.0,  8.0]},
}

const DEFAULT_LEFT: Dictionary = {
	"Pickaxe":   {"south":[-20.0, 10.0], "north":[-20.0, -8.0], "east":[-16.0, 10.0], "west":[16.0, 10.0]},
	"Pebble":    {"south":[-20.0, 10.0], "north":[-20.0, -8.0], "east":[-16.0, 10.0], "west":[16.0, 10.0]},
	"Sword":     {"south":[-20.0,  0.0], "north":[-20.0,-18.0], "east":[-16.0,  0.0], "west":[16.0,  0.0]},
	"Coal":      {"south":[-20.0, 10.0], "north":[-20.0, -8.0], "east":[-16.0, 10.0], "west":[16.0, 10.0]},
	"IronOre":   {"south":[-20.0, 10.0], "north":[-20.0, -8.0], "east":[-16.0, 10.0], "west":[16.0, 10.0]},
	"IronIngot": {"south":[-20.0, 10.0], "north":[-20.0, -8.0], "east":[-16.0, 10.0], "west":[16.0, 10.0]},
	"Lamp":      {"south":[-20.0, 10.0], "north":[-20.0, -8.0], "east":[-16.0, 10.0], "west":[16.0, 10.0]},
}

const DEFAULT_WAIST: Dictionary = {
	"Pickaxe":   {"south":[12.0, 4.0], "north":[-12.0, 4.0], "east":[0.0, 4.0], "west":[0.0, 4.0]},
	"Pebble":    {"south":[12.0, 4.0], "north":[-12.0, 4.0], "east":[0.0, 4.0], "west":[0.0, 4.0]},
	"Sword":     {"south":[12.0, 4.0], "north":[-12.0, 4.0], "east":[0.0, 4.0], "west":[0.0, 4.0]},
	"Coal":      {"south":[12.0, 4.0], "north":[-12.0, 4.0], "east":[0.0, 4.0], "west":[0.0, 4.0]},
	"IronOre":   {"south":[12.0, 4.0], "north":[-12.0, 4.0], "east":[0.0, 4.0], "west":[0.0, 4.0]},
	"IronIngot": {"south":[12.0, 4.0], "north":[-12.0, 4.0], "east":[0.0, 4.0], "west":[0.0, 4.0]},
	"Lamp":      {"south":[12.0, 4.0], "north":[-12.0, 4.0], "east":[0.0, 4.0], "west":[0.0, 4.0]},
}

var panel: Control

func _init(p: Control) -> void:
	panel = p

# ---------------------------------------------------------------------------
# Entry / mutation helpers
# ---------------------------------------------------------------------------

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

func store_clothing_field(item: String, facing: String, offset: Vector2, scale: float) -> void:
	if not panel._clothing_offsets.has(item):
		panel._clothing_offsets[item] = {}
	if not panel._clothing_offsets[item].has(facing):
		panel._clothing_offsets[item][facing] = {}
	panel._clothing_offsets[item][facing]["offset"] = [offset.x, offset.y]
	panel._clothing_offsets[item][facing]["scale"] = scale

# ---------------------------------------------------------------------------
# Read helpers
# ---------------------------------------------------------------------------

func read_offset(item: String, facing: String, hand_key: String) -> Vector2:
	if panel._offsets.has(item) and panel._offsets[item].has(facing):
		var entry = panel._offsets[item][facing]
		if entry.has(hand_key):
			var arr = entry[hand_key]
			return Vector2(float(arr[0]), float(arr[1]))
	return default_offset(item, facing, hand_key)

func read_flipped(item: String, facing: String, flip_key: String) -> bool:
	if panel._offsets.has(item) and panel._offsets[item].has(facing):
		return panel._offsets[item][facing].get(flip_key, false)
	return false

func read_rotation(item: String, facing: String, rot_key: String) -> float:
	if panel._offsets.has(item) and panel._offsets[item].has(facing):
		return float(panel._offsets[item][facing].get(rot_key, 45.0 if item == "Sword" and rot_key.begins_with("waist") else 0.0))
	return 45.0 if item == "Sword" and rot_key.begins_with("waist") else 0.0

func read_scale(item: String, facing: String, scale_key: String, default: float) -> float:
	if panel._offsets.has(item) and panel._offsets[item].has(facing):
		return float(panel._offsets[item][facing].get(scale_key, default))
	return default

func read_clothing_data(item: String, facing: String) -> Dictionary:
	if panel._clothing_offsets.has(item) and panel._clothing_offsets[item].has(facing):
		var entry = panel._clothing_offsets[item][facing]
		return {
			"offset": Vector2(float(entry.get("offset", [0, 0])[0]), float(entry.get("offset", [0, 0])[1])),
			"scale":  float(entry.get("scale", 1.0))
		}
	return {"offset": Vector2.ZERO, "scale": 1.0}

func default_offset(item: String, facing: String, hand_key: String) -> Vector2:
	var table := DEFAULT_RIGHT if hand_key == "right" else DEFAULT_LEFT if hand_key == "left" else DEFAULT_WAIST
	if table.has(item) and table[item].has(facing):
		var arr = table[item][facing]
		return Vector2(float(arr[0]), float(arr[1]))
	return Vector2.ZERO

# ---------------------------------------------------------------------------
# Save / load
# ---------------------------------------------------------------------------

func load_offsets() -> void:
	if not FileAccess.file_exists(OFFSETS_PATH):
		set_status("No saved offsets — using defaults.")
		return
	var file := FileAccess.open(OFFSETS_PATH, FileAccess.READ)
	if file == null:
		set_status("Could not read " + OFFSETS_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		set_status("JSON parse error — using defaults.")
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
	if not dir.dir_exists("clothing"):
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
