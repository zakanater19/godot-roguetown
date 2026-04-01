# res://scripts/player/playercrafting.gd
extends RefCounted

var player: Node2D

const TILE_SIZE: int = 64

# --- CRAFTING STATE ---
var craft_panel: Control = null
var active_craft_attempts: Array =[]
const CRAFT_DURATION: float = 5.0

func _init(p_player: Node2D) -> void:
	player = p_player

# ===========================================================================
# Lifecycle Updates
# ===========================================================================

func update(delta: float) -> void:
	_update_craft_attempts(delta)

func on_tile_pos_changed() -> void:
	if craft_panel != null and is_instance_valid(craft_panel):
		_open_crafting_menu()

func close_menus() -> void:
	if craft_panel != null:
		_close_crafting_menu()

# ===========================================================================
# Crafting Logic
# ===========================================================================

func toggle_crafting_menu() -> void:
	if not player._is_local_authority():
		return
	if craft_panel != null and is_instance_valid(craft_panel):
		_close_crafting_menu()
	else:
		_open_crafting_menu()

func _close_crafting_menu() -> void:
	if craft_panel != null and is_instance_valid(craft_panel):
		craft_panel.queue_free()
	craft_panel = null

func _get_available_crafting_resources() -> Array:
	var available_nodes =[]
	for i in range(2):
		if player.hands[i] != null:
			available_nodes.append(player.hands[i])
	
	for obj in player.get_tree().get_nodes_in_group("pickable"):
		if obj == player.hands[0] or obj == player.hands[1]:
			continue
		if obj.get("z_level") != null and obj.z_level != player.z_level:
			continue
		var obj_tile = Vector2i(int(obj.global_position.x / TILE_SIZE), int(obj.global_position.y / TILE_SIZE))
		var diff = (obj_tile - player.tile_pos).abs()
		if diff.x <= 1 and diff.y <= 1:
			available_nodes.append(obj)
			
	return available_nodes

func _open_crafting_menu() -> void:
	if craft_panel != null and is_instance_valid(craft_panel):
		craft_panel.queue_free()
		
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(240, 260)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left   = 120
	panel.offset_right  = 360
	panel.offset_top    = -150
	panel.offset_bottom = 150
	panel.mouse_filter  = Control.MOUSE_FILTER_STOP
	craft_panel = panel
	player._ui_root.add_child(panel)
	
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   = 6
	vbox.offset_right  = -6
	vbox.offset_top    = 6
	vbox.offset_bottom = -6
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)
	
	var title := Label.new()
	title.text = "Crafting Menu"
	title.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	title.add_theme_font_size_override("font_size", 12)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(24, 20)
	close_btn.pressed.connect(_close_crafting_menu)
	title_row.add_child(close_btn)
	
	vbox.add_child(HSeparator.new())
	
	var avail = _get_available_crafting_resources()
	var counts = {}
	for obj in avail:
		var iname = obj.get("item_type")
		if iname == null: iname = obj.name.get_slice("@", 0)
		counts[iname] = counts.get(iname, 0) + 1
		
	var recipes =[
		{"id": "sword", "name": "Sword", "req": "IronIngot", "req_amt": 1, "skill_req": {"blacksmithing": 3}},
		{"id": "pickaxe", "name": "Pickaxe", "req": "IronIngot", "req_amt": 1, "skill_req": {"blacksmithing": 2}},
		{"id": "wooden_floor", "name": "Wooden Floor", "req": "Log", "req_amt": 1},
		{"id": "cobble_floor", "name": "Cobble Floor", "req": "Pebble", "req_amt": 1},
		{"id": "stone_wall", "name": "Stone Wall", "req": "Pebble", "req_amt": 2}
	]
	
	var recipes_added: int = 0
	
	for r in recipes:
		var can_craft = true
		if r.has("skill_req"):
			for skill_name in r["skill_req"]:
				if player.skills.get(skill_name, 0) < r["skill_req"][skill_name]:
					can_craft = false
					
		if can_craft and counts.get(r["req"], 0) >= r["req_amt"]:
			var row := HBoxContainer.new()
			vbox.add_child(row)
			
			var r_lbl := Label.new()
			r_lbl.text = r["name"] + " (" + str(r["req_amt"]) + " " + r["req"] + ")"
			r_lbl.add_theme_font_size_override("font_size", 11)
			r_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(r_lbl)
			
			var btn := Button.new()
			btn.text = "Craft"
			btn.add_theme_font_size_override("font_size", 10)
			btn.pressed.connect(func(): _on_craft_button_pressed(r["id"]))
			row.add_child(btn)
			recipes_added += 1
			
	if recipes_added == 0:
		var empty_lbl := Label.new()
		empty_lbl.text = "No recipes available."
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		empty_lbl.add_theme_font_size_override("font_size", 11)
		vbox.add_child(empty_lbl)

