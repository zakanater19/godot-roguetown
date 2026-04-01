# res://scripts/world/world_objects.gd
# Coordinator: delegates to domain-specific sub-modules in objects/
extends RefCounted

var world: Node

var harvesting = null
var doors      = null
var items      = null
var coins      = null
var loot       = null
var crafting   = null
var storage    = null

func _init(p_world: Node) -> void:
	world      = p_world
	harvesting = preload("res://scripts/world/objects/world_harvesting.gd").new(world)
	doors      = preload("res://scripts/world/objects/world_doors.gd").new(world)
	items      = preload("res://scripts/world/objects/world_items.gd").new(world)
	coins      = preload("res://scripts/world/objects/world_coins.gd").new(world)
	loot       = preload("res://scripts/world/objects/world_loot.gd").new(world)
	crafting   = preload("res://scripts/world/objects/world_crafting.gd").new(world)
	storage    = preload("res://scripts/world/objects/world_storage.gd").new(world)

# Shared utility used by items, loot, crafting, storage sub-modules.
func drop_item_at(obj: Node2D, tile: Vector2i, spread: float) -> void:
	var drop_offset := Vector2(
		randf_range(-spread, spread),
		randf_range(-spread, spread)
	)
	obj.global_position = world.utils.tile_to_pixel(tile) + drop_offset

# ── Harvesting ────────────────────────────────────────────────────────────────
func handle_rpc_request_hit_rock(sender_id: int, rock_path: NodePath) -> void:      harvesting.handle_rpc_request_hit_rock(sender_id, rock_path)
func handle_rpc_confirm_hit_rock(rock_path: NodePath) -> void:                       harvesting.handle_rpc_confirm_hit_rock(rock_path)
func handle_rpc_confirm_break_rock(rock_path: NodePath, drops_data: Array) -> void: harvesting.handle_rpc_confirm_break_rock(rock_path, drops_data)
func handle_rpc_request_hit_tree(sender_id: int, tree_path: NodePath) -> void:      harvesting.handle_rpc_request_hit_tree(sender_id, tree_path)
func handle_rpc_confirm_hit_tree(tree_path: NodePath) -> void:                       harvesting.handle_rpc_confirm_hit_tree(tree_path)
func handle_rpc_confirm_break_tree(tree_path: NodePath, log_names: Array) -> void:  harvesting.handle_rpc_confirm_break_tree(tree_path, log_names)
func handle_rpc_request_hit_breakable(sender_id: int, obj_path: NodePath) -> void:  harvesting.handle_rpc_request_hit_breakable(sender_id, obj_path)
func handle_rpc_confirm_hit_breakable(obj_path: NodePath) -> void:                   harvesting.handle_rpc_confirm_hit_breakable(obj_path)
func handle_rpc_confirm_break_breakable(obj_path: NodePath) -> void:                 harvesting.handle_rpc_confirm_break_breakable(obj_path)

# ── Doors ─────────────────────────────────────────────────────────────────────
func handle_rpc_request_hit_door(sender_id: int, door_path: NodePath) -> void:      doors.handle_rpc_request_hit_door(sender_id, door_path)
func handle_rpc_confirm_toggle_door(door_path: NodePath) -> void:                    doors.handle_rpc_confirm_toggle_door(door_path)
func handle_rpc_confirm_hit_door(door_path: NodePath) -> void:                       doors.handle_rpc_confirm_hit_door(door_path)
func handle_rpc_confirm_destroy_door(door_path: NodePath) -> void:                   doors.handle_rpc_confirm_destroy_door(door_path)
func handle_rpc_confirm_remove_door(door_path: NodePath) -> void:                    doors.handle_rpc_confirm_remove_door(door_path)

