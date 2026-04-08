class_name MaterialData
extends Resource

## Unique key used by MaterialRegistry (e.g. "wood", "stone", "coarse_rock").
@export var material_id: String = ""

## Human-readable label for inspectors/debugging.
@export var display_name: String = ""

## Maps Defs.TOOL_* values to per-hit progress against this material.
## Missing tools default to 0.0, meaning they cannot meaningfully damage it.
@export var tool_efficiencies: Dictionary = {}

func get_efficiency(tool_type: String) -> float:
	if tool_type == "":
		return 0.0
	var value: Variant = tool_efficiencies.get(tool_type, 0.0)
	if value is int or value is float:
		return maxf(float(value), 0.0)
	return 0.0
