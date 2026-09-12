# In-memory character preferences shared by the main menu, lobby and player.
# Deliberately no FileAccess calls: choices reset whenever the application exits.
extends Node

signal appearance_changed(appearance: Dictionary)

const SEX_MALE := "male"
const SEX_FEMALE := "female"
const BODY_MALE_TEXTURE := "res://assets/player.png"
const BODY_FEMALE_TEXTURE := "res://assets/characters/body_female.png"
const HAIR_TEXTURE := "res://assets/characters/hair_styles.png"
const FACIAL_HAIR_TEXTURE := "res://assets/characters/facial_hair_styles.png"

const DEFAULT_HAIR_COLOR := "#4a3026"
const DEFAULT_FACIAL_HAIR_COLOR := "#3a251e"

# Row values match the deterministic order in import_roguetown_character_assets.py.
const MALE_HAIR_OPTIONS: Array[Dictionary] = [
	{"id": "", "label": "Bald", "row": -1},
	{"id": "hair_skinhead", "label": "Shaved", "row": 0},
	{"id": "hair_gelled", "label": "Slicked Back", "row": 1},
	{"id": "hair_pirate", "label": "Pirate", "row": 2},
	{"id": "hair_ponytail", "label": "Tied", "row": 3},
	{"id": "hair_business2", "label": "Heroic", "row": 4},
	{"id": "hair_business", "label": "Noble", "row": 5},
	{"id": "hair_shavedmohawk", "label": "Berserker", "row": 6},
	{"id": "hair_bedhead", "label": "Helmet Hair", "row": 7},
	{"id": "hair_bowlcut2", "label": "Bowlcut", "row": 8},
	{"id": "hair_undercut", "label": "Conscript", "row": 9},
	{"id": "hair_father", "label": "Forged", "row": 10},
	{"id": "hair_thinning", "label": "Cavehead", "row": 11},
	{"id": "hair_thinningrear", "label": "Dome", "row": 12},
	{"id": "hair_baldfade", "label": "Scribe", "row": 13},
	{"id": "hair_forelock", "label": "Mercenary", "row": 14},
	{"id": "hair_rogue", "label": "Rogue", "row": 15},
	{"id": "hair_tied", "label": "Tied Long", "row": 16},
	{"id": "hair_romantic", "label": "Romantic", "row": 17},
	{"id": "hair_runt", "label": "Runt", "row": 18},
	{"id": "hair_son", "label": "Sun", "row": 19},
	{"id": "hair_bog", "label": "Bog", "row": 20},
]

const FEMALE_HAIR_OPTIONS: Array[Dictionary] = [
	{"id": "", "label": "Bald", "row": -1},
	{"id": "fhair_shorthairg", "label": "Curly Short", "row": 21},
	{"id": "fhair_vlongfringe", "label": "Plain Long", "row": 22},
	{"id": "fhair_beehive", "label": "Updo", "row": 23},
	{"id": "fhair_barmaid", "label": "Maiden", "row": 24},
	{"id": "fhair_longstraightponytail", "label": "Tied Ponytail", "row": 25},
	{"id": "fhair_messy", "label": "Messy", "row": 26},
	{"id": "fhair_twintail", "label": "Tails", "row": 27},
	{"id": "fhair_doublebun", "label": "Buns", "row": 28},
	{"id": "fhair_bob", "label": "Bob", "row": 29},
	{"id": "hair_runt", "label": "Tomboy", "row": 18},
	{"id": "fhair_amazon", "label": "Barbarian", "row": 30},
	{"id": "fhair_tressshoulder", "label": "Loose Braid", "row": 31},
	{"id": "fhair_himecut2", "label": "Mystery", "row": 32},
	{"id": "fhair_homely", "label": "Homely", "row": 33},
	{"id": "fhair_bob2", "label": "Queenly", "row": 34},
	{"id": "fhair_pixie", "label": "Pixie", "row": 35},
]

