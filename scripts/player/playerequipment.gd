# res://scripts/player/playerequipment.gd
extends RefCounted

var player: Node2D

func _init(p_player: Node2D) -> void:
	player = p_player

# ===========================================================================
# Equipment Management
# ===========================================================================

func equip_clothing(item: Node) -> void:
	var item_slot: String = item.get("slot")
	if item_slot == null or item_slot == "":
		return
	var item_id := World.get_entity_id(item)
	if player.multiplayer.is_server():
		World.rpc_request_equip(item_id, item_slot, player.active_hand)
	else:
		World.rpc_request_equip.rpc_id(1, item_id, item_slot, player.active_hand)

func equip_clothing_to_slot(item: Node, slot_name: String) -> void:
	var item_id := World.get_entity_id(item)
	if player.multiplayer.is_server():
		World.rpc_request_equip(item_id, slot_name, player.active_hand)
	else:
		World.rpc_request_equip.rpc_id(1, item_id, slot_name, player.active_hand)

func perform_equip(item: Node, slot_name: String, hand_index: int) -> void:
	var item_name = item.get("item_type")
	if item_name == null: item_name = item.name.get_slice("@", 0)
	player.equipped[slot_name] = item_name

	var data_to_save = {}
	if "contents" in item:
		data_to_save["contents"] = item.get("contents").duplicate(true)
	if "amount" in item:
		data_to_save["amount"] = item.get("amount")
	if "metal_type" in item:
		data_to_save["metal_type"] = item.get("metal_type")
	if "key_id" in item:
		data_to_save["key_id"] = item.get("key_id")

	if not data_to_save.is_empty():
		player.equipped_data[slot_name] = data_to_save
	else:
		player.equipped_data[slot_name] = null

	player.hands[hand_index] = null
	item.queue_free()

	if player._is_local_authority():
		player._update_hands_ui()
		player._apply_action_cooldown(null)
		if player._hud != null:
			player._hud.update_clothing_display(player.equipped, player.equipped_data)

	player._update_clothing_sprites()

	if player.misc and player.misc.loot_target != null and is_instance_valid(player.misc.loot_target):
		player.misc.refresh_loot_panel()

func sync_equip_state(slot_name: String, hand_index: int, item_type: String, slot_data: Variant, expected_item_id: String = "") -> void:
	_clear_hand_for_sync(hand_index, expected_item_id)
	if item_type != "":
		player.equipped[slot_name] = item_type
	else:
		player.equipped[slot_name] = null
	player.equipped_data[slot_name] = _duplicate_slot_data(slot_data)
	_refresh_after_equipment_change(true)

func unequip_clothing_from_slot(slot_name: String) -> void:
	var _equipped_val = player.equipped.get(slot_name)
	if not (_equipped_val is String) or _equipped_val == "":
		return
	if player.multiplayer.is_server():
		World.rpc_request_unequip(slot_name, player.active_hand)
	else:
		World.rpc_request_unequip.rpc_id(1, slot_name, player.active_hand)

func perform_unequip(slot_name: String, new_entity_id: String, hand_index: int) -> void:
	var _raw = player.equipped.get(slot_name)
	var item_name: String = _raw if _raw is String else ""
	if item_name == "":
		return

	var scene_path = ItemRegistry.get_scene_path(item_name)
	if scene_path == "":
		return

	var scene := load(scene_path) as PackedScene
	if scene == null:
		return

	var item: Node2D = scene.instantiate()
	item.position = player.pixel_pos
	item.set("z_level", player.z_level)

	if player.equipped_data.get(slot_name) != null:
		var data = player.equipped_data[slot_name]
		if "contents" in data and "contents" in item:
			item.set("contents", data["contents"].duplicate(true))
		if "amount" in data and "amount" in item:
			item.set("amount", data["amount"])
		if "metal_type" in data and "metal_type" in item:
			item.set("metal_type", data["metal_type"])
		if "key_id" in data and "key_id" in item:
			item.set("key_id", data["key_id"])

	player.equipped_data[slot_name] = null

	item.set_meta("entity_id", new_entity_id)
	player.get_parent().add_child(item)
	if item.has_method("_update_sprite"):
		item._update_sprite()
	World.register_entity(item, new_entity_id)

	player.hands[hand_index] = item
	for child in item.get_children():
		if child is CollisionShape2D:
			child.disabled = true
	player.equipped[slot_name] = null

	if player._is_local_authority():
		player._update_hands_ui()
		if player._hud != null:
			player._hud.update_clothing_display(player.equipped, player.equipped_data)

	player._update_clothing_sprites()

	if player.misc and player.misc.loot_target != null and is_instance_valid(player.misc.loot_target):
		player.misc.refresh_loot_panel()

