# res://npcs/blood_spray.gd
extends Node2D

@export var count: int = 40 
@export var is_drip: bool = false

func _ready() -> void:
	# Blood particles are purely visual and handled by Tweens
	set_process(false)
	
	# Ensure the spray is drawn above players and floor tiles
	z_index = 50
	
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for i in count:
		var dot := Polygon2D.new()
		
		# s = 0.8 to 1.2 creates particles between 1.6 and 2.4 pixels in size
		var s := rng.randf_range(0.8, 1.2)
		dot.polygon = PackedVector2Array([
			Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s)
		])
		
		# Randomize color between deep maroon and bright arterial red
		var r := rng.randf_range(0.6, 1.0)
		var g := rng.randf_range(0.0, 0.1)
		dot.color = Color(r, g, 0.0, 1.0)
		
		add_child(dot)

		var tween := create_tween()
		tween.set_parallel(true)

		if is_drip:
			# --- DRIP BEHAVIOR ---
			# Start slightly higher (torso area) with very tight horizontal jitter
			dot.position = Vector2(rng.randf_range(-4.0, 4.0), rng.randf_range(-10.0, -2.0))
			
			var formation_time := rng.randf_range(0.1, 0.2)
			var fall_duration := rng.randf_range(0.4, 0.6)
			var fall_dist := rng.randf_range(15.0, 25.0)
			
			# Sequence: Form/Pause then fall
			var seq = create_tween()
			# Brief "clinging" phase
			seq.tween_property(dot, "position:x", dot.position.x + rng.randf_range(-1, 1), formation_time)
			# Gravity phase
			seq.tween_property(dot, "position:y", dot.position.y + fall_dist, fall_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			
			# Fade out during the fall
			tween.tween_property(dot, "color:a", 0.0, formation_time + fall_duration)
		else:
			# --- SPRAY BEHAVIOR (Standard Hit) ---
			var angle  := rng.randf_range(0.0, TAU)
			# Only use wide spray distance if this isn't a small drip
			var max_dist = 28.0 if count > 10 else 6.0
			var target_dist := rng.randf_range(8.0, max_dist)
			var target := Vector2(cos(angle), sin(angle)) * target_dist
			var duration := rng.randf_range(0.2, 0.45)

			tween.tween_property(dot, "position", target, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(dot, "color", Color(dot.color.r, dot.color.g, dot.color.b, 0.0), duration)

	# Clean up the node once all tweens have finished
	get_tree().create_timer(1.0 if is_drip else 0.5).timeout.connect(queue_free)
	