# res://scripts/world/objects/world_loot.gd
extends RefCounted

var world: Node

func _init(p_world: Node) -> void:
	world = p_world

func handle_rpc_notify_loot_warning(target_path: NodePath, looter_peer_id: int, item_desc: String) -> void:
	if not world.multiplayer.is_server(): return
	var looter: Node2D = world.utils.find_player_by_peer(looter_peer_id) as Node2D
	if looter == null or looter.dead: return

	var target = world.get_node_or_null(target_path)
	if target == null: return
	var target_peer_id = target.get_multiplayer_authority() if target.is_in_group("player") and target.get("is_possessed") == true else -1

	if target_peer_id == 1: world.rpc_deliver_loot_warning(looter_peer_id, item_desc)
	elif target_peer_id in world.multiplayer.get_peers(): world.rpc_deliver_loot_warning.rpc_id(target_peer_id, looter_peer_id, item_desc)

func handle_rpc_deliver_loot_warning(looter_peer_id: int, item_desc: String) -> void:
	var local_player: Node2D = world.utils.get_local_player() as Node2D
	if local_player != null and local_player.has_method("show_loot_warning"):
		local_player.show_loot_warning(looter_peer_id, item_desc)

func handle_rpc_request_loot_item(sender_id: int, target_path: NodePath, looter_peer_id: int, slot_type: String, slot_index: Variant) -> void:
	if not world.multiplayer.is_server() or sender_id != looter_peer_id: return
	var target: Node2D = world.get_node_or_null(target_path) as Node2D
	var looter: Node2D = world.utils.find_player_by_peer(looter_peer_id) as Node2D
	if target == null or looter == null or looter.dead: return
	var diff: Vector2i = (target.tile_pos - looter.tile_pos).abs()
	if diff.x > 1 or diff.y > 1 or target.z_level != looter.z_level: return

	var drop_tile: Vector2i = target.tile_pos
	const SPREAD: float = 14.0

	if slot_type == "hand":
		var idx: int  = int(slot_index)
		var obj: Node = target.hands[idx]
		if obj == null or not is_instance_valid(obj): return
		world.rpc_drop_item_at.rpc(target_path, obj.get_path(), drop_tile, SPREAD, idx)
	elif slot_type == "equip":
		var equip_slot: String = str(slot_index)
		var item_name: String  = target.equipped.get(equip_slot, "")
		if item_name == "": return
		var new_name := "Loot_" + equip_slot + "_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000)
		world.rpc_confirm_loot_unequip_drop.rpc(target_path, equip_slot, new_name, drop_tile, SPREAD)

func handle_rpc_confirm_loot_unequip_drop(target_path: NodePath, equip_slot: String, new_node_name: String, drop_tile: Vector2i, spread: float) -> void:
	var target: Node2D = world.get_node_or_null(target_path) as Node2D
	if target == null: return
	var item_name: String = target.equipped.get(equip_slot, "")
	if item_name == "": return

	var scene_path = ""
	if world.has_node("/root/ItemRegistry"):
		scene_path = world.get_node("/root/ItemRegistry").get_scene_path(item_name)
	if scene_path == "": return
	var scene := load(scene_path) as PackedScene
	if scene == null: return

	target.equipped[equip_slot] = null
	target._update_clothing_sprites()

	if target._is_local_authority():
		if target._hud != null:
			target._hud.update_clothing_display(target.equipped)

	var item: Node2D = scene.instantiate()
	item.name        = new_node_name
	item.position    = world.utils.tile_to_pixel(drop_tile)

	var land_z = world.calculate_gravity_z(drop_tile, target.z_level)
	item.set("z_level", land_z)

	if "equipped_data" in target and target.equipped_data.get(equip_slot) != null:
		var edata = target.equipped_data[equip_slot]
		if "contents" in edata and "contents" in item:
			item.set("contents", edata["contents"].duplicate(true))
		if "amount" in edata and "amount" in item:
			item.set("amount", edata["amount"])
		if "metal_type" in edata and "metal_type" in item:
			item.set("metal_type", edata["metal_type"])
		target.equipped_data[equip_slot] = null

	target.get_parent().add_child(item)
	world.objects.drop_item_at(item, drop_tile, spread)
	for child in item.get_children():
		if child is CollisionShape2D: child.disabled = false