func sync_unequip_state(slot_name: String, new_entity_id: String, hand_index: int, item_type: String, slot_data: Variant = null) -> void:
	_clear_hand_for_sync(hand_index)
	if item_type == "":
		player.equipped[slot_name] = null
		player.equipped_data[slot_name] = null
		_refresh_after_equipment_change(false)
		return

	var scene_path := ItemRegistry.get_scene_path(item_type)
	if scene_path == "":
		player.equipped[slot_name] = null
		player.equipped_data[slot_name] = null
		_refresh_after_equipment_change(false)
		return

	var scene := load(scene_path) as PackedScene
	if scene == null:
		player.equipped[slot_name] = null
		player.equipped_data[slot_name] = null
		_refresh_after_equipment_change(false)
		return

	var item: Node2D = scene.instantiate()
	item.position = player.pixel_pos
	item.set("z_level", player.z_level)

	var restored_data: Variant = _duplicate_slot_data(slot_data)
	if restored_data is Dictionary:
		if "contents" in restored_data and "contents" in item:
			item.set("contents", restored_data["contents"].duplicate(true))
		if "amount" in restored_data and "amount" in item:
			item.set("amount", restored_data["amount"])
		if "metal_type" in restored_data and "metal_type" in item:
			item.set("metal_type", restored_data["metal_type"])
		if "key_id" in restored_data and "key_id" in item:
			item.set("key_id", restored_data["key_id"])

	item.set_meta("entity_id", new_entity_id)
	player.get_parent().add_child(item)
	if item.has_method("_update_sprite"):
		item._update_sprite()
	World.register_entity(item, new_entity_id)

	player.hands[hand_index] = item
	for child in item.get_children():
		if child is CollisionShape2D:
			child.disabled = true
	player.equipped[slot_name] = null
	player.equipped_data[slot_name] = null
	_refresh_after_equipment_change(false)

func _clear_hand_for_sync(hand_index: int, expected_item_id: String = "") -> void:
	if hand_index < 0 or hand_index >= player.hands.size():
		return
	var held_item: Node = player.hands[hand_index]
	player.hands[hand_index] = null
	if held_item == null or not is_instance_valid(held_item):
		return
	var held_entity_id := str(held_item.get_meta("entity_id", ""))
	if expected_item_id != "" and held_entity_id != "" and held_entity_id != expected_item_id:
		return
	World.unregister_entity(held_item)
	held_item.queue_free()

func _duplicate_slot_data(slot_data: Variant) -> Variant:
	if slot_data is Dictionary:
		return slot_data.duplicate(true) if not slot_data.is_empty() else null
	if slot_data is Array:
		return slot_data.duplicate(true)
	return slot_data

func _refresh_after_equipment_change(apply_cooldown: bool) -> void:
	if player._is_local_authority():
		player._update_hands_ui()
		if apply_cooldown:
			player._apply_action_cooldown(null)
		if player._hud != null:
			player._hud.update_clothing_display(player.equipped, player.equipped_data)

	player._update_clothing_sprites()

	if player.misc and player.misc.loot_target != null and is_instance_valid(player.misc.loot_target):
		player.misc.refresh_loot_panel()
