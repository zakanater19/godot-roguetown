# res://scripts/core/player.gd
extends Node2D

const MOVE_TIME:   float = PlayerDefs.MOVE_TIME
const THROW_TILES:    int   = PlayerDefs.THROW_TILES
const THROW_DURATION: float = PlayerDefs.THROW_DURATION
const DROP_SPREAD:    float = Defs.DROP_SPREAD

const FACING_NAMES: Array = ["south", "north", "east", "west"]

const BloodSpray = preload("res://npcs/blood_spray.gd")

# ── Sub-systems ───────────────────────────────────────────────────────────────
var backend  = null
var misc     = null
var combat   = null
var crafting = null
var body     = null
var visuals  = null
var sleep_   = null
var sneak    = null
var chat     = null
var ui       = null
var input    = null
var inspect  = null

# ── State ─────────────────────────────────────────────────────────────────────
var is_possessed: bool = true

enum SleepState { AWAKE, FALLING_ASLEEP, ASLEEP, WAKING_UP }
var sleep_state: SleepState = SleepState.AWAKE
var sleep_timer: float = 0.0
var health_regen_accumulator: float = 0.0
@warning_ignore("unused_private_class_variable")
var _sleep_blackout: ColorRect = null
@warning_ignore("unused_private_class_variable")
var _sleeping_on_bed: bool = false

@export var character_name: String = "noob"
@export var character_class: String = "peasant"
@export var z_level: int = 3
var view_z_level: int = 3

var tile_pos: Vector2i = Vector2i.ZERO :
	set(val):
		var diff := (val - tile_pos).abs()
		tile_pos = val
		if diff.x > 1 or diff.y > 1:
			pixel_pos = World.tile_to_pixel(val)
			position = pixel_pos
		if misc != null:    misc.on_tile_pos_changed()
		if crafting != null: crafting.on_tile_pos_changed()

var pixel_pos:    Vector2
var moving:       bool    = false
var move_elapsed: float   = 0.0
var move_from:    Vector2
var move_to:      Vector2
var current_move_duration: float = MOVE_TIME
var facing:       int     = 0 :
	set(val):
		facing = val
		_update_sprite()
var action_cooldown: float    = 0.0
var buffered_dir:    Vector2i = Vector2i.ZERO
var camera:          Camera2D = null

var intent: String = "help"
var combat_mode: bool = false
var combat_stance: String = "dodge"
var _awaiting_move_confirm: bool = false

var is_sprinting: bool = false
var is_lying_down: bool = false
var _stand_up_timer: float = -1.0
@warning_ignore("unused_private_class_variable")
var _stand_up_label: Label = null

var exhausted: bool = false :
	set(val):
		if exhausted != val:
			exhausted = val
			if _is_local_authority() and multiplayer.has_multiplayer_peer():
				_sync_exhausted.rpc(val)

@rpc("authority", "call_remote", "reliable")
func _sync_exhausted(val: bool) -> void:
	exhausted = val
	_update_water_submerge()

var skills: Dictionary = {"sword_fighting": 0, "blacksmithing": 0, "sneaking": 0}

var is_sneaking: bool = false
var sneak_alpha: float = 1.0
@warning_ignore("unused_private_class_variable")
var _last_synced_sneak_alpha: float = 1.0
@warning_ignore("unused_private_class_variable")
var _sneak_was_hidden: bool = false
var prices_shown: bool = false
var stats: Dictionary = {"strength": 10, "agility": 10}
var health: int = PlayerDefs.DEFAULT_HEALTH
var stamina: float = CombatDefs.STAMINA_MAX
var max_stamina: float = CombatDefs.STAMINA_MAX
var last_exertion_time: float = 0.0
var _blood_drip_timer: float = 0.0

var dead: bool = false :
	set(val):
		dead = val
		if dead: _die_visuals()

var hands:        Array[Node] = [null, null]
var active_hand:  int         = 0
@warning_ignore("unused_private_class_variable")
var _is_throwing: bool        = false

