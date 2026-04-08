# res://scripts/defines/tile_defs.gd
# Authoritative tile definition table.
# All per-tile properties live here: opacity, break behaviour, material tags, descriptions.
#
# Usage:
#   TileDefs.get_def(source_id, atlas_coords)              → Dictionary (empty if unknown)
#   TileDefs.is_opaque(source_id, atlas_coords)            → bool
#   TileDefs.get_description(source_id, atlas_coords)      → String
#   TileDefs.get_material_id(source_id, atlas_coords)      → String
class_name TileDefs

# ---------------------------------------------------------------------------
# Break result types
# ---------------------------------------------------------------------------
const BREAK_DEBRIS  = "debris"   # places a floor tile AND spawns a debris scene
const BREAK_REPLACE = "replace"  # places a floor tile only

# ---------------------------------------------------------------------------
# Tile definitions
#
# DEFS[source_id][atlas_coords] = {
#   "opaque"            : bool     — blocks FOV and light
#   "description"       : String   — player-visible inspect text
#   --- breakable walls only ---
#   "break_hits"        : int      — hits required to break
#   "break_type"        : String   — BREAK_DEBRIS or BREAK_REPLACE
#   "break_floor"       : Vector2i — floor tile (source_id 0) placed after breaking
#   "break_debris"      : String   — scene path for debris object (BREAK_DEBRIS only)
#   "material_id"       : String   — MaterialRegistry key that governs tool efficiency
# }
#
# Solidity for source_id 1 is always implicit — all walls block movement.
# Floors (source_id 0) are never solid by tile alone.
# ---------------------------------------------------------------------------
const DEFS: Dictionary = {
	# -------------------------------------------------------------------------
	# Source 0 — Floor tiles
	# -------------------------------------------------------------------------
	0: {
		Vector2i(0, 0): { "opaque": false, "description": "short tangled grass, wild and unkempt" },
		Vector2i(1, 0): { "opaque": false, "description": "rough cobble, jagged worn stones" },
		Vector2i(2, 0): { "opaque": false, "description": "rough dirt, uneven and loose" },
		Vector2i(4, 0): { "opaque": false, "description": "worn wooden planks, creaking underfoot" },
		Vector2i(5, 0): { "opaque": false, "description": "cobblestone floor, rough and uneven" },
		Vector2i(8, 0): { "opaque": false, "description": "greenblocks, a green patterned floor" },
		Vector2i(9, 0): { "opaque": false, "description": "loose rock, scattered debris on the floor" },
	},
	# -------------------------------------------------------------------------
	# Source 1 — Wall tiles (all implicitly solid)
	# -------------------------------------------------------------------------
	1: {
		Vector2i(3, 0): {
			"opaque"            : true,
			"description"       : "a rock wall, solid and immovable",
			"break_hits"        : 3,
			"break_type"        : "debris",
			"break_floor"       : Vector2i(9, 0),
			"break_debris"      : "res://objects/rock.tscn",
			"material_id"       : "coarse_rock",
		},
		Vector2i(6, 0): {
			"opaque"            : true,
			"description"       : "a stone wall, solid but workable",
			"break_hits"        : 10,
			"break_type"        : "replace",
			"break_floor"       : Vector2i(5, 0),
			"material_id"       : "stone",
		},
		Vector2i(7, 0): {
			"opaque"            : true,
			"description"       : "a wooden wall, solid and sturdy",
			"break_hits"        : 5,
			"break_type"        : "replace",
			"break_floor"       : Vector2i(4, 0),
			"material_id"       : "wood",
		},
		Vector2i(10, 0): {
			"opaque"            : false,   # solid but transparent — light and FOV pass through
			"description"       : "a wooden window, solid but lets light through",
			"break_hits"        : 5,
			"break_type"        : "replace",
			"break_floor"       : Vector2i(4, 0),
			"material_id"       : "wood",
		},
	},
	# -------------------------------------------------------------------------
	# Source 2 — Stairs (4 orientations share one description)
	# -------------------------------------------------------------------------
	2: {
		"_default": { "opaque": false, "description": "a set of stairs" },
	},
	# -------------------------------------------------------------------------
	# Source 5 — Water
	# -------------------------------------------------------------------------
	5: {
		"_default": { "opaque": false, "description": "water, murky and still" },
	},
}

# ---------------------------------------------------------------------------
# Lookup helpers
# ---------------------------------------------------------------------------

## Returns the def dict for (source_id, atlas_coords). Empty dict if unknown.
static func get_def(source_id: int, atlas_coords: Vector2i) -> Dictionary:
	if not DEFS.has(source_id):
		return {}
	var src: Dictionary = DEFS[source_id]
	if src.has(atlas_coords):
		return src[atlas_coords]
	if src.has("_default"):
		return src["_default"]
	return {}

## True if this tile blocks FOV and light.
static func is_opaque(source_id: int, atlas_coords: Vector2i) -> bool:
	return get_def(source_id, atlas_coords).get("opaque", false)

## Player-visible description string for a tile.
static func get_description(source_id: int, atlas_coords: Vector2i) -> String:
	if source_id == -1:
		return "empty space, nothing here"
	return get_def(source_id, atlas_coords).get("description", "something")

## Material tag for a tile. Empty string means no material-driven wall logic.
static func get_material_id(source_id: int, atlas_coords: Vector2i) -> String:
	return get_def(source_id, atlas_coords).get("material_id", "")
