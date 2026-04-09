@tool
extends Node2D

const TREE_SEGMENT_SCENE: PackedScene = preload("res://objects/tree_segment.tscn")

const BRANCH_OPTIONS: Array = [
	{
		"name": "south",
		"tile_offset": Vector2i(0, 1),
		"atlas_index": 19,
	},
	{
		"name": "north",
		"tile_offset": Vector2i(0, -1),
		"atlas_index": 20,
	},
	{
		"name": "east",
		"tile_offset": Vector2i(1, 0),
		"atlas_index": 21,
	},
	{
		"name": "west",
		"tile_offset": Vector2i(-1, 0),
		"atlas_index": 22,
	},
]

const LEAF_ATLAS_INDICES: Array[int] = [
	0, 1,
	2, 3, 4, 5, 6, 7, 8, 9,
	10, 11, 12, 13, 14, 15, 16, 17,
]
const CANOPY_RING_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
	Vector2i(1, 1),
]
const LEAF_Z_OFFSET: int = Defs.Z_OFFSET_ITEMS - 1

@export var z_level: int = 3
@export var seed_override: int = 0

@onready var preview: Sprite2D = $Preview

func _ready() -> void:
	_update_preview()
	if Engine.is_editor_hint():
		return

	if preview != null:
		preview.visible = false

	call_deferred("_spawn_runtime_tree")

func _spawn_runtime_tree() -> void:
	if not is_inside_tree():
		return

	var parent_node: Node = get_parent()
	if parent_node == null:
		return

	var base_z: int = clampi(z_level, 1, 5)
	var anchor_tile: Vector2i = Defs.world_to_tile(global_position)
	var tree_key: String = "TreeSpawn"
	var node_name: String = String(name)
	if node_name != "":
		tree_key = node_name

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _resolve_seed(anchor_tile)

	var trunk_names: Dictionary = {}
	var trunk_levels: Array[int] = []
	for offset in range(3):
		var piece_z: int = base_z + offset
		if piece_z > 5:
			break
		trunk_levels.append(piece_z)
		trunk_names[piece_z] = _piece_name(tree_key, "trunk_z%d" % piece_z)

	var lower_branch_idx: int = rng.randi_range(0, BRANCH_OPTIONS.size() - 1)
	var lower_branch: Dictionary = BRANCH_OPTIONS[lower_branch_idx]
	var upper_branch: Dictionary = BRANCH_OPTIONS[_get_opposite_branch_index(lower_branch_idx)]
	var upper_branch_level: int = -1

	if trunk_levels.size() > 1:
		upper_branch_level = trunk_levels.back()
		if trunk_levels.size() > 2 and rng.randf() < 0.5:
			upper_branch_level = trunk_levels[1]

	for piece_z in trunk_levels:
		var support_name: String = ""
		if piece_z > base_z and trunk_names.has(piece_z - 1):
			support_name = String(trunk_names[piece_z - 1])

		_spawn_segment(parent_node, {
			"tree_key": tree_key,
			"piece_name": String(trunk_names[piece_z]),
			"piece_z": piece_z,
			"tile_pos": anchor_tile,
			"support_name": support_name,
			"piece_kind": "trunk",
			"atlas_index": 18,
			"break_hits": 5.0,
			"log_drop_count": 2,
			"solid_piece": true,
			"blocks_fov": true,
			"decor_configs": [],
		})

	var lower_branch_name: String = _piece_name(
		tree_key,
		"branch_%s_z%d" % [lower_branch["name"], base_z]
	)
	var canopy_branch_infos: Array = [{
		"piece_name": lower_branch_name,
		"tile_offset": Vector2i(lower_branch["tile_offset"]),
	}]
	var upper_branch_name: String = ""
	if upper_branch_level != -1:
		upper_branch_name = _piece_name(
			tree_key,
			"branch_%s_z%d" % [upper_branch["name"], upper_branch_level]
		)
		canopy_branch_infos.append({
			"piece_name": upper_branch_name,
			"tile_offset": Vector2i(upper_branch["tile_offset"]),
		})

	var leaf_z_levels: Array[int] = []
	for leaf_z in [4, 5]:
		if leaf_z > base_z:
			leaf_z_levels.append(leaf_z)

	var canopy_configs_by_branch: Dictionary = _make_canopy_branch_leaf_configs(
		rng,
		canopy_branch_infos,
		leaf_z_levels
	)
	_spawn_segment(parent_node, {
		"tree_key": tree_key,
		"piece_name": lower_branch_name,
		"piece_z": base_z,
		"tile_pos": anchor_tile + lower_branch["tile_offset"],
		"support_name": String(trunk_names[base_z]),
		"piece_kind": "branch",
		"atlas_index": int(lower_branch["atlas_index"]),
		"break_hits": 2.0,
		"log_drop_count": 0,
		"solid_piece": false,
		"blocks_fov": false,
		"decor_configs": canopy_configs_by_branch.get(lower_branch_name, []).duplicate(true),
	})

	if upper_branch_level != -1:
		var upper_support_name: String = String(trunk_names[upper_branch_level])
		_spawn_segment(parent_node, {
			"tree_key": tree_key,
			"piece_name": upper_branch_name,
			"piece_z": upper_branch_level,
			"tile_pos": anchor_tile + upper_branch["tile_offset"],
			"support_name": upper_support_name,
			"piece_kind": "branch",
			"atlas_index": int(upper_branch["atlas_index"]),
			"break_hits": 2.0,
			"log_drop_count": 0,
			"solid_piece": false,
			"blocks_fov": false,
			"decor_configs": canopy_configs_by_branch.get(upper_branch_name, []).duplicate(true),
		})

	queue_free()