var equipped: Dictionary = {"head": null, "face": null, "cloak": null, "armor": null, "backpack": null, "waist": null, "clothing": null, "trousers": null, "feet": null, "gloves": null, "pocket_l": null, "pocket_r": null}
var equipped_data: Dictionary = {"head": null, "face": null, "cloak": null, "armor": null, "backpack": null, "waist": null, "clothing": null, "trousers": null, "feet": null, "gloves": null, "pocket_l": null, "pocket_r": null}

var throwing_mode:     bool    = false
@warning_ignore("unused_private_class_variable")
var _throw_label:      Label   = null
var _inspect_label:    Label   = null
var _combat_indicator: Label   = null
var _dead_container:   Control = null
var _canvas_layer:     CanvasLayer = null
@warning_ignore("unused_private_class_variable")
var _ui_root:          Control = null
var _hud: CanvasLayer = null

var _chat_input:           LineEdit        = null
@warning_ignore("unused_private_class_variable")
var _active_chat_messages: Array[Node2D]   = []

@warning_ignore("unused_private_class_variable")
var _drag_candidate:  Node    = null
@warning_ignore("unused_private_class_variable")
var _drag_origin:     Vector2 = Vector2.ZERO
const DRAG_THRESHOLD: float   = PlayerDefs.DRAG_THRESHOLD
@warning_ignore("unused_private_class_variable")
var _dragging_player: Node = null

var grabbed_target: Node = null
var grabbed_by:     Node = null
var grab_hand_idx:  int  = -1

# ── Character name sync ───────────────────────────────────────────────────────

@rpc("any_peer", "call_local", "reliable")
func _sync_character_name(p_name: String, p_class: String) -> void:
	var class_changed = (character_class != p_class)
	character_name = p_name
	character_class = p_class
	if class_changed: _apply_class_defaults()

func set_character_name(p_name: String, p_class: String) -> void:
	var class_changed = (character_class != p_class)
	character_name = p_name
	character_class = p_class
	if class_changed: _apply_class_defaults()
	if multiplayer.has_multiplayer_peer():
		var peer_id = get_multiplayer_authority()
		if peer_id != 1:
			_sync_character_name.rpc_id(peer_id, p_name, p_class)

# ── Description / inspection delegation ──────────────────────────────────────

func get_description() -> String:         return inspect.get_description()         if inspect else character_name
func get_detailed_description() -> String: return inspect.get_detailed_description() if inspect else character_name
func get_inspect_color() -> Color:         return inspect.get_inspect_color()        if inspect else Color.WHITE
func get_inspect_font_size() -> int:       return inspect.get_inspect_font_size()    if inspect else 11

# ── Backend / misc delegation ─────────────────────────────────────────────────

func _apply_class_defaults() -> void:                                          if backend: backend.apply_class_defaults()
func _spend_stamina(amount: float) -> void:                                    if backend: backend.spend_stamina(amount)
func _check_stamina_regen(delta: float) -> void:                               if backend: backend.check_stamina_regen(delta)
func _equip_clothing(item: Node) -> void:                                      if backend: backend.equip_clothing(item)
func _equip_clothing_to_slot(item: Node, slot_name: String) -> void:          if backend: backend.equip_clothing_to_slot(item, slot_name)
func _perform_equip(item: Node, slot_name: String, hand_index: int) -> void:  if backend: backend.perform_equip(item, slot_name, hand_index)
func _unequip_clothing_from_slot(slot_name: String) -> void:                   if backend: backend.unequip_clothing_from_slot(slot_name)
func _perform_unequip(slot_name: String, new_node_name: String, hand_index: int) -> void: if backend: backend.perform_unequip(slot_name, new_node_name, hand_index)
func _inspect_at(world_pos: Vector2) -> void:                                  if inspect: inspect.inspect_at(world_pos)
func _show_inspect_text(text: String, detailed_desc: String) -> void:         if inspect: inspect.show_inspect_text(text, detailed_desc)
func _apply_action_cooldown(item: Node, is_attack: bool = false) -> void:     if backend: backend.apply_action_cooldown(item, is_attack)
func _face_toward(world_pos: Vector2) -> void:                                 if backend: backend.face_toward(world_pos)

