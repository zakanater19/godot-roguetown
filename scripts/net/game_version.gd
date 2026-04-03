# res://scripts/net/game_version.gd
extends Node

## Bump this whenever scripts, compiled code, or scene structure changes in a way
## that a PCK patch alone cannot fix (i.e. any .gd change, new node types, etc.).
## Clients with a different APP_VERSION are told to download the new executable
## rather than being patched — preventing crashes from script/binary mismatches.
const APP_VERSION: String = "1775215543"

## Directories whose .tres files are included in both the version hash AND the
## server PCK.  Keep this list in sync with _stage_res_dir_recursive's allowed[].
const HASHED_DIRS: Array[String] = [
	"res://items/",
	"res://recipes/",
	"res://clothing/",
	"res://objects/",
]

var _version: String = ""
var server_pck_ready: bool = false
## Non-empty when the last generate_server_pck() call failed.
var pck_generation_error: String = ""
## True after _apply_pending_patch() successfully loaded a patch this session.
var patch_applied: bool = false


func _ready() -> void:
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
		RecipeRegistry.reload()
		# File is now fully loaded into the virtual FS — safe to remove.
		DirAccess.remove_absolute(pck_path)
	else:
		push_error("GameVersion: failed to load patch PCK '%s' — file may be corrupt, deleting." % pck_path)
		DirAccess.remove_absolute(pck_path)


func get_version() -> String:
	return _version


func compute_version() -> String:
	return _compute_version()


func _compute_version() -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	for dir in HASHED_DIRS:
		_hash_resource_dir(ctx, dir)
	return ctx.finish().hex_encode()


func _hash_resource_dir(ctx: HashingContext, dir_path: String) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	var files: Array[String] = []
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var clean_name: String = fname.replace(".remap", "")
			if clean_name.ends_with(".tres"):
				files.append(clean_name)
		fname = dir.get_next()
	dir.list_dir_end()

	var unique_files: Dictionary = {}
	for f in files:
		unique_files[f] = true
	var sorted_files: Array = unique_files.keys()
	sorted_files.sort()

	for f in sorted_files:
		var res: Resource = load(dir_path + f)
		if res != null:
			ctx.update(var_to_bytes(_serialize(res)))


func build_manifest() -> Dictionary:
	var manifest: Dictionary = {}
	for dir in HASHED_DIRS:
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

	_stage_res_dir_recursive("res://", stage_user)

	var user_os: String  = OS.get_user_data_dir()
	var pck_os: String   = user_os + "/server_patch.pck"
	var stage_os: String = user_os + "/pck_stage"

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

	print("GameVersion: server_patch.pck ready (%d files)" % file_count)
	server_pck_ready = true
	return OK


func _stage_res_dir_recursive(res_dir: String, stage_base: String) -> void:
	var dir: DirAccess = DirAccess.open(res_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var res_path: String = res_dir + entry
			if dir.current_is_dir():
				var allowed: Array = ["items", "recipes", "clothing", "objects", "assets", "animated", "doors", "ui", ".godot"]
				if res_dir != "res://" or entry in allowed:
					_stage_res_dir_recursive(res_path + "/", stage_base)
			else:
				var ext: String = entry.get_extension()
				if ext in ["tres", "tscn", "png", "jpg", "remap", "import"]:
					_stage_file(res_path, stage_base)
		entry = dir.get_next()
	dir.list_dir_end()


func _stage_file(res_path: String, stage_base: String) -> Error:
	var relative: String = res_path.substr(6)
	var dest: String = stage_base + "/" + relative

	if res_path.ends_with(".remap"):
		var target_path: String = ""
		var remap_data: String = FileAccess.get_file_as_bytes(res_path).get_string_from_utf8()
		for line in remap_data.split("\n"):
			if line.strip_edges().begins_with("path="):
				target_path = line.strip_edges().trim_prefix("path=").replace("\"", "")
				break
		if target_path != "":
			var clean_dest: String = dest.replace(".remap", "")
			DirAccess.make_dir_recursive_absolute(clean_dest.get_base_dir())
			var bin_data: PackedByteArray = FileAccess.get_file_as_bytes(target_path)
			if not bin_data.is_empty():
				var dst: FileAccess = FileAccess.open(clean_dest, FileAccess.WRITE)
				if dst:
					dst.store_buffer(bin_data)
					dst.close()
					return OK
		return ERR_FILE_CANT_READ

	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	var data: PackedByteArray = FileAccess.get_file_as_bytes(res_path)
	if not data.is_empty():
		var dst: FileAccess = FileAccess.open(dest, FileAccess.WRITE)
		if dst:
			dst.store_buffer(data)
			dst.close()

		if res_path.ends_with(".import"):
			var txt: String = data.get_string_from_utf8()
			for line in txt.split("\n"):
				if line.strip_edges().begins_with("path="):
					var ctex_path: String = line.strip_edges().trim_prefix("path=").replace("\"", "")
					if ctex_path.begins_with("res://.godot/imported/"):
						_stage_file(ctex_path, stage_base)
		return OK
	return ERR_FILE_CANT_WRITE


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
