# res://scripts/core/player.gd
extends Node2D

const MOVE_TIME:   float = 0.22
const THROW_TILES:    int   = 4
const THROW_DURATION: float = 0.18
const DROP_SPREAD:    float = 14.0

const FACING_NAMES: Array =["south", "north", "east", "west"]

const BloodSpray = preload("res://npcs/blood_spray.gd")

var backend = null
var misc = null
var combat = null
var crafting = null
var body = null
var visuals = null
var sleep_ = null

var is_possessed: bool = true

enum SleepState { AWAKE, FALLING_ASLEEP, ASLEEP, WAKING_UP }
var sleep_state: SleepState = SleepState.AWAKE
var sleep_timer: float = 0.0
var health_regen_accumulator: float = 0.0
var _sleep_blackout: ColorRect = null
@warning_ignore("unused_private_class_variable")
var _sleeping_on_bed: bool = false

@export var character_name: String = "noob"
@export var character_class: String = "peasant"
@export var z_level: int = 3

var tile_pos: Vector2i = Vector2i.ZERO :
	set(val):
		var diff := (val - tile_pos).abs()
		tile_pos = val
		if diff.x > 1 or diff.y > 1:
			pixel_pos = World.tile_to_pixel(val)
			position = pixel_pos
		if misc != null:
			misc.on_tile_pos_changed()
		if crafting != null:
			crafting.on_tile_pos_changed()

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

var skills: Dictionary = {"sword_fighting": 0, "blacksmithing": 0}
var prices_shown: bool = false
var stats: Dictionary = {"strength": 10, "agility": 10}
var health: int = 100
var stamina: float = 100.0
var max_stamina: float = 100.0
var last_exertion_time: float = 0.0
var _blood_drip_timer: float = 0.0

var dead: bool = false :
	set(val):
		dead = val
		if dead: _die_visuals()

var hands:        Array[Node] =[null, null]
var active_hand:  int         = 0
var _is_throwing: bool        = false

var equipped: Dictionary = {"head": null, "face": null, "cloak": null, "armor": null, "backpack": null, "waist": null, "clothing": null, "trousers": null, "feet": null, "gloves": null, "pocket_l": null, "pocket_r": null}
var equipped_data: Dictionary = {"head": null, "face": null, "cloak": null, "armor": null, "backpack": null, "waist": null, "clothing": null, "trousers": null, "feet": null, "gloves": null, "pocket_l": null, "pocket_r": null}

var throwing_mode:     bool    = false
var _throw_label:      Label   = null
var _inspect_label:    Label   = null
var _combat_indicator: Label   = null
var _dead_container:   Control = null
var _canvas_layer:     CanvasLayer = null
var _ui_root:          Control = null
var _hud: CanvasLayer = null

var _chat_input:           LineEdit        = null
var _active_chat_messages: Array[Node2D]   =[]

var _drag_candidate:  Node    = null
var _drag_origin:     Vector2 = Vector2.ZERO
const DRAG_THRESHOLD: float   = 10.0
var _dragging_player: Node = null

var grabbed_target: Node = null
var grabbed_by:     Node = null
var grab_hand_idx:  int  = -1

@rpc("any_peer", "call_local", "reliable")
func _sync_character_name(p_name: String, p_class: String) -> void:
	var class_changed = (character_class != p_class)
	character_name = p_name
	character_class = p_class
	if class_changed:
		_apply_class_defaults()

func set_character_name(p_name: String, p_class: String) -> void:
	var class_changed = (character_class != p_class)
	character_name = p_name
	character_class = p_class
	if class_changed:
		_apply_class_defaults()
	if multiplayer.has_multiplayer_peer():
		var peer_id = get_multiplayer_authority()
		if peer_id != 1:
			_sync_character_name.rpc_id(peer_id, p_name, p_class)