# ── Items / Equipment / Furnace / Pickup / Drop / Throw ───────────────────────
func handle_rpc_request_interact_hand_item(sender_id: int, hand_idx: int) -> void:                                                        items.handle_rpc_request_interact_hand_item(sender_id, hand_idx)
func handle_rpc_confirm_interact_hand_item(peer_id: int, hand_idx: int) -> void:                                                          items.handle_rpc_confirm_interact_hand_item(peer_id, hand_idx)
func handle_rpc_request_equip(sender_id: int, item_path: NodePath, slot_name: String, hand_index: int) -> void:                           items.handle_rpc_request_equip(sender_id, item_path, slot_name, hand_index)
func handle_rpc_confirm_equip(peer_id: int, item_path: NodePath, slot_name: String, hand_index: int) -> void:                             items.handle_rpc_confirm_equip(peer_id, item_path, slot_name, hand_index)
func handle_rpc_request_unequip(sender_id: int, slot_name: String, hand_index: int) -> void:                                              items.handle_rpc_request_unequip(sender_id, slot_name, hand_index)
func handle_rpc_confirm_unequip(peer_id: int, slot_name: String, new_node_name: String, hand_index: int) -> void:                         items.handle_rpc_confirm_unequip(peer_id, slot_name, new_node_name, hand_index)
func handle_rpc_request_furnace_action(sender_id: int, furnace_path: NodePath, action: String, hand_idx: int) -> void:                    items.handle_rpc_request_furnace_action(sender_id, furnace_path, action, hand_idx)
func handle_rpc_confirm_furnace_action(peer_id: int, furnace_path: NodePath, action: String, hand_idx: int, generated_names: Array) -> void: items.handle_rpc_confirm_furnace_action(peer_id, furnace_path, action, hand_idx, generated_names)
func handle_rpc_request_pickup(sender_id: int, item_path: NodePath, hand_index: int) -> void:                                             items.handle_rpc_request_pickup(sender_id, item_path, hand_index)
func handle_rpc_confirm_pickup(peer_id: int, item_path: NodePath, hand_index: int) -> void:                                               items.handle_rpc_confirm_pickup(peer_id, item_path, hand_index)
func handle_rpc_request_drop(sender_id: int, item_path: NodePath, tile: Vector2i, spread: float, hand_index: int) -> void:                items.handle_rpc_request_drop(sender_id, item_path, tile, spread, hand_index)
func handle_rpc_drop_item_at(player_path: NodePath, item_path: NodePath, tile: Vector2i, spread: float, hand_index: int) -> void:         items.handle_rpc_drop_item_at(player_path, item_path, tile, spread, hand_index)
func handle_rpc_request_throw(sender_id: int, item_path: NodePath, hand_index: int, dir: Vector2, throw_range: int) -> void:              items.handle_rpc_request_throw(sender_id, item_path, hand_index, dir, throw_range)
func handle_rpc_confirm_throw(peer_id: int, item_path: NodePath, hand_index: int, land_pixel: Vector2, land_z: int) -> void:              items.handle_rpc_confirm_throw(peer_id, item_path, hand_index, land_pixel, land_z)

# ── Coins ─────────────────────────────────────────────────────────────────────
func handle_rpc_request_split_coins(sender_id: int, from_hand: int, to_hand: int, split_amount: int) -> void:                             coins.handle_rpc_request_split_coins(sender_id, from_hand, to_hand, split_amount)
func handle_rpc_confirm_split_coins(peer_id: int, from_hand: int, to_hand: int, new_name: String, split_amount: int, metal_type: int) -> void: coins.handle_rpc_confirm_split_coins(peer_id, from_hand, to_hand, new_name, split_amount, metal_type)
func handle_rpc_request_combine_hand_coins(sender_id: int, from_hand: int, to_hand: int) -> void:                                         coins.handle_rpc_request_combine_hand_coins(sender_id, from_hand, to_hand)
func handle_rpc_confirm_combine_hand_coins(peer_id: int, from_hand: int, to_hand: int, amount: int) -> void:                              coins.handle_rpc_confirm_combine_hand_coins(peer_id, from_hand, to_hand, amount)
func handle_rpc_request_combine_ground_coin(sender_id: int, coin_path: NodePath, hand_idx: int) -> void:                                  coins.handle_rpc_request_combine_ground_coin(sender_id, coin_path, hand_idx)
func handle_rpc_confirm_combine_ground_coin(peer_id: int, coin_path: NodePath, hand_idx: int, amount: int) -> void:                       coins.handle_rpc_confirm_combine_ground_coin(peer_id, coin_path, hand_idx, amount)

