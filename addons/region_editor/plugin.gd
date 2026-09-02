@tool
extends EditorPlugin

const REGION_PREFIX := "RegionMapLayer_Z"
const TILE_PREFIX := "TileMapLayer_Z"
const DEFAULT_Z_LEVEL := 3

var _panel: VBoxContainer = null
var _bottom_button: Button = null
var _level_label: Label = null
var _active_z: int = DEFAULT_Z_LEVEL


func _enter_tree() -> void:
	_build_panel()
	_bottom_button = add_control_to_bottom_panel(_panel, "Region")
	_bottom_button.visible = false
	_panel.visibility_changed.connect(_on_panel_visibility_changed)
	get_editor_interface().get_selection().selection_changed.connect(_on_selection_changed)
	_set_region_visibility(-1)
	_on_selection_changed()


func _exit_tree() -> void:
	var selection := get_editor_interface().get_selection()
	if selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.disconnect(_on_selection_changed)
	_set_region_visibility(-1)
	if _panel != null:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null
		_bottom_button = null


func _build_panel() -> void:
	_panel = VBoxContainer.new()
	_panel.name = "Region"
	_panel.custom_minimum_size = Vector2(0, 118)

	var title := Label.new()
	title.text = "Region painting"
	title.add_theme_font_size_override("font_size", 16)
	_panel.add_child(title)

	var row := HBoxContainer.new()
	_panel.add_child(row)

	var prompt := Label.new()
	prompt.text = "Edit region layer:"
	row.add_child(prompt)

	for z_level in range(1, 6):
		var button := Button.new()
		button.text = "Z%d" % z_level
		button.tooltip_text = "Open the region TileMap for Z-level %d" % z_level
		button.pressed.connect(_select_region_layer.bind(z_level))
		row.add_child(button)

	_level_label = Label.new()
	_level_label.text = "Current: Z%d" % _active_z
	row.add_child(_level_label)

	var help := Label.new()
	help.text = "Choose a Z-level, then use the normal TileMap tab to paint or erase the brown 'town' tile. Regions are editor-only and do not replace floors or walls."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(help)


func _on_panel_visibility_changed() -> void:
	if _panel == null:
		return
	if _panel.is_visible_in_tree():
		_set_region_visibility(_active_z)
	else:
		_on_selection_changed()


func _on_selection_changed() -> void:
	var selected := get_editor_interface().get_selection().get_selected_nodes()
	var selected_region_z := -1
	for node in selected:
		var z_level := _z_level_from_name(str(node.name), REGION_PREFIX)
		if z_level != -1:
			selected_region_z = z_level
			break
		z_level = _z_level_from_name(str(node.name), TILE_PREFIX)
		if z_level != -1:
			_active_z = z_level

	if selected_region_z != -1:
		_active_z = selected_region_z
		if _bottom_button != null:
			_bottom_button.visible = true
		_set_region_visibility(_active_z)
	else:
		if _bottom_button != null:
			_bottom_button.visible = false
		if _panel != null and _panel.is_visible_in_tree():
			hide_bottom_panel()
		_set_region_visibility(-1)
	_update_level_label()


func _select_region_layer(z_level: int) -> void:
	_active_z = clampi(z_level, 1, 5)
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		return
	var layer := root.get_node_or_null(REGION_PREFIX + str(_active_z))
	if layer == null:
		push_warning("The edited scene has no region map for Z%d." % _active_z)
		return
	var selection := get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(layer)
	_set_region_visibility(_active_z)
	_update_level_label()


func _set_region_visibility(visible_z: int) -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		return
	for z_level in range(1, 6):
		var layer := root.get_node_or_null(REGION_PREFIX + str(z_level)) as TileMapLayer
		if layer != null:
			layer.visible = z_level == visible_z


func _update_level_label() -> void:
	if _level_label != null:
		_level_label.text = "Current: Z%d" % _active_z


func _z_level_from_name(node_name: String, prefix: String) -> int:
	if not node_name.begins_with(prefix):
		return -1
	var suffix := node_name.trim_prefix(prefix)
	if not suffix.is_valid_int():
		return -1
	var z_level := int(suffix)
	return z_level if z_level >= 1 and z_level <= 5 else -1
