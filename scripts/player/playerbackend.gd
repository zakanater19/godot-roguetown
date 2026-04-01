# res://scripts/player/playerbackend.gd
extends RefCounted

var player: Node2D

var equipment = null
var actions   = null

var hand_offsets: Dictionary = {}
var clothing_offsets: Dictionary = {}

func _init(p_player: Node2D) -> void:
	player    = p_player
	equipment = preload("res://scripts/player/playerequipment.gd").new(p_player)
	actions   = preload("res://scripts/player/playeraction.gd").new(p_player)
	load_hand_offsets()
	load_clothing_offsets()

# ===========================================================================
# Description / Inspection
# ===========================================================================

func is_disguised() -> bool:
	if player.equipped.get("face") == "Hood":
		var face_data = player.equipped_data.get("face", null)
		if face_data is Dictionary and face_data.get("hood_up", false):
			return true
	return false

func get_description() -> String:
	var peer_id: int = player.get_multiplayer_authority()
	var is_me: bool  = (player.multiplayer.get_unique_id() == peer_id)

	var desc: String = player.character_name
	if not is_me and is_disguised():
		desc = "You cannot see their face"

	if player.dead:
		desc += " (dead)"
	elif player.sleep_state != player.SleepState.AWAKE:
		desc += " (sleeping)"
	return desc

func get_detailed_description() -> String:
	var peer_id: int = player.get_multiplayer_authority()
	var is_me: bool  = (player.multiplayer.get_unique_id() == peer_id)

	var title_col: String = get_inspect_color().to_html(false)
	var name_str = player.character_name

	if not is_me and is_disguised():
		name_str = "You cannot see their face"
		title_col = "888888"

	if is_me:
		name_str += " (You)"

	var desc: String = "[color=#" + title_col + "][b]" + name_str + "[/b][/color]"

	if player.dead:
		desc += " (dead)"
	elif player.sleep_state != player.SleepState.AWAKE:
		desc += " (sleeping)"

	if not (not is_me and is_disguised()):
		if player.character_class == "bandit":
			desc += "\n[color=purple][b][font_size=24]BANDIT!!![/font_size][/b][/color]"

	if player.hands[0] != null:
		var rhand_name = player.hands[0].get("item_type")
		if rhand_name == null or rhand_name == "":
			rhand_name = player.hands[0].name.get_slice("@", 0)
		desc += "\n[color=gray]right hand:[/color] " + rhand_name
	if player.hands[1] != null:
		var lhand_name = player.hands[1].get("item_type")
		if lhand_name == null or lhand_name == "":
			lhand_name = player.hands[1].name.get_slice("@", 0)
		desc += "\n[color=gray]left hand:[/color] " + lhand_name

	var slots_order: Array[String] = ["head", "face", "cloak", "armor", "backpack", "gloves", "waist", "clothing", "trousers", "feet", "pocket_l", "pocket_r"]
	for slot in slots_order:
		var item = player.equipped.get(slot, null)
		if item != null and item is String and item != "":
			desc += "\n[color=gray]" + slot + ":[/color] " + item

	if is_me and player.body != null:
		var limb_display: Array = [["head", "head"], ["chest", "chest"], ["r_arm", "right arm"], ["l_arm", "left arm"], ["r_leg", "right leg"], ["l_leg", "left leg"]]
		for entry in limb_display:
			var limb_key: String   = entry[0]
			var limb_label: String = entry[1]
			var damage_taken: int  = 70 - player.body.limb_hp[limb_key]
			if damage_taken > 0:
				desc += "\n[color=gray]" + limb_label + ":[/color] " + _get_limb_status(damage_taken)

	return desc

func _get_limb_status(damage_taken: int) -> String:
	if damage_taken >= 70:
		return "[color=#cc0000]broken[/color]"
	elif damage_taken >= 60:
		return "[color=#ff2200]mangled[/color]"
	elif damage_taken >= 40:
		return "[color=#ff6600]severely injured[/color]"
	elif damage_taken >= 20:
		return "[color=#ffaa00]injured[/color]"
	else:
		return "[color=#ffdd44]a little injured[/color]"

func get_inspect_color() -> Color:
	if player.dead:
		return Color.WHITE
	return Color(1.0, 0.0, 0.0)

func get_inspect_font_size() -> int:
	if player.dead:
		return 11
	return 14

