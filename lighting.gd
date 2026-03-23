# res://lighting.gd
# AutoLoad singleton — registered as "Lighting" in project.godot
# Handles the global day/night cycle and testing lights for players.
extends Node

var canvas_mod: CanvasModulate
var is_midnight: bool = false
var current_day: int = 1
var time_offset: float = 0.0

var light_texture: GradientTexture2D

func _ready() -> void:
	# 1. Create the global day/night modulator
	canvas_mod = CanvasModulate.new()
	canvas_mod.color = Color.WHITE
	add_child(canvas_mod)

	# 2. Programmatically generate a soft radial gradient for the player lights
	var grad = Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 0.7)) # Bright center
	grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0)) # Transparent edge
	
	light_texture = GradientTexture2D.new()
	light_texture.gradient = grad
	light_texture.fill = GradientTexture2D.FILL_RADIAL
	light_texture.fill_from = Vector2(0.5, 0.5)
	light_texture.fill_to = Vector2(1.0, 0.5)
	
	# 3 tiles radius = 6 tiles diameter (6 * 64 = 384 pixels)
	light_texture.width = 384
	light_texture.height = 384

func _process(_delta: float) -> void:
	# Calculate current time in the cycle.
	# Day = 30 mins (1800s), Night = 30 mins (1800s). Full cycle = 3600s.
	var total_time = Lobby.round_time + time_offset
	current_day = 1 + int(total_time / 3600.0)
	
	# If the current 1800s block is odd, it's night time
	is_midnight = (int(total_time / 1800.0) % 2 != 0)
	
	if is_midnight:
		# Dark blueish-gray tint for midnight
		canvas_mod.color = Color(0.1, 0.1, 0.15, 1.0)
	else:
		# Pure white for midday
		canvas_mod.color = Color.WHITE

	# Continually ensure all players have a weak test light attached
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		var light = p.get_node_or_null("PlayerLight")
		if light == null:
			light = PointLight2D.new()
			light.name = "PlayerLight"
			light.texture = light_texture
			# Use MIX blend mode so lights don't blow out into pure white when stacked
			light.blend_mode = PointLight2D.BLEND_MODE_MIX
			light.energy = 0.8
			light.z_index = 15 # Render above most player sprites
			p.add_child(light)
			
		# Hide the player light during the day
		light.enabled = is_midnight

# Called by the UI button
func toggle_time_of_day() -> void:
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			rpc_add_time_offset.rpc(1800.0)
		else:
			request_toggle_time.rpc_id(1)
	else:
		time_offset += 1800.0

@rpc("any_peer", "call_local", "reliable")
func request_toggle_time() -> void:
	if multiplayer.is_server():
		rpc_add_time_offset.rpc(1800.0)

@rpc("authority", "call_local", "reliable")
func rpc_add_time_offset(amount: float) -> void:
	time_offset += amount
	
