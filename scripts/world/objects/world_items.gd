# res://scripts/world/objects/world_items.gd
# Handles: hand item interaction, equip/unequip, furnace, pickup, drop, throw
extends RefCounted

var world: Node
const TORCH_SCENE_PATH: String = "res://objects/torch.tscn"
const TORCH_SCRIPT_PATH: String = "res://objects/torch.gd"

func _init(p_world: Node) -> void:
	world = p_world

func _is_torch_item(item: Node) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if item.has_method("is_torch_item") and item.is_torch_item():
		return true
	if str(item.get("item_type")) == "Torch":
		return true
	if item.scene_file_path == TORCH_SCENE_PATH:
		return true
	var script := item.get_script() as Script
	return script != null and script.resource_path == TORCH_SCRIPT_PATH

# ── Hand item interaction ─────────────────────────────────────────────────────

func handle_rpc_request_interact_hand_item(sender_id: int, hand_idx: int) -> void:
	if not world.multiplayer.is_server() or not Defs.is_valid_hand_index(hand_idx): return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player): return
	if player.body != null and player.body.is_arm_broken(hand_idx): return
	var item = player.hands[hand_idx]
	if item == null or not is_instance_valid(item) or not item.has_method("interact_in_hand"): return
	if not world.utils.server_check_action_cooldown(player): return
	world.rpc_confirm_interact_hand_item.rpc(sender_id, hand_idx)

func handle_rpc_confirm_interact_hand_item(peer_id: int, hand_idx: int) -> void:
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	if player != null:
		var item = player.hands[hand_idx]
		if item != null and is_instance_valid(item) and item.has_method("interact_in_hand"):
			item.interact_in_hand(player)

func handle_rpc_request_keyring_insert(sender_id: int, keyring_id: String, hand_idx: int) -> void:
	if not world.multiplayer.is_server() or not Defs.is_valid_hand_index(hand_idx): return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player): return
	if player.body != null and player.body.is_arm_broken(hand_idx): return
	var key_item: Node = player.hands[hand_idx]
	if key_item == null or not is_instance_valid(key_item) or not key_item.has_method("has_key_id"): return

	var keyring: Node = world.get_entity(keyring_id)
	if keyring == null or not is_instance_valid(keyring) or keyring == key_item or not keyring.has_method("validate_key_insert"): return

	var keyring_in_hand := false
	for hand_item in player.hands:
		if hand_item == keyring:
			keyring_in_hand = true
			break

	if not keyring_in_hand:
		if keyring.get("z_level") != null and keyring.get("z_level") != player.z_level: return
		if not world.utils.is_within_interaction_range(player, keyring.global_position): return

	var validation = keyring.validate_key_insert(key_item)
	if not (validation is Dictionary): return
	if not validation.get("ok", false):
		var failure_message := str(validation.get("message", ""))
		if failure_message != "":
			world.rpc_send_direct_message.rpc_id(sender_id, failure_message)
		return

	var key_state: Dictionary = validation.get("key_state", {}).duplicate(true)
	world.rpc_confirm_keyring_insert.rpc(sender_id, keyring_id, hand_idx, key_state)
	world.rpc_send_direct_message.rpc_id(sender_id, "[color=#aaffaa]You add the key to the keyring.[/color]")

func handle_rpc_confirm_keyring_insert(peer_id: int, keyring_id: String, hand_idx: int, key_state: Dictionary) -> void:
	var keyring: Node = world.get_entity(keyring_id)
	if keyring == null or not is_instance_valid(keyring) or not keyring.has_method("insert_key_state"): return
	keyring.insert_key_state(key_state)

	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	if player == null: return
	var held_item: Node = player.hands[hand_idx]
	if held_item != null and is_instance_valid(held_item):
		world.unregister_entity(held_item)
		held_item.queue_free()
	player.hands[hand_idx] = null
	if player._is_local_authority():
		player._update_hands_ui()

