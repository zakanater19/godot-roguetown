# res://npcs/spider.gd
extends Node2D

const TILE_SIZE:       int   = 64
const GRID_WIDTH:      int   = 1000
const GRID_HEIGHT:     int   = 1000
const MOVE_TIME:       float = 0.5
const DETECTION_RANGE: int   = 8
const ATTACK_RANGE:    int   = 1
const ATTACK_DAMAGE:   int   = 20
const ATTACK_COOLDOWN: float = 1.0
const MOVE_COOLDOWN:   float = 0.5
const WANDER_INTERVAL: float = 10.0

const BloodSpray = preload("res://npcs/blood_spray.gd")

@export var z_level: int = 3
var blocks_fov: bool = false

var health:       int   = 80
var dead: bool = false :
	set(val):
		dead = val
		if dead:
			# Unregister from solid grid and flip to dead sprite on all peers
			World.unregister_solid(tile_pos, z_level, self)
			var sprite: Sprite2D = get_node_or_null("Sprite2D")
			if sprite != null:
				sprite.region_rect = Rect2(128, 0, 64, 64)
				sprite.flip_v = true

var tile_pos:     Vector2i
var pixel_pos:    Vector2
var moving:       bool  = false
var move_elapsed: float = 0.0
var move_from:    Vector2
var move_to:      Vector2
var facing: int = 0 :
	set(val):
		facing = val
		_update_sprite()
var attack_timer: float = 0.0
var move_timer:   float = 0.0
var wander_timer: float = 0.0

var ai_timer: float = 0.0
var current_target: Node2D = null

func get_description() -> String:
	if dead:
		return "a dead spider, curled up and harmless"
	return "a giant spider! careful!"

func get_inspect_color() -> Color:
	if dead:
		return Color.WHITE
	return Color(1.0, 0.0, 0.0) # Red for danger

func get_inspect_font_size() -> int:
	if dead:
		return 11
	return 14

func _ready() -> void:
	z_index = (z_level - 1) * 200 + z_index
	add_to_group("z_entity")
	
	# Ensure the spider is in the NPC group for targeting
	if not is_in_group("npc"):
		add_to_group("npc")

	var p: Vector2 = position
	tile_pos  = Vector2i(int(p.x / TILE_SIZE), int(p.y / TILE_SIZE))
	pixel_pos = World.tile_to_pixel(tile_pos)
	position  = pixel_pos
	_update_sprite()
	World.register_solid(tile_pos, z_level, self)

@rpc("authority", "call_remote", "reliable")
func rpc_sync_spider_z_level(new_z: int) -> void:
	z_level = new_z
	z_index = (z_level - 1) * 200 + (z_index % 200)

@rpc("call_local", "reliable")
func rpc_spawn_blood(pos: Vector2) -> void:
	var spray := Node2D.new()
	spray.set_script(BloodSpray)
	spray.position = pos
	spray.z_index = (z_level - 1) * 200 + 50
	get_parent().add_child(spray)

func receive_damage(amount: int) -> void:
	if dead:
		return
	rpc_spawn_blood.rpc(global_position)
	health -= amount
	if health <= 0:
		# Setter handles unregister_solid and sprite flip on all peers via StateSync
		dead = true

func _process(delta: float) -> void:
	# Spider AI is server-authoritative only
	if not multiplayer.is_server():
		return

	if dead:
		return

	if attack_timer > 0.0:
		attack_timer -= delta
	if move_timer > 0.0:
		move_timer -= delta

	# Always tick wander timer
	wander_timer += delta

	if moving:
		move_elapsed += delta
		var t: float = clamp(move_elapsed / MOVE_TIME, 0.0, 1.0)
		pixel_pos = move_from.lerp(move_to, t)
		position  = pixel_pos
		if t >= 1.0:
			moving    = false
			pixel_pos = move_to
			position  = pixel_pos
		return

	# OPTIMIZATION: Target acquisition throttled to 4 times a second
	ai_timer -= delta
	if ai_timer <= 0.0:
		ai_timer = 0.25
		_find_target()

	if current_target != null and is_instance_valid(current_target) and not current_target.dead and current_target.z_level == z_level:
		var diff:  Vector2i = current_target.tile_pos - tile_pos
		var cheby: int      = max(abs(diff.x), abs(diff.y))

		if cheby <= DETECTION_RANGE:
			# Reset wander timer so we don't instantly wander after losing aggro
			wander_timer = 0.0

			if cheby <= ATTACK_RANGE:
				if attack_timer <= 0.0:
					_attack_player(current_target)
			elif move_timer <= 0.0:
				_move_toward_player(current_target)
		else:
			# Lost aggro
			current_target = null
			if wander_timer >= WANDER_INTERVAL:
				_wander()
	else:
		current_target = null
		if wander_timer >= WANDER_INTERVAL:
			_wander()

