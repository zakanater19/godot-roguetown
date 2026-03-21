@tool
extends EditorPlugin

var _panel: Control = null


func _enter_tree() -> void:
	_panel = Control.new()
	_panel.set_script(load("res://addons/pixel_hand_editor/hand_editor_panel.gd"))
	_panel.name = "Hand Editor"
	add_control_to_bottom_panel(_panel, "Hand Editor")


func _exit_tree() -> void:
	if _panel != null:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null
