@tool
class_name BreakableWorldObject
extends WorldObject

var hits: float = 0.0

func set_hits(val: float) -> void:
	hits = val

func perform_hit(main_node: Node) -> void:
	shake(main_node)
