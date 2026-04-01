# res://scripts/defines/defs.gd
# Central definitions file. All magic strings live here as named constants.
# Reference via Defs.GROUP_PICKABLE, Defs.SLOT_HEAD, Defs.TOOL_SLASHING, etc.
class_name Defs

# ---------------------------------------------------------------------------
# Node groups — used with add_to_group() and get_nodes_in_group()
# ---------------------------------------------------------------------------
const GROUP_PICKABLE    = "pickable"
const GROUP_DOOR        = "door"
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
const INTENT_HELP  = "help"
const INTENT_HARM  = "harm"
const INTENT_GRAB  = "grab"
const INTENT_DISARM = "disarm"
