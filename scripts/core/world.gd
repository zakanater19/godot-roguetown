# res://scripts/core/world.gd
extends Node

const TILE_SIZE:   int = Defs.TILE_SIZE
const GRID_WIDTH:  int = Defs.GRID_WIDTH
const GRID_HEIGHT: int = Defs.GRID_HEIGHT

var tilemap: TileMapLayer = null

var solid_grid: Dictionary = {1:{}, 2:{}, 3:{}, 4:{}, 5:{}}
var tile_hit_counts: Dictionary = {1:{}, 2:{}, 3:{}, 4:{}, 5:{}}


var server_action_cooldowns: Dictionary = {}
const SERVER_SNEAK_VISUAL_INTERVAL: float = 0.1
const CLIENT_LIGHT_SAMPLE_STALE_MS: int = 1500
const SERVER_SNEAK_SYNC_EPSILON: float = 0.04
var _server_sneak_visual_timer: float = 0.0
var _client_light_samples: Dictionary = {}

var current_laws: Array =[
	"1. You may not injure a king or, through inaction, allow a king to come to harm.",
	"2. You must obey orders given to you by a king, except where such orders would conflict with the First Law.",
]

var grab_map: Dictionary = {}
var grab_cooldown_map:   Dictionary = {}
var resist_cooldown_map: Dictionary = {}

var utils   = null
var tiles   = null
var combat  = null
var objects = null
var physics = null
var session = null

var main_scene: Node = null

var _tilemap_cache: Dictionary = {}
var _entity_registry: Dictionary = {}

func _make_entity_id(prefix: String = "entity") -> String:
	return "%s:%s:%s" % [prefix, Time.get_ticks_usec(), randi()]

