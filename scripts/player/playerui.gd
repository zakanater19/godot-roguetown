# res://scripts/player/playerui.gd
# Builds and manages all local-player UI nodes; exposes update helpers.
extends RefCounted

var player: Node2D

func _init(p_player: Node2D) -> void:
	player = p_player

func build_ui() -> void:
	var cl := CanvasLayer.new()
	cl.layer      = 10
	player._canvas_layer = cl
	player.add_child(cl)

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
	player._ui_root = safe_area

	player._sleep_blackout = ColorRect.new()
	player._sleep_blackout.color = Color(0, 0, 0, 0)
	player._sleep_blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player._sleep_blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe_area.add_child(player._sleep_blackout)

	player._throw_label = Label.new()
	player._throw_label.text = "THROWING"
	player._throw_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.0))
	player._throw_label.add_theme_font_size_override("font_size", 14)
	player._throw_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	player._throw_label.offset_left   = 12
	player._throw_label.offset_top    = -10
	player._throw_label.offset_right  = 120
	player._throw_label.offset_bottom = 10
	player._throw_label.visible       = false
	safe_area.add_child(player._throw_label)

	player._inspect_label = Label.new()
	player._inspect_label.text = "INSPECTING"
	player._inspect_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.0))
	player._inspect_label.add_theme_font_size_override("font_size", 14)
	player._inspect_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	player._inspect_label.offset_left   = 12
	player._inspect_label.offset_top    = 10
	player._inspect_label.offset_right  = 140
	player._inspect_label.offset_bottom = 30
	player._inspect_label.visible       = false
	safe_area.add_child(player._inspect_label)

	player._combat_indicator = Label.new()
	player._combat_indicator.text = "!"
	player._combat_indicator.add_theme_color_override("font_color", Color.RED)
	player._combat_indicator.add_theme_font_size_override("font_size", 24)
	player._combat_indicator.position = Vector2(-4, -60)
	player._combat_indicator.visible  = false
	player.add_child(player._combat_indicator)

	player._dead_container = VBoxContainer.new()
	player._dead_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	player._dead_container.alignment = BoxContainer.ALIGNMENT_CENTER
	player._dead_container.visible   = false
	safe_area.add_child(player._dead_container)

	var you_died_label := Label.new()
	you_died_label.text = "YOU DIED"
	you_died_label.add_theme_color_override("font_color", Color(0.85, 0.0, 0.0))
	you_died_label.add_theme_font_size_override("font_size", 72)
	you_died_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player._dead_container.add_child(you_died_label)

	var respawn_btn := Button.new()
	respawn_btn.text = "Respawn"
	respawn_btn.add_theme_font_size_override("font_size", 24)
	respawn_btn.pressed.connect(player._on_respawn_pressed)
	player._dead_container.add_child(respawn_btn)

	player._chat_input = LineEdit.new()
	player._chat_input.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	player._chat_input.offset_left      = 12
	player._chat_input.offset_top       = -40
	player._chat_input.offset_right     = 312
	player._chat_input.offset_bottom    = -10
	player._chat_input.placeholder_text = "Say something..."
	player._chat_input.visible          = false
	player._chat_input.text_submitted.connect(player._on_chat_submitted)
	safe_area.add_child(player._chat_input)

	player._hud = CanvasLayer.new()
	player._hud.set_script(load("res://scripts/ui/HUD.gd"))
	player.add_child(player._hud)
	player._hud.setup(player)
	player._hud.update_clothing_display(player.equipped, player.equipped_data)
	player._hud.update_combat_display(player.combat_mode)
	player._hud.update_stance_display(player.combat_stance)

	update_hands_ui()

func update_hands_ui() -> void:
	if player._hud != null: player._hud.update_hands_display(player.hands, player.active_hand)

func update_grab_ui() -> void:
	if player._hud != null:
		player._hud.update_grab_display(
			player.grabbed_target != null and is_instance_valid(player.grabbed_target),
			player.grabbed_by     != null and is_instance_valid(player.grabbed_by)
		)
	update_hands_ui()

func show_stats_skills() -> void:
	var lines: Array[String] = []
	lines.append("[color=#aaccff][b]--- Stats ---[/b][/color]")
	for stat_name in player.stats:
		var val = player.stats[stat_name]
		var col = "#aaaaaa"
		if val > 10: col = "#44ff44"
		elif val < 10: col = "#ff4444"
		lines.append("[color=" + col + "]" + stat_name + ": " + str(val) + "[/color]")
	lines.append("")
	lines.append("[color=#aaccff][b]--- Skills ---[/b][/color]")
	for skill_name in player.skills:
		var val = player.skills[skill_name]
		lines.append("[color=#cccccc]" + skill_name + ": " + str(val) + "[/color]")
	if player.prices_shown: lines.append("[color=#ffff44]Special Skill: Prices Shown[/color]")
	for line in lines: Sidebar.add_message(line)
