# res://scripts/player/playerbackend.gd
extends RefCounted

var player: Node2D

var equipment = null
var actions   = null

# Description / inspection is handled by playerinspect.gd (player.inspect).

var hand_offsets: Dictionary = {}
var clothing_offsets: Dictionary = {}

func _init(p_player: Node2D) -> void:
	player    = p_player
	equipment = preload("res://scripts/player/playerequipment.gd").new(p_player)
	actions   = preload("res://scripts/player/playeraction.gd").new(p_player)
	load_hand_offsets()
	load_clothing_offsets()

# ===========================================================================
# Description / Inspection  (delegated to player.inspect)
# ===========================================================================

func is_disguised() -> bool:
	return player.inspect.is_disguised() if player.inspect else false

# ===========================================================================
# Class Initialization
# ===========================================================================

func apply_class_defaults() -> void:
	var class_data = Classes.DATA.get(player.character_class, Classes.DATA["peasant"])
	player.skills = class_data["skills"].duplicate()
	player.prices_shown = class_data.get("prices_shown", false)

	var base_stats = class_data.get("stats", {})
	player.stats = {}
	for stat_name in base_stats:
		var base_val = base_stats[stat_name]
		var variation = randi_range(-1, 1)
		player.stats[stat_name] = clamp(base_val + variation, 0, 20)

	player.equipped      = {}
	player.equipped_data = {}
	for s in Defs.SLOTS_ALL:
		player.equipped[s]      = null
		player.equipped_data[s] = null

	for slot in class_data["equipment"]:
		player.equipped[slot] = class_data["equipment"][slot]

	player._update_clothing_sprites()
	if player._is_local_authority() and player._hud != null:
		player._hud.update_clothing_display(player.equipped, player.equipped_data)

# ===========================================================================
# Stamina Logic
# ===========================================================================

func spend_stamina(amount: float) -> void:
	player.stamina = clamp(player.stamina - amount, 0.0, player.max_stamina)
	player.last_exertion_time = Time.get_ticks_msec() / 1000.0

func check_stamina_regen(delta: float) -> void:
	if not player._is_local_authority():
		return

	if player.combat_mode:
		player.stamina = clamp(player.stamina - (delta * 0.25), 0.0, player.max_stamina)
		if player.stamina <= 0.0 and not player.exhausted:
			player.exhausted = true
			Sidebar.add_message("[color=#ffaaaa]You overexerted yourself![/color]")
	else:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - player.last_exertion_time >= CombatDefs.STAMINA_REGEN_DELAY:
			if player.stamina < player.max_stamina:
				player.stamina = clamp(player.stamina + (delta * CombatDefs.STAMINA_REGEN_RATE), 0.0, player.max_stamina)
				if player.exhausted and player.stamina >= CombatDefs.STAMINA_EXHAUSTION_THRESHOLD:
					player.exhausted = false
					Sidebar.add_message("[color=#aaffaa]You have caught your breath.[/color]")

# ===========================================================================
# Offsets Loading
# ===========================================================================

func load_hand_offsets() -> void:
	var path := "res://objects/hand_offsets.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		hand_offsets = parsed

func load_clothing_offsets() -> void:
	var path := "res://clothing/clothing_offsets.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		clothing_offsets = parsed

func get_hand_transform(item_name: String, facing_name: String, hand: String) -> Dictionary:
	var res = {"offset": Vector2.ZERO, "flip_h": false, "rotation": 0.0, "scale": 1.0}

	if hand_offsets.has(item_name) and hand_offsets[item_name].has(facing_name):
		var entry = hand_offsets[item_name][facing_name]
		if entry.has(hand):
			var arr = entry[hand]
			res.offset = Vector2(float(arr[0]), float(arr[1]))
		res.flip_h   = entry.get(hand + "_flipped", false)
		res.rotation = float(entry.get(hand + "_rotation", 0.0))
		res.scale    = float(entry.get(hand + "_scale", 1.0))
		return res

	var _fallback_data = ItemRegistry.get_by_type(item_name)
	var base_y: float = _fallback_data.hand_offset_y if _fallback_data != null else 0.0
	if hand == "right":
		match facing_name:
			"south": res.offset = Vector2( 20.0,   8.0 + base_y)
			"north": res.offset = Vector2( 20.0, -10.0 + base_y)
			"east":  res.offset = Vector2( 16.0,   8.0 + base_y)
			"west":  res.offset = Vector2(-16.0,   8.0 + base_y)
	elif hand == "left":
		match facing_name:
			"south": res.offset = Vector2(-20.0,  10.0 + base_y)
			"north": res.offset = Vector2(-20.0,  -8.0 + base_y)
			"east":  res.offset = Vector2(-16.0,  10.0 + base_y)
			"west":  res.offset = Vector2( 16.0,  10.0 + base_y)
	elif hand == "waist":
		match facing_name:
			"south": res.offset = Vector2( 12.0, 4.0)
			"north": res.offset = Vector2(-12.0, 4.0)
			"east":  res.offset = Vector2(  0.0, 4.0)
			"west":  res.offset = Vector2(  0.0, 4.0)
		var _wd = ItemRegistry.get_by_type(item_name)
		if _wd != null: res.rotation = _wd.waist_rotation
	return res

func get_clothing_transform(item_name: String, facing_name: String) -> Dictionary:
	if clothing_offsets.has(item_name) and clothing_offsets[item_name].has(facing_name):
		var entry = clothing_offsets[item_name][facing_name]
		return {
			"offset": Vector2(float(entry.get("offset",[0, 0])[0]), float(entry.get("offset",[0, 0])[1])),
			"scale":  float(entry.get("scale", 1.0))
		}
	return {"offset": Vector2.ZERO, "scale": 1.0}

# ===========================================================================
# Equipment delegation
# ===========================================================================

func equip_clothing(item: Node) -> void:                                              equipment.equip_clothing(item)
func equip_clothing_to_slot(item: Node, slot_name: String) -> void:                  equipment.equip_clothing_to_slot(item, slot_name)
func perform_equip(item: Node, slot_name: String, hand_index: int) -> void:          equipment.perform_equip(item, slot_name, hand_index)
func unequip_clothing_from_slot(slot_name: String) -> void:                          equipment.unequip_clothing_from_slot(slot_name)
func perform_unequip(slot_name: String, new_node_name: String, hand_index: int) -> void: equipment.perform_unequip(slot_name, new_node_name, hand_index)

# ===========================================================================
# Action delegation
# ===========================================================================

func apply_action_cooldown(item: Node, is_attack: bool = false) -> void: actions.apply_action_cooldown(item, is_attack)
func face_toward(world_pos: Vector2) -> void:                             actions.face_toward(world_pos)
func on_object_picked_up(object_node: Node) -> void:                     actions.on_object_picked_up(object_node)
func drop_item_from_hand(hand_idx: int) -> void:                         actions.drop_item_from_hand(hand_idx)
func drop_held_object() -> void:                                          actions.drop_held_object()
func throw_held_object(mouse_world_pos: Vector2) -> void:                actions.throw_held_object(mouse_world_pos)
func interact_held_object() -> void:                                      actions.interact_held_object()
func use_held_object(mouse_world_pos: Vector2) -> void:                  actions.use_held_object(mouse_world_pos)