func get_entity_id(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return ""
	var entity_id := str(node.get_meta("entity_id", ""))
	if entity_id == "":
		entity_id = ensure_entity_id(node)
	return entity_id

func ensure_entity_id(node: Node, preferred_id: String = "") -> String:
	if node == null or not is_instance_valid(node):
		return ""
	var existing_id := str(node.get_meta("entity_id", ""))
	if existing_id != "":
		_entity_registry[existing_id] = node
		return existing_id

	var root_scene: Node = main_scene
	if root_scene == null:
		root_scene = get_tree().current_scene

	var entity_id := preferred_id
	if entity_id == "":
		if node.is_in_group("player"):
			entity_id = "player:%s" % node.name
		elif root_scene != null and node.get_parent() == root_scene:
			entity_id = "scene:%s" % str(root_scene.get_path_to(node))
		else:
			entity_id = _make_entity_id()

	if _entity_registry.has(entity_id):
		var existing = _entity_registry[entity_id]
		if existing != null and is_instance_valid(existing) and existing != node:
			entity_id = _make_entity_id(entity_id.replace(":", "_"))

	node.set_meta("entity_id", entity_id)
	_entity_registry[entity_id] = node
	return entity_id

func register_entity(node: Node, preferred_id: String = "") -> String:
	return ensure_entity_id(node, preferred_id)

func unregister_entity(node: Node) -> void:
	if node == null:
		return
	var entity_id := get_entity_id(node)
	if entity_id == "":
		return
	if _entity_registry.get(entity_id) == node:
		_entity_registry.erase(entity_id)

func get_entity(entity_id: String) -> Node:
	if entity_id == "":
		return null
	var node = _entity_registry.get(entity_id, null)
	if node != null and is_instance_valid(node):
		return node
	if entity_id.begins_with("scene:") and main_scene != null:
		var rel_path := entity_id.trim_prefix("scene:")
		var scene_node := main_scene.get_node_or_null(NodePath(rel_path))
		if scene_node != null:
			register_entity(scene_node, entity_id)
			return scene_node
	if entity_id.begins_with("player:"):
		var player_name := entity_id.trim_prefix("player:")
		for candidate in get_tree().get_nodes_in_group("player"):
			if candidate.name == player_name:
				register_entity(candidate, entity_id)
				return candidate
	_entity_registry.erase(entity_id)
	return null

func register_main(node: Node) -> void:
	main_scene = node

func unregister_main() -> void:
	main_scene = null

func _ready() -> void:
	utils   = preload("res://scripts/world/world_utils.gd").new(self)
	tiles   = preload("res://scripts/world/world_tiles.gd").new(self)
	combat  = preload("res://scripts/world/world_combat.gd").new(self)
	objects = preload("res://scripts/world/world_objects.gd").new(self)
	physics = preload("res://scripts/world/world_physics.gd").new(self)
	session = preload("res://scripts/world/world_session.gd").new(self)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return
	_server_sneak_visual_timer += delta
	if _server_sneak_visual_timer < SERVER_SNEAK_VISUAL_INTERVAL:
		return
	var step := _server_sneak_visual_timer
	_server_sneak_visual_timer = 0.0
	_update_server_sneak_visuals(step)

func get_tilemap(z: int) -> TileMapLayer:
	if _tilemap_cache.has(z) and is_instance_valid(_tilemap_cache[z]):
		return _tilemap_cache[z]
	if main_scene != null:
		var tm = main_scene.get_node_or_null("TileMapLayer_Z" + str(z)) as TileMapLayer
		if tm != null:
			_tilemap_cache[z] = tm
		return tm
	return null

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		print("LateJoin: Peer disconnected - ", id)
		if grab_map.has(id):
			combat.release_grab_for_peer(id, true)
		_client_light_samples.erase(id)

func update_client_light_sample(peer_id: int, tile: Vector2i, z_level: int, light_value: float) -> void:
	_client_light_samples[peer_id] = {
		"tile": tile,
		"z_level": z_level,
		"light": clampf(light_value, 0.0, 1.0),
		"updated_ms": Time.get_ticks_msec(),
	}

func _push_server_sneak_alpha(player: Node, alpha: float) -> void:
	var clamped_alpha := clampf(alpha, 0.0, 1.0)
	player.set("sneak_alpha", clamped_alpha)
	player.call("_apply_sneak_alpha", clamped_alpha)
	var last_synced := float(player.get("_last_synced_sneak_alpha"))
	if abs(clamped_alpha - last_synced) >= SERVER_SNEAK_SYNC_EPSILON or (clamped_alpha >= 0.999 and last_synced < 0.999):
		player.set("_last_synced_sneak_alpha", clamped_alpha)
		if multiplayer.has_multiplayer_peer():
			rpc_sync_player_sneak_alpha.rpc(player.get_multiplayer_authority(), clamped_alpha)

func _update_server_sneak_visuals(delta: float) -> void:
	var now_ms := Time.get_ticks_msec()
	var players := get_tree().get_nodes_in_group("player")
	for player in players:
		if player == null or not is_instance_valid(player):
			continue
		if utils.is_ghost(player) or player.get("dead") == true:
			if float(player.get("sneak_alpha")) < 0.999:
				_push_server_sneak_alpha(player, 1.0)
			player.set("_sneak_was_hidden", false)
			continue
		if player.get("is_sneaking") != true:
			if float(player.get("sneak_alpha")) < 0.999:
				_push_server_sneak_alpha(player, 1.0)
			player.set("_sneak_was_hidden", false)
			continue

		var sample = _client_light_samples.get(player.get_multiplayer_authority(), {})
		var has_fresh_light_sample := false
		var tile_light := 1.0
		if sample is Dictionary and not sample.is_empty():
			var sample_tile: Vector2i = sample.get("tile", Vector2i(-9999, -9999))
			var sample_z: int = int(sample.get("z_level", -1))
			var sample_age: int = now_ms - int(sample.get("updated_ms", 0))
			if sample_tile == player.tile_pos and sample_z == player.z_level and sample_age <= CLIENT_LIGHT_SAMPLE_STALE_MS:
				has_fresh_light_sample = true
				tile_light = float(sample.get("light", 1.0))

		if not has_fresh_light_sample:
			continue

		var sneak_level: int = int(player.skills.get("sneaking", 0))
		var dark_threshold: float = 0.10 + sneak_level * 0.08
		var fade_speed: float = 0.3 + sneak_level * 0.15
		var reveal_radius: int = max(1, 5 - sneak_level * 2)
		var proximity_revealed := false

		if reveal_radius > 0:
			for other in players:
				if other == player or other == null or not is_instance_valid(other):
					continue
				if other.get("dead") == true or utils.is_ghost(other):
					continue
				if other.z_level != player.z_level:
					continue
				var dist: int = (other.tile_pos - player.tile_pos).abs().x + (other.tile_pos - player.tile_pos).abs().y
				if dist <= reveal_radius:
					proximity_revealed = true
					break

		var target_alpha := float(player.get("sneak_alpha"))
		if tile_light >= dark_threshold or proximity_revealed:
			target_alpha = 1.0
			if player.get("_sneak_was_hidden") == true:
				player.set("_sneak_was_hidden", false)
				rpc_broadcast_sneak_reveal.rpc(player.character_name, player.tile_pos, player.z_level)
		else:
			target_alpha = move_toward(target_alpha, 0.0, fade_speed * delta)
			if target_alpha <= 0.5:
				player.set("_sneak_was_hidden", true)

		if abs(target_alpha - float(player.get("sneak_alpha"))) > 0.001:
			_push_server_sneak_alpha(player, target_alpha)

func _is_within_interaction_range(player: Node, target_pos: Vector2, target_z: int) -> bool:
	if player.z_level != target_z: return false
	return utils.is_within_interaction_range(player, target_pos)

func _server_check_action_cooldown(player: Node, is_attack: bool = false) -> bool:
	return utils.server_check_action_cooldown(player, is_attack)

func get_entities_at_tile(tile: Vector2i, z_level: int, exclude_peer: int = 0, include_dead: bool = false) -> Array:
	return utils.get_entities_at_tile(tile, z_level, exclude_peer, include_dead)

func get_tile_movement_multiplier(tile: Vector2i, z_level: int) -> float:
	return utils.get_tile_movement_multiplier(tile, z_level)

func _find_player_by_peer(peer_id: int) -> Node:
	return utils.find_player_by_peer(peer_id)

func tile_to_pixel(t: Vector2i) -> Vector2:
	return utils.tile_to_pixel(t)

func _world_to_tile(world_pos: Vector2) -> Vector2i:
	return utils.world_to_tile(world_pos)

func get_local_player() -> Node:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED: return null
	var local_id = multiplayer.get_unique_id()
	return _find_player_by_peer(local_id)

func cast_throw(from_tile: Vector2i, from_pixel: Vector2, z_level: int, dir: Vector2, max_tiles: int) -> Vector2i:
	return utils.cast_throw(from_tile, from_pixel, z_level, dir, max_tiles)

func find_path(start: Vector2i, target: Vector2i, z_level: int) -> Array[Vector2i]:
	return utils.find_path(start, target, z_level)

func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	return utils.reconstruct_path(came_from, current)

func register_solid(pos: Vector2i, z_level: int, obj: Node) -> void:
	tiles.register_solid(pos, z_level, obj)

func unregister_solid(pos: Vector2i, z_level: int, obj: Node) -> void:
	tiles.unregister_solid(pos, z_level, obj)

func is_solid(pos: Vector2i, z_level: int) -> bool:
	return tiles.is_solid(pos, z_level)

func is_opaque(pos: Vector2i, z_level: int) -> bool:
	return tiles.is_opaque(pos, z_level)

func try_move(from: Vector2i, z_level: int, dir: Vector2i) -> Vector2i:
	return tiles.try_move(from, z_level, dir)

func break_wall(pos: Vector2i, z_level: int, parent: Node, rock_name: String = "", break_floor: Vector2i = Vector2i(9, 0)) -> void:
	tiles.break_wall(pos, z_level, parent, rock_name, break_floor)

func get_tile_description(source_id: int, atlas_coords: Vector2i) -> String:
	return tiles.get_tile_description(source_id, atlas_coords)

func _calculate_combat_roll(attacker: Node, defender: Node, base_amount: int, is_sword_attack: bool) -> Dictionary:
	return combat.calculate_combat_roll(attacker, defender, base_amount, is_sword_attack)

func deal_damage_at_tile(tile: Vector2i, z_level: int, amount: int, attacker_id: int = 0, is_sword_attack: bool = false) -> Dictionary:
	return combat.deal_damage_at_tile(tile, z_level, amount, attacker_id, is_sword_attack)

func drop_item_at(obj: Node2D, tile: Vector2i, spread: float) -> void:
	objects.drop_item_at(obj, tile, spread)

func calculate_gravity_z(tile_pos: Vector2i, current_z: int) -> int:
	return physics.calculate_gravity_z(tile_pos, current_z)

func apply_gravity_to_player(player: Node2D) -> void:
	physics.apply_gravity_to_player(player)

@rpc("any_peer", "call_local", "reliable")
func rpc_request_respawn(request_peer_id: int) -> void:
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	session.handle_rpc_request_respawn(sender_id, request_peer_id)

@rpc("authority", "call_local", "reliable")
func rpc_return_to_lobby() -> void:
	var local_entity: Node = get_local_player()
	if multiplayer.has_multiplayer_peer():
		var local_id: int = multiplayer.get_unique_id()
		Host.peers.erase(local_id)
	if local_entity != null and is_instance_valid(local_entity):
		local_entity.set("is_possessed", false)
		if local_entity.has_method("_set_fov_visibility"):
			local_entity._set_fov_visibility(false)
		elif "visible" in local_entity:
			local_entity.visible = false
	if FOV != null and FOV.has_method("refresh_local_fov"):
		FOV.refresh_local_fov()
	if Lighting != null and Lighting.has_method("invalidate_local_lighting"):
		Lighting.invalidate_local_lighting()
	Lobby.show_lobby()

@rpc("any_peer", "call_local", "reliable")
func rpc_set_object_z_level(obj_id: String, new_z: int) -> void:
	if not multiplayer.is_server(): return
	var obj = get_entity(obj_id)
	if obj != null:
		var old_z = obj.get("z_level")
		obj.set("z_level", new_z)
		var base = obj.z_index % Defs.Z_LAYER_SIZE
		obj.z_index = Defs.get_z_index(new_z, base)
		
		if old_z != null and old_z != new_z:
			var tile = utils.world_to_tile(obj.global_position)
			if obj.is_in_group("choppable_object") or obj.is_in_group("minable_object") or obj.is_in_group("door") or obj.is_in_group("inspectable") or obj.is_in_group("bed"):
				unregister_solid(tile, old_z, obj)
				register_solid(tile, new_z, obj)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_update_laws(new_laws: Array) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	utils.handle_rpc_request_update_laws(sender_id, new_laws)

@rpc("authority", "call_local", "reliable")
func rpc_update_laws(new_laws: Array) -> void:
	utils.handle_rpc_update_laws(new_laws)

@rpc("any_peer", "call_remote", "reliable")
func rpc_try_move(dir: Vector2i, is_sprinting: bool = false) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	tiles.handle_rpc_try_move(sender_id, dir, is_sprinting)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_move(peer_id: int, new_pos: Vector2i, is_sprinting: bool = false) -> void:
	tiles.handle_rpc_confirm_move(peer_id, new_pos, is_sprinting)

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
func rpc_confirm_hit_wall(pos: Vector2i, z_level: int) -> void:
	tiles.handle_rpc_confirm_hit_wall(pos, z_level)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_break_wall(pos: Vector2i, z_level: int, rock_name: String, break_floor: Vector2i) -> void:
	tiles.handle_rpc_confirm_break_wall(pos, z_level, rock_name, break_floor)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_replace_tile(pos: Vector2i, z_level: int, source_id: int, atlas_coords: Vector2i) -> void:
	tiles.handle_rpc_confirm_replace_tile(pos, z_level, source_id, atlas_coords)


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
func rpc_confirm_break_tree(tree_path: NodePath, break_payload: Dictionary) -> void:
	objects.handle_rpc_confirm_break_tree(tree_path, break_payload)

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
func rpc_request_hit_gate(gate_path: NodePath) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_hit_gate(sender_id, gate_path)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_toggle_gate(_gate_path: NodePath) -> void:
	objects.handle_rpc_confirm_toggle_gate(_gate_path)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_hit_gate(gate_path: NodePath) -> void:
	objects.handle_rpc_confirm_hit_gate(gate_path)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_destroy_gate(gate_path: NodePath) -> void:
	objects.handle_rpc_confirm_destroy_gate(gate_path)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_remove_gate(gate_path: NodePath) -> void:
	objects.handle_rpc_confirm_remove_gate(gate_path)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_interact_hand_item(hand_idx: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_interact_hand_item(sender_id, hand_idx)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_interact_hand_item(peer_id: int, hand_idx: int) -> void:
	objects.handle_rpc_confirm_interact_hand_item(peer_id, hand_idx)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_equip(item_id: String, slot_name: String, hand_index: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_equip(sender_id, item_id, slot_name, hand_index)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_equip(peer_id: int, item_id: String, slot_name: String, hand_index: int) -> void:
	objects.handle_rpc_confirm_equip(peer_id, item_id, slot_name, hand_index)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_unequip(slot_name: String, hand_index: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_unequip(sender_id, slot_name, hand_index)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_unequip(peer_id: int, slot_name: String, new_entity_id: String, hand_index: int) -> void:
	objects.handle_rpc_confirm_unequip(peer_id, slot_name, new_entity_id, hand_index)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_furnace_action(furnace_id: String, action: String, hand_idx: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_furnace_action(sender_id, furnace_id, action, hand_idx)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_furnace_action(peer_id: int, furnace_id: String, action: String, hand_idx: int, generated_ids: Array) -> void:
	objects.handle_rpc_confirm_furnace_action(peer_id, furnace_id, action, hand_idx, generated_ids)

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
func rpc_request_combine_ground_coin(coin_id: String, hand_idx: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_combine_ground_coin(sender_id, coin_id, hand_idx)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_combine_ground_coin(peer_id: int, coin_id: String, hand_idx: int, amount: int) -> void:
	objects.handle_rpc_confirm_combine_ground_coin(peer_id, coin_id, hand_idx, amount)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_pickup(item_id: String, hand_index: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_pickup(sender_id, item_id, hand_index)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_pickup(peer_id: int, item_id: String, hand_index: int) -> void:
	objects.handle_rpc_confirm_pickup(peer_id, item_id, hand_index)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_drop(item_id: String, tile: Vector2i, spread: float, hand_index: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_drop(sender_id, item_id, tile, spread, hand_index)

@rpc("authority", "call_local", "reliable")
func rpc_drop_item_at(player_peer_id: int, item_id: String, tile: Vector2i, spread: float, hand_index: int) -> void:
	objects.handle_rpc_drop_item_at(player_peer_id, item_id, tile, spread, hand_index)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_throw(item_id: String, hand_index: int, dir: Vector2, throw_range: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_throw(sender_id, item_id, hand_index, dir, throw_range)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_throw(peer_id: int, item_id: String, hand_index: int, land_pixel: Vector2, land_z: int) -> void:
	objects.handle_rpc_confirm_throw(peer_id, item_id, hand_index, land_pixel, land_z)

@rpc("any_peer", "call_remote", "reliable")
func rpc_send_chat(message: String) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	utils.handle_rpc_send_chat(sender_id, message)

@rpc("authority", "call_local", "reliable")
func rpc_broadcast_deadchat(sender_peer_id: int, message: String) -> void:
	utils.handle_rpc_broadcast_deadchat(sender_peer_id, message)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_ghost_z_change(new_z: int) -> void:
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	var ghost = utils.find_player_by_peer(sender_id)
	if ghost == null or not utils.is_ghost(ghost): return
	var target_z: int = clampi(new_z, 1, 5)
	ghost.rpc_sync_z_level(target_z)
	ghost.rpc_sync_z_level.rpc(target_z)
	LateJoin.update_player_state(sender_id, {"position": ghost.position, "z_level": target_z})

@rpc("authority", "call_local", "reliable")
func rpc_broadcast_chat(sender_peer_id: int, message: String, sender_tile: Vector2i, sender_z: int) -> void:
	utils.handle_rpc_broadcast_chat(sender_peer_id, message, sender_tile, sender_z)

@rpc("authority", "call_local", "reliable")
func rpc_broadcast_damage_log(attacker_name: String, target_name: String, amount: int, source_tile: Vector2i, source_z: int, blocked: bool = false, is_shove: bool = false, targeted_limb: String = "", block_type: String = "", weapon_type: String = "") -> void:
	utils.handle_rpc_broadcast_damage_log(attacker_name, target_name, amount, source_tile, source_z, blocked, is_shove, targeted_limb, block_type, weapon_type)

@rpc("any_peer", "call_remote", "unreliable")
func rpc_report_client_light_sample(tile: Vector2i, z_level: int, light_value: float) -> void:
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	var player = utils.find_player_by_peer(sender_id)
	if player == null: return
	update_client_light_sample(sender_id, tile, z_level, light_value)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_sneak_reveal(character_name: String, source_tile: Vector2i, source_z: int) -> void:
	if not multiplayer.is_server(): return
	rpc_broadcast_sneak_reveal.rpc(character_name, source_tile, source_z)

@rpc("authority", "call_remote", "unreliable")
func rpc_sync_player_sneak_alpha(peer_id: int, alpha: float) -> void:
	var player = utils.find_player_by_peer(peer_id)
	if player == null: return
	player.set("sneak_alpha", alpha)
	if player.has_method("_apply_sneak_alpha"):
		player.call("_apply_sneak_alpha", alpha)
	player.set("_last_synced_sneak_alpha", alpha)

@rpc("authority", "call_local", "reliable")
func rpc_broadcast_sneak_reveal(character_name: String, source_tile: Vector2i, source_z: int) -> void:
	utils.handle_rpc_broadcast_sneak_reveal(character_name, source_tile, source_z)

@rpc("any_peer", "call_remote", "reliable")
func rpc_notify_loot_warning(target_id: String, looter_peer_id: int, item_desc: String) -> void:
	objects.handle_rpc_notify_loot_warning(target_id, looter_peer_id, item_desc)

@rpc("authority", "call_remote", "reliable")
func rpc_deliver_loot_warning(looter_peer_id: int, item_desc: String) -> void:
	objects.handle_rpc_deliver_loot_warning(looter_peer_id, item_desc)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_loot_item(target_id: String, looter_peer_id: int, slot_type: String, slot_index: Variant) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_loot_item(sender_id, target_id, looter_peer_id, slot_type, slot_index)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_loot_unequip_drop(target_id: String, equip_slot: String, new_entity_id: String, drop_tile: Vector2i, spread: float) -> void:
	objects.handle_rpc_confirm_loot_unequip_drop(target_id, equip_slot, new_entity_id, drop_tile, spread)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_craft(looter_peer_id: int, recipe_id: String) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_craft(sender_id, looter_peer_id, recipe_id)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_craft_item(peer_id: int, consumed_paths: Array, scene_path: String, result_name: String, drop_tile: Vector2i) -> void:
	objects.handle_rpc_confirm_craft_item(peer_id, consumed_paths, scene_path, result_name, drop_tile)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_craft_tile(peer_id: int, consumed_paths: Array, tile_pos: Vector2i, z_level: int, source_id: int, atlas_coords: Vector2i) -> void:
	objects.handle_rpc_confirm_craft_tile(peer_id, consumed_paths, tile_pos, z_level, source_id, atlas_coords)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_satchel_insert(satchel_id: String, hand_idx: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_satchel_insert(sender_id, satchel_id, hand_idx)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_satchel_insert(peer_id: int, satchel_id: String, item_id: String, hand_idx: int, slot_index: int, scene_path: String, itype: String, item_state: Dictionary) -> void:
	objects.handle_rpc_confirm_satchel_insert(peer_id, satchel_id, item_id, hand_idx, slot_index, scene_path, itype, item_state)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_satchel_extract(satchel_id: String, slot_index: int, hand_idx: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_satchel_extract(sender_id, satchel_id, slot_index, hand_idx)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_satchel_extract(peer_id: int, satchel_id: String, slot_index: int, hand_idx: int, new_entity_id: String, scene_path: String, item_state: Dictionary) -> void:
	objects.handle_rpc_confirm_satchel_extract(peer_id, satchel_id, slot_index, hand_idx, new_entity_id, scene_path, item_state)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_grab(target_id: String, limb: String = "chest") -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	combat.handle_rpc_request_grab(sender_id, target_id, limb)

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
func rpc_confirm_grab_start(grabber_peer_id: int, is_player: bool, target_peer_id: int, target_id: String, grabber_name: String = "", target_name: String = "", limb: String = "chest", grab_hand: int = 0) -> void:
	combat.handle_rpc_confirm_grab_start(grabber_peer_id, is_player, target_peer_id, target_id, grabber_name, target_name, limb, grab_hand)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_grab_released(grabber_peer_id: int, is_player: bool, target_peer_id: int, grabber_name: String = "", target_name: String = "", silent: bool = false) -> void:
	combat.handle_rpc_confirm_grab_released(grabber_peer_id, is_player, target_peer_id, grabber_name, target_name, silent)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_resist_result(grabber_peer_id: int, grabbed_peer_id: int, broke_free: bool) -> void:
	combat.handle_rpc_confirm_resist_result(grabber_peer_id, grabbed_peer_id, broke_free)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_drag_object(obj_id: String, new_pixel: Vector2) -> void:
	combat.handle_rpc_confirm_drag_object(obj_id, new_pixel)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_drag_corpse(corpse_id: String, new_pos: Vector2i) -> void:
	combat.handle_rpc_confirm_drag_corpse(corpse_id, new_pos)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_table_place(table_id: String, hand_idx: int, place_pos: Vector2) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	objects.handle_rpc_request_table_place(sender_id, table_id, hand_idx, place_pos)

@rpc("authority", "call_local", "reliable")
func rpc_confirm_table_place(peer_id: int, table_id: String, hand_idx: int, place_pos: Vector2) -> void:
	objects.handle_rpc_confirm_table_place(peer_id, table_id, hand_idx, place_pos)

@rpc("any_peer", "call_local", "reliable")
func rpc_request_round_end() -> void:
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != 1 and sender_id != 0: return
	rpc("rpc_execute_round_end")

@rpc("authority", "call_local", "reliable")
func rpc_execute_round_end() -> void:
	session.handle_rpc_execute_round_end()

@rpc("authority", "call_local", "reliable")
func rpc_send_direct_message(message: String) -> void:
	Sidebar.add_message(message)
