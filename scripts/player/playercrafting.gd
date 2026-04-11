# res://scripts/player/playercrafting.gd
# Client-side crafting UI and progress tracking.
# Recipe definitions are loaded from RecipeRegistry -- no recipe data lives here.
extends RefCounted

const CRAFTING_MENU_SCENE_PATH := "res://scenes/ui/crafting_menu.tscn"
const CRAFTING_RECIPE_ROW_SCENE_PATH := "res://scenes/ui/crafting_recipe_row.tscn"

var player: Node2D

var craft_panel: Control = null
var active_craft_attempts: Array = []
const CRAFT_DURATION: float = 5.0

func _init(p_player: Node2D) -> void:
	player = p_player

# ===========================================================================
# Lifecycle
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
# Menu
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
	var available_nodes: Array = []
	for i in range(2):
		if player.hands[i] != null:
			available_nodes.append(player.hands[i])

	for obj in player.get_tree().get_nodes_in_group(Defs.GROUP_PICKABLE):
		if obj == player.hands[0] or obj == player.hands[1]:
			continue
		if obj.get("z_level") != null and obj.z_level != player.z_level:
			continue
		var obj_tile := Vector2i(int(obj.global_position.x / World.TILE_SIZE), int(obj.global_position.y / World.TILE_SIZE))
		var diff: Vector2i = (obj_tile - player.tile_pos).abs()
		if diff.x <= 1 and diff.y <= 1:
			available_nodes.append(obj)

	return available_nodes

func _open_crafting_menu() -> void:
	if craft_panel != null and is_instance_valid(craft_panel):
		craft_panel.queue_free()

	var panel := _instantiate_ui_scene(CRAFTING_MENU_SCENE_PATH)
	if panel == null:
		return

	craft_panel = panel
	player._ui_root.add_child(panel)

	var close_btn := panel.get_node("Content/TitleRow/CloseButton") as Button
	var recipe_list := panel.get_node("Content/RecipeList") as VBoxContainer
	var empty_lbl := panel.get_node("Content/RecipeList/EmptyLabel") as Label
	close_btn.pressed.connect(_close_crafting_menu)

	for child in recipe_list.get_children():
		if child != empty_lbl:
			child.queue_free()

	# Count available ingredients nearby.
	var avail := _get_available_crafting_resources()
	var counts: Dictionary = {}
	for obj in avail:
		var iname: String = obj.get("item_type")
		if iname == null or iname == "":
			iname = obj.name.get_slice("@", 0)
		counts[iname] = counts.get(iname, 0) + 1

	# Build UI rows for every recipe the player qualifies for and has materials.
	var recipes_added: int = 0
	for recipe_value in RecipeRegistry.get_available_recipes(player.skills):
		var recipe := recipe_value as RecipeData
		if recipe == null:
			continue
		var required_item_type: String = recipe.get_required_item_type()
		if required_item_type == "":
			continue
		if counts.get(required_item_type, 0) >= recipe.req_amount:
			var row := _instantiate_ui_scene(CRAFTING_RECIPE_ROW_SCENE_PATH) as HBoxContainer
			if row == null:
				continue

			var recipe_id: String = recipe.recipe_id
			var recipe_label := row.get_node("RecipeLabel") as Label
			var craft_btn := row.get_node("CraftButton") as Button
			recipe_label.text = recipe.display_name + " (" + str(recipe.req_amount) + " " + required_item_type + ")"
			craft_btn.pressed.connect(func(): _on_craft_button_pressed(recipe_id))
			recipe_list.add_child(row)
			recipes_added += 1

	empty_lbl.visible = recipes_added == 0

func _instantiate_ui_scene(scene_path: String) -> Control:
	var scene := load(scene_path) as PackedScene
	if scene == null:
		push_error("PlayerCrafting: failed to load %s" % scene_path)
		return null
	return scene.instantiate() as Control

# ===========================================================================
# Progress tracking
# ===========================================================================

func _on_craft_button_pressed(recipe_id: String) -> void:
	for attempt in active_craft_attempts:
		if attempt["recipe_id"] == recipe_id:
			return

	var prog_lbl := _create_craft_indicator(player, recipe_id)
	prog_lbl.text = "."
	prog_lbl.visible = true

	active_craft_attempts.append({
		"recipe_id": recipe_id,
		"elapsed": 0.0,
		"blink_elapsed": 0.0,
		"prog_label": prog_lbl,
		"start_tile": player.tile_pos
	})
	Sidebar.add_message("[color=#aaffaa]Started crafting " + recipe_id + "...[/color]")

func _update_craft_attempts(delta: float) -> void:
	var completed_keys: Array = []
	var cancelled_keys: Array = []

	for attempt in active_craft_attempts:
		var recipe_id: String = attempt["recipe_id"]
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

	var all_done: Array = completed_keys + cancelled_keys
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
	var my_peer_id := player.multiplayer.get_unique_id()
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
	var lbl := target.get_node_or_null("CraftProg_" + recipe_id)
	if lbl != null:
		lbl.queue_free()