func get_description() -> String: return backend.get_description() if backend else character_name
func get_detailed_description() -> String: return backend.get_detailed_description() if backend else character_name
func get_inspect_color() -> Color: return backend.get_inspect_color() if backend else Color.WHITE
func get_inspect_font_size() -> int: return backend.get_inspect_font_size() if backend else 11
func _apply_class_defaults() -> void: if backend: backend.apply_class_defaults()
func _spend_stamina(amount: float) -> void: if backend: backend.spend_stamina(amount)

@rpc("any_peer", "call_local", "reliable")
func rpc_consume_stamina(amount: float) -> void:
	if _is_local_authority():
		if stamina < amount:
			exhausted = true
			Sidebar.add_message("[color=#ffaaaa]You overexerted yourself defending![/color]")
		_spend_stamina(amount)

func _check_stamina_regen(delta: float) -> void: if backend: backend.check_stamina_regen(delta)
func _equip_clothing(item: Node) -> void: if backend: backend.equip_clothing(item)
func _equip_clothing_to_slot(item: Node, slot_name: String) -> void: if backend: backend.equip_clothing_to_slot(item, slot_name)
func _perform_equip(item: Node, slot_name: String, hand_index: int) -> void: if backend: backend.perform_equip(item, slot_name, hand_index)
func _unequip_clothing_from_slot(slot_name: String) -> void: if backend: backend.unequip_clothing_from_slot(slot_name)
func _perform_unequip(slot_name: String, new_node_name: String, hand_index: int) -> void: if backend: backend.perform_unequip(slot_name, new_node_name, hand_index)
func _inspect_at(world_pos: Vector2) -> void: if backend: backend.inspect_at(world_pos)
func _show_inspect_text(text: String, detailed_desc: String) -> void: if backend: backend.show_inspect_text(text, detailed_desc)
func _apply_action_cooldown(item: Node, is_attack: bool = false) -> void: if backend: backend.apply_action_cooldown(item, is_attack)
func _face_toward(world_pos: Vector2) -> void: if backend: backend.face_toward(world_pos)

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
func toggle_crafting_menu() -> void: if crafting: crafting.toggle_crafting_menu()
func toggle_combat_mode() -> void: if combat: combat.toggle_combat_mode()
func toggle_combat_stance() -> void: if combat: combat.toggle_combat_stance()
func show_loot_warning(looter_peer_id: int, item_desc: String) -> void: if misc: misc.show_loot_warning(looter_peer_id, item_desc)
func get_strength_damage_modifier() -> float: return combat.get_strength_damage_modifier() if combat else 0.0
func _get_weapon_damage(item: Node) -> int: return combat.get_weapon_damage(item) if combat else 5

@rpc("any_peer", "call_local", "reliable")
func receive_damage(amount: int, limb: String = "chest") -> void:
	if body: body.receive_limb_damage(limb, amount)
	if combat: combat.receive_damage(amount)
	if multiplayer.is_server():
		var peer := get_multiplayer_authority()
		if LateJoin.is_player_disconnected(peer):
			LateJoin.update_disconnected_health(peer, health)

func _die() -> void: if combat: combat.die()
func _die_visuals() -> void: if combat: combat.die_visuals()

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
	if _hud != null:
		_hud.update_clothing_display(equipped, equipped_data)
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			rpc("_sync_hood_state", hood_up)
		else:
			rpc_id(1, "_sync_hood_state", hood_up)

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

# ─────────────────────────────────────────────────────────────────────────────

func toggle_sleep() -> void: if sleep_: sleep_.toggle_sleep()
func _is_on_bed() -> bool: return sleep_.is_on_bed() if sleep_ else false
func _sync_sleep_state_update(new_state: SleepState) -> void: if sleep_: sleep_.sync_sleep_state_update(new_state)

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

func _set_lying_down_visuals(_lying_down: bool) -> void: if sleep_: sleep_.set_lying_down_visuals(_lying_down)
func toggle_lying_down() -> void: if sleep_: sleep_.toggle_lying_down()
func _cancel_stand_up() -> void: if sleep_: sleep_.cancel_stand_up()
func _create_stand_up_label() -> Label: return sleep_.create_stand_up_label() if sleep_ else null
func _complete_stand_up() -> void: if sleep_: sleep_.complete_stand_up()

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

