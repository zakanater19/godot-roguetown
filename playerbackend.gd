# res://playerbackend.gd
extends RefCounted

var player: Node2D

var hand_offsets: Dictionary = {}
var clothing_offsets: Dictionary = {}

func _init(p_player: Node2D) -> void:
	player = p_player
	load_hand_offsets()
	load_clothing_offsets()

# ===========================================================================
# Description / Inspection
# ===========================================================================

func get_description() -> String:
	var desc: String = player.character_name
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
	if is_me:
		name_str += " (You)"

	var desc: String = "[color=#" + title_col + "][b]" + name_str + "[/b][/color]"
	
	if player.dead:
		desc += " (dead)"
	elif player.sleep_state != player.SleepState.AWAKE:
		desc += " (sleeping)"
		
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

	var slots_order: Array[String] =["head", "cloak", "armor", "backpack", "waist", "clothing", "trousers", "feet"]
	for slot in slots_order:
		var item = player.equipped.get(slot, null)
		if item != null and item is String and item != "":
			desc += "\n[color=gray]" + slot + ":[/color] " + item

	if is_me and player.body != null:
		var limb_display: Array =[["head",  "head"],["chest", "chest"],["r_arm", "right arm"],["l_arm", "left arm"],["r_leg", "right leg"],["l_leg", "left leg"],
		]
		for entry in limb_display:
			var limb_key: String    = entry[0]
			var limb_label: String  = entry[1]
			var damage_taken: int   = 70 - player.body.limb_hp[limb_key]
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

	# Self-inspect: if clicking on own tile, show self (equipped clothing + hands)
	if target_tile == player.tile_pos:
		show_inspect_text(get_description(), get_detailed_description())
		return

	# Check held items explicitly
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

	# Check NPCs
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
			show_inspect_text(short_desc, detailed_desc)
		return

	# Check Objects
	for group in["pickable", "minable_object", "inspectable", "choppable_object", "door", "breakable_object"]:
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

	# Check Tiles
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
		"head":     null,
		"cloak":    null,
		"armor":    null,
		"backpack": null,
		"waist":    null,
		"clothing": null,
		"trousers": null,
		"feet":     null,
	}
	
	player.equipped_data = {
		"head":     null,
		"cloak":    null,
		"armor":    null,
		"backpack": null,
		"waist":    null,
		"clothing": null,
		"trousers": null,
		"feet":     null,
	}
	
	for slot in class_data["equipment"]:
		player.equipped[slot] = class_data["equipment"][slot]
		
	player._update_clothing_sprites()
	if player._is_local_authority() and player._hud != null:
		player._hud.update_clothing_display(player.equipped)

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
		res.flip_h = entry.get(hand + "_flipped", false)
		res.rotation = float(entry.get(hand + "_rotation", 0.0))
		res.scale = float(entry.get(hand + "_scale", 1.0))
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
			"south": res.offset = Vector2( 12.0,   4.0)
			"north": res.offset = Vector2(-12.0,   4.0)
			"east":  res.offset = Vector2(  0.0,   4.0)
			"west":  res.offset = Vector2(  0.0,   4.0)
		if item_name == "Sword":
			res.rotation = 45.0
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
# Equipment Management
# ===========================================================================

func equip_clothing(item: Node) -> void:
	var item_slot: String = item.get("slot")
	if item_slot == null or item_slot == "":
		return
	if player.multiplayer.is_server():
		World.rpc_request_equip(item.get_path(), item_slot, player.active_hand)
	else:
		World.rpc_request_equip.rpc_id(1, item.get_path(), item_slot, player.active_hand)

func equip_clothing_to_slot(item: Node, slot_name: String) -> void:
	if player.multiplayer.is_server():
		World.rpc_request_equip(item.get_path(), slot_name, player.active_hand)
	else:
		World.rpc_request_equip.rpc_id(1, item.get_path(), slot_name, player.active_hand)

