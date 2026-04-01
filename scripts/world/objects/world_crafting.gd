# res://scripts/world/objects/world_crafting.gd
# Server-side crafting handler. Recipe definitions live in res://recipes/ as
# RecipeData .tres files — add new ones there without touching any code.
extends RefCounted

var world: Node

func _init(p_world: Node) -> void:
	world = p_world

func handle_rpc_request_craft(sender_id: int, looter_peer_id: int, recipe_id: String) -> void:
	if not world.multiplayer.is_server() or sender_id != looter_peer_id: return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if player == null or player.dead: return

	var recipe: RecipeData = RecipeRegistry.get_recipe(recipe_id)
	if recipe == null: return

	# Gather nearby items (hands + adjacent ground tiles).
	var avail: Array = []
	for i in range(2):
		if player.hands[i] != null: avail.append(player.hands[i])
	for obj in world.get_tree().get_nodes_in_group(Defs.GROUP_PICKABLE):
		if obj == player.hands[0] or obj == player.hands[1]: continue
		if obj.get("z_level") != null and obj.z_level != player.z_level: continue
		var obj_tile := Vector2i(int(obj.global_position.x / world.TILE_SIZE), int(obj.global_position.y / world.TILE_SIZE))
		var diff: Vector2i = (obj_tile - player.tile_pos).abs()
		if diff.x <= 1 and diff.y <= 1:
			avail.append(obj)

	# Collect the required ingredients.
	var matched_nodes: Array = []
	for obj in avail:
		if matched_nodes.size() >= recipe.req_amount: break
		var itype: String = obj.get("item_type") if obj.get("item_type") != null else obj.name.get_slice("@", 0)
		if itype == recipe.req_item:
			matched_nodes.append(obj)
	if matched_nodes.size() < recipe.req_amount: return

	var result_name := "Craft_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000)
	var consumed_paths: Array = []
	for n in matched_nodes:
		consumed_paths.append(n.get_path())

	if recipe.result_type == Defs.RECIPE_RESULT_ITEM:
		world.rpc_confirm_craft_item.rpc(sender_id, consumed_paths, recipe.result_scene_path, result_name, player.tile_pos)
	elif recipe.result_type == Defs.RECIPE_RESULT_TILE:
		world.rpc_confirm_craft_tile.rpc(sender_id, consumed_paths, player.tile_pos, player.z_level, recipe.result_tile_source, recipe.result_tile_coords)

func handle_rpc_confirm_craft_item(peer_id: int, consumed_paths: Array, scene_path: String, result_name: String, drop_tile: Vector2i) -> void:
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	for p in consumed_paths:
		var n = world.get_node_or_null(p)
		if n != null:
			if player != null:
				for i in range(2):
					if player.hands[i] == n:
						player.hands[i] = null
						if player._is_local_authority(): player._update_hands_ui()
						break
			n.queue_free()

	var scene := load(scene_path) as PackedScene
	if scene == null: return
	var item: Node2D = scene.instantiate()
	item.name = result_name

	if player != null:
		var land_z: int = world.calculate_gravity_z(drop_tile, player.z_level)
		item.set("z_level", land_z)

	var main = world.get_tree().root.get_node_or_null("Main")
	if main:
		main.add_child(item)
		world.objects.drop_item_at(item, drop_tile, 14.0)
		for child in item.get_children():
			if child is CollisionShape2D: child.disabled = false

func handle_rpc_confirm_craft_tile(peer_id: int, consumed_paths: Array, tile_pos: Vector2i, z_level: int, source_id: int, atlas_coords: Vector2i) -> void:
	for p in consumed_paths:
		var n = world.get_node_or_null(p)
		if n != null:
			var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
			if player != null:
				for i in range(2):
					if player.hands[i] == n:
						player.hands[i] = null
						if player._is_local_authority(): player._update_hands_ui()
						break
			n.queue_free()

	var tm = world.get_tilemap(z_level)
	if tm != null:
		tm.set_cell(tile_pos, source_id, atlas_coords)
		if world.has_node("/root/LateJoin"):
			world.get_node("/root/LateJoin").register_tile_change(tile_pos, z_level, source_id, atlas_coords)
