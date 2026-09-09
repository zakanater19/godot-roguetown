# res://scripts/world/objects/world_storage.gd
# Handles: satchel and equipped-pouch insert/extract, table placement
extends RefCounted

var world: Node

func _init(p_world: Node) -> void:
	world = p_world

# ── Satchel ───────────────────────────────────────────────────────────────────

func handle_rpc_request_satchel_insert(sender_id: int, satchel_id: String, hand_idx: int) -> void:
	if not world.multiplayer.is_server() or not Defs.is_valid_hand_index(hand_idx): return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player): return
	var satchel: Node = world.get_entity(satchel_id)
	if satchel == null or satchel.get("z_level") != player.z_level: return
	if not world.utils.is_within_interaction_range(player, satchel.global_position): return
	var item: Node = player.hands[hand_idx]
	if item == null or not is_instance_valid(item): return
	var itype: String = item.get("item_type") if item.get("item_type") != null else item.name.get_slice("@", 0)

	var scene_path = ItemRegistry.get_scene_path(itype)
	if scene_path == "": return

	var slot_index: int = -1
	for i in satchel.contents.size():
		if satchel.contents[i] == null:
			slot_index = i
			break
	if slot_index == -1: return

	var item_state = {}
	if "amount" in item: item_state["amount"] = item.get("amount")
	if "metal_type" in item: item_state["metal_type"] = item.get("metal_type")
	if "contents" in item: item_state["contents"] = item.get("contents").duplicate(true)
	if "key_id" in item: item_state["key_id"] = item.get("key_id")

	world.rpc_confirm_satchel_insert.rpc(sender_id, satchel_id, world.get_entity_id(item), hand_idx, slot_index, scene_path, itype, item_state)

func handle_rpc_confirm_satchel_insert(peer_id: int, satchel_id: String, _item_id: String, hand_idx: int, slot_index: int, scene_path: String, itype: String, item_state: Dictionary) -> void:
	var satchel: Node = world.get_entity(satchel_id)
	if satchel == null: return
	if slot_index >= 0 and slot_index < satchel.contents.size():
		satchel.contents[slot_index] = {"scene_path": scene_path, "item_type": itype, "state": item_state}
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	if player != null:
		if player.hands[hand_idx] != null and is_instance_valid(player.hands[hand_idx]):
			world.unregister_entity(player.hands[hand_idx])
			player.hands[hand_idx].queue_free()
		player.hands[hand_idx] = null
		if player._is_local_authority():
			player._update_hands_ui()
	if satchel.has_method("_refresh_ui"): satchel._refresh_ui()

func handle_rpc_request_satchel_extract(sender_id: int, satchel_id: String, slot_index: int, hand_idx: int) -> void:
	if not world.multiplayer.is_server() or not Defs.is_valid_hand_index(hand_idx): return
	if slot_index < 0 or slot_index >= Defs.SATCHEL_SLOT_COUNT: return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player): return
	if player.hands[hand_idx] != null: return
	if player.body != null and player.body.is_arm_broken(hand_idx): return
	var satchel: Node = world.get_entity(satchel_id)
	if satchel == null or satchel.get("z_level") != player.z_level: return
	if not world.utils.is_within_interaction_range(player, satchel.global_position): return
	if slot_index >= satchel.contents.size(): return
	var slot = satchel.contents[slot_index]
	if slot == null: return
	var scene_path: String = slot.get("scene_path", "")
	if scene_path == "": return
	var item_state: Dictionary = slot.get("state", {})
	var new_entity_id: String = world._make_entity_id("satchel_extract")
	world.rpc_confirm_satchel_extract.rpc(sender_id, satchel_id, slot_index, hand_idx, new_entity_id, scene_path, item_state)

func handle_rpc_confirm_satchel_extract(peer_id: int, satchel_id: String, slot_index: int, hand_idx: int, new_entity_id: String, scene_path: String, item_state: Dictionary) -> void:
	var satchel: Node = world.get_entity(satchel_id)
	if satchel == null: return
	if slot_index >= 0 and slot_index < satchel.contents.size():
		satchel.contents[slot_index] = null
	var scene := load(scene_path) as PackedScene
	if scene == null: return
	var item: Node2D = scene.instantiate()
	item.position = satchel.global_position
	item.set("z_level", satchel.z_level)

	if item_state.has("amount") and "amount" in item: item.set("amount", item_state["amount"])
	if item_state.has("metal_type") and "metal_type" in item: item.set("metal_type", item_state["metal_type"])
	if item_state.has("contents") and "contents" in item: item.set("contents", item_state["contents"].duplicate(true))
	if item_state.has("key_id") and "key_id" in item: item.set("key_id", item_state["key_id"])

	item.set_meta("entity_id", new_entity_id)
	satchel.get_parent().add_child(item)
	if item.has_method("_update_sprite"): item._update_sprite()
	world.register_entity(item, new_entity_id)
	for child in item.get_children():
		if child is CollisionShape2D: child.disabled = true
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	if player != null:
		player.hands[hand_idx] = item
		if player._is_local_authority():
			player._update_hands_ui()
	if satchel.has_method("_refresh_ui"): satchel._refresh_ui()