@rpc("any_peer", "call_local", "reliable")
func rpc_sync_z_level(new_z: int) -> void:
	z_level = new_z
	z_index = (z_level - 1) * 200 + 10
	_update_water_submerge()
	
	for h in hands:
		if h != null and is_instance_valid(h):
			h.set("z_level", new_z)

	if _is_local_authority():
		if _hud:
			_hud.update_stats(health, stamina)

@rpc("any_peer", "call_local", "reliable")
func rpc_make_corpse() -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != 1 and sender_id != 0: return
	
	is_possessed = false
	set_multiplayer_authority(1) 
	
	if _canvas_layer:
		_canvas_layer.queue_free()
		_canvas_layer = null
	if _hud:
		_hud.queue_free()
		_hud = null
	if camera:
		# Do NOT free the shared Camera2D. Just clear the reference.
		camera = null
	if _combat_indicator:
		_combat_indicator.queue_free()
		_combat_indicator = null

func _enter_tree() -> void:
	if name.begins_with("Player_"):
		var parts = name.split("_")
		if parts.size() > 1:
			set_multiplayer_authority(parts[1].to_int())

func _ready() -> void:
	z_index = (z_level - 1) * 200 + 10
	add_to_group("z_entity")
	backend = preload("res://scripts/player/playerbackend.gd").new(self)
	misc = preload("res://scripts/player/playermisc.gd").new(self)
	combat = preload("res://scripts/player/playercombat.gd").new(self)
	crafting = preload("res://scripts/player/playercrafting.gd").new(self)
	body = preload("res://scripts/player/body.gd").new(self)
	visuals = preload("res://scripts/player/playervisuals.gd").new(self)
	sleep_ = preload("res://scripts/player/playersleep.gd").new(self)
	
	add_to_group("player")

	_apply_class_defaults()

	if position == Vector2.ZERO and multiplayer.is_server():
		tile_pos = Vector2i(500, 500)
		position = Vector2(32032, 32032)

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

func _start_move_lerp() -> void:
	_awaiting_move_confirm = false
	var new_pixel := World.tile_to_pixel(tile_pos)
	if new_pixel == pixel_pos: return

	if dead:
		pixel_pos = new_pixel
		position  = pixel_pos
		return

	if is_sprinting and _is_local_authority():
		if stamina < 3.0:
			exhausted = true
			Sidebar.add_message("[color=#ffaaaa]You overexerted yourself![/color]")
		_spend_stamina(3.0)

	_update_water_submerge()
	move_from    = pixel_pos
	move_to      = new_pixel
	move_elapsed = 0.0
	moving       = true

func _on_authority_changed() -> void:
	if _is_local_authority():
		if camera == null: camera = get_parent().get_node_or_null("Camera2D")
		if _canvas_layer == null: _build_ui()
		if _hud: _hud.update_stats(health, stamina)
		if _dead_container: _dead_container.visible = dead

func sync_hands(hand_names: Array) -> void:
	var main = get_tree().root.get_node_or_null("Main")
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

func _setup_clothing_sprites() -> void:
	if visuals: visuals.setup_sprites()

func _update_clothing_sprites() -> void:
	if visuals: visuals.update_clothing_sprites()

