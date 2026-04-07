# res://scripts/player/playervisuals.gd
# Handles clothing sprite setup/update, sprite orientation, and water submersion.
extends RefCounted

var player: Node2D

func _init(p_player: Node2D) -> void:
	player = p_player

func setup_sprites() -> void:
	var layers = [
		["TrousersSprite", 1], ["ClothingSprite", 2], ["ChestSprite", 3],
		["GlovesSprite", 4],   ["BackpackSprite", 4], ["WaistSprite", 5],
		["BootsSprite", 5],    ["HelmetSprite", 6],   ["FaceSprite", 6],
		["CloakSprite", 7],
	]
	for spec in layers:
		var s := Sprite2D.new()
		s.name           = spec[0]
		s.scale          = Vector2(2.0, 2.0)
		s.region_enabled = true
		s.region_rect    = Rect2(0, 0, 32, 32)
		s.visible        = false
		s.z_index        = spec[1]
		player.add_child(s)

func update_clothing_sprites() -> void:
	if not player.backend: return
	var facing_name: String = player.FACING_NAMES[player.facing]
	var target_rot: float = 0.0
	if player.dead: target_rot = 90.0
	elif player.sleep_state != player.SleepState.AWAKE:
		if player._is_local_authority(): target_rot = 90.0
		elif player.sleep_state == player.SleepState.ASLEEP: target_rot = 90.0
	elif player.is_lying_down: target_rot = 90.0

	var slots := [
		["HelmetSprite",  "head"],    ["CloakSprite",   "cloak"],
		["ChestSprite",   "armor"],   ["BackpackSprite", "backpack"],
		["WaistSprite",   "waist"],   ["BootsSprite",    "feet"],
		["ClothingSprite","clothing"],["TrousersSprite", "trousers"],
		["GlovesSprite",  "gloves"],
	]

	for slot in slots:
		var sprite: Sprite2D = player.get_node_or_null(slot[0])
		if sprite == null: continue
		var item_name = player.equipped[slot[1]]

		if slot[1] == "waist":
			if item_name != null and item_name != "":
				var _idata = ItemRegistry.get_by_type(item_name)
				var _mob_tex = _idata.mob_texture_path if (_idata and _idata.mob_texture_path != "") else ""
				sprite.texture = load(_mob_tex) if _mob_tex != "" else load("res://objects/objects.png")
				var w_transform = player.backend.get_hand_transform(item_name, facing_name, "waist")
				
				var w_pos = w_transform.offset
				if target_rot == 90.0:
					w_pos = Vector2(-w_pos.y, w_pos.x) # Rotate offset 90 deg
					
				sprite.position = w_pos
				if player.facing == 1: sprite.z_index = -1
				else: sprite.z_index = 4
				var flip_h = w_transform.flip_h
				if player.facing == 3: flip_h = not flip_h
				var region = Rect2(0, 0, 64, 64)
				var final_scale = w_transform.scale
				if _idata != null and _idata.sprite_col >= 0:
					region = Rect2(_idata.sprite_col * 64, 0, 64, 64)
					final_scale *= _idata.waist_sprite_scale
				elif _mob_tex != "" and _mob_tex != "res://objects/objects.png":
					if sprite.texture != null: region = Rect2(0, 0, sprite.texture.get_width(), sprite.texture.get_height())
				sprite.region_rect = region
				sprite.rotation_degrees = w_transform.rotation + target_rot
				sprite.scale = Vector2(-final_scale if flip_h else final_scale, final_scale)
				sprite.visible = true
			else: sprite.visible = false
			continue

		var _idata2 = ItemRegistry.get_by_type(item_name) if (item_name != null and item_name != "") else null
		if _idata2 != null and _idata2.mob_texture_path != "":
			sprite.texture = load(_idata2.mob_texture_path)
			var cd = player.backend.get_clothing_transform(item_name, facing_name)
			
			var pos = cd.offset
			if target_rot == 90.0:
				pos = Vector2(-pos.y, pos.x) # Rotate offset 90 deg
				
			sprite.position           = pos
			sprite.scale              = Vector2(2.0 * cd.scale, 2.0 * cd.scale)
			sprite.region_rect        = Rect2(player.facing * 32, 0, 32, 32)
			sprite.rotation_degrees   = target_rot
			sprite.visible            = true
		else: sprite.visible = false

	# ── Face slot / Hood sprite ───────────────────────────────────────────────
	var face_sprite: Sprite2D = player.get_node_or_null("FaceSprite")
	if face_sprite != null:
		var face_item = player.equipped.get("face", null)
		if face_item == "Hood":
			var face_data = player.equipped_data.get("face", null)
			var hood_up: bool = false
			if face_data is Dictionary:
				hood_up = face_data.get("hood_up", false)
			var hood_data = ItemRegistry.get_by_type("Hood")
			if hood_up and hood_data and hood_data.mob_texture_path != "":
				face_sprite.texture = load(hood_data.mob_texture_path)
				var cd = player.backend.get_clothing_transform("Hood", facing_name)
				
				var pos = cd.offset
				if target_rot == 90.0:
					pos = Vector2(-pos.y, pos.x) # Rotate offset 90 deg
					
				face_sprite.position           = pos
				face_sprite.scale              = Vector2(2.0 * cd.scale, 2.0 * cd.scale)
				face_sprite.region_rect        = Rect2(player.facing * 32, 0, 32, 32)
				face_sprite.rotation_degrees   = target_rot
				face_sprite.visible            = true
			else:
				face_sprite.visible = false
		else:
			face_sprite.visible = false

	update_water_submerge()

