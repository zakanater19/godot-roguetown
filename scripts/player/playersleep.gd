# res://scripts/player/playersleep.gd
# Sleep, lying-down, and stand-up logic extracted from player.gd.
extends RefCounted

var player: Node2D

func _init(p_player: Node2D) -> void:
	player = p_player

# ---------------------------------------------------------------------------
# Sleep
# ---------------------------------------------------------------------------

func toggle_sleep() -> void:
	if not player._is_local_authority() or player.dead: return
	if player.sleep_state == player.SleepState.AWAKE:
		if player.combat_mode: player.toggle_combat_mode()
		if player.is_lying_down: toggle_lying_down()
		player.sleep_state = player.SleepState.FALLING_ASLEEP
		player.sleep_timer = 10.0
		Sidebar.add_message("[color=#aaccff]You start falling asleep...[/color]")
		sync_sleep_state_update(player.sleep_state)
	elif player.sleep_state == player.SleepState.FALLING_ASLEEP:
		player.sleep_state = player.SleepState.AWAKE
		player.sleep_timer = 0.0
		Sidebar.add_message("[color=#aaccff]You jolt awake.[/color]")
		sync_sleep_state_update(player.sleep_state)
	elif player.sleep_state == player.SleepState.ASLEEP:
		player.sleep_state = player.SleepState.WAKING_UP
		player.sleep_timer = 10.0
		Sidebar.add_message("[color=#aaccff]You start waking up...[/color]")
		sync_sleep_state_update(player.sleep_state)

func is_on_bed() -> bool:
	for obj in player.get_tree().get_nodes_in_group("bed"):
		if obj.z_level != player.z_level: continue
		var obj_tile = Vector2i(int(obj.global_position.x / World.TILE_SIZE), int(obj.global_position.y / World.TILE_SIZE))
		if obj_tile == player.tile_pos: return true
	return false

func sync_sleep_state_update(new_state) -> void:
	set_lying_down_visuals(new_state != player.SleepState.AWAKE)
	if player.multiplayer.has_multiplayer_peer():
		if player.multiplayer.is_server(): player.rpc("_sync_sleep_state", new_state)
		else: player.rpc_id(1, "_sync_sleep_state", new_state)

func set_lying_down_visuals(_lying_down: bool) -> void:
	if player.dead: return
	player._update_sprite()

# ---------------------------------------------------------------------------
# Lying down / stand-up
# ---------------------------------------------------------------------------

func toggle_lying_down() -> void:
	if not player._is_local_authority() or player.dead: return
	if player.sleep_state != player.SleepState.AWAKE: return

	if not player.is_lying_down:
		player.is_lying_down = true
		cancel_stand_up()
		player._update_sprite()
		player._update_water_submerge()
		if player.multiplayer.has_multiplayer_peer():
			if player.multiplayer.is_server(): player.rpc("_rpc_sync_lying_down", player.is_lying_down)
			else: player.rpc_id(1, "_rpc_sync_lying_down", player.is_lying_down)
	else:
		if player._stand_up_timer < 0.0:
			player._stand_up_timer = 0.0
			Sidebar.add_message("[color=#aaccff]Stay still to stand up...[/color]")
			player._stand_up_label = create_stand_up_label()

func cancel_stand_up() -> void:
	if player._stand_up_timer >= 0.0:
		player._stand_up_timer = -1.0
		if player._stand_up_label != null and is_instance_valid(player._stand_up_label):
			player._stand_up_label.queue_free()
		player._stand_up_label = null

func create_stand_up_label() -> Label:
	var lbl := Label.new()
	lbl.name = "StandUpProg"
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.position = Vector2(-20, -64)
	lbl.text = "."
	player.add_child(lbl)
	return lbl

func complete_stand_up() -> void:
	if player.body != null and player.body.are_legs_broken():
		cancel_stand_up()
		if player._is_local_authority(): Sidebar.add_message("[color=#ffaaaa]Your broken legs won't let you stand.[/color]")
		return
	cancel_stand_up()
	player.is_lying_down = false
	player._update_sprite()
	player._update_water_submerge()
	if player.multiplayer.has_multiplayer_peer():
		if player.multiplayer.is_server(): player.rpc("_rpc_sync_lying_down", player.is_lying_down)
		else: player.rpc_id(1, "_rpc_sync_lying_down", player.is_lying_down)

func update_stand_up(delta: float, buffered_dir: Vector2i) -> void:
	const STAND_UP_DURATION: float = 2.0
	if buffered_dir != Vector2i.ZERO:
		cancel_stand_up()
		Sidebar.add_message("[color=#ffaaaa]Stand up cancelled.[/color]")
	else:
		player._stand_up_timer += delta
		var progress: float = clamp(player._stand_up_timer / STAND_UP_DURATION, 0.0, 1.0)
		var dot_count: int = clamp(int(progress * 5.0) + 1, 1, 5)
		var dot_str: String = ""
		for _d in range(dot_count): dot_str += "."
		if player._stand_up_label != null and is_instance_valid(player._stand_up_label):
			player._stand_up_label.text = dot_str
		if player._stand_up_timer >= STAND_UP_DURATION:
			complete_stand_up()

# ---------------------------------------------------------------------------
# Per-frame update (called from player._process)
# ---------------------------------------------------------------------------

func update(delta: float, is_local: bool) -> void:
	if player.sleep_state != player.SleepState.AWAKE and not player.dead and player.is_possessed:
		if player.sleep_state == player.SleepState.FALLING_ASLEEP:
			player.sleep_timer -= delta
			if player.sleep_timer <= 0.0:
				player.sleep_state = player.SleepState.ASLEEP
				player._sleeping_on_bed = is_on_bed()
				if is_local:
					Sidebar.add_message("[color=#aaccff]You are now fast asleep.[/color]")
					sync_sleep_state_update(player.sleep_state)
		elif player.sleep_state == player.SleepState.WAKING_UP:
			player.sleep_timer -= delta
			if player.sleep_timer <= 0.0:
				player.sleep_state = player.SleepState.AWAKE
				if is_local:
					Sidebar.add_message("[color=#aaccff]You are fully awake.[/color]")
					sync_sleep_state_update(player.sleep_state)
		elif player.sleep_state == player.SleepState.ASLEEP:
			if is_local:
				var regen_rate = 4.0 if player._sleeping_on_bed else 2.0
				player.health_regen_accumulator += regen_rate * delta
				if player.health_regen_accumulator >= 1.0:
					var heal_amount = int(player.health_regen_accumulator)
					player.health_regen_accumulator -= heal_amount
					if player.health < 100:
						var missing = 100 - player.health
						if heal_amount <= missing:
							player.health += heal_amount
							heal_amount = 0
						else:
							player.health = 100
							heal_amount -= missing
					if heal_amount > 0:
						player.rpc_heal_limbs.rpc(heal_amount)

	if is_local and player._sleep_blackout != null:
		if   player.sleep_state == player.SleepState.AWAKE:          player._sleep_blackout.color.a = 0.0
		elif player.sleep_state == player.SleepState.FALLING_ASLEEP: player._sleep_blackout.color.a = clamp(1.0 - (player.sleep_timer / 10.0), 0.0, 1.0)
		elif player.sleep_state == player.SleepState.ASLEEP:         player._sleep_blackout.color.a = 1.0
		elif player.sleep_state == player.SleepState.WAKING_UP:      player._sleep_blackout.color.a = 1.0 if player.sleep_timer > 2.0 else 0.0
