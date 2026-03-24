# file: project/world.gd
extends Node

# --- CONFIGURATION ---
const TILE_SIZE:   int = 64
const GRID_WIDTH:  int = 1000
const GRID_HEIGHT: int = 1000

var tilemap: TileMapLayer = null

# --- STATE ---
var solid_grid: Dictionary = {}
var tile_hit_counts: Dictionary = {}
const WALL_HITS_TO_BREAK: int = 3
const STONE_WALL_HITS_TO_BREAK: int = 10
const WOODEN_WALL_HITS_TO_BREAK: int = 5

var server_action_cooldowns: Dictionary = {}

var current_laws: Array =[
	"1. You may not injure a king or, through inaction, allow a king to come to harm.",
	"2. You must obey orders given to you by a king, except where such orders would conflict with the First Law.",
]

# Public maps for backend module access
var grab_map: Dictionary = {}
const GRAB_COOLDOWN_MS:   int = 1000
const RESIST_COOLDOWN_MS: int = 1000
var grab_cooldown_map:   Dictionary = {}
var resist_cooldown_map: Dictionary = {}

# --- BACKEND MODULES ---
var utils = null
var tiles = null
var combat = null
var objects = null

func _ready() -> void:
	utils = preload("res://world_utils.gd").new(self)
	tiles = preload("res://world_tiles.gd").new(self)
	combat = preload("res://world_combat.gd").new(self)
	objects = preload("res://world_objects.gd").new(self)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		print("LateJoin: Peer disconnected - ", id)
		if grab_map.has(id):
			combat.release_grab_for_peer(id, true)

# ---------------------------------------------------------------------------
# API Wrappers (Delegates to Modules)
# ---------------------------------------------------------------------------

func _is_within_interaction_range(player: Node, target_pos: Vector2) -> bool:
	return utils.is_within_interaction_range(player, target_pos)

func _server_check_action_cooldown(player: Node, is_attack: bool = false) -> bool:
	return utils.server_check_action_cooldown(player, is_attack)

func get_entities_at_tile(tile: Vector2i, exclude_peer: int = 0) -> Array:
	return utils.get_entities_at_tile(tile, exclude_peer)

func _find_player_by_peer(peer_id: int) -> Node:
	return utils.find_player_by_peer(peer_id)

func tile_to_pixel(t: Vector2i) -> Vector2:
	return utils.tile_to_pixel(t)

func _world_to_tile(world_pos: Vector2) -> Vector2i:
	return utils.world_to_tile(world_pos)

func get_local_player() -> Node:
	return utils.get_local_player()

func cast_throw(from_tile: Vector2i, from_pixel: Vector2, dir: Vector2, max_tiles: int) -> Vector2i:
	return utils.cast_throw(from_tile, from_pixel, dir, max_tiles)

func find_path(start: Vector2i, target: Vector2i) -> Array[Vector2i]:
	return utils.find_path(start, target)

func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	return utils.reconstruct_path(came_from, current)

func register_solid(pos: Vector2i, obj: Node) -> void:
	tiles.register_solid(pos, obj)

func unregister_solid(pos: Vector2i, obj: Node) -> void:
	tiles.unregister_solid(pos, obj)

func is_solid(pos: Vector2i) -> bool:
	return tiles.is_solid(pos)

func try_move(from: Vector2i, dir: Vector2i) -> Vector2i:
	return tiles.try_move(from, dir)

func break_wall(pos: Vector2i, parent: Node, rock_name: String = "") -> void:
	tiles.break_wall(pos, parent, rock_name)

func get_tile_description(source_id: int, atlas_coords: Vector2i) -> String:
	return tiles.get_tile_description(source_id, atlas_coords)

func _calculate_combat_roll(attacker: Node, defender: Node, base_amount: int, is_sword_attack: bool) -> Dictionary:
	return combat.calculate_combat_roll(attacker, defender, base_amount, is_sword_attack)

func deal_damage_at_tile(tile: Vector2i, amount: int, attacker_id: int = 0, is_sword_attack: bool = false) -> Dictionary:
	return combat.deal_damage_at_tile(tile, amount, attacker_id, is_sword_attack)