func _find_target() -> void:
	var players = get_tree().get_nodes_in_group("player")
	var min_dist = INF
	current_target = null

	for p in players:
		if p.dead or p.z_level != z_level: continue
		var d = (p.tile_pos - tile_pos).length_squared()
		if d < min_dist:
			min_dist = d
			current_target = p

func _attack_player(player: Node) -> void:
	attack_timer = ATTACK_COOLDOWN
	
	var roll = World._calculate_combat_roll(self, player, ATTACK_DAMAGE, false)
	
	if roll.damage > 0:
		if player.has_method("receive_damage"):
			player.receive_damage.rpc(roll.damage)
	elif roll.blocked:
		if player.has_method("rpc_consume_stamina"):
			var tgt_peer = player.get_multiplayer_authority()
			if tgt_peer == 1 or tgt_peer in multiplayer.get_peers():
				player.rpc_consume_stamina.rpc_id(tgt_peer, 3.0)
		if roll.block_type == "dodged" and roll.has("dodge_tile"):
			player.tile_pos = roll.dodge_tile
			World.rpc_confirm_move.rpc(player.get_multiplayer_authority(), roll.dodge_tile, false)
			
	var target_name: String = player.character_name
	World.rpc_broadcast_damage_log.rpc("Spider", target_name, roll.damage, tile_pos, z_level, roll.blocked, false, "", roll.get("block_type", ""))

func _move_toward_player(player: Node) -> void:
	var path: Array[Vector2i] = World.find_path(tile_pos, player.tile_pos, z_level)

	if path.size() > 0:
		var next_tile := path[0]
		var dir := next_tile - tile_pos
		_try_move(dir)

func _wander() -> void:
	var dirs =[Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var dir = dirs.pick_random()
	_try_move(dir)
	# Reset timer regardless of whether move succeeded, to keep interval consistent
	wander_timer = 0.0

func _try_move(dir: Vector2i) -> void:
	if   dir.y > 0: facing = 0
	elif dir.y < 0: facing = 1
	elif dir.x > 0: facing = 2
	elif dir.x < 0: facing = 3

	var next: Vector2i = tile_pos + dir

	# Bounds check
	if next.x < 0 or next.x >= GRID_WIDTH or next.y < 0 or next.y >= GRID_HEIGHT:
		return

	# Solid check
	if World.is_solid(next, z_level):
		return

	# Don't walk onto any player (unless they are dead)
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if next == p.tile_pos and not p.dead and p.z_level == z_level:
			return

	# Execute move
	World.unregister_solid(tile_pos, z_level, self)
	tile_pos     = next
	
	var land_z = World.calculate_gravity_z(tile_pos, z_level)
	if land_z < z_level:
		var drop = z_level - land_z
		z_level = land_z
		z_index = (z_level - 1) * 200 + (z_index % 200)
		rpc_sync_spider_z_level.rpc(land_z)
		
		var dmg = randi_range(20, 30) * drop
		receive_damage(dmg)
		
	World.register_solid(tile_pos, z_level, self)

	move_from    = pixel_pos
	move_to      = World.tile_to_pixel(tile_pos)
	move_elapsed = 0.0
	moving       = true
	move_timer   = MOVE_TIME

func _update_sprite() -> void:
	var sprite: Sprite2D = get_node_or_null("Sprite2D")
	if sprite == null:
		return
	sprite.region_rect = Rect2(facing * 64, 0, 64, 64)