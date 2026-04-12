class_name ObjectSpawnUtils
extends RefCounted

const DROP_ITEM_TYPES: Dictionary = {
	"pebble": "Pebble",
	"coal": "Coal",
	"goldore": "GoldOre",
	"ironore": "IronOre",
	"goldingot": "GoldIngot",
	"log": "Log",
	"ironingot": "IronIngot",
}

static func instantiate_item_type(item_type: String) -> Node2D:
	var scene_path := ItemRegistry.get_scene_path(item_type)
	if scene_path.is_empty():
		return null
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return null
	return scene.instantiate() as Node2D

static func instantiate_drop(drop_type: String) -> Node2D:
	var item_type := String(DROP_ITEM_TYPES.get(drop_type, ""))
	if item_type.is_empty():
		return null
	return instantiate_item_type(item_type)

static func spawn_node(parent: Node, obj: Node2D, node_name: String, z_level: int, global_position: Vector2, entity_id: String = "") -> Node2D:
	if parent == null or obj == null:
		return null

	obj.name = node_name
	if "z_level" in obj:
		obj.set("z_level", z_level)
	if not entity_id.is_empty():
		obj.set_meta("entity_id", entity_id)

	parent.add_child(obj)
	obj.global_position = global_position

	if not entity_id.is_empty():
		World.register_entity(obj, entity_id)
	return obj

static func spawn_item_type(parent: Node, item_type: String, node_name: String, z_level: int, global_position: Vector2, entity_id: String = "") -> Node2D:
	var obj := instantiate_item_type(item_type)
	return spawn_node(parent, obj, node_name, z_level, global_position, entity_id)

static func spawn_drop_with_seed(parent: Node, drop_type: String, node_name: String, z_level: int, center: Vector2, spread: float) -> Node2D:
	var obj := instantiate_drop(drop_type)
	if obj == null:
		return null

	var rng := RandomNumberGenerator.new()
	rng.seed = node_name.hash()
	var offset := Vector2(
		rng.randf_range(-spread, spread),
		rng.randf_range(-spread, spread)
	)
	return spawn_node(parent, obj, node_name, z_level, center + offset)