const FACIAL_HAIR_OPTIONS: Array[Dictionary] = [
	{"id": "", "label": "None", "row": -1},
	{"id": "facial_stubble", "label": "Stubble", "row": 0},
	{"id": "facial_fullbeard", "label": "Full Beard", "row": 1},
	{"id": "facial_burns", "label": "Sideburns", "row": 2},
	{"id": "facial_pipe", "label": "Pipesmoker", "row": 3},
	{"id": "facial_knightly", "label": "Knightly", "row": 4},
	{"id": "facial_5oclockmoustache", "label": "Mustache", "row": 5},
	{"id": "facial_vandyke", "label": "Rumata", "row": 6},
	{"id": "facial_muttonmus", "label": "Choppe", "row": 7},
	{"id": "facial_moonshiner", "label": "Wise Hermit", "row": 8},
	{"id": "facial_longbeard", "label": "Long Beard", "row": 9},
	{"id": "facial_wise", "label": "Knowledge", "row": 10},
	{"id": "facial_dwarf", "label": "Ranger", "row": 11},
	{"id": "facial_brokenman", "label": "Fullest Beard", "row": 12},
	{"id": "facial_chin", "label": "Clean Chin", "row": 13},
	{"id": "facial_manly", "label": "Drinker", "row": 14},
	{"id": "facial_viking", "label": "Raider", "row": 15},
]

const DEFAULT_APPEARANCE := {
	"sex": SEX_MALE,
	"hair_style": "hair_bedhead",
	"hair_color": DEFAULT_HAIR_COLOR,
	"facial_hair": "facial_stubble",
	"facial_hair_color": DEFAULT_FACIAL_HAIR_COLOR,
}

var _appearance: Dictionary = DEFAULT_APPEARANCE.duplicate(true)


func get_appearance() -> Dictionary:
	return _appearance.duplicate(true)


func get_default_appearance() -> Dictionary:
	return DEFAULT_APPEARANCE.duplicate(true)


func set_appearance(value: Dictionary) -> Dictionary:
	_appearance = sanitize_appearance(value)
	appearance_changed.emit(_appearance.duplicate(true))
	return _appearance.duplicate(true)


func sanitize_appearance(value: Variant) -> Dictionary:
	var input: Dictionary = value if value is Dictionary else {}
	var sex := str(input.get("sex", SEX_MALE)).to_lower()
	if sex not in [SEX_MALE, SEX_FEMALE]:
		sex = SEX_MALE

	var hair_options := get_hair_options(sex)
	var default_hair := "hair_bedhead" if sex == SEX_MALE else "fhair_bob"
	var hair_style := _sanitize_option_id(str(input.get("hair_style", default_hair)), hair_options, default_hair)
	var facial_hair := ""
	if sex == SEX_MALE:
		facial_hair = _sanitize_option_id(str(input.get("facial_hair", "facial_stubble")), FACIAL_HAIR_OPTIONS, "facial_stubble")

	return {
		"sex": sex,
		"hair_style": hair_style,
		"hair_color": _sanitize_color(input.get("hair_color", DEFAULT_HAIR_COLOR), DEFAULT_HAIR_COLOR),
		"facial_hair": facial_hair,
		"facial_hair_color": _sanitize_color(input.get("facial_hair_color", DEFAULT_FACIAL_HAIR_COLOR), DEFAULT_FACIAL_HAIR_COLOR),
	}


func get_hair_options(sex: String) -> Array[Dictionary]:
	return FEMALE_HAIR_OPTIONS.duplicate(true) if sex == SEX_FEMALE else MALE_HAIR_OPTIONS.duplicate(true)


func get_facial_hair_options() -> Array[Dictionary]:
	return FACIAL_HAIR_OPTIONS.duplicate(true)


func get_hair_row(style_id: String) -> int:
	for option in MALE_HAIR_OPTIONS:
		if str(option["id"]) == style_id:
			return int(option["row"])
	for option in FEMALE_HAIR_OPTIONS:
		if str(option["id"]) == style_id:
			return int(option["row"])
	return -1


func get_hair_vertical_offset(sex: String) -> int:
	return 1 if sex == SEX_FEMALE else -1


func get_facial_hair_row(style_id: String) -> int:
	for option in FACIAL_HAIR_OPTIONS:
		if str(option["id"]) == style_id:
			return int(option["row"])
	return -1


func get_facial_hair_vertical_offset() -> int:
	return -2


func get_body_texture_path(sex: String) -> String:
	return BODY_FEMALE_TEXTURE if sex == SEX_FEMALE else BODY_MALE_TEXTURE


func color_to_storage(color: Color) -> String:
	var opaque := Color(color.r, color.g, color.b, 1.0)
	return "#" + opaque.to_html(false)


func color_from_storage(value: Variant, fallback: Color = Color.WHITE) -> Color:
	return Color.from_string(str(value), fallback)


func _sanitize_option_id(value: String, options: Array[Dictionary], fallback: String) -> String:
	for option in options:
		if str(option["id"]) == value:
			return value
	return fallback


func _sanitize_color(value: Variant, fallback: String) -> String:
	var parsed := Color.from_string(str(value).left(16), Color.from_string(fallback, Color.WHITE))
	return color_to_storage(parsed)
