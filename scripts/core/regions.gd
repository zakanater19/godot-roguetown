extends Node

const REGION_LAYER_PREFIX: String = "RegionMapLayer_Z"

const NONE: StringName = &""
const TOWN: StringName = &"town"
const TAME_WILDS: StringName = &"tame wilds"

const REGION_DEFINITIONS: Dictionary = {
	TAME_WILDS: {
		"source_id": 1,
		"atlas_coords": Vector2i.ZERO,
		"allows_grass_decor": true,
		"allows_bushes": true,
		"tree_chance": 0.05,
		"grass_chance": 0.10,
		"bush_chance": 0.02,
	},
	TOWN: {
		"source_id": 0,
		"atlas_coords": Vector2i(0, 0),
		"allows_grass_decor": false,
		"allows_bushes": false,
	},
}


func get_region_at(map_root: Node, tile_pos: Vector2i, z_level: int) -> StringName:
	if map_root == null:
		return NONE
	var region_layer := map_root.get_node_or_null(REGION_LAYER_PREFIX + str(z_level)) as TileMapLayer
	if region_layer == null:
		return NONE

	var source_id := region_layer.get_cell_source_id(tile_pos)
	var atlas_coords := region_layer.get_cell_atlas_coords(tile_pos)
	for region_name: StringName in REGION_DEFINITIONS:
		var definition: Dictionary = REGION_DEFINITIONS[region_name]
		if source_id == int(definition["source_id"]) and atlas_coords == Vector2i(definition["atlas_coords"]):
			return region_name
	return NONE


func allows_grass_decor_at(map_root: Node, tile_pos: Vector2i, z_level: int) -> bool:
	return _allows_feature_at(map_root, tile_pos, z_level, "allows_grass_decor")


func allows_bushes_at(map_root: Node, tile_pos: Vector2i, z_level: int) -> bool:
	return _allows_feature_at(map_root, tile_pos, z_level, "allows_bushes")


func _allows_feature_at(map_root: Node, tile_pos: Vector2i, z_level: int, feature: String) -> bool:
	var region_name := get_region_at(map_root, tile_pos, z_level)
	if region_name == NONE:
		return false
	return bool(REGION_DEFINITIONS[region_name].get(feature, false))
const TREE_SCENE: PackedScene = preload("res://objects/tree_spawn.tscn")
const BUSH_SCENE: PackedScene = preload("res://objects/bush.tscn")
const LAYOUT_RECORD_SIZE: int = 5 # z, x, y, kind (tree/grass/bush), variant/seed
const GENERATION_VERSION: int = 1

func create_generation_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return int(rng.randi()) + 1

func populate_runtime_features(map_root: Node, seed_value: int) -> void:
	if not map_root.multiplayer.is_server():
		return
	var occupied: Dictionary = {1: {}, 2: {}, 3: {}, 4: {}, 5: {}}
	for child in map_root.get_children():
		if not (child is Node2D) or child.get("z_level") == null:
			continue
		var z := clampi(int(child.get("z_level")), 1, 5)
		occupied[z][Defs.world_to_tile(child.global_position)] = true
		if child.has_method("get_solid_tiles"):
			for cell in child.call("get_solid_tiles"):
				occupied[z][Vector2i(cell)] = true
	var layout := PackedInt32Array()
	for z in range(1, 6):
		var layer := map_root.get_node_or_null(REGION_LAYER_PREFIX + str(z)) as TileMapLayer
		var terrain := map_root.get_node_or_null("TileMapLayer_Z" + str(z)) as TileMapLayer
		if layer == null or terrain == null:
			continue
		var definition: Dictionary = REGION_DEFINITIONS[TAME_WILDS]
		var cells := layer.get_used_cells_by_id(int(definition["source_id"]), definition["atlas_coords"])
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.y < b.y if a.y != b.y else a.x < b.x
		)
		for cell in cells:
			if occupied[z].has(cell) or terrain.get_cell_source_id(cell) != 0 or terrain.get_cell_atlas_coords(cell) != Vector2i.ZERO:
				continue
			var roll := _foliage_hash(seed_value, cell, z, 0) % 10000
			var kind := -1
			var tree_limit := roundi(float(definition["tree_chance"]) * 10000)
			var grass_limit := tree_limit + roundi(float(definition["grass_chance"]) * 10000)
			var bush_limit := grass_limit + roundi(float(definition["bush_chance"]) * 10000)
			if roll < tree_limit:
				kind = 0
			elif roll < grass_limit:
				kind = 1
			elif roll < bush_limit:
				kind = 2
			if kind < 0:
				continue
			var variant := _foliage_hash(seed_value, cell, z, 1)
			if kind == 1:
				variant %= 8
			layout.append_array(PackedInt32Array([z, cell.x, cell.y, kind, variant]))
	map_root.set_meta("region_seed", seed_value)
	map_root.set_meta("region_layout", layout)
	_build_layout(map_root, layout)

