# res://scripts/core/combatant.gd
class_name Combatant
extends Node2D

## Shared state required by the combat system. Concrete combatants can override
## the change hooks to keep visual, movement, or lifecycle side effects local.
@export var z_level: int = 3

var _tile_pos: Vector2i = Vector2i.ZERO
var tile_pos: Vector2i:
	get:
		return _tile_pos
	set(value):
		if _tile_pos == value:
			return
		var previous := _tile_pos
		_tile_pos = value
		_on_tile_pos_changed(previous, value)

var _facing: int = 0
var facing: int:
	get:
		return _facing
	set(value):
		_facing = value
		_on_facing_changed()

var combat_mode: bool = false
var combat_stance: String = "dodge"
var is_possessed: bool = true

var _exhausted: bool = false
var exhausted: bool:
	get:
		return _exhausted
	set(value):
		if _exhausted == value:
			return
		_exhausted = value
		_on_exhausted_changed()

var skills: Dictionary = {"sword_fighting": 0, "blacksmithing": 0, "sneaking": 0}
var stats: Dictionary = {"strength": 10, "agility": 10}
var stamina: float = CombatDefs.STAMINA_MAX
var hands: Array[Node] = [null, null]
var grabbed_by: Node = null

var _dead: bool = false
var dead: bool:
	get:
		return _dead
	set(value):
		_dead = value
		_on_dead_changed()

func _on_tile_pos_changed(_previous: Vector2i, _value: Vector2i) -> void:
	pass

func _on_facing_changed() -> void:
	pass

func _on_exhausted_changed() -> void:
	pass

func _on_dead_changed() -> void:
	pass
