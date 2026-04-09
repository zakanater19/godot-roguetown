# res://scripts/net/lobby_ui.gd
# Instantiates the Lobby UI scene and assigns the relevant controls back to the lobby node.
extends RefCounted

const LOBBY_UI_SCENE_PATH := "res://scenes/ui/lobby_ui.tscn"
const CLASS_OPTIONS: Array[String] = ["peasant", "merchant", "bandit", "adventurer", "king"]

var lobby: Node

func _init(lobby_node: Node) -> void:
	lobby = lobby_node

func build(bg: ColorRect) -> void:
	var scene := load(LOBBY_UI_SCENE_PATH) as PackedScene
	if scene == null:
		push_error("LobbyUI: failed to load %s" % LOBBY_UI_SCENE_PATH)
		return

	var ui_root := scene.instantiate() as Control
	if ui_root == null:
		push_error("LobbyUI: failed to instantiate %s" % LOBBY_UI_SCENE_PATH)
		return

	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_child(ui_root)

	_bind_main_controls(ui_root)
	_bind_latejoin_panel(ui_root)
	_bind_subclass_panel(ui_root)
	_bind_chat_input(ui_root)

func _bind_main_controls(ui_root: Control) -> void:
	lobby._main_content = ui_root.get_node("MainContent") as Control
	lobby._time_label = ui_root.get_node("MainContent/TimeLabel") as Label
	lobby._name_input = ui_root.get_node("MainContent/NameInput") as LineEdit
	lobby._class_option = ui_root.get_node("MainContent/ClassOption") as OptionButton
	lobby._ready_btn = ui_root.get_node("MainContent/ReadyButton") as Button
	lobby._force_btn = ui_root.get_node("MainContent/ForceButton") as Button

	_populate_class_option(lobby._class_option)
	lobby._ready_btn.pressed.connect(lobby._on_ready_pressed)
	lobby._force_btn.pressed.connect(lobby._on_force_pressed)
	lobby._force_btn.visible = false

func _bind_latejoin_panel(ui_root: Control) -> void:
	lobby._latejoin_panel = ui_root.get_node("LatejoinPanel") as Panel
	lobby._lj_name_input = ui_root.get_node("LatejoinPanel/Content/NameInput") as LineEdit
	lobby._lj_class_option = ui_root.get_node("LatejoinPanel/Content/ClassOption") as OptionButton

	_populate_class_option(lobby._lj_class_option)

	var spawn_btn := ui_root.get_node("LatejoinPanel/Content/SpawnButton") as Button
	var back_btn := ui_root.get_node("LatejoinPanel/Content/BackButton") as Button
	spawn_btn.pressed.connect(lobby._on_confirm_latejoin_pressed)
	back_btn.pressed.connect(func():
		lobby._latejoin_panel.visible = false
		lobby._main_content.visible = true
	)

func _bind_subclass_panel(ui_root: Control) -> void:
	lobby._subclass_panel = ui_root.get_node("SubclassPanel") as Panel

	var swordsman_btn := ui_root.get_node("SubclassPanel/Content/SwordsmanButton") as Button
	var miner_btn := ui_root.get_node("SubclassPanel/Content/MinerButton") as Button
	var cancel_btn := ui_root.get_node("SubclassPanel/Content/CancelButton") as Button

	swordsman_btn.pressed.connect(func(): lobby._on_subclass_chosen("swordsman"))
	miner_btn.pressed.connect(func(): lobby._on_subclass_chosen("miner"))
	cancel_btn.pressed.connect(func():
		lobby._subclass_panel.visible = false
		if lobby._pending_action == "latejoin":
			lobby._latejoin_panel.visible = true
		else:
			lobby._main_content.visible = true
	)

func _bind_chat_input(ui_root: Control) -> void:
	lobby._chat_input = ui_root.get_node("ChatInput") as LineEdit
	lobby._chat_input.text_submitted.connect(lobby._on_chat_submitted)

func _populate_class_option(option: OptionButton) -> void:
	if option == null:
		return
	option.clear()
	for cls in CLASS_OPTIONS:
		option.add_item(cls)