func _on_craft_button_pressed(recipe_id: String) -> void:
	for attempt in active_craft_attempts:
		if attempt["recipe_id"] == recipe_id:
			return
	
	var prog_lbl = _create_craft_indicator(player, recipe_id)
	prog_lbl.text = "."
	prog_lbl.visible = true
	
	var attempt = {
		"recipe_id": recipe_id,
		"elapsed": 0.0,
		"blink_elapsed": 0.0,
		"prog_label": prog_lbl,
		"start_tile": player.tile_pos
	}
	active_craft_attempts.append(attempt)
	Sidebar.add_message("[color=#aaffaa]Started crafting " + recipe_id + "...[/color]")

func _update_craft_attempts(delta: float) -> void:
	var completed_keys: Array =[]
	var cancelled_keys: Array =[]
	
	for attempt in active_craft_attempts:
		var recipe_id = attempt["recipe_id"]
		var prog_lbl: Label = attempt["prog_label"]
		
		if player.tile_pos != attempt["start_tile"]:
			cancelled_keys.append(recipe_id)
			continue
			
		attempt["elapsed"] += delta
		attempt["blink_elapsed"] += delta
		
		var progress: float = clamp(attempt["elapsed"] / CRAFT_DURATION, 0.0, 1.0)
		var dot_count: int = clamp(int(progress * 5.0) + 1, 1, 5)
		var dot_str: String = ""
		for _d in range(dot_count):
			dot_str += "."
		
		if attempt["blink_elapsed"] >= 0.25:
			attempt["blink_elapsed"] = 0.0
			prog_lbl.visible = not prog_lbl.visible
			
		if prog_lbl.visible:
			prog_lbl.text = dot_str
			
		if attempt["elapsed"] >= CRAFT_DURATION:
			completed_keys.append(recipe_id)
			
	for r_id in completed_keys:
		_complete_craft_attempt(r_id)
		
	var all_done = completed_keys + cancelled_keys
	for r_id in all_done:
		for attempt in active_craft_attempts:
			if attempt["recipe_id"] == r_id:
				_remove_craft_indicator(player, r_id)
				if r_id in cancelled_keys and player._is_local_authority():
					Sidebar.add_message("[color=#ffaaaa]Crafting cancelled (moved).[/color]")
				break
				
	active_craft_attempts = active_craft_attempts.filter(
		func(a): return not (a["recipe_id"] in all_done)
	)
	
	if craft_panel != null and is_instance_valid(craft_panel) and all_done.size() > 0:
		_open_crafting_menu()

func _complete_craft_attempt(recipe_id: String) -> void:
	var my_peer_id = player.multiplayer.get_unique_id()
	if player.multiplayer.is_server():
		World.rpc_request_craft(my_peer_id, recipe_id)
	else:
		World.rpc_request_craft.rpc_id(1, my_peer_id, recipe_id)

func _create_craft_indicator(target: Node, recipe_id: String) -> Label:
	var lbl := Label.new()
	lbl.name = "CraftProg_" + recipe_id
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.position = Vector2(-20, -64) # Above head
	target.add_child(lbl)
	return lbl

func _remove_craft_indicator(target: Node, recipe_id: String) -> void:
	var lbl = target.get_node_or_null("CraftProg_" + recipe_id)
	if lbl != null:
		lbl.queue_free()