func _on_object_picked_up(object_node: Node) -> void:
	if active_hand == grab_hand_idx: return
	if body != null and body.is_arm_broken(active_hand):
		if _is_local_authority(): Sidebar.add_message("[color=#ffaaaa]That arm is useless![/color]")
		return
	if backend: backend.on_object_picked_up(object_node)

func _drop_held_object() -> void: if backend: backend.drop_held_object()

func _throw_held_object(mouse_world_pos: Vector2) -> void:
	if active_hand == grab_hand_idx: return
	if body != null and body.is_arm_broken(active_hand):
		if _is_local_authority(): Sidebar.add_message("[color=#ffaaaa]That arm is useless![/color]")
		return
	if backend: backend.throw_held_object(mouse_world_pos)

func _use_held_object(mouse_world_pos: Vector2) -> void:
	if active_hand == grab_hand_idx: return
	if body != null and body.is_arm_broken(active_hand):
		if _is_local_authority(): Sidebar.add_message("[color=#ffaaaa]That arm is useless![/color]")
		return
	if backend: backend.use_held_object(mouse_world_pos)

func _interact_held_object() -> void: if backend: backend.interact_held_object()

# ── Crafting / combat / sneak / sleep / UI delegation ────────────────────────

func toggle_crafting_menu() -> void: if crafting: crafting.toggle_crafting_menu()
func toggle_combat_mode() -> void:   if combat:   combat.toggle_combat_mode()
func toggle_combat_stance() -> void: if combat:   combat.toggle_combat_stance()
func toggle_sneak_mode() -> void:    if sneak:    sneak.toggle_sneak_mode()

func show_loot_warning(looter_peer_id: int, item_desc: String) -> void: if misc: misc.show_loot_warning(looter_peer_id, item_desc)
func get_strength_damage_modifier() -> float: return combat.get_strength_damage_modifier() if combat else 0.0
func _get_weapon_damage(item: Node) -> int:   return combat.get_weapon_damage(item) if combat else 5

func _build_ui() -> void:           if ui: ui.build_ui()
func _update_hands_ui() -> void:    if ui: ui.update_hands_ui()
func _update_grab_ui() -> void:     if ui: ui.update_grab_ui()
func show_stats_skills() -> void:   if ui: ui.show_stats_skills()
func show_remote_chat(sender_name: String, message: String) -> void: if chat: chat.show_remote_chat(sender_name, message)

# ── Sneak RPCs (stubs on the node; logic lives in playersneak.gd) ─────────────

@rpc("authority", "call_local", "reliable")
func _rpc_sync_sneak_mode(val: bool) -> void:
	if sneak: sneak.set_sneak_mode_local(val)

@rpc("authority", "call_remote", "reliable")
func _rpc_sync_sneak_alpha(alpha: float) -> void:
	if sneak: sneak.handle_sync_sneak_alpha(alpha)

func _apply_sneak_alpha(alpha: float) -> void: if sneak: sneak.apply_sneak_alpha(alpha)

# ── Stamina RPC ───────────────────────────────────────────────────────────────

@rpc("any_peer", "call_local", "reliable")
func rpc_consume_stamina(amount: float) -> void:
	if _is_local_authority():
		if stamina < amount:
			exhausted = true
			Sidebar.add_message("[color=#ffaaaa]You overexerted yourself defending![/color]")
		_spend_stamina(amount)

# ── Combat mode / stance RPCs ─────────────────────────────────────────────────

@rpc("any_peer", "call_remote", "reliable")
func _sync_combat_mode(mode: bool) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	if multiplayer.is_server():
		if sender_id == get_multiplayer_authority():
			if combat: combat.set_combat_mode_local(mode)
			rpc("_sync_combat_mode", mode)
	else:
		if sender_id == 1:
			if combat: combat.set_combat_mode_local(mode)

