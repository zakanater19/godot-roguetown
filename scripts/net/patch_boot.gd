extends Node

# This must be the FIRST autoload and have no gameplay dependencies. _init()
# runs before Godot instantiates the other autoloads; _ready() is too late.
const STATE_PATH := "user://active_patch.json"
const MANIFEST_PATH := "res://.patch_manifest.json"
const ACK_PATH := "user://patch_started.json"

var pack_path: String = ""
var files: Array = []
var boot_error: String = ""
var _state: Dictionary = {}


func _init() -> void:
	_state = read_json(STATE_PATH)
	# Editor-hosted games must always use the developer's current source files.
	if OS.has_feature("editor") or _state.is_empty():
		return
	# A newly installed executable supersedes patches for the old executable.
	if str(_state.get("base_sha256", "")) != FileAccess.get_sha256(OS.get_executable_path()):
		return
	var path := str(_state.get("pack_path", ""))
	if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != str(_state.get("pack_sha256", "")):
		boot_error = "The saved update is missing or damaged. Reconnect to download it again."
		return
	if not ProjectSettings.load_resource_pack(path, true):
		boot_error = "The saved update could not be opened. Reconnect to download it again."
		return
	var manifest := read_json(MANIFEST_PATH)
	if manifest.get("version", "") != _state.get("version", "") or not manifest.get("files") is Array:
		boot_error = "The saved update has an invalid manifest."
		return
	files = manifest["files"]
	# A mounted pack overlays the embedded one. Hide obsolete files, including
	# exported .remap stubs that would otherwise redirect to OLD compiled code
	# when the patch comes from an editor-hosted game with plain .gd/.tscn files.
	var keep := {}
	for path_entry in files:
		keep[str(path_entry)] = true
	keep[MANIFEST_PATH] = true
	var cleanup_path := "user://patch_cleanup_%d.pck" % OS.get_process_id()
	var cleanup := PCKPacker.new()
	if cleanup.pck_start(cleanup_path) != OK or not _hide_obsolete_files("res://", keep, cleanup) or cleanup.flush() != OK:
		boot_error = "The saved update could not be prepared."
		return
	if not ProjectSettings.load_resource_pack(cleanup_path, true):
		boot_error = "The saved update could not be prepared."
		return
	# This pack contains only removal records, with no lazily read file data.
	DirAccess.remove_absolute(cleanup_path)
	pack_path = path
	print("PatchBoot: mounted ", path)


func _hide_obsolete_files(directory: String, keep: Dictionary, cleanup: PCKPacker) -> bool:
	var dir := DirAccess.open(directory)
	if dir == null:
		return false
	for file_name in dir.get_files():
		var path := directory.path_join(file_name)
		if not keep.has(path) and cleanup.add_file_removal(path) != OK:
			return false
	for directory_name in dir.get_directories():
		if not _hide_obsolete_files(directory.path_join(directory_name), keep, cleanup):
			return false
	return true


func confirm_startup(version: String) -> void:
	if not boot_error.is_empty() or _state.get("version", "") != version:
		return
	write_json(ACK_PATH, {"token": _state.get("token", ""), "pid": OS.get_process_id(), "version": version})


func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func write_json(path: String, data: Dictionary) -> Error:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	file.flush()
	var err := file.get_error()
	file.close()
	if err == OK:
		err = DirAccess.rename_absolute(temporary, path)
	return err
