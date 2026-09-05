extends RefCounted

# Static scenery costs nothing per frame. Only transformed entities change buckets.
const CHUNK_SIZE: int = 16
var nodes: Dictionary = {}
var tiles: Dictionary = {}
var chunks: Dictionary = {}
var modifiers: Dictionary = {}

func clear() -> void:
	nodes.clear()
	tiles.clear()
	chunks.clear()
	modifiers.clear()

func chunk_at(tile: Vector2i) -> Vector2i:
	return Vector2i(floori(float(tile.x) / CHUNK_SIZE), floori(float(tile.y) / CHUNK_SIZE))

func insert(node: Node2D) -> void:
	var id := node.get_instance_id()
	if nodes.has(id):
		update(node)
		return
	nodes[id] = node
	_add_tile(id, Defs.world_to_tile(node.global_position))

func erase(node: Node2D) -> void:
	var id := node.get_instance_id()
	if not nodes.has(id):
		return
	_remove_tile(id)
	nodes.erase(id)

func update(node: Node2D) -> bool:
	var id := node.get_instance_id()
	if not nodes.has(id):
		return false
	var tile := Defs.world_to_tile(node.global_position)
	if tiles[id] == tile:
		return false
	_remove_tile(id)
	_add_tile(id, tile)
	return true

func _add_tile(id: int, tile: Vector2i) -> void:
	tiles[id] = tile
	var chunk := chunk_at(tile)
	if not chunks.has(chunk):
		chunks[chunk] = {}
	chunks[chunk][id] = nodes[id]
	if nodes[id].has_method("get_movement_slow_multiplier"):
		if not modifiers.has(tile):
			modifiers[tile] = {}
		modifiers[tile][id] = nodes[id]

func _remove_tile(id: int) -> void:
	var tile: Vector2i = tiles[id]
	var chunk := chunk_at(tile)
	chunks[chunk].erase(id)
	if chunks[chunk].is_empty():
		chunks.erase(chunk)
	if modifiers.has(tile):
		modifiers[tile].erase(id)
		if modifiers[tile].is_empty():
			modifiers.erase(tile)
	tiles.erase(id)

func query(rect: Rect2i) -> Dictionary:
	var result: Dictionary = {}
	if not rect.has_area():
		return result
	var first := chunk_at(rect.position)
	var last := chunk_at(rect.end - Vector2i.ONE)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var bucket: Dictionary = chunks.get(Vector2i(x, y), {})
			for id: int in bucket:
				if rect.has_point(tiles[id]):
					var node: Node2D = bucket[id]
					if is_instance_valid(node) and not node.is_queued_for_deletion():
						result[id] = node
	return result

func movement_multiplier(tile: Vector2i, z_level: int, map_root: Node) -> float:
	var result := 1.0
	var bucket: Dictionary = modifiers.get(tile, {})
	for node: Node2D in bucket.values():
		if is_instance_valid(node) and not node.is_queued_for_deletion() and node.get_parent() == map_root and int(node.get("z_level")) == z_level:
			result = maxf(result, float(node.call("get_movement_slow_multiplier")))
	return result