# ── Equipped pouch ───────────────────────────────────────────────────────────

func handle_rpc_request_equipped_pouch_insert(sender_id: int, pocket_slot: String, hand_idx: int) -> void:
	if not world.multiplayer.is_server() or not Defs.is_valid_hand_index(hand_idx): return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player): return
	if player.body != null and player.body.is_arm_broken(hand_idx): return
	if not _is_equipped_pouch(player, pocket_slot): return

	var item: Node = player.hands[hand_idx]
	if item == null or not is_instance_valid(item): return
	if item.get("too_large_for_satchel") == true: return
	var item_type: String = item.get("item_type") if item.get("item_type") != null else item.name.get_slice("@", 0)
	var scene_path := ItemRegistry.get_scene_path(item_type)
	if scene_path == "": return

	var contents := _get_pouch_contents(player, pocket_slot)
	var slot_index := contents.find(null)
	if slot_index < 0: return

	var item_state := _capture_item_state(item)
	world.rpc_confirm_equipped_pouch_insert.rpc(
		sender_id,
		pocket_slot,
		world.get_entity_id(item),
		hand_idx,
		slot_index,
		scene_path,
		item_type,
		item_state
	)

func handle_rpc_confirm_equipped_pouch_insert(peer_id: int, pocket_slot: String, item_id: String, hand_idx: int, slot_index: int, scene_path: String, item_type: String, item_state: Dictionary) -> void:
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	if not _is_equipped_pouch(player, pocket_slot): return
	if slot_index < 0 or slot_index >= Defs.POUCH_SLOT_COUNT: return

	var pouch_data := _get_pouch_data(player, pocket_slot)
	var contents: Array = pouch_data["contents"]
	contents[slot_index] = {"scene_path": scene_path, "item_type": item_type, "state": item_state}
	pouch_data["contents"] = contents
	player.equipped_data[pocket_slot] = pouch_data

	var held_item: Node = player.hands[hand_idx] if Defs.is_valid_hand_index(hand_idx) else null
	if held_item != null and is_instance_valid(held_item) and world.get_entity_id(held_item) == item_id:
		world.unregister_entity(held_item)
		held_item.queue_free()
		player.hands[hand_idx] = null
		if player._is_local_authority():
			player._update_hands_ui()
	_refresh_equipped_pouch_ui(player, pocket_slot)

func handle_rpc_request_equipped_pouch_extract(sender_id: int, pocket_slot: String, slot_index: int, hand_idx: int) -> void:
	if not world.multiplayer.is_server() or not Defs.is_valid_hand_index(hand_idx): return
	if slot_index < 0 or slot_index >= Defs.POUCH_SLOT_COUNT: return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player): return
	if player.hands[hand_idx] != null: return
	if player.body != null and player.body.is_arm_broken(hand_idx): return
	if not _is_equipped_pouch(player, pocket_slot): return

	var contents := _get_pouch_contents(player, pocket_slot)
	var entry = contents[slot_index]
	if entry == null: return
	var scene_path := str(entry.get("scene_path", ""))
	if scene_path == "": return
	var item_state: Dictionary = entry.get("state", {}).duplicate(true)
	var new_entity_id: String = world._make_entity_id("pouch_extract")
	world.rpc_confirm_equipped_pouch_extract.rpc(sender_id, pocket_slot, slot_index, hand_idx, new_entity_id, scene_path, item_state)