func _build_ui() -> void:
	var cl := CanvasLayer.new()
	cl.layer      = 10
	_canvas_layer = cl
	add_child(cl)
	var safe_area := Control.new()
	safe_area.name          = "SafeArea"
	safe_area.anchor_left   = 0.0
	safe_area.anchor_right  = 0.0
	safe_area.anchor_top    = 0.0
	safe_area.anchor_bottom = 0.0
	safe_area.offset_right  = 1000.0
	safe_area.offset_bottom = 720.0
	safe_area.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	cl.add_child(safe_area)
	_ui_root = safe_area

	_sleep_blackout = ColorRect.new()
	_sleep_blackout.color = Color(0, 0, 0, 0)
	_sleep_blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sleep_blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe_area.add_child(_sleep_blackout)

	_throw_label = Label.new()
	_throw_label.text = "THROWING"
	_throw_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.0))
	_throw_label.add_theme_font_size_override("font_size", 14)
	_throw_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_throw_label.offset_left   = 12
	_throw_label.offset_top    = -10
	_throw_label.offset_right  = 120
	_throw_label.offset_bottom = 10
	_throw_label.visible       = false
	safe_area.add_child(_throw_label)

	_inspect_label = Label.new()
	_inspect_label.text = "INSPECTING"
	_inspect_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.0))
	_inspect_label.add_theme_font_size_override("font_size", 14)
	_inspect_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_inspect_label.offset_left   = 12
	_inspect_label.offset_top    = 10
	_inspect_label.offset_right  = 140
	_inspect_label.offset_bottom = 30
	_inspect_label.visible       = false
	safe_area.add_child(_inspect_label)

	_combat_indicator = Label.new()
	_combat_indicator.text = "!"
	_combat_indicator.add_theme_color_override("font_color", Color.RED)
	_combat_indicator.add_theme_font_size_override("font_size", 24)
	_combat_indicator.position = Vector2(-4, -60)
	_combat_indicator.visible  = false
	add_child(_combat_indicator)

	_dead_container = VBoxContainer.new()
	_dead_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dead_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_dead_container.visible   = false
	safe_area.add_child(_dead_container)
	
	var you_died_label := Label.new()
	you_died_label.text = "YOU DIED"
	you_died_label.add_theme_color_override("font_color", Color(0.85, 0.0, 0.0))
	you_died_label.add_theme_font_size_override("font_size", 72)
	you_died_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dead_container.add_child(you_died_label)
	
	var respawn_btn := Button.new()
	respawn_btn.text = "Respawn"
	respawn_btn.add_theme_font_size_override("font_size", 24)
	respawn_btn.pressed.connect(_on_respawn_pressed)
	_dead_container.add_child(respawn_btn)

	_chat_input = LineEdit.new()
	_chat_input.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_input.offset_left      = 12
	_chat_input.offset_top       = -40
	_chat_input.offset_right     = 312
	_chat_input.offset_bottom    = -10
	_chat_input.placeholder_text = "Say something..."
	_chat_input.visible          = false
	_chat_input.text_submitted.connect(_on_chat_submitted)
	safe_area.add_child(_chat_input)

	_hud = CanvasLayer.new()
	_hud.set_script(load("res://scripts/ui/HUD.gd"))
	add_child(_hud)
	_hud.setup(self)
	_hud.update_clothing_display(equipped, equipped_data)
	_hud.update_combat_display(combat_mode)
	_hud.update_stance_display(combat_stance)

	_update_hands_ui()

func _on_respawn_pressed() -> void:
	# Yield authority locally immediately to prevent the synchronizer warning
	# when the server takes over this corpse.
	set_multiplayer_authority(1)
	
	if multiplayer.is_server():
		World.rpc_request_respawn.rpc(multiplayer.get_unique_id())
	else:
		World.rpc_request_respawn.rpc_id(1, multiplayer.get_unique_id())

func _update_hands_ui() -> void:
	if _hud != null: _hud.update_hands_display(hands, active_hand)

func _update_grab_ui() -> void:
	if _hud != null:
		_hud.update_grab_display(grabbed_target != null and is_instance_valid(grabbed_target), grabbed_by != null and is_instance_valid(grabbed_by))
	_update_hands_ui()

