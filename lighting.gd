# res://lighting.gd
# AutoLoad singleton — registered as "Lighting" in project.godot
# Handles the global day/night cycle and testing lights for players.
extends Node

signal sun_weight_updated(weight: float)

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

# Throttle: only run the full update 4 times per second.
# The day/night cycle is 2400 s — 0.25 s resolution is imperceptibly smooth.
var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.25

# Track previous sun_weight to skip canvas / signal updates when nothing changed.
var _last_sun_weight: float = -1.0

# Track the current night state so PlayerLight is only touched when the
# threshold (sun_weight < 0.5) actually flips, not every frame.
var _player_light_night: bool = false

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

func _process(delta: float) -> void:
	# Throttle: only do work every UPDATE_INTERVAL seconds.
	_update_timer += delta
	if _update_timer < UPDATE_INTERVAL:
		return
	_update_timer = 0.0

	var total_time = Lobby.round_time + time_offset
	current_day = 1 + int(total_time / CYCLE_DURATION)
	
	var cycle_time = fmod(total_time, CYCLE_DURATION)
	
	# Weight determines brightness (1.0 = Day, 0.0 = Night)
	# 0 to 900: Full Day (weight 1.0)
	# 900 to 1200: Transition Day -> Night (weight 1.0 down to 0.0)
	# 1200 to 2100: Full Night (weight 0.0)
	# 2100 to 2400: Transition Night -> Day (weight 0.0 up to 1.0)
	var new_sun_weight: float = 1.0
	if cycle_time >= 900.0 and cycle_time < 1200.0:
		new_sun_weight = 1.0 - ((cycle_time - 900.0) / TRANSITION_DURATION)
	elif cycle_time >= 1200.0 and cycle_time < 2100.0:
		new_sun_weight = 0.0
	elif cycle_time >= 2100.0:
		new_sun_weight = (cycle_time - 2100.0) / TRANSITION_DURATION

	# Only update visuals and emit signal when sun_weight has changed meaningfully.
	# At 0.25 s intervals the transition advances ~0.00083 per tick, so 0.0005
	# ensures we never miss a visible step while skipping redundant full-day frames.
	if abs(new_sun_weight - _last_sun_weight) > 0.0005:
		sun_weight = new_sun_weight
		_last_sun_weight = new_sun_weight

		# Apply visual color (Black for total darkness at night)
		var night_color = Color(0.0, 0.0, 0.0, 1.0)
		canvas_mod.color = night_color.lerp(Color.WHITE, sun_weight)

		# Notify subscribers (lamps, etc.) — avoids per-frame polling in each object.
		sun_weight_updated.emit(sun_weight)

	# Manage the local player's sight light.
	# Only call _update_player_light when the day/night threshold actually flips.
	var should_be_night: bool = (sun_weight < 0.5)
	if should_be_night != _player_light_night:
		_player_light_night = should_be_night
		_update_player_light()

func _update_player_light() -> void:
	var local_player = World.get_local_player()
	if local_player == null:
		return

	var light = local_player.get_node_or_null("PlayerLight")

	# Ensure the light exists and is configured
	if light == null:
		light = PointLight2D.new()
		light.name = "PlayerLight"
		light.texture = light_texture
		# Use MIX blend mode so lights don't blow out into pure white when stacked
		light.blend_mode = PointLight2D.BLEND_MODE_MIX
		light.z_index = 15
		light.range_z_min = -4096
		light.range_z_max = 4096
		light.energy = 0.4
		local_player.add_child(light)

	light.enabled = _player_light_night

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