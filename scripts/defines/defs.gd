# res://scripts/defines/defs.gd
# Central definitions file. All magic strings and shared constants live here.
# Reference via Defs.GROUP_PICKABLE, Defs.SLOT_HEAD, Defs.TOOL_SLASHING, etc.
class_name Defs

# ---------------------------------------------------------------------------
# World geometry — must stay in sync with World.TILE_SIZE / World.GRID_*
# ---------------------------------------------------------------------------
const TILE_SIZE:    int = 64
const GRID_WIDTH:   int = 1000
const GRID_HEIGHT:  int = 1000

# ---------------------------------------------------------------------------
# Z-index layering — every z_level occupies Z_LAYER_SIZE index slots
# ---------------------------------------------------------------------------
const Z_LAYER_SIZE:    int = 200   # index units per z_level
const Z_OFFSET_ITEMS:  int = 2     # items render below players
const Z_OFFSET_PLAYERS: int = 10   # players render above items

# ---------------------------------------------------------------------------
# Item drop / loot constants
# ---------------------------------------------------------------------------
const DROP_SPREAD:        float = 14.0   # pixel radius items scatter on drop
const LOOT_DURATION:      float = 4.0    # seconds to complete a loot action
const LOOT_BLINK_INTERVAL: float = 0.25  # progress indicator blink rate (s)

# ---------------------------------------------------------------------------
# Node groups — used with add_to_group() and get_nodes_in_group()
# ---------------------------------------------------------------------------
const GROUP_PICKABLE    = "pickable"
const GROUP_DOOR        = "door"
const GROUP_GATE        = "gate"
const GROUP_CHOPPABLE   = "choppable_object"
const GROUP_MINABLE     = "minable_object"
const GROUP_BREAKABLE   = "breakable_object"
const GROUP_BED         = "bed"
const GROUP_INSPECTABLE = "inspectable"
const GROUP_COIN        = "coin"

# ---------------------------------------------------------------------------
# Equipment slots — matches ItemData.slot values
# ---------------------------------------------------------------------------
const SLOT_HEAD     = "head"
const SLOT_CLOAK    = "cloak"
const SLOT_FACE     = "face"
const SLOT_ARMOR    = "armor"
const SLOT_BACKPACK = "backpack"
const SLOT_GLOVES   = "gloves"
const SLOT_CLOTHING = "clothing"
const SLOT_TROUSERS = "trousers"
const SLOT_FEET     = "feet"
const SLOT_WAIST    = "waist"

# ---------------------------------------------------------------------------
# Tool types — matches ItemData.tool_type values
# ---------------------------------------------------------------------------
const TOOL_SLASHING = "slashing"
const TOOL_STABBING = "stabbing"
const TOOL_PICKAXE = "pickaxe"

# ---------------------------------------------------------------------------
# Recipe result types — matches RecipeData.result_type values
# ---------------------------------------------------------------------------
const RECIPE_RESULT_ITEM = "item"
const RECIPE_RESULT_TILE = "tile"

# ---------------------------------------------------------------------------
# Intent modes
# ---------------------------------------------------------------------------
const INTENT_HELP   = "help"
const INTENT_HARM   = "harm"
const INTENT_GRAB   = "grab"
const INTENT_DISARM = "disarm"

# ---------------------------------------------------------------------------
# Equipment slots — canonical ordered list; drives UI, init, and loot panels
# ---------------------------------------------------------------------------
const SLOTS_ALL: Array = [
	"head", "face", "cloak", "armor", "backpack",
	"gloves", "waist", "clothing", "trousers", "feet",
	"pocket_l", "pocket_r"
]

# Display labels for the loot/inspect UI (key → human-readable label).
# "armor" maps to "Chest" intentionally (chest-slot is displayed as "Chest").
const SLOT_DISPLAY: Dictionary = {
	"head":     "Head",
	"face":     "Face",
	"cloak":    "Cloak",
	"armor":    "Chest",
	"backpack": "Backpack",
	"gloves":   "Gloves",
	"waist":    "Waist",
	"clothing": "Clothing",
	"trousers": "Trousers",
	"feet":     "Feet",
	"pocket_l": "L. Pocket",
	"pocket_r": "R. Pocket",
}

# ---------------------------------------------------------------------------
# Social / class knowledge — classes that are considered "outsiders" to townsfolk
# ---------------------------------------------------------------------------
const OUTSIDER_CLASSES: Array = ["adventurer", "bandit"]