func show_stats_skills() -> void:
	var lines: Array[String] =[]
	lines.append("[color=#aaccff][b]--- Stats ---[/b][/color]")
	for stat_name in stats:
		var val = stats[stat_name]
		var col = "#aaaaaa"
		if val > 10: col = "#44ff44"
		elif val < 10: col = "#ff4444"
		lines.append("[color=" + col + "]" + stat_name + ": " + str(val) + "[/color]")
	lines.append("")
	lines.append("[color=#aaccff][b]--- Skills ---[/b][/color]")
	for skill_name in skills:
		var val = skills[skill_name]
		lines.append("[color=#cccccc]" + skill_name + ": " + str(val) + "[/color]")
	if prices_shown: lines.append("[color=#ffff44]Special Skill: Prices Shown[/color]")
	for line in lines: Sidebar.add_message(line)

func _process(delta: float) -> void:
	var is_local := _is_local_authority()
	
	if is_possessed:
		_check_stamina_regen(delta)
		
	if sleep_: sleep_.update(delta, is_local)

	if not dead:
		_blood_drip_timer += delta
		var drip_period: float = 0.0
		var drip_count: int = 0
		if health <= 30:
			drip_period = 2.0
			drip_count = 9
		elif health <= 40:
			drip_period = 5.0
			drip_count = 6
		elif health <= 60:
			drip_period = 10.0
			drip_count = 3
		if drip_count > 0 and _blood_drip_timer >= drip_period:
			_blood_drip_timer = 0.0
			var drip = Node2D.new()
			drip.set_script(BloodSpray)
			drip.is_drip = true 
			drip.count = drip_count
			drip.position = pixel_pos
			drip.z_index = (z_level - 1) * 200 + 50
			get_parent().add_child(drip)

	if is_local and _hud: _hud.update_stats(health, stamina)
	
	if is_possessed:
		if misc: misc.update(delta)
		if crafting: crafting.update(delta)
		
	if is_local and action_cooldown > 0.0: action_cooldown -= delta
	
	if dead:
		if camera and is_local:
			camera.position = pixel_pos
			var vp_size = get_viewport_rect().size
			camera.offset = Vector2((vp_size.x / 2.0) - 500.0, (vp_size.y / 2.0) - 360.0)
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
		camera.offset = Vector2((vp_size.x / 2.0) - 500.0, (vp_size.y / 2.0) - 360.0)

	if is_local and _inspect_label != null: _inspect_label.visible = Input.is_key_pressed(KEY_SHIFT)

	if is_local:
		if grabbed_target != null and not is_instance_valid(grabbed_target):
			grabbed_target = null; _update_grab_ui()
		if grabbed_by != null and not is_instance_valid(grabbed_by):
			grabbed_by = null; _update_grab_ui()

	if backend:
		for i in range(2):
			var obj = hands[i]
			if obj != null and not (i == active_hand and _is_throwing):
				var hand_key:    String = "right" if i == 0 else "left"
				var facing_name: String = FACING_NAMES[facing]
				var item_name = obj.get("item_type")
				if item_name == null: item_name = obj.name.get_slice("@", 0)
				var hand_transform = backend.get_hand_transform(item_name, facing_name, hand_key)
				var flip_h: bool = hand_transform.flip_h
				if facing == 3: flip_h = not flip_h
				obj.global_position = pixel_pos + hand_transform.offset
				obj.z_index = z_index - 1 if facing == 1 else z_index + 6
				var sprite: Sprite2D = obj.get_node_or_null("Sprite2D")
				if sprite != null:
					sprite.rotation_degrees = hand_transform.rotation
					var mag_x := absf(sprite.scale.x)
					var mag_y := absf(sprite.scale.y)
					sprite.scale = Vector2(-mag_x if flip_h else mag_x, mag_y)