func inspect_at(world_pos: Vector2) -> void:
	var target_tile := Vector2i(int(world_pos.x / World.TILE_SIZE), int(world_pos.y / World.TILE_SIZE))
	var best_npc:  Node  = null
	var best_dist: float = INF

	if target_tile == player.tile_pos:
		show_inspect_text(get_description(), get_detailed_description())
		return

	for i in range(2):
		var held = player.hands[i]
		if held == null or not is_instance_valid(held):
			continue
		var hand_tile := Vector2i(int(held.global_position.x / World.TILE_SIZE), int(held.global_position.y / World.TILE_SIZE))
		if hand_tile == target_tile:
			var hand_label := " (in right hand)" if i == 0 else " (in left hand)"
			var desc = held.get_description() if held.has_method("get_description") else (held.get("item_type") if held.get("item_type") != null else held.name.get_slice("@", 0))
			show_inspect_text(desc + hand_label, "")
			return

	for obj in World.get_entities_at_tile(target_tile, player.z_level):
		var d: float = (world_pos - player.global_position).length()
		if d < best_dist:
			best_dist = d
			best_npc  = obj

	if best_npc != null:
		if best_npc.has_method("get_description"):
			var short_desc = best_npc.get_description()

			if player.prices_shown and best_npc.get("item_type"):
				var p = Trade.get_price(best_npc.item_type)
				if p > 0: short_desc += "[Price: " + str(p) + "]"

			var detailed_desc = best_npc.get_detailed_description() if best_npc.has_method("get_detailed_description") else ""

			if best_npc.is_in_group("player") and best_npc != player:
				var is_npc_disguised = false
				if best_npc.get("backend") != null and best_npc.backend.has_method("is_disguised"):
					is_npc_disguised = best_npc.backend.is_disguised()

				if not is_npc_disguised:
					var outsiders = ["adventurer", "bandit"]
					if best_npc.character_class == "king":
						detailed_desc += "\n[color=#88ccaa]I know them as the king.[/color]"
					elif not (player.character_class in outsiders):
						if best_npc.character_class in outsiders:
							detailed_desc += "\n[color=#88ccaa]I know them as an outsider.[/color]"
						else:
							detailed_desc += "\n[color=#88ccaa]I know them as a " + best_npc.character_class + ".[/color]"
					else:
						detailed_desc += "\n[color=#88ccaa]I don't recognize them.[/color]"

			show_inspect_text(short_desc, detailed_desc)
		return

	for group in ["pickable", "minable_object", "inspectable", "choppable_object", "door", "breakable_object"]:
		var best: Node = null
		best_dist = INF
		for obj in player.get_tree().get_nodes_in_group(group):
			if obj.get("z_level") != null and obj.z_level != player.z_level:
				continue
			if group == "pickable" and (player.hands[0] == obj or player.hands[1] == obj):
				continue
			var col := obj.get_node_or_null("CollisionShape2D")
			if col != null and col.shape is RectangleShape2D:
				var extents:   Vector2 = col.shape.size / 2.0
				var local_pos: Vector2 = world_pos - obj.global_position
				if abs(local_pos.x) <= extents.x and abs(local_pos.y) <= extents.y:
					var d: float = local_pos.length()
					if d < best_dist:
						best_dist = d
						best      = obj
		if best != null:
			if best.has_method("get_description"):
				var short_desc = best.get_description()

				if player.prices_shown and best.get("item_type"):
					var p = Trade.get_price(best.item_type)
					if p > 0: short_desc += "[Price: " + str(p) + "]"

				var detailed_desc = best.get_detailed_description() if best.has_method("get_detailed_description") else ""
				show_inspect_text(short_desc, detailed_desc)
			return

	var source_id:    int      = -1
	var atlas_coords: Vector2i = Vector2i(-1, -1)
	var tm = World.get_tilemap(player.z_level)
	if tm != null:
		source_id    = tm.get_cell_source_id(target_tile)
		atlas_coords = tm.get_cell_atlas_coords(target_tile)
	show_inspect_text(World.get_tile_description(source_id, atlas_coords), "")

func show_inspect_text(text: String, detailed_desc: String) -> void:
	var log_msg = detailed_desc if detailed_desc != "" else text
	Sidebar.add_message(log_msg)

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

	player.equipped = {
		"head": null, "face": null, "cloak": null, "armor": null,
		"backpack": null, "gloves": null, "waist": null, "clothing": null,
		"trousers": null, "feet": null, "pocket_l": null, "pocket_r": null
	}

	player.equipped_data = {
		"head": null, "face": null, "cloak": null, "armor": null,
		"backpack": null, "gloves": null, "waist": null, "clothing": null,
		"trousers": null, "feet": null, "pocket_l": null, "pocket_r": null
	}

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
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - player.last_exertion_time >= 5.0:
		if player.stamina < player.max_stamina:
			player.stamina = clamp(player.stamina + (delta * 1.0), 0.0, player.max_stamina)
			if player.exhausted and player.stamina >= 10.0:
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

	var base_y: float = -10.0 if item_name == "Sword" else 0.0
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
		if item_name == "Sword":
			res.rotation = 45.0
	return res

func get_clothing_transform(item_name: String, facing_name: String) -> Dictionary:
	if clothing_offsets.has(item_name) and clothing_offsets[item_name].has(facing_name):
		var entry = clothing_offsets[item_name][facing_name]
		return {
			"offset": Vector2(float(entry.get("offset", [0, 0])[0]), float(entry.get("offset", [0, 0])[1])),
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