func perform_equip(item: Node, slot_name: String, hand_index: int) -> void:
	var item_name = item.get("item_type")
	if item_name == null: item_name = item.name.get_slice("@", 0)
	player.equipped[slot_name] = item_name
	
	if "contents" in item:
		player.equipped_data[slot_name] = {"contents": item.get("contents").duplicate(true)}
	else:
		player.equipped_data[slot_name] = null
		
	player.hands[hand_index] = null
	item.queue_free()

	if player._is_local_authority():
		player._update_hands_ui()
		apply_action_cooldown(null)
		if player._hud != null:
			player._hud.update_clothing_display(player.equipped)

	player._update_clothing_sprites()

	if player.misc and player.misc.loot_target != null and is_instance_valid(player.misc.loot_target):
		player.misc.refresh_loot_panel()

func unequip_clothing_from_slot(slot_name: String) -> void:
	if player.equipped.get(slot_name, "") == "":
		return
	if player.multiplayer.is_server():
		World.rpc_request_unequip(slot_name, player.active_hand)
	else:
		World.rpc_request_unequip.rpc_id(1, slot_name, player.active_hand)

func perform_unequip(slot_name: String, new_node_name: String, hand_index: int) -> void:
	var item_name: String = player.equipped.get(slot_name, "")
	if item_name == "":
		return
		
	var scene_path = ItemRegistry.get_scene_path(item_name)
	if scene_path == "":
		return
		
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return

	var item: Node2D = scene.instantiate()
	item.name     = new_node_name
	item.position = player.pixel_pos
	item.set("z_level", player.z_level)
	
	if player.equipped_data.get(slot_name) != null:
		if "contents" in player.equipped_data[slot_name] and "contents" in item:
			item.set("contents", player.equipped_data[slot_name]["contents"].duplicate(true))
	player.equipped_data[slot_name] = null
	
	player.get_parent().add_child(item)

	player.hands[hand_index] = item
	for child in item.get_children():
		if child is CollisionShape2D:
			child.disabled = true
	player.equipped[slot_name] = null

	if player._is_local_authority():
		player._update_hands_ui()
		if player._hud != null:
			player._hud.update_clothing_display(player.equipped)

	player._update_clothing_sprites()

	if player.misc and player.misc.loot_target != null and is_instance_valid(player.misc.loot_target):
		player.misc.refresh_loot_panel()

# ===========================================================================
# Action Execution
# ===========================================================================

func apply_action_cooldown(item: Node, is_attack: bool = false) -> void:
	var delay = 0.5
	if item != null and item.has_method("get_use_delay"):
		delay = item.get_use_delay()

	if is_attack and delay < 1.0:
		delay = 1.0

	if player.exhausted:
		delay *= 3.0

	player.action_cooldown = delay

func face_toward(world_pos: Vector2) -> void:
	var delta: Vector2 = world_pos - player.pixel_pos
	if abs(delta.x) >= abs(delta.y):
		player.facing = 2 if delta.x >= 0 else 3
	else:
		player.facing = 0 if delta.y >= 0 else 1
	player._update_sprite()

func on_object_picked_up(object_node: Node) -> void:
	if not player._is_local_authority():
		return
		
	var active_item = player.hands[player.active_hand]
	if active_item != null:
		# Combine ground coins
		if active_item.get("is_coin_stack") and object_node.get("is_coin_stack"):
			if active_item.get("item_type") == object_node.get("item_type"):
				if player.multiplayer.is_server():
					World.rpc_request_combine_ground_coin(object_node.get_path(), player.active_hand)
				else:
					World.rpc_request_combine_ground_coin.rpc_id(1, object_node.get_path(), player.active_hand)
		return
		
	if player.multiplayer.is_server():
		World.rpc_request_pickup(object_node.get_path(), player.active_hand)
	else:
		World.rpc_request_pickup.rpc_id(1, object_node.get_path(), player.active_hand)

func drop_item_from_hand(hand_idx: int) -> void:
	if player.hands[hand_idx] == null:
		return
	var obj = player.hands[hand_idx]
	if player.multiplayer.is_server():
		World.rpc_drop_item_at.rpc(player.get_path(), obj.get_path(), player.tile_pos, player.DROP_SPREAD, hand_idx)
	else:
		World.rpc_request_drop.rpc_id(1, obj.get_path(), player.tile_pos, player.DROP_SPREAD, hand_idx)

func drop_held_object() -> void:
	drop_item_from_hand(player.active_hand)