func drop_item_at(obj: Node2D, tile: Vector2i, spread: float) -> void:
	objects.drop_item_at(obj, tile, spread)

# ---------------------------------------------------------------------------
# Laws
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_update_laws(new_laws: Array) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	utils.handle_rpc_request_update_laws(sender_id, new_laws)

@rpc("authority", "call_local", "reliable")
func rpc_update_laws(new_laws: Array) -> void:
	utils.handle_rpc_update_laws(new_laws)

# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_try_move(dir: Vector2i, is_sprinting: bool = false) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	tiles.handle_rpc_try_move(sender_id, dir, is_sprinting)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_move(peer_id: int, new_pos: Vector2i, is_sprinting: bool = false) -> void:
	tiles.handle_rpc_confirm_move(peer_id, new_pos, is_sprinting)

# ---------------------------------------------------------------------------
# Active Shoving & Damage
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_shove(target_tile: Vector2i) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	combat.handle_rpc_request_shove(sender_id, target_tile)

@rpc("any_peer", "call_remote", "reliable")
func rpc_deal_damage_at_tile(tile: Vector2i, targeted_limb: String = "chest") -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	combat.handle_rpc_deal_damage_at_tile(sender_id, tile, targeted_limb)

@rpc("any_peer", "call_remote", "reliable")
func rpc_damage_wall(pos: Vector2i) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	tiles.handle_rpc_damage_wall(sender_id, pos)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_hit_wall(pos: Vector2i) -> void:
	tiles.handle_rpc_confirm_hit_wall(pos)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_break_wall(pos: Vector2i, rock_name: String) -> void:
	tiles.handle_rpc_confirm_break_wall(pos, rock_name)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_replace_tile(pos: Vector2i, source_id: int, atlas_coords: Vector2i) -> void:
	tiles.handle_rpc_confirm_replace_tile(pos, source_id, atlas_coords)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_break_stone_wall(pos: Vector2i) -> void:
	tiles.handle_rpc_confirm_break_stone_wall(pos)

# ---------------------------------------------------------------------------
# Object Mining/Breaking
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_hit_rock(rock_path: NodePath) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_hit_rock(sender_id, rock_path)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_hit_rock(rock_path: NodePath) -> void:
	objects.handle_rpc_confirm_hit_rock(rock_path)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_break_rock(rock_path: NodePath, drops_data: Array) -> void:
	objects.handle_rpc_confirm_break_rock(rock_path, drops_data)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_hit_tree(tree_path: NodePath) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_hit_tree(sender_id, tree_path)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_hit_tree(tree_path: NodePath) -> void:
	objects.handle_rpc_confirm_hit_tree(tree_path)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_break_tree(tree_path: NodePath, log_names: Array) -> void:
	objects.handle_rpc_confirm_break_tree(tree_path, log_names)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_hit_breakable(obj_path: NodePath) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_hit_breakable(sender_id, obj_path)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_hit_breakable(obj_path: NodePath) -> void:
	objects.handle_rpc_confirm_hit_breakable(obj_path)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_break_breakable(obj_path: NodePath) -> void:
	objects.handle_rpc_confirm_break_breakable(obj_path)