func handle_rpc_confirm_equipped_pouch_extract(peer_id: int, pocket_slot: String, slot_index: int, hand_idx: int, new_entity_id: String, scene_path: String, item_state: Dictionary) -> void:
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	if not _is_equipped_pouch(player, pocket_slot): return
	if not Defs.is_valid_hand_index(hand_idx) or player.hands[hand_idx] != null: return
	if slot_index < 0 or slot_index >= Defs.POUCH_SLOT_COUNT: return

	var pouch_data := _get_pouch_data(player, pocket_slot)
	var contents: Array = pouch_data["contents"]
	if contents[slot_index] == null: return
	contents[slot_index] = null
	pouch_data["contents"] = contents
	player.equipped_data[pocket_slot] = pouch_data

	var scene := load(scene_path) as PackedScene
	if scene == null: return
	var item := scene.instantiate() as Node2D
	if item == null: return
	item.position = player.pixel_pos
	item.set("z_level", player.z_level)
	_restore_item_state(item, item_state)
	item.set_meta("entity_id", new_entity_id)
	player.get_parent().add_child(item)
	if item.has_method("_update_sprite"): item._update_sprite()
	world.register_entity(item, new_entity_id)
	for child in item.get_children():
		if child is CollisionShape2D: child.disabled = true
	player.hands[hand_idx] = item
	if player._is_local_authority():
		player._update_hands_ui()
	_refresh_equipped_pouch_ui(player, pocket_slot)

func _is_equipped_pouch(player: Node, pocket_slot: String) -> bool:
	return (
		player != null
		and pocket_slot in ["pocket_1", "pocket_2"]
		and player.equipped.get(pocket_slot) == "Pouch"
	)

func _get_pouch_data(player: Node, pocket_slot: String) -> Dictionary:
	var raw_data = player.equipped_data.get(pocket_slot, {})
	var pouch_data: Dictionary = raw_data.duplicate(true) if raw_data is Dictionary else {}
	var raw_contents = pouch_data.get("contents", [])
	var contents: Array = raw_contents.duplicate(true) if raw_contents is Array else []
	contents.resize(Defs.POUCH_SLOT_COUNT)
	pouch_data["contents"] = contents
	return pouch_data

func _get_pouch_contents(player: Node, pocket_slot: String) -> Array:
	return _get_pouch_data(player, pocket_slot)["contents"]

func _capture_item_state(item: Node) -> Dictionary:
	var item_state := {}
	if "amount" in item: item_state["amount"] = item.get("amount")
	if "metal_type" in item: item_state["metal_type"] = item.get("metal_type")
	if "contents" in item: item_state["contents"] = item.get("contents").duplicate(true)
	if "key_id" in item: item_state["key_id"] = item.get("key_id")
	return item_state

func _restore_item_state(item: Node, item_state: Dictionary) -> void:
	if item_state.has("amount") and "amount" in item: item.set("amount", item_state["amount"])
	if item_state.has("metal_type") and "metal_type" in item: item.set("metal_type", item_state["metal_type"])
	if item_state.has("contents") and "contents" in item: item.set("contents", item_state["contents"].duplicate(true))
	if item_state.has("key_id") and "key_id" in item: item.set("key_id", item_state["key_id"])

func _refresh_equipped_pouch_ui(player: Node, pocket_slot: String) -> void:
	var hud = player.get("_hud")
	if hud != null and hud.has_method("refresh_equipped_pouch"):
		hud.refresh_equipped_pouch(pocket_slot)

# ── Table placement ───────────────────────────────────────────────────────────

func handle_rpc_request_table_place(sender_id: int, table_id: String, hand_idx: int, place_pos: Vector2) -> void:
	if not world.multiplayer.is_server() or not Defs.is_valid_hand_index(hand_idx): return
	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player): return
	if player.body != null and player.body.is_arm_broken(hand_idx): return
	var table = world.get_entity(table_id)
	if table == null: return
	if not world.utils.is_within_interaction_range(player, table.global_position): return
	var item: Node = player.hands[hand_idx]
	if item == null or not is_instance_valid(item): return
	world.rpc_confirm_table_place.rpc(sender_id, table_id, hand_idx, place_pos)

func handle_rpc_confirm_table_place(peer_id: int, table_id: String, hand_idx: int, place_pos: Vector2) -> void:
	var player: Node2D = world.utils.find_player_by_peer(peer_id) as Node2D
	if player == null: return
	var item: Node = player.hands[hand_idx]
	if item == null or not is_instance_valid(item): return
	var table = world.get_entity(table_id)
	if table == null: return
	player.hands[hand_idx] = null
	if player._is_local_authority():
		player._update_hands_ui()
	var sprite: Node = item.get_node_or_null("Sprite2D")
	if sprite != null:
		sprite.rotation_degrees = 0.0
		sprite.scale = Vector2(abs(sprite.scale.x), abs(sprite.scale.y))
	item.global_position = place_pos
	item.set("z_level", table.z_level)
	item.z_index = Defs.get_z_index(table.z_level, 3)
	for child in item.get_children():
		if child is CollisionShape2D: child.disabled = false
