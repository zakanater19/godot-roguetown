extends Node

var _materials: Dictionary = {}

func _ready() -> void:
	_load_all_materials()

func _load_all_materials(force_replace: bool = false) -> void:
	var cache_mode := ResourceLoader.CACHE_MODE_REPLACE if force_replace else ResourceLoader.CACHE_MODE_REUSE
	_materials.clear()
	var dir := DirAccess.open("res://materials/")
	if dir == null:
		push_error("MaterialRegistry: res://materials/ directory not found.")
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		var clean_name: String = file_name.replace(".remap", "")
		if not dir.current_is_dir() and clean_name.ends_with(".tres"):
			var path := "res://materials/" + clean_name
			var res := ResourceLoader.load(path, "", cache_mode)
			if res is MaterialData:
				if res.material_id == "":
					push_warning("MaterialRegistry: material at '%s' has no material_id, skipping." % path)
				elif _materials.has(res.material_id):
					push_warning("MaterialRegistry: duplicate material_id '%s' in '%s', skipping." % [res.material_id, path])
				else:
					_materials[res.material_id] = res
		file_name = dir.get_next()
	dir.list_dir_end()

func reload() -> void:
	_load_all_materials(true)

func patch_material(material: MaterialData) -> void:
	_materials[material.material_id] = material

func get_material(material_id: String) -> MaterialData:
	return _materials.get(material_id, null)

func get_all_materials() -> Array:
	return _materials.values()

func resolve_material_id(material_ref: Variant) -> String:
	if material_ref is MaterialData:
		return material_ref.material_id
	if material_ref is String:
		return String(material_ref)
	if material_ref is Node:
		var node := material_ref as Node
		if "material_data" in node:
			return resolve_material_id(node.get("material_data"))
		if "item_data" in node:
			var item_data: Variant = node.get("item_data")
			if item_data is Resource:
				return resolve_material_id(item_data.get("material_data"))
	return ""

func get_tool_type(item: Node) -> String:
	if item == null:
		return ""
	var tool_type: Variant = item.get("tool_type")
	return tool_type if tool_type is String else ""

func get_tool_efficiency(material_ref: Variant, item: Node) -> float:
	var material_id := resolve_material_id(material_ref)
	if material_id == "":
		return 0.0
	var material := get_material(material_id)
	if material == null:
		return 0.0
	return material.get_efficiency(get_tool_type(item))

func can_tool_affect(material_ref: Variant, item: Node) -> bool:
	return get_tool_efficiency(material_ref, item) > 0.0