# ── Loot ──────────────────────────────────────────────────────────────────────
func handle_rpc_notify_loot_warning(target_path: NodePath, looter_peer_id: int, item_desc: String) -> void:                               loot.handle_rpc_notify_loot_warning(target_path, looter_peer_id, item_desc)
func handle_rpc_deliver_loot_warning(looter_peer_id: int, item_desc: String) -> void:                                                     loot.handle_rpc_deliver_loot_warning(looter_peer_id, item_desc)
func handle_rpc_request_loot_item(sender_id: int, target_path: NodePath, looter_peer_id: int, slot_type: String, slot_index: Variant) -> void: loot.handle_rpc_request_loot_item(sender_id, target_path, looter_peer_id, slot_type, slot_index)
func handle_rpc_confirm_loot_unequip_drop(target_path: NodePath, equip_slot: String, new_node_name: String, drop_tile: Vector2i, spread: float) -> void: loot.handle_rpc_confirm_loot_unequip_drop(target_path, equip_slot, new_node_name, drop_tile, spread)

# ── Crafting ──────────────────────────────────────────────────────────────────
func handle_rpc_request_craft(sender_id: int, looter_peer_id: int, recipe_id: String) -> void:                                            crafting.handle_rpc_request_craft(sender_id, looter_peer_id, recipe_id)
func handle_rpc_confirm_craft_item(peer_id: int, consumed_paths: Array, scene_path: String, result_name: String, drop_tile: Vector2i) -> void: crafting.handle_rpc_confirm_craft_item(peer_id, consumed_paths, scene_path, result_name, drop_tile)
func handle_rpc_confirm_craft_tile(peer_id: int, consumed_paths: Array, tile_pos: Vector2i, z_level: int, source_id: int, atlas_coords: Vector2i) -> void: crafting.handle_rpc_confirm_craft_tile(peer_id, consumed_paths, tile_pos, z_level, source_id, atlas_coords)

# ── Storage (satchel / table) ─────────────────────────────────────────────────
func handle_rpc_request_satchel_insert(sender_id: int, satchel_path: NodePath, hand_idx: int) -> void:                                    storage.handle_rpc_request_satchel_insert(sender_id, satchel_path, hand_idx)
func handle_rpc_confirm_satchel_insert(peer_id: int, satchel_path: NodePath, item_path: NodePath, hand_idx: int, slot_index: int, scene_path: String, itype: String, item_state: Dictionary) -> void: storage.handle_rpc_confirm_satchel_insert(peer_id, satchel_path, item_path, hand_idx, slot_index, scene_path, itype, item_state)
func handle_rpc_request_satchel_extract(sender_id: int, satchel_path: NodePath, slot_index: int, hand_idx: int) -> void:                  storage.handle_rpc_request_satchel_extract(sender_id, satchel_path, slot_index, hand_idx)
func handle_rpc_confirm_satchel_extract(peer_id: int, satchel_path: NodePath, slot_index: int, hand_idx: int, new_node_name: String, scene_path: String, item_state: Dictionary) -> void: storage.handle_rpc_confirm_satchel_extract(peer_id, satchel_path, slot_index, hand_idx, new_node_name, scene_path, item_state)
func handle_rpc_request_table_place(sender_id: int, table_path: NodePath, hand_idx: int, place_pos: Vector2) -> void:                     storage.handle_rpc_request_table_place(sender_id, table_path, hand_idx, place_pos)
func handle_rpc_confirm_table_place(peer_id: int, table_path: NodePath, hand_idx: int, place_pos: Vector2) -> void:                       storage.handle_rpc_confirm_table_place(peer_id, table_path, hand_idx, place_pos)