func _foliage_hash(seed_value: int, cell: Vector2i, z: int, salt: int) -> int:
	var value := (seed_value ^ (cell.x * 73856093) ^ (cell.y * 19349663) ^ (z * 83492791) ^ (salt * 2654435761)) & 0x7fffffff
	value = ((value ^ (value >> 16)) * 1103515245 + 12345) & 0x7fffffff
	return value ^ (value >> 16)

func _build_layout(map_root: Node, layout: PackedInt32Array) -> void:
	for cursor in range(0, layout.size(), LAYOUT_RECORD_SIZE):
		var z := layout[cursor]
		var cell := Vector2i(layout[cursor + 1], layout[cursor + 2])
		var kind := layout[cursor + 3]
		var variant := layout[cursor + 4]
		if kind == 1:
			map_root._grass_decor_layers[z].set_cell(cell, 0, Vector2i(variant, 0))
			continue
		var node := (TREE_SCENE if kind == 0 else BUSH_SCENE).instantiate() as Node2D
		node.name = "Region%s_Z%d_X%d_Y%d" % ["Tree" if kind == 0 else "Bush", z, cell.x, cell.y]
		node.position = Defs.tile_to_pixel(cell)
		node.set("z_level", z)
		node.set_meta("region_generated", true)
		if kind == 0:
			node.set("manual_runtime_spawn", true)
			node.set("seed_override", variant + 1)
		else:
			node.set_meta("entity_id", "world:%s" % node.name)
		map_root.add_child(node)
		if kind == 0:
			node.call("_spawn_runtime_tree")
		else:
			register_generated_object(map_root, node)

func register_generated_object(map_root: Node, node: Node2D) -> void:
	var entity_id := World.register_entity(node, "world:%s" % node.name)
	map_root.region_generation_baseline[entity_id] = {
		"position": node.position,
		"z_level": node.get("z_level"),
		"state": node.call("capture_authoritative_state"),
	}

func capture_generation_snapshot(map_root: Node) -> Dictionary:
	var removed: Array[String] = []
	var overrides: Dictionary = {}
	for entity_id: String in map_root.region_generation_baseline:
		var node := World.get_entity(entity_id) as Node2D
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			removed.append(entity_id)
			continue
		var initial: Dictionary = map_root.region_generation_baseline[entity_id]
		var state: Dictionary = node.call("capture_authoritative_state")
		var changed: Dictionary = {}
		for field: String in state:
			if state[field] != initial["state"].get(field):
				changed[field] = state[field]
		if not changed.is_empty() or node.position != initial["position"] or node.get("z_level") != initial["z_level"]:
			overrides[entity_id] = {"state": changed, "position": node.position, "z_level": node.get("z_level")}
	return {
		"version": GENERATION_VERSION,
		"seed": map_root.get_meta("region_seed", 0),
		"layout": map_root.get_meta("region_layout", PackedInt32Array()),
		"removed": removed, "overrides": overrides,
		"grass_cuts": map_root._region_grass_cuts.keys(),
	}

func apply_generation_snapshot(map_root: Node, snapshot: Dictionary) -> void:
	for entity_id: String in map_root.region_generation_baseline:
		var node := World.get_entity(entity_id)
		if is_instance_valid(node):
			node.free()
	map_root.region_generation_baseline.clear()
	map_root._region_grass_cuts.clear()
	for layer: TileMapLayer in map_root._grass_decor_layers.values():
		layer.clear()
	map_root.set_meta("region_seed", int(snapshot.get("seed", 0)))
	var layout: PackedInt32Array = snapshot.get("layout", PackedInt32Array())
	map_root.set_meta("region_layout", layout)
	# Reproduce the cached server placement plan, even if terrain has since changed.
	_build_layout(map_root, layout)
	for entity_id: String in snapshot.get("removed", []):
		var node := World.get_entity(entity_id)
		if is_instance_valid(node):
			node.free()
	for entity_id: String in snapshot.get("overrides", {}):
		var node := World.get_entity(entity_id) as Node2D
		if not is_instance_valid(node):
			continue
		var entry: Dictionary = snapshot["overrides"][entity_id]
		node.position = entry["position"]
		node.set("z_level", entry["z_level"])
		node.call("apply_authoritative_state", entry["state"])
	for cut: Vector3i in snapshot.get("grass_cuts", []):
		map_root.remove_runtime_grass_decor(Vector2i(cut.x, cut.y), cut.z)

func validate_generation_snapshot(snapshot: Dictionary) -> bool:
	if int(snapshot.get("version", -1)) != GENERATION_VERSION or not (snapshot.get("layout") is PackedInt32Array):
		return false
	var layout: PackedInt32Array = snapshot["layout"]
	if layout.size() % LAYOUT_RECORD_SIZE != 0:
		return false
	for cursor in range(0, layout.size(), LAYOUT_RECORD_SIZE):
		if layout[cursor] < 1 or layout[cursor] > 5 or layout[cursor + 3] < 0 or layout[cursor + 3] > 2:
			return false
	return snapshot.get("removed") is Array and snapshot.get("overrides") is Dictionary and snapshot.get("grass_cuts") is Array
