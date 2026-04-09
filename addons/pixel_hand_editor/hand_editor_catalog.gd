@tool
extends RefCounted

const ITEM_DATA_DIR: String = "res://items/"


func load_catalog() -> Dictionary:
	var items_by_type: Dictionary = {}
	var preview_data_by_type: Dictionary = {}
	var hand_items: Array[String] = []
	var clothing_items: Array[String] = []

	var dir := DirAccess.open(ITEM_DATA_DIR)
	if dir == null:
		return {
			"items_by_type": items_by_type,
			"preview_data_by_type": preview_data_by_type,
			"hand_items": hand_items,
			"clothing_items": clothing_items,
		}

	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		var clean_name := fname.replace(".remap", "")
		if clean_name.ends_with(".tres"):
			var path := ITEM_DATA_DIR + clean_name
			var item_data := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as ItemData
			if item_data != null and item_data.item_type != "":
				items_by_type[item_data.item_type] = item_data
				preview_data_by_type[item_data.item_type] = _build_preview_data(item_data)
				if bool(item_data.pickable):
					hand_items.append(item_data.item_type)
				if _is_clothing_item(item_data):
					clothing_items.append(item_data.item_type)
		fname = dir.get_next()
	dir.list_dir_end()

	hand_items.sort()
	clothing_items.sort()

	return {
		"items_by_type": items_by_type,
		"preview_data_by_type": preview_data_by_type,
		"hand_items": hand_items,
		"clothing_items": clothing_items,
	}


func _is_clothing_item(item_data: ItemData) -> bool:
	return item_data.slot != "" and item_data.slot != "waist" and item_data.mob_texture_path != ""


func _build_preview_data(item_data: ItemData) -> Dictionary:
	return {
		"slot": item_data.slot,
		"default_clothing_layer": PlayerVisualDefs.get_default_clothing_layer_for_slot(item_data.slot),
		"hand": _build_hand_preview(item_data),
		"waist": _build_waist_preview(item_data),
		"clothing": _build_clothing_preview(item_data),
	}


func _build_hand_preview(item_data: ItemData) -> Dictionary:
	var sprite_state := _extract_scene_sprite_state(item_data.scene_path)
	var texture: Texture2D = sprite_state.get("texture", null)
	var region_enabled: bool = bool(sprite_state.get("region_enabled", false))
	var region_rect: Rect2 = sprite_state.get("region_rect", Rect2())
	var scale: Vector2 = _normalize_scale(sprite_state.get("scale", Vector2.ONE))

	if item_data.sprite_col >= 0:
		if texture == null and item_data.hud_texture_path != "":
			texture = ResourceLoader.load(item_data.hud_texture_path, "", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D
		region_enabled = true
		region_rect = Rect2(item_data.sprite_col * 64.0, 0.0, 64.0, 64.0)
	elif texture == null:
		var fallback_path := item_data.mob_texture_path if item_data.mob_texture_path != "" else item_data.hud_texture_path
		if fallback_path != "":
			texture = ResourceLoader.load(fallback_path, "", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D
		region_enabled = false
		region_rect = Rect2()

	return _make_preview(texture, region_enabled, region_rect, scale)


func _build_waist_preview(item_data: ItemData) -> Dictionary:
	var texture: Texture2D = null
	var region_enabled := false
	var region_rect := Rect2()
	var scale := Vector2.ONE

	if item_data.mob_texture_path != "":
		texture = ResourceLoader.load(item_data.mob_texture_path, "", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D
	elif item_data.hud_texture_path != "":
		texture = ResourceLoader.load(item_data.hud_texture_path, "", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D

	if item_data.sprite_col >= 0:
		region_enabled = true
		region_rect = Rect2(item_data.sprite_col * 64.0, 0.0, 64.0, 64.0)
		scale = Vector2.ONE * item_data.waist_sprite_scale

	return _make_preview(texture, region_enabled, region_rect, scale)


func _build_clothing_preview(item_data: ItemData) -> Dictionary:
	var texture: Texture2D = null
	if item_data.mob_texture_path != "":
		texture = ResourceLoader.load(item_data.mob_texture_path, "", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D

	return {
		"texture": texture,
		"frame_size": Vector2(32.0, 32.0),
	}


func _extract_scene_sprite_state(scene_path: String) -> Dictionary:
	var result := {
		"texture": null,
		"region_enabled": false,
		"region_rect": Rect2(),
		"scale": Vector2.ONE,
	}
	if scene_path == "":
		return result

	var scene := ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if scene == null:
		return result

	var state := scene.get_state()
	for i in range(state.get_node_count()):
		if String(state.get_node_name(i)) != "Sprite2D":
			continue
		for j in range(state.get_node_property_count(i)):
			var property_name := String(state.get_node_property_name(i, j))
			var value = state.get_node_property_value(i, j)
			match property_name:
				"texture":
					result["texture"] = value
				"region_enabled":
					result["region_enabled"] = bool(value)
				"region_rect":
					result["region_rect"] = value
				"scale":
					result["scale"] = value
		break

	return result


func _make_preview(texture: Texture2D, region_enabled: bool, region_rect: Rect2, scale: Vector2) -> Dictionary:
	return {
		"texture": texture,
		"region_enabled": region_enabled,
		"region_rect": region_rect,
		"scale": _normalize_scale(scale),
	}


func _normalize_scale(value: Variant) -> Vector2:
	if value is Vector2:
		var scale := value as Vector2
		return Vector2(maxf(absf(scale.x), 0.001), maxf(absf(scale.y), 0.001))
	return Vector2.ONE
