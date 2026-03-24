# res://lighting.gd
# AutoLoad singleton — registered as "Lighting" in project.godot
# Handles the global day/night cycle and testing lights for players.
extends Node

var canvas_mod: CanvasModulate
var current_day: int = 1
var time_offset: float = 0.0
var time_multiplier: float = 1.0
var sun_weight: float = 1.0  # Added for global access

# 20 min day (1200s) + 20 min night (1200s) = 2400s cycle
# Transition is 5 minutes (300s)
const CYCLE_DURATION: float = 2400.0
const TRANSITION_DURATION: float = 300.0

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
	var total_time = Lobby.round_time + time_offset
	current_day = 1 + int(total_time / CYCLE_DURATION)
	
	var cycle_time = fmod(total_time, CYCLE_DURATION)
	
	# Weight determines brightness (1.0 = Day, 0.0 = Night)
	sun_weight = 1.0
	
	# 0 to 900: Full Day (weight 1.0)
	# 900 to 1200: Transition Day -> Night (weight 1.0 down to 0.0)
	# 1200 to 2100: Full Night (weight 0.0)
	# 2100 to 2400: Transition Night -> Day (weight 0.0 up to 1.0)
	
	if cycle_time >= 900.0 and cycle_time < 1200.0:
		sun_weight = 1.0 - ((cycle_time - 900.0) / TRANSITION_DURATION)
	elif cycle_time >= 1200.0 and cycle_time < 2100.0:
		sun_weight = 0.0
	elif cycle_time >= 2100.0:
		sun_weight = (cycle_time - 2100.0) / TRANSITION_DURATION
	else:
		sun_weight = 1.0

	# Apply visual color (Black for total darkness at night)
	var night_color = Color(0.0, 0.0, 0.0, 1.0) 
	canvas_mod.color = night_color.lerp(Color.WHITE, sun_weight)

	# Manage player "sight" lights
	var players = get_tree().get_nodes_in_group("player")
	var local_player = World.get_local_player()
	
	for p in players:
		var light = p.get_node_or_null("PlayerLight")
		
		# If this is the local player, ensure the light exists and is configured
		if p == local_player:
			if light == null:
				light = PointLight2D.new()
				light.name = "PlayerLight"
				light.texture = light_texture
				# Use MIX blend mode so lights don't blow out into pure white when stacked
				light.blend_mode = PointLight2D.BLEND_MODE_MIX
				light.z_index = 15
				p.add_child(light)
			
			light.energy = 0.4 # Halved from 0.8
			light.enabled = (sun_weight < 0.5)
			
		# If this is a remote player, ensure their light is removed
		elif light != null:
			light.queue_free()

# Called by the UI button
func toggle_time_of_day() -> void:
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			rpc_add_time_offset.rpc(1200.0)
		else:
			request_toggle_time.rpc_id(1)
	else:
		time_offset += 1200.0

@rpc("any_peer", "call_local", "reliable")
func request_toggle_time() -> void:
	if multiplayer.is_server():
		rpc_add_time_offset.rpc(1200.0)

@rpc("authority", "call_local", "reliable")
func rpc_add_time_offset(amount: float) -> void:
	time_offset += amount

@rpc("authority", "call_local", "reliable")
func sync_time_multiplier(val: float) -> void:
	time_multiplier = val
	
