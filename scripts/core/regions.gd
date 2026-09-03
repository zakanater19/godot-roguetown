extends Node

const REGION_LAYER_PREFIX: String = "RegionMapLayer_Z"

const NONE: StringName = &""
const TOWN: StringName = &"town"

const REGION_DEFINITIONS: Dictionary = {
	TOWN: {
		"source_id": 0,
		"atlas_coords": Vector2i(0, 0),
		"allows_grass_decor": false,
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
	var region_name := get_region_at(map_root, tile_pos, z_level)
	if region_name == NONE:
		return true
	return bool(REGION_DEFINITIONS[region_name].get("allows_grass_decor", true))