func _unhandled_input(event: InputEvent) -> void:
	if not _is_local_authority(): return
	if dead: return

	if sleep_state != SleepState.AWAKE:
		if event is InputEventMouseButton: return
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode in[KEY_C, KEY_X, KEY_R, KEY_Q, KEY_V, KEY_Z, KEY_SHIFT, KEY_T]: return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_drag_candidate = null
		if _dragging_player != null:
			if is_instance_valid(_dragging_player):
				var mw := get_global_mouse_position()
				if mw.distance_to(pixel_pos) < float(World.TILE_SIZE) * 0.6:
					if misc: misc.open_target_inventory(_dragging_player)
			_dragging_player = null
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion:
		if _drag_candidate != null and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if event.position.distance_to(_drag_origin) > DRAG_THRESHOLD:
				_dragging_player = _drag_candidate
				_drag_candidate  = null
		return

	if _chat_input != null and _chat_input.has_focus():
		if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
			_chat_input.visible = false
			_chat_input.clear()
			_chat_input.release_focus()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.keycode == KEY_T and event.pressed and not event.echo:
		if _chat_input != null and not _chat_input.visible:
			_chat_input.visible = true
			_chat_input.grab_focus()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.keycode == KEY_C and event.pressed and not event.echo: toggle_combat_mode(); return
	if event is InputEventKey and event.keycode == KEY_X and event.pressed and not event.echo:
		active_hand = 1 - active_hand
		_update_hands_ui()
		if _throw_label != null: _throw_label.visible = throwing_mode and hands[active_hand] != null
		if multiplayer.has_multiplayer_peer():
			if multiplayer.is_server(): rpc("_sync_active_hand", active_hand)
			else: rpc_id(1, "_sync_active_hand", active_hand)
		return
	if event is InputEventKey and event.keycode == KEY_R and event.pressed and not event.echo:
		throwing_mode = !throwing_mode
		if _throw_label != null: _throw_label.visible = throwing_mode and hands[active_hand] != null
		return
	if event is InputEventKey and event.keycode == KEY_Q and event.pressed and not event.echo:
		throwing_mode = false
		if _throw_label != null: _throw_label.visible = false
		if grabbed_target != null and is_instance_valid(grabbed_target):
			if multiplayer.is_server(): World.rpc_request_release_grab()
			else: World.rpc_request_release_grab.rpc_id(1)
		else: _drop_held_object()
		return
	if event is InputEventKey and event.keycode == KEY_Z and event.pressed and not event.echo:
		if grabbed_by != null and is_instance_valid(grabbed_by):
			if exhausted: Sidebar.add_message("[color=#ffaaaa]You are too exhausted to resist the grab![/color]"); return
			if multiplayer.is_server(): World.rpc_request_resist()
			else: World.rpc_request_resist.rpc_id(1)
		else: _interact_held_object()
		return
	if event is InputEventKey and event.keycode == KEY_V and event.pressed and not event.echo: toggle_lying_down(); return
		
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var mouse_world := get_global_mouse_position()
		var target_tile := Vector2i(int(mouse_world.x / World.TILE_SIZE), int(mouse_world.y / World.TILE_SIZE))
		if not FOV._visible_tiles.has(target_tile): return
		var diff := (target_tile - tile_pos).abs()
		if diff.x <= 1 and diff.y <= 1 and target_tile != tile_pos:
			if combat_mode and hands[active_hand] == null:
				if body != null and body.is_arm_broken(active_hand):
					Sidebar.add_message("[color=#ffaaaa]That arm is useless![/color]")
					get_viewport().set_input_as_handled()
					return
				if action_cooldown > 0.0: return
				if exhausted: Sidebar.add_message("[color=#ffaaaa]You are too exhausted to shove![/color]")
				else:
					if stamina < 5.0:
						exhausted = true
						Sidebar.add_message("[color=#ffaaaa]You overexerted yourself![/color]")
					_spend_stamina(5.0)
					_face_toward(mouse_world)
					_apply_action_cooldown(null, true)
					if multiplayer.is_server(): World.rpc_request_shove(target_tile)
					else: World.rpc_request_shove.rpc_id(1, target_tile)
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var mouse_world := get_global_mouse_position()
		var target_tile := Vector2i(int(mouse_world.x / World.TILE_SIZE), int(mouse_world.y / World.TILE_SIZE))
		if not FOV._visible_tiles.has(target_tile): return

		if Input.is_key_pressed(KEY_CTRL):
			if body != null and body.is_arm_broken(active_hand):
				Sidebar.add_message("[color=#ffaaaa]That arm is useless![/color]")
				get_viewport().set_input_as_handled()
				return
			var grab_target: Node = null
			for p in get_tree().get_nodes_in_group("player"):
				if p == self or p.z_level != z_level: continue
				if p.global_position.distance_to(mouse_world) < float(World.TILE_SIZE) * 0.7:
					grab_target = p; break
			if grab_target == null:
				for obj in get_tree().get_nodes_in_group("pickable"):
					if hands[0] == obj or hands[1] == obj or obj.z_level != z_level: continue
					var obj_tile := Vector2i(int(obj.global_position.x / World.TILE_SIZE), int(obj.global_position.y / World.TILE_SIZE))
					if obj_tile == target_tile: grab_target = obj; break
			if grab_target != null:
				var grab_limb: String = "chest"
				if _hud != null: grab_limb = _hud.targeted_limb
				if multiplayer.is_server(): World.rpc_request_grab(grab_target.get_path(), grab_limb)
				else: World.rpc_request_grab.rpc_id(1, grab_target.get_path(), grab_limb)
			get_viewport().set_input_as_handled()
			return

		if not Input.is_key_pressed(KEY_SHIFT):
			for p in get_tree().get_nodes_in_group("player"):
				if p == self or p.z_level != z_level: continue
				if p.global_position.distance_to(mouse_world) < float(World.TILE_SIZE) * 0.6:
					_drag_candidate = p
					_drag_origin    = event.position
					break

		if Input.is_key_pressed(KEY_SHIFT):
			_face_toward(mouse_world)
			_inspect_at(mouse_world)
			return

		if action_cooldown > 0.0: return
		_face_toward(mouse_world)

		if hands[active_hand] != null and throwing_mode:
			if exhausted: Sidebar.add_message("[color=#ffaaaa]You are too exhausted to throw![/color]")
			else:
				if stamina < 5.0:
					exhausted = true; Sidebar.add_message("[color=#ffaaaa]You overexerted yourself![/color]")
				_spend_stamina(5.0)
				_throw_held_object(mouse_world)
		else: _use_held_object(mouse_world)

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

