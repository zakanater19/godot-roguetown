# res://scripts/world/objects/world_storage.gd
# Handles: satchel insert/extract, table placement
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