@rpc("any_peer", "call_remote", "reliable")
func _sync_combat_stance(stance: String) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	if multiplayer.is_server():
		if sender_id == get_multiplayer_authority():
			if combat: combat.set_combat_stance_local(stance)
			rpc("_sync_combat_stance", stance)
	else:
		if sender_id == 1:
			if combat: combat.set_combat_stance_local(stance)

# ── Hood toggle ───────────────────────────────────────────────────────────────

func toggle_hood_state() -> void:
	if not _is_local_authority(): return
	if equipped.get("face") != "Hood": return
	var data = equipped_data.get("face", null)
	if not data is Dictionary: data = {}
	var hood_up: bool = not data.get("hood_up", false)
	data["hood_up"] = hood_up
	equipped_data["face"] = data
	_update_clothing_sprites()
	if _hud != null: _hud.update_clothing_display(equipped, equipped_data)
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server(): rpc("_sync_hood_state", hood_up)
		else: rpc_id(1, "_sync_hood_state", hood_up)

@rpc("any_peer", "call_remote", "reliable")
func _sync_hood_state(hood_up: bool) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	if multiplayer.is_server():
		if sender_id == get_multiplayer_authority():
			var data = equipped_data.get("face", null)
			if not data is Dictionary: data = {}
			data["hood_up"] = hood_up
			equipped_data["face"] = data
			_update_clothing_sprites()
			rpc("_sync_hood_state", hood_up)
	else:
		if sender_id == 1:
			var data = equipped_data.get("face", null)
			if not data is Dictionary: data = {}
			data["hood_up"] = hood_up
			equipped_data["face"] = data
			_update_clothing_sprites()

# ── Sleep RPCs ────────────────────────────────────────────────────────────────

func toggle_sleep() -> void:                                              if sleep_: sleep_.toggle_sleep()
func _is_on_bed() -> bool:                                                return sleep_.is_on_bed() if sleep_ else false
func _sync_sleep_state_update(new_state: SleepState) -> void:            if sleep_: sleep_.sync_sleep_state_update(new_state)
func _set_lying_down_visuals(_lying_down: bool) -> void:                  if sleep_: sleep_.set_lying_down_visuals(_lying_down)
func toggle_lying_down() -> void:                                          if sleep_: sleep_.toggle_lying_down()
func _cancel_stand_up() -> void:                                           if sleep_: sleep_.cancel_stand_up()
func _create_stand_up_label() -> Label:                                    return sleep_.create_stand_up_label() if sleep_ else null
func _complete_stand_up() -> void:                                         if sleep_: sleep_.complete_stand_up()

