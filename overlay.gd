@tool
extends Node2D

# Draws grid outlines on top of everything.
# Reads display config from Main (get_parent()); grid dimensions from World.

func _ready() -> void:
	var main: Node2D = get_parent()
	if main and main.get("HIDE_OUTLINES_AT_RUNTIME") and not Engine.is_editor_hint():
		set_process(false)
		hide()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var main: Node2D = get_parent()
	if not main or not main.get("SHOW_OUTLINES"):
		return
		
	if main.get("HIDE_OUTLINES_AT_RUNTIME") and not Engine.is_editor_hint():
		return

	var total_w := float(World.GRID_WIDTH  * World.TILE_SIZE)
	var total_h := float(World.GRID_HEIGHT * World.TILE_SIZE)

	for x in range(World.GRID_WIDTH + 1):
		var xf := float(x * World.TILE_SIZE)
		draw_line(Vector2(xf, 0.0), Vector2(xf, total_h), main.OUTLINE_COLOR, main.OUTLINE_WIDTH)

	for y in range(World.GRID_HEIGHT + 1):
		var yf := float(y * World.TILE_SIZE)
		draw_line(Vector2(0.0, yf), Vector2(total_w, yf), main.OUTLINE_COLOR, main.OUTLINE_WIDTH)