func _on_chat_submitted(text: String) -> void:
	_chat_input.visible = false; _chat_input.clear(); _chat_input.release_focus()
	if text.strip_edges() == "": return
	if multiplayer.is_server(): World.rpc_send_chat(text)
	else: World.rpc_send_chat.rpc_id(1, text)

func show_remote_chat(sender_name: String, message: String) -> void:
	var full_msg = sender_name + " says: " + message
	Sidebar.add_message(full_msg)
	_show_chat_message(message)

func _show_chat_message(text: String) -> void:
	_active_chat_messages = _active_chat_messages.filter(func(n): return is_instance_valid(n))
	const STEP: float = 22.0
	for msg in _active_chat_messages: msg.position.y -= STEP
	var container := Node2D.new()
	container.position = Vector2(0, -40); container.z_index  = (z_level - 1) * 200 + 100
	add_child(container)
	var label := Label.new()
	label.text = "\"" + text + "\""
	label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1))
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 3)
	label.custom_minimum_size  = Vector2(400, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	label.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	label.grow_vertical        = Control.GROW_DIRECTION_BEGIN
	label.position             = Vector2(-200, 0)
	container.add_child(label)
	_active_chat_messages.append(container)
	get_tree().create_timer(5.0).timeout.connect(func():
		if is_instance_valid(container):
			_active_chat_messages.erase(container)
			container.queue_free()
	)

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

func _update_sprite() -> void:
	if visuals: visuals.update_sprite()

func _update_water_submerge() -> void:
	if visuals: visuals.update_water_submerge()

func get_pixel_pos() -> Vector2: return pixel_pos

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
		camera.offset = Vector2((vp_size.x / 2.0) - 500.0, (vp_size.y / 2.0) - 360.0)
