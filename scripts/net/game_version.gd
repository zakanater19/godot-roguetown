# res://scripts/net/game_version.gd
extends Node

## Keep this for executable/binary level compatibility only. Runtime content,
## scenes, scripts, and maps are synced via the server bundle hash below.
const APP_VERSION: String = "1776004056"

## Directories that still support lightweight resource diffs as a fallback when
## talking to older servers. Full bundle sync does not depend on this list.
const RESOURCE_DIFF_DIRS: Array[String] = [
	"res://items/",
	"res://materials/",
	"res://recipes/",
	"res://clothing/",
	"res://objects/",
]
const SERVER_BUNDLE_PATH: String = "user://server_bundle.pck"
const PACK_EXCLUDED_DIR_PREFIXES: Array[String] = [
	".git/",
	".claude/",
	".godot/editor/",
	".godot/exported/",
]
const PACK_EXCLUDED_FILES: Array[String] = [
	".gitattributes",
	".gitignore",
	"README.md",
	"LICENSE",
	"export_presets.cfg",
	".godot/export_credentials.cfg",
]
const PACK_EXCLUDED_EXTENSIONS: Array[String] = ["md", "md5", "cache"]

var _version: String = ""
var server_pck_ready: bool = false
## Non-empty when the last generate_server_pck() call failed.
var pck_generation_error: String = ""
## True after _apply_pending_patch() successfully loaded a patch this session.
var patch_applied: bool = false
var launched_with_main_pack: bool = false
var active_main_pack_path: String = ""


func _ready() -> void:
	_detect_main_pack_launch()
	_apply_pending_patch()
	_version = _compute_version()
	print("GameVersion: APP_VERSION=%s  content=%s..." % [APP_VERSION, _version.left(8)])


func _apply_pending_patch() -> void:
	var pck_path: String = "user://pending_patch.pck"
	if not FileAccess.file_exists(pck_path):
		return
	var ok: bool = ProjectSettings.load_resource_pack(pck_path, true)
	if ok:
		print("GameVersion: applied patch from ", pck_path)
		patch_applied = true
		ItemRegistry.reload()
		MaterialRegistry.reload()
		RecipeRegistry.reload()
		# File is now fully loaded into the virtual FS — safe to remove.
		DirAccess.remove_absolute(pck_path)
	else:
		push_error("GameVersion: failed to load patch PCK '%s' — file may be corrupt, deleting." % pck_path)
		DirAccess.remove_absolute(pck_path)


func get_version() -> String:
	return _version


func has_active_content_patch() -> bool:
	return patch_applied or launched_with_main_pack


func get_server_bundle_path() -> String:
	return SERVER_BUNDLE_PATH


func build_restart_args(main_pack_path: String = "") -> PackedStringArray:
	var args: PackedStringArray = OS.get_cmdline_args()
	var cleaned := PackedStringArray()
	var skip_next: bool = false

	for arg in args:
		if skip_next:
			skip_next = false
			continue
		if arg == "--main-pack":
			skip_next = true
			continue
		cleaned.append(arg)

	if main_pack_path != "":
		cleaned.append("--main-pack")
		cleaned.append(ProjectSettings.globalize_path(main_pack_path))

	return cleaned


func compute_version() -> String:
	return _compute_version()


func _compute_version() -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	for entry in _get_runtime_entries():
		ctx.update(entry["dest"].to_utf8_buffer())
		ctx.update(_read_file_bytes(entry["source"]))
	return ctx.finish().hex_encode()


func build_manifest() -> Dictionary:
	var manifest: Dictionary = {}
	for dir in RESOURCE_DIFF_DIRS:
		_add_dir_to_manifest(manifest, dir)
	return manifest


func _add_dir_to_manifest(manifest: Dictionary, dir_path: String) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var clean_name: String = fname.replace(".remap", "")
			if clean_name.ends_with(".tres"):
				var path: String = dir_path + clean_name
				if not manifest.has(path):
					var res: Resource = load(path)
					if res != null:
						var ctx: HashingContext = HashingContext.new()
						ctx.start(HashingContext.HASH_MD5)
						ctx.update(var_to_bytes(_serialize(res)))
						manifest[path] = ctx.finish().hex_encode()
		fname = dir.get_next()
	dir.list_dir_end()


