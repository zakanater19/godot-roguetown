# res://scripts/player/playerinput.gd
# Handles all _unhandled_input logic for the local player.
extends RefCounted

var player: Node2D

func _init(p_player: Node2D) -> void:
	player = p_player

func handle_input(event: InputEvent) -> void:
	if not player._is_local_authority(): return
	if player.dead: return

	if player.sleep_state != player.SleepState.AWAKE:
		if event is InputEventMouseButton: return
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode in [KEY_C, KEY_X, KEY_R, KEY_Q, KEY_V, KEY_Z, KEY_SHIFT, KEY_T]: return

	# ── Drag / inventory release ──────────────────────────────────────────────
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		player._drag_candidate = null
		if player._dragging_player != null:
			if is_instance_valid(player._dragging_player):
				var mw := player.get_global_mouse_position()
				if mw.distance_to(player.pixel_pos) < float(World.TILE_SIZE) * 0.6:
					if player.misc: player.misc.open_target_inventory(player._dragging_player)
			player._dragging_player = null
			player.get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion:
		if player._drag_candidate != null and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if event.position.distance_to(player._drag_origin) > player.DRAG_THRESHOLD:
				player._dragging_player = player._drag_candidate
				player._drag_candidate  = null
		return

	# ── Chat input ────────────────────────────────────────────────────────────
	if player._chat_input != null and player._chat_input.has_focus():
		if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
			player._chat_input.visible = false
			player._chat_input.clear()
			player._chat_input.release_focus()
			player.get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.keycode == KEY_T and event.pressed and not event.echo:
		if player._chat_input != null and not player._chat_input.visible:
			player._chat_input.visible = true
			player._chat_input.grab_focus()
			player.get_viewport().set_input_as_handled()
			return

	# ── Z-level look up/down ─────────────────────────────────────────────────
	if event is InputEventKey and event.keycode == KEY_F and event.pressed and not event.echo:
		if Input.is_key_pressed(KEY_SHIFT):
			if player.view_z_level != player.z_level:
				player.view_z_level = player.z_level
			else:
				if player.z_level >= 5:
					Sidebar.add_message("[color=#ffaaaa]there is nothing above you[/color]")
				else:
					var tm = World.get_tilemap(player.z_level + 1)
					var is_blocked = false
					if tm != null:
						var src = tm.get_cell_source_id(player.tile_pos)
						if src != -1 and src != 2:
							is_blocked = true
					if World.is_opaque(player.tile_pos, player.z_level + 1):
						is_blocked = true
					if is_blocked:
						Sidebar.add_message("[color=#ffaaaa]there is something blocking your view above[/color]")
					else:
						player.view_z_level = player.z_level + 1
						Sidebar.add_message("[color=#aaccff]You look up.[/color]")
			player.get_viewport().set_input_as_handled()
			return

	# ── Key bindings ──────────────────────────────────────────────────────────
	if event is InputEventKey and event.keycode == KEY_C and event.pressed and not event.echo:
		player.toggle_combat_mode(); return
	if event is InputEventKey and event.keycode == KEY_X and event.pressed and not event.echo:
		player.active_hand = 1 - player.active_hand
		player._update_hands_ui()
		if player._throw_label != null: player._throw_label.visible = player.throwing_mode and player.hands[player.active_hand] != null
		if player.multiplayer.has_multiplayer_peer():
			if player.multiplayer.is_server(): player.rpc("_sync_active_hand", player.active_hand)
			else: player.rpc_id(1, "_sync_active_hand", player.active_hand)
		return
	if event is InputEventKey and event.keycode == KEY_R and event.pressed and not event.echo:
		player.throwing_mode = not player.throwing_mode
		if player._throw_label != null: player._throw_label.visible = player.throwing_mode and player.hands[player.active_hand] != null
		return
	if event is InputEventKey and event.keycode == KEY_Q and event.pressed and not event.echo:
		player.throwing_mode = false
		if player._throw_label != null: player._throw_label.visible = false
		if player.grabbed_target != null and is_instance_valid(player.grabbed_target):
			if player.multiplayer.is_server(): World.rpc_request_release_grab()
			else: World.rpc_request_release_grab.rpc_id(1)
		else: player._drop_held_object()
		return
	if event is InputEventKey and event.keycode == KEY_Z and event.pressed and not event.echo:
		if player.grabbed_by != null and is_instance_valid(player.grabbed_by):
			if player.exhausted: Sidebar.add_message("[color=#ffaaaa]You are too exhausted to resist the grab![/color]"); return
			if player.multiplayer.is_server(): World.rpc_request_resist()
			else: World.rpc_request_resist.rpc_id(1)
		else: player._interact_held_object()
		return
	if event is InputEventKey and event.keycode == KEY_V and event.pressed and not event.echo:
		player.toggle_lying_down(); return

	# ── Right-click (shove) ───────────────────────────────────────────────────
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var mouse_world := player.get_global_mouse_position()
		var target_tile := Vector2i(int(mouse_world.x / World.TILE_SIZE), int(mouse_world.y / World.TILE_SIZE))
		if not FOV._visible_tiles.has(target_tile): return
		var diff: Vector2i = (target_tile - player.tile_pos).abs()
		if diff.x <= 1 and diff.y <= 1 and target_tile != player.tile_pos:
			if player.combat_mode and player.hands[player.active_hand] == null:
				if player.body != null and player.body.is_arm_broken(player.active_hand):
					Sidebar.add_message("[color=#ffaaaa]That arm is useless![/color]")
					player.get_viewport().set_input_as_handled()
					return
				if player.action_cooldown > 0.0: return
				if player.exhausted: Sidebar.add_message("[color=#ffaaaa]You are too exhausted to shove![/color]")
				else:
					if player.stamina < 5.0:
						player.exhausted = true
						Sidebar.add_message("[color=#ffaaaa]You overexerted yourself![/color]")
					player._spend_stamina(5.0)
					player._face_toward(mouse_world)
					player._apply_action_cooldown(null, true)
					if player.multiplayer.is_server(): World.rpc_request_shove(target_tile)
					else: World.rpc_request_shove.rpc_id(1, target_tile)
				player.get_viewport().set_input_as_handled()
				return

	# ── Left-click (grab, inspect, use, throw) ────────────────────────────────
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var mouse_world := player.get_global_mouse_position()
		var target_tile := Vector2i(int(mouse_world.x / World.TILE_SIZE), int(mouse_world.y / World.TILE_SIZE))
		if not FOV._visible_tiles.has(target_tile): return

		if Input.is_key_pressed(KEY_CTRL):
			if player.body != null and player.body.is_arm_broken(player.active_hand):
				Sidebar.add_message("[color=#ffaaaa]That arm is useless![/color]")
				player.get_viewport().set_input_as_handled()
				return
			var grab_target: Node = null
			for p in player.get_tree().get_nodes_in_group("player"):
				if p == player or p.z_level != player.z_level: continue
				if p.global_position.distance_to(mouse_world) < float(World.TILE_SIZE) * 0.7:
					grab_target = p; break
			if grab_target == null:
				for obj in player.get_tree().get_nodes_in_group("pickable"):
					if player.hands[0] == obj or player.hands[1] == obj or obj.z_level != player.z_level: continue
					var obj_tile := Vector2i(int(obj.global_position.x / World.TILE_SIZE), int(obj.global_position.y / World.TILE_SIZE))
					if obj_tile == target_tile: grab_target = obj; break
			if grab_target != null:
				var grab_limb: String = "chest"
				if player._hud != null: grab_limb = player._hud.targeted_limb
				if player.multiplayer.is_server(): World.rpc_request_grab(grab_target.get_path(), grab_limb)
				else: World.rpc_request_grab.rpc_id(1, grab_target.get_path(), grab_limb)
			player.get_viewport().set_input_as_handled()
			return

		if not Input.is_key_pressed(KEY_SHIFT):
			for p in player.get_tree().get_nodes_in_group("player"):
				if p == player or p.z_level != player.z_level: continue
				if p.global_position.distance_to(mouse_world) < float(World.TILE_SIZE) * 0.6:
					player._drag_candidate = p
					player._drag_origin    = event.position
					break

		if Input.is_key_pressed(KEY_SHIFT):
			player._face_toward(mouse_world)
			player._inspect_at(mouse_world)
			return

		if player.action_cooldown > 0.0: return
		player._face_toward(mouse_world)

		if player.hands[player.active_hand] != null and player.throwing_mode:
			player._throw_held_object(mouse_world)
		else:
			player._use_held_object(mouse_world)
