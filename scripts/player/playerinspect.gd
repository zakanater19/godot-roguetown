# res://scripts/player/playerinspect.gd
# Handles player description, inspection, and class-context annotations.
extends RefCounted

var player: Node2D

func _init(p_player: Node2D) -> void:
	player = p_player

# ===========================================================================
# Identity / Description
# ===========================================================================

func is_disguised() -> bool:
	if player.equipped.get("face") == "Hood":
		var face_data = player.equipped_data.get("face", null)
		if face_data is Dictionary and face_data.get("hood_up", false):
			return true
	return false

func get_description() -> String:
	var is_me: bool = player.has_method("_is_local_authority") and player._is_local_authority()
	var desc: String = player.character_name
	if not is_me and is_disguised():
		desc = "You cannot see their face"
	if player.dead:
		desc += " (dead)"
	elif player.sleep_state != player.SleepState.AWAKE:
		desc += " (sleeping)"
	return desc

func get_detailed_description() -> String:
	var is_me: bool = player.has_method("_is_local_authority") and player._is_local_authority()
	var title_col: String = get_inspect_color().to_html(false)
	var name_str = player.character_name
	if not is_me and is_disguised():
		name_str  = "You cannot see their face"
		title_col = "888888"
	if is_me:
		name_str += " (You)"
	var desc: String = "[color=#" + title_col + "][b]" + name_str + "[/b][/color]"
	if player.dead:
		desc += " (dead)\nthey are stiff and dead."
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
	for slot in Defs.SLOTS_ALL:
		var item = player.equipped.get(slot, null)
		if item != null and item is String and item != "":
			desc += "\n[color=gray]" + slot + ":[/color] " + item
	if is_me and player.body != null:
		for limb_key in Defs.LIMBS:
			var limb_label: String = Defs.LIMB_DISPLAY.get(limb_key, limb_key)
			var limb_max: int = int(player.body.LIMB_MAX_HP.get(limb_key, CombatDefs.LIMB_HP_MAX))
			var limb_hp: int = int(player.body.limb_hp.get(limb_key, limb_max))
			var damage_ratio: float = 1.0 - (float(limb_hp) / float(maxi(limb_max, 1)))
			if damage_ratio > 0.0:
				desc += "\n[color=gray]" + limb_label + ":[/color] " + _get_limb_status(damage_ratio)
	return desc

func get_inspect_color() -> Color:
	return Color.WHITE if player.dead else Color(1.0, 0.0, 0.0)

func get_inspect_font_size() -> int:
	return 11 if player.dead else 14

func _get_limb_status(damage_ratio: float) -> String:
	var broken_ratio: float = float(CombatDefs.LIMB_BROKEN) / float(CombatDefs.LIMB_HP_MAX)
	var mangled_ratio: float = float(CombatDefs.LIMB_MANGLED) / float(CombatDefs.LIMB_HP_MAX)
	var severe_ratio: float = float(CombatDefs.LIMB_SEVERE) / float(CombatDefs.LIMB_HP_MAX)
	var injured_ratio: float = float(CombatDefs.LIMB_INJURED) / float(CombatDefs.LIMB_HP_MAX)
	if damage_ratio >= broken_ratio: return "[color=#cc0000]broken[/color]"
	elif damage_ratio >= mangled_ratio: return "[color=#ff2200]mangled[/color]"
	elif damage_ratio >= severe_ratio: return "[color=#ff6600]severely injured[/color]"
	elif damage_ratio >= injured_ratio: return "[color=#ffaa00]injured[/color]"
	else: return "[color=#ffdd44]a little injured[/color]"

# ===========================================================================
# World Inspection
# ===========================================================================

func inspect_at(world_pos: Vector2) -> void:
	var target_tile := Vector2i(int(world_pos.x / World.TILE_SIZE), int(world_pos.y / World.TILE_SIZE))
	var viewer_is_ghost: bool = player.get("is_ghost") == true
	var interaction_z: int = _get_interaction_z_level()

	if interaction_z == player.z_level and target_tile == player.tile_pos:
		show_inspect_text(get_description(), get_detailed_description())
		return

	if interaction_z == player.z_level:
		for i in range(2):
			var held = player.hands[i]
			if held == null or not is_instance_valid(held): continue
			var hand_tile := Vector2i(int(held.global_position.x / World.TILE_SIZE), int(held.global_position.y / World.TILE_SIZE))
			if hand_tile == target_tile:
				var hand_label := " (in right hand)" if i == 0 else " (in left hand)"
				var desc = held.get_description() if held.has_method("get_description") else (held.get("item_type") if held.get("item_type") != null else held.name.get_slice("@", 0))
				show_inspect_text(desc + hand_label, "")
				return

	var best_npc:  Node  = null
	var best_dist: float = INF
	for obj in World.get_entities_at_tile(target_tile, interaction_z, 0, true):
		if obj.get("is_ghost") == true and not viewer_is_ghost:
			continue
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
				if best_npc.get("inspect") != null and best_npc.inspect.has_method("is_disguised"):
					is_npc_disguised = best_npc.inspect.is_disguised()
				elif best_npc.get("backend") != null and best_npc.backend.has_method("is_disguised"):
					is_npc_disguised = best_npc.backend.is_disguised()
				if not is_npc_disguised:
					var outsiders = Defs.OUTSIDER_CLASSES
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
			if obj.get("z_level") != null and obj.z_level != interaction_z: continue
			if group == "pickable" and (player.hands[0] == obj or player.hands[1] == obj): continue
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

	var leaf_decor: Node = _find_leaf_decor_at(target_tile, interaction_z)
	if leaf_decor != null and leaf_decor.has_method("get_description"):
		var short_desc: String = leaf_decor.get_description()
		var detailed_desc: String = leaf_decor.get_detailed_description() if leaf_decor.has_method("get_detailed_description") else ""
		show_inspect_text(short_desc, detailed_desc)
		return

	var source_id:    int      = -1
	var atlas_coords: Vector2i = Vector2i(-1, -1)
	var tm = World.get_tilemap(interaction_z)
	if tm != null:
		source_id    = tm.get_cell_source_id(target_tile)
		atlas_coords = tm.get_cell_atlas_coords(target_tile)
	show_inspect_text(World.get_tile_description(source_id, atlas_coords), "")

func show_inspect_text(text: String, detailed_desc: String) -> void:
	var log_msg = detailed_desc if detailed_desc != "" else text
	Sidebar.add_message(log_msg)

func _find_leaf_decor_at(target_tile: Vector2i, interaction_z: int) -> Node:
	for leaf in player.get_tree().get_nodes_in_group("leaf_canopy"):
		if leaf == null or not is_instance_valid(leaf):
			continue
		if leaf.get("z_level") != null and int(leaf.get("z_level")) != interaction_z:
			continue
		var leaf_tile := Vector2i(int(leaf.global_position.x / World.TILE_SIZE), int(leaf.global_position.y / World.TILE_SIZE))
		if leaf_tile == target_tile:
			return leaf
	return null

func _get_interaction_z_level() -> int:
	if player.has_method("get_interaction_z_level"):
		return int(player.get_interaction_z_level())
	var view_z: int = player.z_level
	if "view_z_level" in player:
		view_z = int(player.get("view_z_level"))
	return clampi(view_z, 1, 5)