# ---------------------------------------------------------------------------
# Doors & Interactions
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_hit_door(door_path: NodePath) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_hit_door(sender_id, door_path)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_toggle_door(_door_path: NodePath) -> void:
	objects.handle_rpc_confirm_toggle_door(_door_path)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_hit_door(door_path: NodePath) -> void:
	objects.handle_rpc_confirm_hit_door(door_path)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_destroy_door(door_path: NodePath) -> void:
	objects.handle_rpc_confirm_destroy_door(door_path)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_remove_door(door_path: NodePath) -> void:
	objects.handle_rpc_confirm_remove_door(door_path)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_interact_hand_item(hand_idx: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_interact_hand_item(sender_id, hand_idx)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_interact_hand_item(peer_id: int, hand_idx: int) -> void:
	objects.handle_rpc_confirm_interact_hand_item(peer_id, hand_idx)

# ---------------------------------------------------------------------------
# Equipment & Furnaces & Coins
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_equip(item_path: NodePath, slot_name: String, hand_index: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_equip(sender_id, item_path, slot_name, hand_index)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_equip(peer_id: int, item_path: NodePath, slot_name: String, hand_index: int) -> void:
	objects.handle_rpc_confirm_equip(peer_id, item_path, slot_name, hand_index)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_unequip(slot_name: String, hand_index: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_unequip(sender_id, slot_name, hand_index)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_unequip(peer_id: int, slot_name: String, new_node_name: String, hand_index: int) -> void:
	objects.handle_rpc_confirm_unequip(peer_id, slot_name, new_node_name, hand_index)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_furnace_action(furnace_path: NodePath, action: String, hand_idx: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_furnace_action(sender_id, furnace_path, action, hand_idx)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_furnace_action(peer_id: int, furnace_path: NodePath, action: String, hand_idx: int, generated_names: Array) -> void:
	objects.handle_rpc_confirm_furnace_action(peer_id, furnace_path, action, hand_idx, generated_names)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_split_coins(from_hand: int, to_hand: int, split_amount: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_split_coins(sender_id, from_hand, to_hand, split_amount)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_split_coins(peer_id: int, from_hand: int, to_hand: int, new_name: String, split_amount: int, metal_type: int) -> void:
	objects.handle_rpc_confirm_split_coins(peer_id, from_hand, to_hand, new_name, split_amount, metal_type)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_combine_hand_coins(from_hand: int, to_hand: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_combine_hand_coins(sender_id, from_hand, to_hand)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_combine_hand_coins(peer_id: int, from_hand: int, to_hand: int, amount: int) -> void:
	objects.handle_rpc_confirm_combine_hand_coins(peer_id, from_hand, to_hand, amount)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_combine_ground_coin(coin_path: NodePath, hand_idx: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_combine_ground_coin(sender_id, coin_path, hand_idx)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_combine_ground_coin(peer_id: int, coin_path: NodePath, hand_idx: int, amount: int) -> void:
	objects.handle_rpc_confirm_combine_ground_coin(peer_id, coin_path, hand_idx, amount)

# ---------------------------------------------------------------------------
# Pickups & Drops & Throws
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_pickup(item_path: NodePath, hand_index: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_pickup(sender_id, item_path, hand_index)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_pickup(peer_id: int, item_path: NodePath, hand_index: int) -> void:
	objects.handle_rpc_confirm_pickup(peer_id, item_path, hand_index)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_drop(item_path: NodePath, tile: Vector2i, spread: float, hand_index: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_drop(sender_id, item_path, tile, spread, hand_index)

@rpc("authority", "call_local", "reliable")
func rpc_drop_item_at(peer_id: int, item_path: NodePath, tile: Vector2i, spread: float, hand_index: int) -> void:
	objects.handle_rpc_drop_item_at(peer_id, item_path, tile, spread, hand_index)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_throw(item_path: NodePath, hand_index: int, dir: Vector2, throw_range: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_throw(sender_id, item_path, hand_index, dir, throw_range)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_throw(peer_id: int, item_path: NodePath, hand_index: int, land_pixel: Vector2) -> void:
	objects.handle_rpc_confirm_throw(peer_id, item_path, hand_index, land_pixel)

# ---------------------------------------------------------------------------
# Chat & Logs
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_send_chat(message: String) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	utils.handle_rpc_send_chat(sender_id, message)

@rpc("authority", "call_local", "reliable")
func rpc_broadcast_chat(sender_peer_id: int, message: String, sender_tile: Vector2i) -> void:
	utils.handle_rpc_broadcast_chat(sender_peer_id, message, sender_tile)

@rpc("authority", "call_local", "reliable")
func rpc_broadcast_damage_log(attacker_name: String, target_name: String, amount: int, source_tile: Vector2i, blocked: bool = false, is_shove: bool = false, targeted_limb: String = "", block_type: String = "") -> void:
	utils.handle_rpc_broadcast_damage_log(attacker_name, target_name, amount, source_tile, blocked, is_shove, targeted_limb, block_type)

# ---------------------------------------------------------------------------
# Looting & Crafting
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_notify_loot_warning(target_peer_id: int, looter_peer_id: int, item_desc: String) -> void:
	objects.handle_rpc_notify_loot_warning(target_peer_id, looter_peer_id, item_desc)

@rpc("authority", "call_remote", "reliable")
func rpc_deliver_loot_warning(looter_peer_id: int, item_desc: String) -> void:
	objects.handle_rpc_deliver_loot_warning(looter_peer_id, item_desc)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_loot_item(target_peer_id: int, looter_peer_id: int, slot_type: String, slot_index: Variant) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_loot_item(sender_id, target_peer_id, looter_peer_id, slot_type, slot_index)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_loot_unequip_drop(target_peer_id: int, equip_slot: String, new_node_name: String, drop_tile: Vector2i, spread: float) -> void:
	objects.handle_rpc_confirm_loot_unequip_drop(target_peer_id, equip_slot, new_node_name, drop_tile, spread)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_craft(looter_peer_id: int, recipe_id: String) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_craft(sender_id, looter_peer_id, recipe_id)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_craft_item(peer_id: int, consumed_paths: Array, scene_path: String, result_name: String, drop_tile: Vector2i) -> void:
	objects.handle_rpc_confirm_craft_item(peer_id, consumed_paths, scene_path, result_name, drop_tile)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_craft_tile(peer_id: int, consumed_paths: Array, tile_pos: Vector2i, source_id: int, atlas_coords: Vector2i) -> void:
	objects.handle_rpc_confirm_craft_tile(peer_id, consumed_paths, tile_pos, source_id, atlas_coords)

# ---------------------------------------------------------------------------
# Satchels
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_satchel_insert(satchel_path: NodePath, hand_idx: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_satchel_insert(sender_id, satchel_path, hand_idx)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_satchel_insert(peer_id: int, satchel_path: NodePath, _item_path: NodePath, hand_idx: int, slot_index: int, scene_path: String, itype: String) -> void:
	objects.handle_rpc_confirm_satchel_insert(peer_id, satchel_path, _item_path, hand_idx, slot_index, scene_path, itype)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_satchel_extract(satchel_path: NodePath, slot_index: int, hand_idx: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_satchel_extract(sender_id, satchel_path, slot_index, hand_idx)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_satchel_extract(peer_id: int, satchel_path: NodePath, slot_index: int, hand_idx: int, new_node_name: String, scene_path: String) -> void:
	objects.handle_rpc_confirm_satchel_extract(peer_id, satchel_path, slot_index, hand_idx, new_node_name, scene_path)

# ---------------------------------------------------------------------------
# Grab System Wrappers
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_grab(target_path: NodePath, limb: String = "chest") -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	combat.handle_rpc_request_grab(sender_id, target_path, limb)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_release_grab() -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	combat.handle_rpc_request_release_grab(sender_id)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_resist() -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	combat.handle_rpc_request_resist(sender_id)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_grab_start(grabber_peer_id: int, is_player: bool, target_peer_id: int, target_path: NodePath, grabber_name: String = "", target_name: String = "", limb: String = "chest", grab_hand: int = 0) -> void:
	combat.handle_rpc_confirm_grab_start(grabber_peer_id, is_player, target_peer_id, target_path, grabber_name, target_name, limb, grab_hand)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_grab_released(grabber_peer_id: int, is_player: bool, target_peer_id: int, grabber_name: String = "", target_name: String = "", silent: bool = false) -> void:
	combat.handle_rpc_confirm_grab_released(grabber_peer_id, is_player, target_peer_id, grabber_name, target_name, silent)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_resist_result(grabber_peer_id: int, grabbed_peer_id: int, broke_free: bool) -> void:
	combat.handle_rpc_confirm_resist_result(grabber_peer_id, grabbed_peer_id, broke_free)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_drag_object(obj_path: NodePath, new_pixel: Vector2) -> void:
	combat.handle_rpc_confirm_drag_object(obj_path, new_pixel)