func handle_rpc_request_keyring_extract(sender_id: int, keyring_id: String, hand_idx: int) -> void:
	if not world.multiplayer.is_server() or not Defs.is_valid_hand_index(hand_idx): return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player): return
	if player.body != null and player.body.is_arm_broken(hand_idx): return
	if player.hands[hand_idx] != null: return

	var keyring: Node = world.get_entity(keyring_id)
	if keyring == null or not is_instance_valid(keyring) or not keyring.has_method("get_random_key_roll") or not keyring.has_method("can_extract_key"): return

	var keyring_in_hand := false
	for hand_item in player.hands:
		if hand_item == keyring:
			keyring_in_hand = true
			break
	if not keyring_in_hand: return
	if not keyring.can_extract_key(): return

	var roll = keyring.get_random_key_roll()
	if not (roll is Dictionary) or not roll.has("index") or not roll.has("key_state"): return

	var key_state: Dictionary = roll.get("key_state", {}).duplicate(true)
	var item_type := str(key_state.get("item_type", "BrownKey"))
	var scene_path := ItemRegistry.get_scene_path(item_type)
	if scene_path == "": return

	var new_entity_id: String = world._make_entity_id("keyring_extract")
	world.rpc_confirm_keyring_extract.rpc(sender_id, keyring_id, hand_idx, int(roll["index"]), new_entity_id, scene_path, key_state)
	world.rpc_send_direct_message.rpc_id(sender_id, "[color=#aaffaa]You pull a key from the keyring.[/color]")

func handle_rpc_confirm_keyring_extract(peer_id: int, keyring_id: String, hand_idx: int, slot_index: int, new_entity_id: String, scene_path: String, key_state: Dictionary) -> void:
	var keyring: Node = world.get_entity(keyring_id)
	if keyring == null or not is_instance_valid(keyring) or not keyring.has_method("remove_key_at"): return
	keyring.remove_key_at(slot_index)

	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	if player == null or player.hands[hand_idx] != null: return

	var scene := load(scene_path) as PackedScene
	if scene == null: return

	var item: Node2D = scene.instantiate()
	item.position = player.pixel_pos
	item.set("z_level", player.z_level)
	if key_state.has("key_id") and "key_id" in item:
		item.set("key_id", int(key_state["key_id"]))

	item.set_meta("entity_id", new_entity_id)
	player.get_parent().add_child(item)
	world.register_entity(item, new_entity_id)
	for child in item.get_children():
		if child is CollisionShape2D:
			child.disabled = true

	player.hands[hand_idx] = item
	if player._is_local_authority():
		player._update_hands_ui()

# ── Equip / Unequip ───────────────────────────────────────────────────────────

func handle_rpc_request_equip(sender_id: int, item_id: String, slot_name: String, hand_index: int) -> void:
	if not world.multiplayer.is_server() or not Defs.is_valid_hand_index(hand_index): return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player): return
	if player.body != null and player.body.is_arm_broken(hand_index): return
	var item = world.get_entity(item_id)
	if item == null or player.hands[hand_index] != item: return
	world.rpc_confirm_equip.rpc(sender_id, item_id, slot_name, hand_index)

func handle_rpc_confirm_equip(peer_id: int, item_id: String, slot_name: String, hand_index: int) -> void:
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	var obj    = world.get_entity(item_id)
	if player != null and obj != null:
		player._perform_equip(obj, slot_name, hand_index)

func handle_rpc_request_unequip(sender_id: int, slot_name: String, hand_index: int) -> void:
	if not world.multiplayer.is_server() or not Defs.is_valid_hand_index(hand_index): return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player): return
	if player.body != null and player.body.is_arm_broken(hand_index): return
	var new_entity_id = world._make_entity_id("unequip")
	world.rpc_confirm_unequip.rpc(sender_id, slot_name, new_entity_id, hand_index)

func handle_rpc_confirm_unequip(peer_id: int, slot_name: String, new_entity_id: String, hand_index: int) -> void:
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	if player != null:
		player._perform_unequip(slot_name, new_entity_id, hand_index)

# ── Furnace ───────────────────────────────────────────────────────────────────

func handle_rpc_request_furnace_action(sender_id: int, furnace_id: String, action: String, hand_idx: int) -> void:
	if not world.multiplayer.is_server() or not Defs.is_valid_hand_index(hand_idx): return
	var furnace = world.get_entity(furnace_id)
	if furnace == null: return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player): return
	if player.body != null and player.body.is_arm_broken(hand_idx): return
	if not world.utils.is_within_interaction_range(player, furnace.global_position): return

	if action.begins_with("insert_") and player.hands[hand_idx] == null: return
	if action == "eject":
		var names = []
		var total = furnace._coal_count + furnace._ironore_count
		for i in total: names.append(world._make_entity_id("eject"))
		world.rpc_confirm_furnace_action.rpc(sender_id, furnace_id, action, hand_idx, names)
	else:
		world.rpc_confirm_furnace_action.rpc(sender_id, furnace_id, action, hand_idx, [])