func _spawn_segment(parent_node: Node, segment_config: Dictionary) -> void:
	var piece_name: String = String(segment_config["piece_name"])
	if parent_node.get_node_or_null(piece_name) != null:
		return

	var segment: TreeSegment = TREE_SEGMENT_SCENE.instantiate() as TreeSegment
	var tile_pos: Vector2i = Vector2i(segment_config["tile_pos"])
	segment.name = piece_name
	segment.tree_id = String(segment_config["tree_key"])
	segment.z_level = int(segment_config["piece_z"])
	segment.position = Defs.tile_to_pixel(tile_pos)
	segment.support_segment_name = String(segment_config["support_name"])
	segment.piece_kind = String(segment_config["piece_kind"])
	segment.atlas_index = int(segment_config["atlas_index"])
	segment.hits_to_break = float(segment_config["break_hits"])
	segment.drop_count = int(segment_config["log_drop_count"])
	segment.solid_piece = bool(segment_config.get("solid_piece", true))
	segment.blocks_fov = bool(segment_config.get("blocks_fov", true))
	segment.decor_configs = segment_config["decor_configs"].duplicate(true)
	parent_node.add_child(segment)

func _make_canopy_branch_leaf_configs(
	rng: RandomNumberGenerator,
	branch_infos: Array,
	leaf_z_levels: Array[int]
) -> Dictionary:
	var configs_by_branch: Dictionary = {}
	for branch_info in branch_infos:
		configs_by_branch[String(branch_info["piece_name"])] = []

	if branch_infos.is_empty() or leaf_z_levels.is_empty():
		return configs_by_branch

	for leaf_level_idx in range(leaf_z_levels.size()):
		var leaf_z: int = leaf_z_levels[leaf_level_idx]
		var ordered_branch_infos: Array = branch_infos.duplicate(true)
		if leaf_level_idx % 2 == 1:
			ordered_branch_infos.reverse()

		for canopy_offset in CANOPY_RING_OFFSETS:
			for branch_info in ordered_branch_infos:
				var branch_tile_offset: Vector2i = Vector2i(branch_info["tile_offset"])
				var relative_offset: Vector2i = canopy_offset - branch_tile_offset
				if abs(relative_offset.x) > 1 or abs(relative_offset.y) > 1:
					continue

				var branch_name: String = String(branch_info["piece_name"])
				var branch_configs: Array = configs_by_branch.get(branch_name, [])
				branch_configs.append({
					"tile_offset": relative_offset,
					"z_level": leaf_z,
					"atlas_index": _pick_leaf_atlas_index(rng),
					"z_offset": LEAF_Z_OFFSET,
					"blocks_fov": false,
				})
				configs_by_branch[branch_name] = branch_configs
				break

	return configs_by_branch

func _get_opposite_branch_index(branch_idx: int) -> int:
	match branch_idx:
		0:
			return 1
		1:
			return 0
		2:
			return 3
		_:
			return 2

func _pick_leaf_atlas_index(rng: RandomNumberGenerator) -> int:
	return LEAF_ATLAS_INDICES[rng.randi_range(0, LEAF_ATLAS_INDICES.size() - 1)]

func _piece_name(tree_key: String, suffix: String) -> String:
	return "%s__%s" % [tree_key, suffix]

func _resolve_seed(anchor_tile: Vector2i) -> int:
	if seed_override != 0:
		return seed_override
	return name.hash() ^ (anchor_tile.x * 73856093) ^ (anchor_tile.y * 19349663) ^ (z_level * 83492791)

func _update_preview() -> void:
	if preview == null:
		return
	preview.visible = Engine.is_editor_hint()
	preview.z_index = Defs.get_z_index(clampi(z_level, 1, 5), Defs.Z_OFFSET_ITEMS)