func throw_held_object(mouse_world_pos: Vector2) -> void:
	var mouse_tile := Vector2i(int(mouse_world_pos.x / World.TILE_SIZE), int(mouse_world_pos.y / World.TILE_SIZE))
	var dist_vec: Vector2i = (mouse_tile - player.tile_pos).abs()
	var dist: float = float(max(dist_vec.x, dist_vec.y))
	var throw_range: int = int(clamp(dist, 1.0, float(player.THROW_TILES)))

	var dir: Vector2 = (mouse_world_pos - player.pixel_pos).normalized()
	if dir == Vector2.ZERO:
		return

	apply_action_cooldown(player.hands[player.active_hand], true)

	var obj: Node = player.hands[player.active_hand]

	player.throwing_mode = false
	if player._throw_label != null:
		player._throw_label.visible = false

	if player.multiplayer.is_server():
		World.rpc_request_throw(obj.get_path(), player.active_hand, dir, throw_range)
	else:
		World.rpc_request_throw.rpc_id(1, obj.get_path(), player.active_hand, dir, throw_range)

func interact_held_object() -> void:
	if player.hands[player.active_hand] != null:
		var item = player.hands[player.active_hand]
		if item.has_method("interact_in_hand"):
			if player.multiplayer.is_server():
				World.rpc_request_interact_hand_item(player.active_hand)
			else:
				World.rpc_request_interact_hand_item.rpc_id(1, player.active_hand)