func _serialize(res: Resource) -> Dictionary:
	var d: Dictionary = {}
	for prop in res.get_property_list():
		if not (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var val = res.get(prop["name"])
		if val == null:                                                    d[prop["name"]] = null
		elif val is bool or val is int or val is float or val is String:   d[prop["name"]] = val
		elif val is Vector2 or val is Vector2i or val is Vector3 or val is Vector3i: d[prop["name"]] = val
		elif val is Color or val is Array or val is Dictionary:            d[prop["name"]] = val
		elif val is Resource: d[prop["name"]] = val.resource_path if val.resource_path != "" else ""
	return d


func build_diff(server_manifest: Dictionary, client_manifest: Dictionary) -> Dictionary:
	var diffs: Dictionary = {}
	for path in server_manifest:
		if not client_manifest.has(path) or client_manifest[path] != server_manifest[path]:
			var res: Resource = load(path)
			if res != null:
				diffs[path] = _serialize(res)
	return diffs


func apply_resource_diff(diffs: Dictionary) -> void:
	for path in diffs:
		var props: Dictionary = diffs[path]
		if path.begins_with("res://items/"):
			var item: ItemData = ItemData.new()
			var prop_types: Dictionary = {}
			for p in item.get_property_list():
				prop_types[p["name"]] = p["type"]
			for key in props:
				if key in item:
					var val = props[key]
					if val is String and val.begins_with("res://") and prop_types.get(key, TYPE_NIL) == TYPE_OBJECT:
						val = load(val)
					item.set(key, val)
			if item.item_type != "":
				ItemRegistry.patch_item(item)
		elif path.begins_with("res://materials/"):
			var material: MaterialData = MaterialData.new()
			for key in props:
				if key in material and props[key] != null:
					material.set(key, props[key])
			if material.material_id != "":
				MaterialRegistry.patch_material(material)
		elif path.begins_with("res://recipes/"):
			var recipe: RecipeData = RecipeData.new()
			for key in props:
				if key in recipe and props[key] != null:
					recipe.set(key, props[key])
			if recipe.recipe_id != "":
				RecipeRegistry.patch_recipe(recipe)

	_version = _compute_version()
	print("GameVersion: patched to version = ", _version.left(8), "...")


func generate_server_pck() -> Error:
	pck_generation_error = ""
	var stage_user: String = "user://pck_stage"
	_rmdir_recursive(stage_user)
	DirAccess.make_dir_recursive_absolute(stage_user)

	var entry_count: int = _stage_runtime_bundle(stage_user)
	if entry_count <= 0:
		pck_generation_error = "no runtime files were collected for staging"
		push_error("GameVersion: generate_server_pck - " + pck_generation_error)
		_rmdir_recursive(stage_user)
		server_pck_ready = false
		return ERR_CANT_CREATE

	var pck_os: String   = ProjectSettings.globalize_path(SERVER_BUNDLE_PATH)
	var stage_os: String = ProjectSettings.globalize_path(stage_user)

	var pck: PCKPacker = PCKPacker.new()
	var err: Error = pck.pck_start(pck_os)
	if err != OK:
		pck_generation_error = "pck_start failed (error %d)" % err
		push_error("GameVersion: generate_server_pck — " + pck_generation_error)
		_rmdir_recursive(stage_user)
		server_pck_ready = false
		return err

	var file_count: int = _add_to_pck_recursive(pck, stage_user, stage_os, "res:/")
	err = pck.flush(false)
	_rmdir_recursive(stage_user)

	if err != OK:
		pck_generation_error = "pck.flush failed (error %d)" % err
		push_error("GameVersion: generate_server_pck — " + pck_generation_error)
		server_pck_ready = false
		return err

	print("GameVersion: server bundle ready (%d files)" % file_count)
	server_pck_ready = true
	return OK


func _detect_main_pack_launch() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == "--main-pack" and i + 1 < args.size():
			launched_with_main_pack = true
			active_main_pack_path = args[i + 1]
			return


func _get_runtime_entries() -> Array:
	var entry_map: Dictionary = {}
	_collect_runtime_entries_recursive("res://", entry_map)

	var dests: Array = entry_map.keys()
	dests.sort()

	var entries: Array = []
	for dest in dests:
		entries.append({
			"dest": dest,
			"source": entry_map[dest],
		})
	return entries


func _collect_runtime_entries_recursive(res_dir: String, entry_map: Dictionary) -> void:
	var dir: DirAccess = DirAccess.open(res_dir)
	if dir == null:
		return

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var res_path: String = res_dir + entry
			var relative: String = res_path.substr(6)
			if dir.current_is_dir():
				if _should_include_dir(relative + "/"):
					_collect_runtime_entries_recursive(res_path + "/", entry_map)
			elif _should_include_file(relative):
				_collect_runtime_file_entries(res_path, entry_map)
		entry = dir.get_next()
	dir.list_dir_end()


func _should_include_dir(relative_dir: String) -> bool:
	for prefix in PACK_EXCLUDED_DIR_PREFIXES:
		if relative_dir.begins_with(prefix):
			return false
	return true


func _should_include_file(relative_file: String) -> bool:
	for prefix in PACK_EXCLUDED_DIR_PREFIXES:
		if relative_file.begins_with(prefix):
			return false

	if relative_file in PACK_EXCLUDED_FILES:
		return false

	var ext: String = relative_file.get_extension().to_lower()
	return not PACK_EXCLUDED_EXTENSIONS.has(ext)


func _collect_runtime_file_entries(res_path: String, entry_map: Dictionary) -> void:
	if res_path.ends_with(".remap"):
		# Exported clients replace text scenes/scripts with .remap stubs that point
		# at compiled resources under .godot/exported/. Keep that indirection intact
		# so restarted outdated clients can boot the downloaded pack as a main pack.
		_register_runtime_entry(entry_map, res_path, res_path)
		var remap_target: String = _extract_pack_target_path(res_path)
		if remap_target != "" and FileAccess.file_exists(remap_target):
			_register_runtime_entry(entry_map, remap_target, remap_target)
		return

	_register_runtime_entry(entry_map, res_path, res_path)

	if res_path.ends_with(".import"):
		var import_target: String = _extract_pack_target_path(res_path)
		if import_target.begins_with("res://.godot/imported/") and FileAccess.file_exists(import_target):
			_register_runtime_entry(entry_map, import_target, import_target)


func _register_runtime_entry(entry_map: Dictionary, dest_res_path: String, source_res_path: String) -> void:
	if not entry_map.has(dest_res_path):
		entry_map[dest_res_path] = source_res_path


func _extract_pack_target_path(res_path: String) -> String:
	var file: FileAccess = FileAccess.open(res_path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()

	for line in text.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("path="):
			return stripped.trim_prefix("path=").replace("\"", "")
	return ""


func _read_file_bytes(res_path: String) -> PackedByteArray:
	var file: FileAccess = FileAccess.open(res_path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var data: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return data


func _stage_runtime_bundle(stage_base: String) -> int:
	var count: int = 0
	for entry in _get_runtime_entries():
		if _stage_runtime_entry(entry["dest"], entry["source"], stage_base) == OK:
			count += 1
	return count


func _stage_runtime_entry(dest_res_path: String, source_res_path: String, stage_base: String) -> Error:
	var relative: String = dest_res_path.substr(6)
	var dest: String = stage_base + "/" + relative
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())

	var src: FileAccess = FileAccess.open(source_res_path, FileAccess.READ)
	if src == null:
		return ERR_FILE_CANT_READ

	var data: PackedByteArray = src.get_buffer(src.get_length())
	src.close()

	var dst: FileAccess = FileAccess.open(dest, FileAccess.WRITE)
	if dst == null:
		return ERR_FILE_CANT_WRITE
	dst.store_buffer(data)
	dst.close()
	return OK


func _add_to_pck_recursive(pck: PCKPacker, stage_user: String, stage_os: String, res_prefix: String) -> int:
	var dir: DirAccess = DirAccess.open(stage_user)
	if dir == null:
		return 0
	var count: int = 0
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var child_user: String = stage_user + "/" + entry
		var child_os: String   = stage_os   + "/" + entry
		var child_res: String  = res_prefix + "/" + entry
		if dir.current_is_dir():
			count += _add_to_pck_recursive(pck, child_user, child_os, child_res)
		else:
			pck.add_file(child_res, child_os)
			count += 1
		entry = dir.get_next()
	dir.list_dir_end()
	return count


func _rmdir_recursive(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			_rmdir_recursive(path + "/" + entry)
		dir.remove(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