@rpc("any_peer", "call_remote", "reliable")
func _sync_sleep_state(new_state: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	if multiplayer.is_server():
		if sender_id == get_multiplayer_authority():
			sleep_state = new_state as SleepState
			_set_lying_down_visuals(sleep_state != SleepState.AWAKE)
			rpc("_sync_sleep_state", new_state)
	else:
		if sender_id == 1:
			sleep_state = new_state as SleepState
			_set_lying_down_visuals(sleep_state != SleepState.AWAKE)

@rpc("authority", "call_local", "reliable")
func rpc_heal_limbs(amount: int) -> void: if body != null: body.heal_limbs(amount)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_sync_lying_down(val: bool) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	if multiplayer.is_server():
		if sender_id == get_multiplayer_authority():
			is_lying_down = val
			_update_sprite()
			_update_water_submerge()
			rpc("_rpc_sync_lying_down", val)
	else:
		if sender_id == 1:
			is_lying_down = val
			_update_sprite()
			_update_water_submerge()

# ── Z-level / corpse / respawn RPCs ──────────────────────────────────────────

@rpc("any_peer", "call_local", "reliable")
func rpc_sync_z_level(new_z: int) -> void:
	z_level = new_z
	view_z_level = new_z
	z_index = Defs.get_z_index(z_level, Defs.Z_OFFSET_PLAYERS)
	_update_water_submerge()
	for h in hands:
		if h != null and is_instance_valid(h):
			h.set("z_level", new_z)
	if _is_local_authority() and _hud:
		_hud.update_stats(health, stamina)

@rpc("any_peer", "call_local", "reliable")
func rpc_make_corpse() -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != 1 and sender_id != 0: return
	is_possessed = false
	if name.begins_with("Player_"):
		name = "Corpse_" + name.trim_prefix("Player_")
	set_multiplayer_authority(1)
	if _canvas_layer:
		_canvas_layer.queue_free()
		_canvas_layer = null
	if _hud:
		_hud.queue_free()
		_hud = null
	if camera: camera = null
	if _combat_indicator:
		_combat_indicator.queue_free()
		_combat_indicator = null

# ── Damage / death ────────────────────────────────────────────────────────────

@rpc("any_peer", "call_local", "reliable")
func receive_damage(amount: int, limb: String = "chest") -> void:
	if body:   body.receive_limb_damage(limb, amount)
	if combat: combat.receive_damage(amount)
	if multiplayer.is_server():
		var peer := get_multiplayer_authority()
		if LateJoin.is_player_disconnected(peer):
			LateJoin.update_disconnected_health(peer, health)

func _die() -> void:        if combat: combat.die()
func _die_visuals() -> void: if combat: combat.die_visuals()

# ── Active hand / transfer ────────────────────────────────────────────────────

@rpc("any_peer", "call_remote", "reliable")
func _sync_active_hand(hand_idx: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	if multiplayer.is_server():
		if sender_id == get_multiplayer_authority():
			active_hand = hand_idx
			rpc("_sync_active_hand", hand_idx)
	else:
		if sender_id == 1: active_hand = hand_idx

@rpc("any_peer", "call_local", "reliable")
func rpc_transfer_to_hand(from_idx: int, to_idx: int) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	if multiplayer.is_server():
		if sender_id != get_multiplayer_authority(): return
		if hands[to_idx] != null or hands[from_idx] == null: return
		if body != null and body.is_arm_broken(to_idx): return
		hands[to_idx]   = hands[from_idx]
		hands[from_idx] = null
		if _is_local_authority(): _update_hands_ui()
		rpc("rpc_transfer_to_hand", from_idx, to_idx)
	else:
		if sender_id != 1: return
		hands[to_idx]   = hands[from_idx]
		hands[from_idx] = null
		if _is_local_authority(): _update_hands_ui()

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _enter_tree() -> void:
	if name.begins_with("Player_"):
		var parts = name.split("_")
		if parts.size() > 1:
			set_multiplayer_authority(parts[1].to_int())

func _ready() -> void:
	view_z_level = z_level
	z_index = Defs.get_z_index(z_level, Defs.Z_OFFSET_PLAYERS)
	add_to_group("z_entity")
	backend  = preload("res://scripts/player/playerbackend.gd").new(self)
	misc     = preload("res://scripts/player/playermisc.gd").new(self)
	combat   = preload("res://scripts/player/playercombat.gd").new(self)
	crafting = preload("res://scripts/player/playercrafting.gd").new(self)
	body     = preload("res://scripts/player/body.gd").new(self)
	visuals  = preload("res://scripts/player/playervisuals.gd").new(self)
	sleep_   = preload("res://scripts/player/playersleep.gd").new(self)
	sneak    = preload("res://scripts/player/playersneak.gd").new(self)
	chat     = preload("res://scripts/player/playerchat.gd").new(self)
	ui       = preload("res://scripts/player/playerui.gd").new(self)
	input    = preload("res://scripts/player/playerinput.gd").new(self)
	inspect  = preload("res://scripts/player/playerinspect.gd").new(self)

	add_to_group("player")
	_apply_class_defaults()

	if position == Vector2.ZERO and multiplayer.is_server():
		tile_pos = Defs.DEFAULT_SPAWN_TILE
		position = World.tile_to_pixel(tile_pos)

	if tile_pos == Vector2i.ZERO and position != Vector2.ZERO:
		tile_pos = Vector2i(int(position.x / World.TILE_SIZE), int(position.y / World.TILE_SIZE))

	pixel_pos = World.tile_to_pixel(tile_pos)
	position  = pixel_pos

	_setup_clothing_sprites()
	_update_sprite()

	if _is_local_authority():
		camera = get_parent().get_node_or_null("Camera2D")
		_build_ui()

func _is_local_authority() -> bool:
	if not is_possessed: return false
	if not is_inside_tree(): return false
	if not multiplayer.has_multiplayer_peer(): return false
	if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED: return false
	return multiplayer.get_unique_id() == get_multiplayer_authority()

# ── Movement ──────────────────────────────────────────────────────────────────

func _start_move_lerp() -> void:
	_awaiting_move_confirm = false
	var new_pixel: Vector2 = World.tile_to_pixel(tile_pos)
	if new_pixel == pixel_pos: return

	if dead:
		pixel_pos = new_pixel
		position  = pixel_pos
		return

	if is_sprinting and _is_local_authority():
		if stamina < PlayerDefs.SPRINT_STAMINA_COST:
			exhausted = true
			Sidebar.add_message("[color=#ffaaaa]You overexerted yourself![/color]")
		_spend_stamina(PlayerDefs.SPRINT_STAMINA_COST)

	_update_water_submerge()
	move_from    = pixel_pos
	move_to      = new_pixel
	move_elapsed = 0.0
	moving       = true

func _try_move(dir: Vector2i) -> void:
	if dir == Vector2i.ZERO or _awaiting_move_confirm: return
	if not combat_mode:
		if   dir.y > 0: facing = 0
		elif dir.y < 0: facing = 1
		elif dir.x > 0: facing = 2
		elif dir.x < 0: facing = 3
		_update_sprite()
	_awaiting_move_confirm = true
	var sprint_intent = Input.is_key_pressed(KEY_SPACE) and not exhausted and not (body != null and body.are_legs_broken())
	if multiplayer.is_server(): World.rpc_try_move(dir, sprint_intent)
	else: World.rpc_try_move.rpc_id(1, dir, sprint_intent)

# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if input: input.handle_input(event)

func _on_chat_submitted(text: String) -> void:
	if chat: chat.on_chat_submitted(text)

func _on_respawn_pressed() -> void:
	set_multiplayer_authority(1)
	if multiplayer.is_server(): World.rpc_request_respawn.rpc(multiplayer.get_unique_id())
	else: World.rpc_request_respawn.rpc_id(1, multiplayer.get_unique_id())

# ── Clothing / visuals ────────────────────────────────────────────────────────

func _setup_clothing_sprites() -> void:   if visuals: visuals.setup_sprites()
func _update_clothing_sprites() -> void:  if visuals: visuals.update_clothing_sprites()
func _update_sprite() -> void:            if visuals: visuals.update_sprite()
func _update_water_submerge() -> void:    if visuals: visuals.update_water_submerge()
func get_pixel_pos() -> Vector2: return pixel_pos

# ── Hands / authority ─────────────────────────────────────────────────────────

func _on_authority_changed() -> void:
	if _is_local_authority():
		if camera == null: camera = get_parent().get_node_or_null("Camera2D")
		if _canvas_layer == null: _build_ui()
		if _hud: _hud.update_stats(health, stamina)
		if _dead_container: _dead_container.visible = dead

func sync_hands(hand_names: Array) -> void:
	var main = World.main_scene
	if not main: return
	for i in range(2):
		var base_name = hand_names[i]
		if base_name == null or base_name == "":
			hands[i] = null
			continue
		var found = null
		for child in main.get_children():
			if child.name.begins_with(base_name):
				found = child
				break
		if found:
			hands[i] = found
			for child in found.get_children():
				if child is CollisionShape2D: child.disabled = true
			found.set("z_level", z_level)
	_update_hands_ui()

# ── Reconnection ──────────────────────────────────────────────────────────────

func _on_reconnection_confirmed() -> void:
	_on_authority_changed()
	_update_sprite()
	_update_clothing_sprites()
	_update_hands_ui()
	if _is_local_authority() and _hud != null: _hud.update_clothing_display(equipped, equipped_data)
	if dead: _die_visuals()
	elif sleep_state != SleepState.AWAKE: _set_lying_down_visuals(true)
	if _is_local_authority(): Sidebar.add_message("[color=#aaffaa]You have reconnected to your body![/color]")

@rpc("any_peer", "call_remote", "reliable")
func rpc_set_spawn_position(spawn_pos: Vector2) -> void:
	if multiplayer.get_remote_sender_id() != 1: return
	position = spawn_pos
	tile_pos = Vector2i(int(position.x / World.TILE_SIZE), int(position.y / World.TILE_SIZE))
	pixel_pos = World.tile_to_pixel(tile_pos)
	if _is_local_authority() and camera != null:
		camera.position = pixel_pos
		var vp_size = get_viewport_rect().size
		camera.offset = PlayerDefs.get_camera_offset(vp_size)

# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	var is_local := _is_local_authority()

	if is_possessed: _check_stamina_regen(delta)
	if sleep_: sleep_.update(delta, is_local)

	if not dead:
		_blood_drip_timer += delta
		var drip_period: float = 0.0
		var drip_count: int = 0
		var drip_z_offset: int = 50
		for drip_state in PlayerDefs.BLOOD_DRIP_STATES:
			if health <= drip_state["health_at_or_below"]:
				drip_period = drip_state["period"]
				drip_count = drip_state["count"]
				drip_z_offset = drip_state["z_offset"]
				break
		if drip_count > 0 and _blood_drip_timer >= drip_period:
			_blood_drip_timer = 0.0
			var drip = Node2D.new()
			drip.set_script(BloodSpray)
			drip.is_drip = true
			drip.count = drip_count
			drip.position = pixel_pos
			drip.z_index = Defs.get_z_index(z_level, drip_z_offset)
			get_parent().add_child(drip)

	if is_local and _hud: _hud.update_stats(health, stamina)

	if is_local and is_sneaking and not dead:
		if sneak: sneak.process_sneak_alpha(delta)

	if is_possessed:
		if misc:     misc.update(delta)
		if crafting: crafting.update(delta)

	if is_local and action_cooldown > 0.0: action_cooldown -= delta

	if dead:
		if camera and is_local:
			camera.position = pixel_pos
			var vp_size = get_viewport_rect().size
			camera.offset = PlayerDefs.get_camera_offset(vp_size)
		return

	buffered_dir = Vector2i.ZERO
	if is_local:
		if sleep_state == SleepState.AWAKE:
			if _chat_input == null or not _chat_input.has_focus():
				if combat_mode and get_window().has_focus(): _face_toward(get_global_mouse_position())
				if   Input.is_key_pressed(KEY_W): buffered_dir.y -= 1
				elif Input.is_key_pressed(KEY_S): buffered_dir.y += 1
				elif Input.is_key_pressed(KEY_A): buffered_dir.x -= 1
				elif Input.is_key_pressed(KEY_D): buffered_dir.x += 1
		if buffered_dir != Vector2i.ZERO and view_z_level != z_level:
			view_z_level = z_level

	if is_local and _stand_up_timer >= 0.0:
		if sleep_: sleep_.update_stand_up(delta, buffered_dir)

	if moving:
		move_elapsed += delta
		var t: float = clamp(move_elapsed / current_move_duration, 0.0, 1.0)
		pixel_pos = move_from.lerp(move_to, t)
		position  = pixel_pos
		if t >= 1.0:
			moving    = false
			pixel_pos = move_to
			position  = pixel_pos
			_update_water_submerge()
			if is_local: _try_move(buffered_dir)
	else:
		if is_local: _try_move(buffered_dir)

	if camera and is_local:
		camera.position = pixel_pos
		var vp_size = get_viewport_rect().size
		camera.offset = PlayerDefs.get_camera_offset(vp_size)

	if is_local and _inspect_label != null: _inspect_label.visible = Input.is_key_pressed(KEY_SHIFT)

	if is_local:
		if grabbed_target != null and not is_instance_valid(grabbed_target):
			grabbed_target = null; _update_grab_ui()
		if grabbed_by != null and not is_instance_valid(grabbed_by):
			grabbed_by = null; _update_grab_ui()

	if visuals: visuals.update_hand_positions()