func update_sprite() -> void:
	var sprite: Sprite2D = player.get_node_or_null("Sprite2D")
	if sprite == null: return
	sprite.region_enabled = true
	sprite.region_rect    = Rect2(player.facing * 32, 0, 32, 32)
	var target_rot = 0.0
	if player.dead: target_rot = 90.0
	elif player.sleep_state != player.SleepState.AWAKE:
		if player._is_local_authority(): target_rot = 90.0
		elif player.sleep_state == player.SleepState.ASLEEP: target_rot = 90.0
	elif player.is_lying_down: target_rot = 90.0
	sprite.rotation_degrees = target_rot
	update_clothing_sprites()

func update_hand_positions() -> void:
	if player.backend == null: return
	for i in range(2):
		var obj = player.hands[i]
		if obj == null or (i == player.active_hand and player._is_throwing): continue
		var hand_key:    String = "right" if i == 0 else "left"
		var facing_name: String = player.FACING_NAMES[player.facing]
		var item_name = obj.get("item_type")
		if item_name == null: item_name = obj.name.get_slice("@", 0)
		var hand_transform = player.backend.get_hand_transform(item_name, facing_name, hand_key)
		var flip_h: bool = hand_transform.flip_h
		if player.facing == 3: flip_h = not flip_h
		obj.global_position = player.pixel_pos + hand_transform.offset
		obj.z_index = player.z_index - 1 if player.facing == 1 else player.z_index + 6
		var sprite: Sprite2D = obj.get_node_or_null("Sprite2D")
		if sprite != null:
			sprite.rotation_degrees = hand_transform.rotation
			var mag_x := absf(sprite.scale.x)
			var mag_y := absf(sprite.scale.y)
			sprite.scale = Vector2(-mag_x if flip_h else mag_x, mag_y)

func update_water_submerge() -> void:
	const FULL_H: int = 32
	const CLIP_H: int = 22
	var tm = World.get_tilemap(player.z_level)
	var on_water := tm != null and tm.get_cell_source_id(player.tile_pos) == 5
	var stamina_penalty = 2.0 if player.exhausted else 1.0
	var sprint_mult = (1.0 / 1.5) if player.is_sprinting else 1.0
	var lying_mult = 3.0 if player.is_lying_down else 1.0
	var sneak_level: int = player.skills.get("sneaking", 0)
	var sneak_mult = max(1.0, 2.0 - sneak_level * 0.25) if player.is_sneaking else 1.0
	if player.grabbed_by != null and is_instance_valid(player.grabbed_by):
		stamina_penalty = 1.0
		lying_mult = 1.0
	if on_water: player.current_move_duration = (player.MOVE_TIME * 2.0 * stamina_penalty) * sprint_mult * lying_mult * sneak_mult
	else: player.current_move_duration = (player.MOVE_TIME * stamina_penalty) * sprint_mult * lying_mult * sneak_mult
	var h            := CLIP_H if on_water else FULL_H
	var compensate_y := (FULL_H - h) / 2.0
	var sprite: Sprite2D = player.get_node_or_null("Sprite2D")
	if sprite != null:
		sprite.region_rect = Rect2(player.facing * 32, 0, 32, h)
		sprite.offset      = Vector2(0.0, -compensate_y)
	var trousers: Sprite2D = player.get_node_or_null("TrousersSprite")
	if trousers != null:
		trousers.region_rect = Rect2(player.facing * 32, 0, 32, h)
		trousers.offset      = Vector2(0.0, -compensate_y)
	var boots: Sprite2D = player.get_node_or_null("BootsSprite")
	if boots != null:
		boots.region_rect = Rect2(player.facing * 32, 0, 32, 0 if on_water else FULL_H)
		boots.offset      = Vector2.ZERO
