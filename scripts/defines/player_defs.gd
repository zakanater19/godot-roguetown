class_name PlayerDefs

const MOVE_TIME: float = 0.22
const THROW_TILES: int = 4
const THROW_DURATION: float = 0.18
const SPRINT_STAMINA_COST: float = 3.0
const DRAG_THRESHOLD: float = 10.0

const CAMERA_VIEW_TILES: Vector2i = Vector2i(17, 13)
const CAMERA_ZOOM: float = 720.0 / (CAMERA_VIEW_TILES.y * Defs.TILE_SIZE)
const CAMERA_VIEW_SIZE: Vector2 = Vector2(CAMERA_VIEW_TILES) * Defs.TILE_SIZE * CAMERA_ZOOM
const CAMERA_VIEW_ANCHOR: Vector2 = CAMERA_VIEW_SIZE * 0.5
const DEFAULT_HEALTH: int = 100

const BLOOD_DRIP_STATES: Array[Dictionary] = [
	{"health_at_or_below": 30, "period": 2.0, "count": 9, "z_offset": 50},
	{"health_at_or_below": 40, "period": 5.0, "count": 6, "z_offset": 50},
	{"health_at_or_below": 60, "period": 10.0, "count": 3, "z_offset": 50},
]

static func get_camera_offset(viewport_size: Vector2) -> Vector2:
	return Vector2(
		(viewport_size.x / 2.0) - CAMERA_VIEW_ANCHOR.x,
		(viewport_size.y / 2.0) - CAMERA_VIEW_ANCHOR.y
	) / CAMERA_ZOOM
