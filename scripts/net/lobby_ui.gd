# res://scripts/net/lobby_ui.gd
# Builds all UI nodes for the Lobby and assigns them back to the lobby node.
extends RefCounted

var lobby: Node

func _init(lobby_node: Node) -> void:
	lobby = lobby_node

func build(bg: ColorRect, main_content: Control) -> void:
	_build_main_controls(main_content)
	_build_latejoin_panel(bg)
	_build_subclass_panel(bg)
	_build_chat_input(bg)

func _build_main_controls(parent: Control) -> void:
	var title = Label.new()
	title.text = "LOBBY"
	title.add_theme_font_size_override("font_size", 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 100
	parent.add_child(title)

	lobby._time_label = Label.new()
	lobby._time_label.text = "300s"
	lobby._time_label.add_theme_font_size_override("font_size", 48)
	lobby._time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby._time_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	lobby._time_label.offset_top = 200
	parent.add_child(lobby._time_label)

	lobby._name_input = LineEdit.new()
	lobby._name_input.text = "noob"
	lobby._name_input.placeholder_text = "Character Name"
	lobby._name_input.add_theme_font_size_override("font_size", 24)
	lobby._name_input.custom_minimum_size = Vector2(250, 60)
	lobby._name_input.set_anchors_preset(Control.PRESET_CENTER)
	lobby._name_input.position = Vector2(-125, -90)
	parent.add_child(lobby._name_input)

	lobby._class_option = OptionButton.new()
	for cls in ["peasant", "merchant", "bandit", "adventurer", "king"]:
		lobby._class_option.add_item(cls)
	lobby._class_option.add_theme_font_size_override("font_size", 24)
	lobby._class_option.custom_minimum_size = Vector2(250, 60)
	lobby._class_option.set_anchors_preset(Control.PRESET_CENTER)
	lobby._class_option.position = Vector2(-125, -20)
	parent.add_child(lobby._class_option)

	lobby._ready_btn = Button.new()
	lobby._ready_btn.text = "Unready"
	lobby._ready_btn.add_theme_font_size_override("font_size", 24)
	lobby._ready_btn.custom_minimum_size = Vector2(250, 60)
	lobby._ready_btn.set_anchors_preset(Control.PRESET_CENTER)
	lobby._ready_btn.position = Vector2(-125, 50)
	lobby._ready_btn.pressed.connect(lobby._on_ready_pressed)
	parent.add_child(lobby._ready_btn)

	lobby._force_btn = Button.new()
	lobby._force_btn.text = "Force Start"
	lobby._force_btn.add_theme_font_size_override("font_size", 24)
	lobby._force_btn.custom_minimum_size = Vector2(250, 60)
	lobby._force_btn.set_anchors_preset(Control.PRESET_CENTER)
	lobby._force_btn.position = Vector2(-125, 120)
	lobby._force_btn.pressed.connect(lobby._on_force_pressed)
	parent.add_child(lobby._force_btn)
	lobby._force_btn.visible = false

func _build_latejoin_panel(bg: ColorRect) -> void:
	lobby._latejoin_panel = Panel.new()
	lobby._latejoin_panel.custom_minimum_size = Vector2(400, 300)
	lobby._latejoin_panel.set_anchors_preset(Control.PRESET_CENTER)
	lobby._latejoin_panel.position = Vector2(-200, -150)
	lobby._latejoin_panel.visible  = false
	bg.add_child(lobby._latejoin_panel)

	var lj_vbox = VBoxContainer.new()
	lj_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lj_vbox.offset_left   = 20
	lj_vbox.offset_right  = -20
	lj_vbox.offset_top    = 20
	lj_vbox.offset_bottom = -20
	lj_vbox.add_theme_constant_override("separation", 20)
	lobby._latejoin_panel.add_child(lj_vbox)

	var lj_title = Label.new()
	lj_title.text = "Latejoin Configuration"
	lj_title.add_theme_font_size_override("font_size", 24)
	lj_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lj_vbox.add_child(lj_title)

	lobby._lj_name_input = LineEdit.new()
	lobby._lj_name_input.text = "noob"
	lobby._lj_name_input.placeholder_text = "Character Name"
	lobby._lj_name_input.add_theme_font_size_override("font_size", 20)
	lj_vbox.add_child(lobby._lj_name_input)

	lobby._lj_class_option = OptionButton.new()
	for cls in ["peasant", "merchant", "bandit", "adventurer", "king"]:
		lobby._lj_class_option.add_item(cls)
	lobby._lj_class_option.add_theme_font_size_override("font_size", 20)
	lj_vbox.add_child(lobby._lj_class_option)

	var lj_confirm_btn = Button.new()
	lj_confirm_btn.text = "Spawn"
	lj_confirm_btn.add_theme_font_size_override("font_size", 24)
	lj_confirm_btn.pressed.connect(lobby._on_confirm_latejoin_pressed)
	lj_vbox.add_child(lj_confirm_btn)

	var lj_back_btn = Button.new()
	lj_back_btn.text = "Back"
	lj_back_btn.add_theme_font_size_override("font_size", 24)
	lj_back_btn.pressed.connect(func():
		lobby._latejoin_panel.visible = false
		lobby._main_content.visible   = true
	)
	lj_vbox.add_child(lj_back_btn)

func _build_subclass_panel(bg: ColorRect) -> void:
	lobby._subclass_panel = Panel.new()
	lobby._subclass_panel.custom_minimum_size = Vector2(300, 240)
	lobby._subclass_panel.set_anchors_preset(Control.PRESET_CENTER)
	lobby._subclass_panel.position = Vector2(-150, -120)
	lobby._subclass_panel.visible  = false
	bg.add_child(lobby._subclass_panel)

	var sub_vbox = VBoxContainer.new()
	sub_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	sub_vbox.add_theme_constant_override("separation", 15)
	lobby._subclass_panel.add_child(sub_vbox)

	var sub_title_lbl = Label.new()
	sub_title_lbl.text = "Choose Subclass:"
	sub_title_lbl.add_theme_font_size_override("font_size", 24)
	sub_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_vbox.add_child(sub_title_lbl)

	var btn_swordsman = Button.new()
	btn_swordsman.text = "Swordsman"
	btn_swordsman.add_theme_font_size_override("font_size", 18)
	btn_swordsman.custom_minimum_size       = Vector2(200, 40)
	btn_swordsman.size_flags_horizontal     = Control.SIZE_SHRINK_CENTER
	btn_swordsman.pressed.connect(func(): lobby._on_subclass_chosen("swordsman"))
	sub_vbox.add_child(btn_swordsman)

	var btn_miner = Button.new()
	btn_miner.text = "Miner"
	btn_miner.add_theme_font_size_override("font_size", 18)
	btn_miner.custom_minimum_size       = Vector2(200, 40)
	btn_miner.size_flags_horizontal     = Control.SIZE_SHRINK_CENTER
	btn_miner.pressed.connect(func(): lobby._on_subclass_chosen("miner"))
	sub_vbox.add_child(btn_miner)

	var btn_cancel = Button.new()
	btn_cancel.text = "Back"
	btn_cancel.add_theme_font_size_override("font_size", 16)
	btn_cancel.custom_minimum_size       = Vector2(200, 30)
	btn_cancel.size_flags_horizontal     = Control.SIZE_SHRINK_CENTER
	btn_cancel.pressed.connect(func():
		lobby._subclass_panel.visible = false
		if lobby._pending_action == "latejoin":
			lobby._latejoin_panel.visible = true
		else:
			lobby._main_content.visible = true
	)
	sub_vbox.add_child(btn_cancel)

func _build_chat_input(bg: ColorRect) -> void:
	lobby._chat_input = LineEdit.new()
	lobby._chat_input.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	lobby._chat_input.offset_left   = 20
	lobby._chat_input.offset_top    = -60
	lobby._chat_input.offset_right  = 420
	lobby._chat_input.offset_bottom = -20
	lobby._chat_input.placeholder_text = "Lobby chat... (Press Escape to cancel)"
	lobby._chat_input.add_theme_font_size_override("font_size", 20)
	lobby._chat_input.visible = false
	lobby._chat_input.text_submitted.connect(lobby._on_chat_submitted)
	bg.add_child(lobby._chat_input)
