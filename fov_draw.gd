extends Node2D

const TILE_SIZE := 64
const DARK := Color(0.0, 0.0, 0.0, 1.0)

func _draw() -> void:
	if FOV._visible_tiles.is_empty():
		return

	var player_tile: Vector2i = FOV._player_tile
	var vp_size: Vector2 = get_viewport_rect().size

	# Tiles visible on screen + 2-tile overdraw buffer
	var half_w: int = int(ceil(vp_size.x / (2.0 * TILE_SIZE))) + 2
	var half_h: int = int(ceil(vp_size.y / (2.0 * TILE_SIZE))) + 2

	var r2: int = FOV.FOV_RADIUS * FOV.FOV_RADIUS

	for dy in range(-half_h, half_h + 1):
		for dx in range(-half_w, half_w + 1):
			var tile := player_tile + Vector2i(dx, dy)

			# Within radius and has LOS → leave clear
			if dx * dx + dy * dy <= r2 and FOV._visible_tiles.has(tile):
				continue

			# Outside radius or blocked → black
			var world_pos := Vector2(tile.x * TILE_SIZE, tile.y * TILE_SIZE)
			draw_rect(Rect2(world_pos, Vector2(TILE_SIZE, TILE_SIZE)), DARK)