func handle_rpc_confirm_furnace_action(peer_id: int, furnace_id: String, action: String, hand_idx: int, generated_ids: Array) -> void:
	var player: Node2D  = world.utils.find_player_by_peer(peer_id) as Node2D
	var furnace = world.get_entity(furnace_id)
	if furnace != null:
		furnace._perform_action(action, player, hand_idx, generated_ids)

func handle_rpc_request_torchwall_action(sender_id: int, torchwall_id: String, action: String, hand_idx: int) -> void:
	if not world.multiplayer.is_server() or not Defs.is_valid_hand_index(hand_idx):
		return

	var torchwall = world.get_entity(torchwall_id)
	if torchwall == null:
		return

	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player):
		return
	if player.body != null and player.body.is_arm_broken(hand_idx):
		return
	if not world.utils.is_within_interaction_range(player, torchwall.global_position):
		return

	match action:
		"insert":
			var held_item: Node = player.hands[hand_idx]
			if not _is_torch_item(held_item):
				return
			if torchwall.get("has_torch") == true:
				return
			world.rpc_confirm_torchwall_action.rpc(sender_id, torchwall_id, action, hand_idx, [])
		"extract":
			if player.hands[hand_idx] != null:
				return
			if torchwall.get("has_torch") != true:
				return
			var new_entity_id: String = world._make_entity_id("torchwall_extract")
			world.rpc_confirm_torchwall_action.rpc(sender_id, torchwall_id, action, hand_idx, [new_entity_id])

func handle_rpc_confirm_torchwall_action(peer_id: int, torchwall_id: String, action: String, hand_idx: int, generated_ids: Array) -> void:
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	var torchwall = world.get_entity(torchwall_id)
	if torchwall != null and torchwall.has_method("_perform_action"):
		torchwall._perform_action(action, player, hand_idx, generated_ids)

# ── Pickup ────────────────────────────────────────────────────────────────────

func handle_rpc_request_pickup(sender_id: int, item_id: String, hand_index: int) -> void:
	if not world.multiplayer.is_server() or not Defs.is_valid_hand_index(hand_index): return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player): return
	if player.body != null and player.body.is_arm_broken(hand_index): return
	var item = world.get_entity(item_id)
	if item == null: return
	if not world.utils.is_within_interaction_range(player, item.global_position): return
	world.rpc_confirm_pickup.rpc(sender_id, item_id, hand_index)

func handle_rpc_confirm_pickup(peer_id: int, item_id: String, hand_index: int) -> void:
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	var obj    = world.get_entity(item_id)
	if player == null or obj == null: return
	player.hands[hand_index] = obj
	for child in obj.get_children():
		if child is CollisionShape2D: child.disabled = true
	if player._is_local_authority():
		player._update_hands_ui()

# ── Drop ──────────────────────────────────────────────────────────────────────

func handle_rpc_request_drop(sender_id: int, item_id: String, tile: Vector2i, spread: float, hand_index: int) -> void:
	if not world.multiplayer.is_server() or not Defs.is_valid_hand_index(hand_index): return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player): return
	var item = world.get_entity(item_id)
	if item == null or player.hands[hand_index] != item: return
	if not Defs.is_within_tile_reach(player.tile_pos, tile): return
	world.rpc_drop_item_at.rpc(sender_id, item_id, tile, spread, hand_index)

func handle_rpc_drop_item_at(player_peer_id: int, item_id: String, tile: Vector2i, spread: float, hand_index: int) -> void:
	var player: Node2D = world.utils.find_player_by_peer(player_peer_id) as Node2D
	if player != null:
		player.hands[hand_index] = null
		if player._is_local_authority():
			player._update_hands_ui()
	var obj: Node = world.get_entity(item_id)
	if obj == null: return
	var sprite: Node = obj.get_node_or_null("Sprite2D")
	if sprite != null:
		sprite.rotation_degrees = 0.0
		sprite.scale = Vector2(abs(sprite.scale.x), abs(sprite.scale.y))

	var land_z = world.calculate_gravity_z(tile, player.z_level if player else obj.get("z_level"))
	world.rpc_set_object_z_level.rpc(item_id, land_z)
	obj.z_index = Defs.get_z_index(land_z, Defs.Z_OFFSET_ITEMS)

	world.objects.drop_item_at(obj, tile, spread)
	for child in obj.get_children():
		if child is CollisionShape2D: child.disabled = false

