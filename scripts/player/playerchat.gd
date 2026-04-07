# res://scripts/player/playerchat.gd
# Handles chat submission, incoming chat display, and speech bubbles.
extends RefCounted

var player: Node2D

func _init(p_player: Node2D) -> void:
	player = p_player

func on_chat_submitted(text: String) -> void:
	player._chat_input.visible = false
	player._chat_input.clear()
	player._chat_input.release_focus()
	if text.strip_edges() == "": return
	if player.multiplayer.is_server(): World.rpc_send_chat(text)
	else: World.rpc_send_chat.rpc_id(1, text)

func show_remote_chat(sender_name: String, message: String) -> void:
	Sidebar.add_message(sender_name + " says: " + message)
	show_chat_bubble(message)

func show_chat_bubble(text: String) -> void:
	player._active_chat_messages = player._active_chat_messages.filter(func(n): return is_instance_valid(n))
	const STEP: float = 22.0
	for msg in player._active_chat_messages: msg.position.y -= STEP
	var container := Node2D.new()
	container.position = Vector2(0, -40)
	container.z_index  = (player.z_level - 1) * 200 + 100
	player.add_child(container)
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
	player._active_chat_messages.append(container)
	player.get_tree().create_timer(5.0).timeout.connect(func():
		if is_instance_valid(container):
			player._active_chat_messages.erase(container)
			container.queue_free()
	)
