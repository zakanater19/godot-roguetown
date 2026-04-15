extends Sprite2D

const TILE_SIZE := 64
const W := 33
const H := 23

var _img: Image
var _tex: ImageTexture
var _rgba_data: PackedByteArray

func _ready() -> void:
	z_index = 4000
	centered = false
	scale = Vector2(TILE_SIZE, TILE_SIZE)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(_img)
	texture = _tex
	_rgba_data.resize(W * H * 4)

func update_fov(player_tile: Vector2i, visible_tiles: Dictionary, fov_radius: int) -> void:
	if visible_tiles.is_empty():
		return
		
	# Center view around player
	position = Vector2((player_tile.x - 16) * TILE_SIZE, (player_tile.y - 11) * TILE_SIZE)
	
	# Clear image data (0 alpha = transparent/visible)
	_rgba_data.fill(0)
	
	var r2 = fov_radius * fov_radius

	# Calculate pixel matrix fully on CPU instead of massive GPU draw_rect loop
	for ly in range(H):
		var dy = ly - 11
		for lx in range(W):
			var dx = lx - 16
			var tile = player_tile + Vector2i(dx, dy)
			
			var tile_visible = false
			if dx * dx + dy * dy <= r2 and visible_tiles.has(tile):
				tile_visible = true

			if not tile_visible:
				var idx = (ly * W + lx) * 4
				# Black, fully opaque shadow mask
				_rgba_data[idx]   = 0
				_rgba_data[idx+1] = 0
				_rgba_data[idx+2] = 0
				_rgba_data[idx+3] = 255
				
	_img.set_data(W, H, false, Image.FORMAT_RGBA8, _rgba_data)
	_tex.update(_img)
