# res://scripts/net/lobby_ui.gd
# Instantiates the Lobby UI scene and assigns the relevant controls back to the lobby node.
extends RefCounted

const LOBBY_UI_SCENE_PATH := "res://scenes/ui/lobby_ui.tscn"
const CLASS_OPTIONS: Array[String] = ["peasant", "merchant", "bandit", "adventurer", "king"]

var lobby: Node

func _init(lobby_node: Node) -> void:
	lobby = lobby_node

func build(bg: Control) -> void:
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
	_constrain_lobby_to_play_area(ui_root)

	_bind_main_controls(ui_root)
	_bind_latejoin_panel(ui_root)
	_bind_subclass_panel(ui_root)
	_bind_chat_input(ui_root)
	_bind_host_dashboard(ui_root)
	_bind_character_creator(ui_root)

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

func _bind_host_dashboard(ui_root: Control) -> void:
	lobby._host_dashboard = ui_root.get_node("HostDashboard") as Control
	lobby._host_dashboard.offset_right = PlayerDefs.CAMERA_VIEW_SIZE.x
	lobby._host_server_label = ui_root.get_node("HostDashboard/Content/StatsPanel/Margin/Stats/ServerLabel") as Label
	lobby._host_phase_label = ui_root.get_node("HostDashboard/Content/StatsPanel/Margin/Stats/PhaseLabel") as Label
	lobby._host_time_label = ui_root.get_node("HostDashboard/Content/StatsPanel/Margin/Stats/TimeLabel") as Label
	lobby._host_player_stats_label = ui_root.get_node("HostDashboard/Content/StatsPanel/Margin/Stats/PlayerStatsLabel") as Label
	lobby._host_count_label = ui_root.get_node("HostDashboard/Content/PlayersPanel/Margin/Players/CountLabel") as Label
	lobby._host_player_list = ui_root.get_node("HostDashboard/Content/PlayersPanel/Margin/Players/PlayerScroll/PlayerList") as VBoxContainer
	lobby._host_force_btn = ui_root.get_node("HostDashboard/Content/StatsPanel/Margin/Stats/ForceStartButton") as Button
	lobby._host_restart_btn = ui_root.get_node("HostDashboard/Content/StatsPanel/Margin/Stats/RestartRoundButton") as Button
	lobby._host_force_btn.pressed.connect(lobby._on_force_pressed)
	lobby._host_restart_btn.pressed.connect(lobby._on_restart_round_pressed)

func _bind_character_creator(ui_root: Control) -> void:
	lobby._character_creator = CharacterCreator.new()
	lobby._character_creator.constrain_to_content_width(PlayerDefs.CAMERA_VIEW_SIZE.x)
	ui_root.add_child(lobby._character_creator)
	lobby._character_creator.character_saved.connect(lobby._on_character_saved)
	var main_button := ui_root.get_node("MainContent/CharacterButton") as Button
	var latejoin_button := ui_root.get_node("LatejoinPanel/Content/CharacterButton") as Button
	main_button.pressed.connect(lobby._open_character_creator)
	latejoin_button.pressed.connect(lobby._open_character_creator)

func _constrain_lobby_to_play_area(ui_root: Control) -> void:
	var play_width := PlayerDefs.CAMERA_VIEW_SIZE.x
	var main_content := ui_root.get_node("MainContent") as Control
	main_content.anchor_left = 0.0
	main_content.anchor_right = 0.0
	main_content.offset_left = 0.0
	main_content.offset_right = play_width

	_center_panel_in_play_area(ui_root.get_node("LatejoinPanel") as Control, play_width)
	_center_panel_in_play_area(ui_root.get_node("SubclassPanel") as Control, play_width)

func _center_panel_in_play_area(panel: Control, play_width: float) -> void:
	var panel_width := panel.offset_right - panel.offset_left
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.offset_left = (play_width - panel_width) * 0.5
	panel.offset_right = panel.offset_left + panel_width

func _populate_class_option(option: OptionButton) -> void:
	if option == null:
		return
	option.clear()
	for cls in CLASS_OPTIONS:
		option.add_item(cls)
