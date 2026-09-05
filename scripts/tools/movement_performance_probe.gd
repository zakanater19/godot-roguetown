extends Node

# Run with: godot --headless --path . res://scripts/tools/movement_performance_probe.tscn -- --benchmark-movement
# Keeps the local scene fixed while adding distant tree-like entities.
class ProbeMain:
	extends "res://scripts/core/main.gd"

	func _ready() -> void:
		pass

	func _process(_delta: float) -> void:
		pass

class ProbeTree:
	extends WorldObject

	var slow_multiplier: float = 1.5

	func get_runtime_groups() -> Array[String]:
		return [Defs.GROUP_CHOPPABLE]

	func get_movement_slow_multiplier() -> float:
		return slow_multiplier

var _main: Node2D
var _player: Node2D
var _failures: int = 0

func _ready() -> void:
	if OS.get_cmdline_user_args().has("--benchmark-movement"):
		call_deferred("_run")

func _run() -> void:
	_main = ProbeMain.new()
	add_child(_main)
	World.register_main(_main)
	_player = Node2D.new()
	_main.add_child(_player)
	for y in range(90, 111):
		for x in range(90, 111):
			_add_tree(Vector2i(x, y))
	await get_tree().process_frame
	_benchmark(0)
	for count in [1000, 10000, 50000]:
		var previous: int = 0 if count == 1000 else (1000 if count == 10000 else 10000)
		for i in range(previous, count):
			_add_tree(Vector2i(300 + i % 500, 300 + floori(float(i) / 500.0)))
		await get_tree().process_frame
		_benchmark(count)
	await _validate_index_lifecycle()
	_main.free()
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)

func _validate_index_lifecycle() -> void:
	var start := Vector2i(40, 40)
	var destination := Vector2i(56, 56)
	var tree := _add_tree(start)
	tree.position = Defs.tile_to_pixel(destination)
	await get_tree().process_frame
	_check(World.get_tile_movement_multiplier(start, 3) == 1.0, "moving removes old slowdown")
	_check(World.get_tile_movement_multiplier(destination, 3) == 1.5, "moving adds new slowdown across chunk boundary")
	tree.set("z_level", 4)
	_check(World.get_tile_movement_multiplier(destination, 3) == 1.0, "Z changes do not leave old slowdown")
	_check(World.get_tile_movement_multiplier(destination, 4) == 1.5, "Z changes keep new slowdown")
	tree.set("slow_multiplier", 2.0)
	_check(World.get_tile_movement_multiplier(destination, 4) == 2.0, "state changes are immediately reflected")
	var entity_id := World.get_entity_id(tree)
	tree.free()
	_check(World.get_tile_movement_multiplier(destination, 4) == 1.0, "freeing removes slowdown")
	_check(not World._entity_registry.has(entity_id), "unloading removes registry entry")
	var rect := WorldStream.window_at(Vector2i.ZERO)
	_check(rect.has_point(Vector2i(-50, -50)) and rect.has_point(Vector2i(50, 50)), "50 tile square includes corners")
	_check(not rect.has_point(Vector2i(51, 0)), "51st tile is outside")
	var area := 0
	for part in WorldStream.difference(WorldStream.window_at(Vector2i.ONE), rect):
		area += part.get_area()
	_check(area == 201, "diagonal step sends only entering strips")
	print("MOVEMENT_REGRESSION failures=%d" % _failures)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("MOVEMENT_REGRESSION: " + message)

func _add_tree(tile: Vector2i) -> Node2D:
	var tree := ProbeTree.new()
	tree.position = Defs.tile_to_pixel(tile)
	_main.add_child(tree)
	return tree

func _benchmark(distant_count: int) -> void:
	var render_us: Array[int] = []
	var movement_us: Array[int] = []
	for step in range(44):
		var tile := Vector2i(100 + step % 2, 100)
		_player.position = Defs.tile_to_pixel(tile)
		var start := Time.get_ticks_usec()
		WorldStream.index.query(WorldStream.window_at(tile))
		var after_render := Time.get_ticks_usec()
		World.get_tile_movement_multiplier(tile, 3)
		var after_movement := Time.get_ticks_usec()
		if step >= 4:
			render_us.append(after_render - start)
			movement_us.append(after_movement - after_render)
	render_us.sort()
	movement_us.sort()
	print("MOVEMENT_BENCH distant=%d local=441 window_query_median_us=%d window_query_p95_us=%d terrain_median_us=%d terrain_p95_us=%d" % [
		distant_count, render_us[20], render_us[37], movement_us[20], movement_us[37]])