func use_held_object(mouse_world_pos: Vector2) -> void:
	var tm = World.get_tilemap(player.z_level)
	if tm == null:
		return

	var target_tile := Vector2i(
		int(mouse_world_pos.x / World.TILE_SIZE),
		int(mouse_world_pos.y / World.TILE_SIZE)
	)

	var diff: Vector2i = (target_tile - player.tile_pos).abs()
	if diff.x > 1 or diff.y > 1:
		return

	var held_item    = player.hands[player.active_hand]
	var is_pickaxe:  bool = false
	var is_sword:    bool = false
	var is_clothing: bool = false

	if held_item != null:
		var i_type = held_item.get("item_type")
		is_pickaxe = (i_type == "Pickaxe" or "Pickaxe" in held_item.name or "pickaxe" in held_item.name.to_lower())
		is_sword = (i_type == "Sword" or "Sword" in held_item.name or "sword" in held_item.name.to_lower()) or (i_type == "Dirk" or "Dirk" in held_item.name or "dirk" in held_item.name.to_lower())
		is_clothing = held_item.get("slot") != null

	var can_attack: bool = false
	var can_mine:   bool = false
	var can_chop:   bool = false
	var can_break:  bool = false

	if held_item == null:
		if player.intent == "harm":
			can_attack = true
	else:
		if is_sword:
			can_attack = true
			can_chop   = true
			can_break  = true
		elif is_pickaxe:
			can_mine = true
			if player.intent == "harm":
				can_attack = true
		else:
			if player.intent == "harm" and not is_clothing:
				can_attack = true

	var source_id = tm.get_cell_source_id(target_tile)
	var atlas_coords = tm.get_cell_atlas_coords(target_tile)
	var is_wooden_wall = (source_id == 1 and atlas_coords == Vector2i(7, 0))
	
	var target_found = false
	var is_exerting = false
	var is_attack_action = false
	
	if can_attack:
		var entities_at := World.get_entities_at_tile(target_tile, player.z_level, player.multiplayer.get_unique_id())
		if not entities_at.is_empty():
			target_found = true
			is_exerting = true
			is_attack_action = true
			
	if not target_found:
		for obj in player.get_tree().get_nodes_in_group("door"):
			if obj.get("z_level") != null and obj.z_level != player.z_level: continue
			if Vector2i(int(obj.global_position.x / World.TILE_SIZE), int(obj.global_position.y / World.TILE_SIZE)) == target_tile:
				if held_item == null:
					target_found = true
					is_exerting = false
				elif is_sword or (is_pickaxe and player.intent == "harm"):
					target_found = true
					is_exerting = true
				break
				
	if not target_found and can_chop:
		for obj in player.get_tree().get_nodes_in_group("choppable_object"):
			if obj.get("z_level") != null and obj.z_level != player.z_level: continue
			if Vector2i(int(obj.global_position.x / World.TILE_SIZE), int(obj.global_position.y / World.TILE_SIZE)) == target_tile:
				target_found = true
				is_exerting = true
				break

	if not target_found and can_break:
		for obj in player.get_tree().get_nodes_in_group("breakable_object"):
			if obj.get("z_level") != null and obj.z_level != player.z_level: continue
			if Vector2i(int(obj.global_position.x / World.TILE_SIZE), int(obj.global_position.y / World.TILE_SIZE)) == target_tile:
				target_found = true
				is_exerting = true
				break

	if not target_found and can_mine:
		for obj in player.get_tree().get_nodes_in_group("minable_object"):
			if obj.get("z_level") != null and obj.z_level != player.z_level: continue
			if Vector2i(int(obj.global_position.x / World.TILE_SIZE), int(obj.global_position.y / World.TILE_SIZE)) == target_tile:
				target_found = true
				is_exerting = true
				break

	if not target_found and source_id == 1:
		if is_wooden_wall:
			if is_sword or (is_pickaxe and player.intent == "harm"):
				target_found = true
				is_exerting = true
		elif can_mine:
			target_found = true
			is_exerting = true

	if not target_found:
		return

	if is_exerting:
		if player.exhausted:
			Sidebar.add_message("[color=#ffaaaa]You are too exhausted to act![/color]")
			return
		if player.stamina < 5.0:
			player.exhausted = true
			Sidebar.add_message("[color=#ffaaaa]You overexerted yourself![/color]")
		spend_stamina(5.0)

	apply_action_cooldown(player.hands[player.active_hand], is_attack_action)

	var acted: bool = false
	if is_attack_action:
		var limb = "chest"
		if player._hud != null:
			limb = player._hud.targeted_limb
			
		if player.multiplayer.is_server():
			World.rpc_deal_damage_at_tile(target_tile, limb)
		else:
			World.rpc_deal_damage_at_tile.rpc_id(1, target_tile, limb)
		acted = true

	if acted:
		return

	for obj in player.get_tree().get_nodes_in_group("door"):
		if obj.get("z_level") != null and obj.z_level != player.z_level: continue
		if Vector2i(int(obj.global_position.x / World.TILE_SIZE), int(obj.global_position.y / World.TILE_SIZE)) == target_tile:
			if player.multiplayer.is_server():
				World.rpc_request_hit_door(obj.get_path())
			else:
				World.rpc_request_hit_door.rpc_id(1, obj.get_path())
			return

	if can_chop:
		for obj in player.get_tree().get_nodes_in_group("choppable_object"):
			if obj.get("z_level") != null and obj.z_level != player.z_level: continue
			if Vector2i(int(obj.global_position.x / World.TILE_SIZE), int(obj.global_position.y / World.TILE_SIZE)) == target_tile:
				if player.multiplayer.is_server():
					World.rpc_request_hit_tree(obj.get_path())
				else:
					World.rpc_request_hit_tree.rpc_id(1, obj.get_path())
				return

	if can_break:
		for obj in player.get_tree().get_nodes_in_group("breakable_object"):
			if obj.get("z_level") != null and obj.z_level != player.z_level: continue
			if Vector2i(int(obj.global_position.x / World.TILE_SIZE), int(obj.global_position.y / World.TILE_SIZE)) == target_tile:
				if player.multiplayer.is_server():
					World.rpc_request_hit_breakable(obj.get_path())
				else:
					World.rpc_request_hit_breakable.rpc_id(1, obj.get_path())
				return

	if can_mine or (is_sword and is_wooden_wall):
		for obj in player.get_tree().get_nodes_in_group("minable_object"):
			if obj.get("z_level") != null and obj.z_level != player.z_level: continue
			if Vector2i(int(obj.global_position.x / World.TILE_SIZE), int(obj.global_position.y / World.TILE_SIZE)) == target_tile:
				if player.multiplayer.is_server():
					World.rpc_request_hit_rock(obj.get_path())
				else:
					World.rpc_request_hit_rock.rpc_id(1, obj.get_path())
				return

		if tm.get_cell_source_id(target_tile) == 1:
			if player.multiplayer.is_server():
				World.rpc_damage_wall(target_tile)
			else:
				World.rpc_damage_wall.rpc_id(1, target_tile)