# ── Throw ─────────────────────────────────────────────────────────────────────

func handle_rpc_request_throw(sender_id: int, item_id: String, hand_index: int, dir: Vector2, throw_range: int, interaction_z: int) -> void:
	if not world.multiplayer.is_server() or not Defs.is_valid_hand_index(hand_index): return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player): return
	var item = world.get_entity(item_id)
	if item == null or player.hands[hand_index] != item: return
	if player.body != null and player.body.is_arm_broken(hand_index): return
	if not world.utils.server_check_action_cooldown(player, true): return
	var safe_range = int(clamp(throw_range, 1, player.THROW_TILES))
	var requested_z := clampi(interaction_z, player.z_level, min(player.z_level + 1, 5))
	var land_tile = world.utils.cast_throw(player.tile_pos, player.pixel_pos, requested_z, dir, safe_range)
	var travel_z = requested_z
	var land_z = world.calculate_gravity_z(land_tile, travel_z)
	var land_pixel = world.utils.tile_to_pixel(land_tile)
	world.rpc_confirm_throw.rpc(sender_id, item_id, hand_index, land_pixel, travel_z, land_z)

func handle_rpc_confirm_throw(peer_id: int, item_id: String, hand_index: int, land_pixel: Vector2, travel_z: int, land_z: int) -> void:
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	var obj    = world.get_entity(item_id)
	if player == null or obj == null: return
	player.hands[hand_index] = null
	if player._is_local_authority():
		player._is_throwing = true
		player._update_hands_ui()
	obj.set("z_level", travel_z)
	obj.z_index = Defs.get_z_index(travel_z, 7)
	var sprite: Node = obj.get_node_or_null("Sprite2D")
	if sprite != null:
		sprite.rotation_degrees = 0.0
		sprite.scale = Vector2(abs(sprite.scale.x), abs(sprite.scale.y))
	var spread_offset := Vector2(randf_range(-player.DROP_SPREAD, player.DROP_SPREAD), randf_range(-player.DROP_SPREAD, player.DROP_SPREAD))
	var final_pos := land_pixel + spread_offset
	var tween = world.get_tree().create_tween()
	tween.tween_property(obj, "global_position", final_pos, player.THROW_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		if player and player._is_local_authority(): player._is_throwing = false

		obj.set("z_level", land_z)
		obj.z_index = Defs.get_z_index(land_z, Defs.Z_OFFSET_ITEMS)

		for child in obj.get_children():
			if child is CollisionShape2D: child.disabled = false
		if world.multiplayer.is_server():
			var land_tile_check = Vector2i(int(land_pixel.x / world.TILE_SIZE), int(land_pixel.y / world.TILE_SIZE))
			var dmg = player._get_weapon_damage(obj) if player else 0
			var attacker_p    := world.utils.find_player_by_peer(peer_id) as Node2D
			var src_tile: Vector2i = attacker_p.tile_pos if attacker_p != null else land_tile_check
			var hit_results = world.combat.deal_damage_at_tile(land_tile_check, travel_z, dmg, peer_id, false)
			var throw_targets = world.utils.get_entities_at_tile(land_tile_check, travel_z, peer_id)
			for entity in throw_targets:
				if world.utils.is_ghost(entity):
					continue
				var target_name: String = ""
				if entity.is_in_group("player"): target_name = (entity as Node2D).character_name
				elif entity.has_method("receive_damage"): target_name = entity.name.get_slice("@", 0)
				if target_name != "":
					var roll = hit_results.get(entity, {"damage": dmg, "blocked": false})
					world.rpc_broadcast_damage_log.rpc(attacker_p.character_name if attacker_p else "Unknown", target_name, roll.damage, src_tile, travel_z, roll.blocked, false, "", roll.get("block_type", ""))
	)
