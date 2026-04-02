# res://scripts/net/game_version.gd
# Autoload: GameVersion
#
# Computes a content-hash from item and recipe resource files so that client
# and server can detect mismatches at join time and sync differences before play.
#
# All hashing uses the serialised @export properties of each Resource — so it
# works in both editor and exported PCK builds (no raw FileAccess needed).

extends Node

var _version: String = ""

func _ready() -> void:
	_apply_pending_patch()
	_version = _compute_version()
	print("GameVersion: local version = ", _version.left(8), "...")


func _apply_pending_patch() -> void:
	var pck_path := "user://pending_patch.pck"
	if not FileAccess.file_exists(pck_path):
		return
	var ok := ProjectSettings.load_resource_pack(pck_path, true)
	if ok:
		print("GameVersion: applied pending patch from ", pck_path)
	else:
		push_warning("GameVersion: failed to apply pending patch from ", pck_path)
	# Remove after applying so it isn't re-applied on subsequent restarts.
	DirAccess.remove_absolute(pck_path)


func get_version() -> String:
	return _version


# ---------------------------------------------------------------------------
# Hashing
# ---------------------------------------------------------------------------

func compute_version() -> String:
	return _compute_version()

func _compute_version() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	_hash_resource_dir(ctx, "res://items/")
	_hash_resource_dir(ctx, "res://recipes/")
	return ctx.finish().hex_encode()


func _hash_resource_dir(ctx: HashingContext, dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var files: Array[String] = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			files.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	files.sort()  # deterministic ordering
	for f in files:
		var res := load(dir_path + f)
		if res != null:
			ctx.update(var_to_bytes(_serialize(res)))


# ---------------------------------------------------------------------------
# Manifest  (path → per-file hash)
# ---------------------------------------------------------------------------

## Returns { "res://items/sword.tres" → "abcd1234...", ... } for all tracked files.
func build_manifest() -> Dictionary:
	var manifest: Dictionary = {}
	_add_dir_to_manifest(manifest, "res://items/")
	_add_dir_to_manifest(manifest, "res://recipes/")
	return manifest


func _add_dir_to_manifest(manifest: Dictionary, dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var path := dir_path + fname
			var res  := load(path)
			if res != null:
				var ctx := HashingContext.new()
				ctx.start(HashingContext.HASH_MD5)
				ctx.update(var_to_bytes(_serialize(res)))
				manifest[path] = ctx.finish().hex_encode()
		fname = dir.get_next()
	dir.list_dir_end()


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------

## Converts a Resource's @export properties into a plain RPC-safe Dictionary.
## Object/Resource-typed values (e.g. Texture2D) are stored as their resource path.
func _serialize(res: Resource) -> Dictionary:
	var d: Dictionary = {}
	for prop in res.get_property_list():
		if not (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var val = res.get(prop["name"])
		if val == null:
			d[prop["name"]] = null
		elif val is bool or val is int or val is float or val is String:
			d[prop["name"]] = val
		elif val is Vector2 or val is Vector2i or val is Vector3 or val is Vector3i:
			d[prop["name"]] = val
		elif val is Color or val is Array or val is Dictionary:
			d[prop["name"]] = val
		elif val is Resource:
			# Store as path string so the client can load it locally.
			d[prop["name"]] = val.resource_path if val.resource_path != "" else ""
	return d


# ---------------------------------------------------------------------------
# Diff  (server → client)
# ---------------------------------------------------------------------------

## Builds { path → serialised_dict } for every file whose hash differs between
## the server manifest (this node) and the client's manifest.
func build_diff(server_manifest: Dictionary, client_manifest: Dictionary) -> Dictionary:
	var diffs: Dictionary = {}
	for path in server_manifest:
		if not client_manifest.has(path) or client_manifest[path] != server_manifest[path]:
			var res := load(path)
			if res != null:
				diffs[path] = _serialize(res)
	return diffs


# ---------------------------------------------------------------------------
# Apply  (client-side patch)
# ---------------------------------------------------------------------------

## Applies a diff received from the server into ItemRegistry / RecipeRegistry.
## Re-computes the local version hash afterwards.
func apply_resource_diff(diffs: Dictionary) -> void:
	for path in diffs:
		var props: Dictionary = diffs[path]
		if path.begins_with("res://items/"):
			var item := ItemData.new()
			for key in props:
				if key in item:
					var val = props[key]
					# Texture2D properties are stored as paths; resolve them.
					if val is String and val.begins_with("res://"):
						val = load(val)
					item.set(key, val)
			if item.item_type != "":
				ItemRegistry.patch_item(item)
		elif path.begins_with("res://recipes/"):
			var recipe := RecipeData.new()
			for key in props:
				if key in recipe and props[key] != null:
					recipe.set(key, props[key])
			if recipe.recipe_id != "":
				RecipeRegistry.patch_recipe(recipe)

	# Recompute so our manifest stays current after patching.
	_version = _compute_version()
	print("GameVersion: patched to version = ", _version.left(8), "...")
