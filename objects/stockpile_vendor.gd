@tool
class_name StockpileVendor
extends WorldObject

const FEED_FRAME: Rect2 = Rect2(32, 0, 32, 32)
const IDLE_FRAME: Rect2 = Rect2(0, 0, 32, 32)
const SPRITE_OFFSET: Vector2 = Vector2(0, -40)
const SPRITE_SCALE: Vector2 = Vector2(2, 2)
const HITBOX_SIZE: Vector2 = Vector2(64, 64)

@export var catalog: StockpileCatalog

var blocks_fov: bool = false
var is_stockpile_vendor: bool = true
var _is_editor_snapping: bool = false

func _ready() -> void:
	set_notify_transform(true)
	super._ready()
	_sync_presentation()
	if Engine.is_editor_hint():
		call_deferred("_snap_to_editor_tile")

func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		call_deferred("_snap_to_editor_tile")

func get_description() -> String:
	return "a stockpile vendor"

func accepts_item(item_type: String) -> bool:
	return catalog != null and catalog.accepts(item_type)

func get_payout(item_type: String) -> int:
	return catalog.get_payout(item_type) if catalog != null else 0

func get_item_label(item_type: String) -> String:
	return catalog.get_item_name(item_type) if catalog != null else item_type

func get_z_offset() -> int:
	return 5

func should_snap_to_tile() -> bool:
	return true

func should_register_entity() -> bool:
	return true

func get_runtime_groups() -> Array[String]:
	return [Defs.GROUP_INSPECTABLE]

func get_solid_tile_offsets() -> Array[Vector2i]:
	return [Vector2i.ZERO]

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if Engine.is_editor_hint():
		return
	if event is not InputEventMouseButton:
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	if Input.is_key_pressed(KEY_SHIFT):
		return

	var player: Node = World.get_local_player()
	if player == null or player.z_level != z_level:
		return
	if not Defs.is_within_tile_reach(player.tile_pos, get_anchor_tile()):
		return
	if not Defs.is_valid_hand_index(player.active_hand):
		return

	var held_item: Node = player.hands[player.active_hand]
	if held_item == null or not is_instance_valid(held_item):
		return
	if player.body != null and player.body.is_arm_broken(player.active_hand):
		player._show_inspect_text("that arm is useless", "")
		return
	if not accepts_item(str(held_item.get("item_type"))):
		player._show_inspect_text("the stockpile vendor doesn't accept that", "")
		return

	get_viewport().set_input_as_handled()
	var vendor_id := World.get_entity_id(self)
	World.rpc_request_stockpile_vendor_sale.rpc_id(1, vendor_id, player.active_hand)

func _play_feed_animation() -> void:
	if Engine.is_editor_hint():
		return
	_set_sprite_frame(FEED_FRAME)
	var timer := get_node_or_null("FeedTimer") as Timer
	if timer != null:
		timer.start()

func _on_feed_timer_timeout() -> void:
	_set_sprite_frame(IDLE_FRAME)

func _sync_presentation() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.region_enabled = true
	sprite.position = SPRITE_OFFSET
	sprite.scale = SPRITE_SCALE
	_set_sprite_frame(IDLE_FRAME)

	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision != null:
		collision.position = SPRITE_OFFSET
		var rect := collision.shape as RectangleShape2D
		if rect != null:
			rect.size = HITBOX_SIZE

func _set_sprite_frame(frame: Rect2) -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.region_rect = frame

func _snap_to_editor_tile() -> void:
	if not Engine.is_editor_hint() or _is_editor_snapping:
		return
	var snapped_position := Defs.tile_to_pixel(Defs.world_to_tile(global_position))
	if global_position.is_equal_approx(snapped_position):
		return
	_is_editor_snapping = true
	global_position = snapped_position
	_is_editor_snapping = false
