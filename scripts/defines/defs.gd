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
const DEFAULT_SPAWN_TILE: Vector2i = Vector2i(int(GRID_WIDTH * 0.5), int(GRID_HEIGHT * 0.5))

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
const HAND_COUNT:         int = 2
const SATCHEL_SLOT_COUNT: int = 10
const MAX_COIN_STACK:     int = 20
const KEYRING_MAX_KEYS:   int = 5
const COIN_STACK_ICON_THRESHOLDS: Array[int] = [20, 15, 10, 5, 4, 3, 2, 1]
const COIN_METAL_SUFFIXES: Array[String] = ["copper", "silver", "gold"]
const COIN_VALUES: Array[int] = [1, 5, 10]
const COIN_ITEM_TYPES: Array[String] = ["CopperCoin", "SilverCoin", "GoldCoin"]
const KEY_NAME_MAP: Dictionary = {
	1: "merchant",
}

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
const GROUP_PLAYER      = "player"
const GROUP_NPC         = "npc"
const GROUP_Z_ENTITY    = "z_entity"
const GROUP_SPAWNERS    = "spawners"

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
# Limbs
# ---------------------------------------------------------------------------
const LIMBS: Array = [
	"head", "r_eye", "l_eye", "chest",
	"r_arm", "l_arm", "r_hand", "l_hand",
	"r_leg", "l_leg", "r_foot", "l_foot"
]

const LIMB_DISPLAY: Dictionary = {
	"head": "head",
	"r_eye": "right eye",
	"l_eye": "left eye",
	"chest": "chest",
	"r_arm": "right arm",
	"l_arm": "left arm",
	"r_hand": "right hand",
	"l_hand": "left hand",
	"r_leg": "right leg",
	"l_leg": "left leg",
	"r_foot": "right foot",
	"l_foot": "left foot"
}

# ---------------------------------------------------------------------------
# Equipment slots — canonical ordered list; drives UI, init, and loot panels
# ---------------------------------------------------------------------------
const SLOTS_ALL: Array =[
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

# ---------------------------------------------------------------------------
# Static Helpers
# ---------------------------------------------------------------------------

static func is_tool_sword(item: Node) -> bool:
	if item == null: return false
	var t_type = item.get("tool_type")
	return t_type == TOOL_SLASHING or t_type == TOOL_STABBING

static func is_tool_pickaxe(item: Node) -> bool:
	if item == null: return false
	return item.get("tool_type") == TOOL_PICKAXE

static func get_z_index(z_level: int, offset: int = 0) -> int:
	return (z_level - 1) * Z_LAYER_SIZE + offset

static func is_valid_hand_index(hand_index: int) -> bool:
	return hand_index >= 0 and hand_index < HAND_COUNT

static func is_within_tile_reach(from_tile: Vector2i, to_tile: Vector2i, reach: int = 1) -> bool:
	var diff := (to_tile - from_tile).abs()
	return diff.x <= reach and diff.y <= reach

static func make_runtime_name(prefix: String, detail: String = "") -> String:
	var base := prefix if detail == "" else prefix + "_" + detail
	return base + "_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000)

static func get_coin_icon_path(amount: int, metal_type: int) -> String:
	if metal_type < 0 or metal_type >= COIN_METAL_SUFFIXES.size():
		return ""
	var suffix := COIN_METAL_SUFFIXES[metal_type]
	for threshold in COIN_STACK_ICON_THRESHOLDS:
		if amount >= threshold:
			var path := "res://objects/coins/" + str(threshold) + suffix + ".png"
			if ResourceLoader.exists(path):
				return path
	return ""

static func get_coin_value(metal_type: int) -> int:
	if metal_type < 0 or metal_type >= COIN_VALUES.size():
		return 0
	return COIN_VALUES[metal_type]

static func get_coin_item_type(metal_type: int) -> String:
	if metal_type < 0 or metal_type >= COIN_ITEM_TYPES.size():
		return ""
	return COIN_ITEM_TYPES[metal_type]

static func get_keyring_icon_path(key_count: int) -> String:
	var clamped_count := clampi(key_count, 0, KEYRING_MAX_KEYS)
	var path := "res://objects/keys/keyring%d.png" % clamped_count
	return path if ResourceLoader.exists(path) else ""

static func get_key_name(key_id: int) -> String:
	return str(KEY_NAME_MAP.get(key_id, ""))

static func get_key_description(key_id: int) -> String:
	var key_name := get_key_name(key_id)
	return "a %s key" % key_name if key_name != "" else "a key"

static func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / TILE_SIZE), int(world_pos.y / TILE_SIZE))

static func tile_to_pixel(tile_pos: Vector2i) -> Vector2:
	return Vector2((tile_pos.x + 0.5) * TILE_SIZE, (tile_pos.y + 0.5) * TILE_SIZE)
