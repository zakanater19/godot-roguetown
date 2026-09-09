# res://scripts/defines/classes.gd
class_name Classes

const DATA: Dictionary = {
	"peasant": {
		"stats": {
			"strength": 8,
			"agility": 7
		},
		"skills": {
			"sword_fighting": 0,
			"blacksmithing": 0,
			"sneaking": 0
		},
		"equipment": {
			"clothing": "Undershirt",
			"trousers": "LeatherTrousers",
			"feet": "LeatherBoots",
			"pocket_1": "Pouch"
		},
		"starting_pouch": [
			{"item_type": "CopperCoin", "metal_type": 0, "amount_min": 10, "amount_max": 20}
		]
	},
	"merchant": {
		"stats": {
			"strength": 10,
			"agility": 10
		},
		"skills": {
			"sword_fighting": 1,
			"blacksmithing": 0,
			"sneaking": 0
		},
		"prices_shown": true,
		"equipment": {
			"clothing": "Undershirt",
			"trousers": "LeatherTrousers",
			"feet": "LeatherBoots",
			"armor": "Merchantrobe",
			"pocket_1": "Pouch",
			"pocket_2": "Keyring"
		},
		"equipment_data": {
			"pocket_2": {
				"contents": [
					{
						"item_type": "BrownKey",
						"key_id": 1
					}
				]
			}
		},
		"starting_pouch": [
			{"item_type": "GoldCoin", "metal_type": 2, "amount": 20, "stacks": 2}
		]
	},
	"bandit": {
		"stats": {
			"strength": 13,
			"agility": 11
		},
		"skills": {
			"sword_fighting": 2,
			"blacksmithing": 0,
			"sneaking": 2
		},
		"equipment": {
			"clothing": "Blackshirt",
			"trousers": "LeatherTrousers",
			"feet": "LeatherBoots",
			"armor": "IronChestplate",
			"waist": "Sword",
			"pocket_1": "Pouch"
		}
	},
	"adventurer": {
		"stats": {
			"strength": 10,
			"agility": 10
		},
		"skills": {
			"sword_fighting": 0,
			"blacksmithing": 0,
			"sneaking": 0
		},
		"equipment": {
			"clothing": "Undershirt",
			"trousers": "LeatherTrousers",
			"feet": "LeatherBoots",
			"pocket_1": "Pouch"
		},
		"starting_pouch": [
			{"item_type": "SilverCoin", "metal_type": 1, "amount_min": 5, "amount_max": 15}
		]
	},
	"swordsman": {
		"stats": {
			"strength": 11,
			"agility": 11
		},
		"skills": {
			"sword_fighting": 3,
			"blacksmithing": 0,
			"sneaking": 0
		},
		"equipment": {
			"clothing": "Undershirt",
			"trousers": "LeatherTrousers",
			"feet": "LeatherBoots",
			"waist": "Sword",
			"pocket_1": "Pouch"
		}
	},
	"miner": {
		"stats": {
			"strength": 12,
			"agility": 10
		},
		"skills": {
			"sword_fighting": 1,
			"blacksmithing": 2,
			"sneaking": 0
		},
		"equipment": {
			"clothing": "Undershirt",
			"trousers": "LeatherTrousers",
			"feet": "LeatherBoots",
			"waist": "Pickaxe",
			"pocket_1": "Pouch"
		}
	},
	"king": {
		"stats": {
			"strength": 10,
			"agility": 10
		},
		"skills": {
			"sword_fighting": 2,
			"blacksmithing": 0,
			"sneaking": 0
		},
		"equipment": {
			"clothing": "Apothshirt",
			"trousers": "LeatherTrousers",
			"feet": "LeatherBoots",
			"cloak": "KingCloak",
			"head": "Crown",
			"pocket_1": "Pouch"
		},
		"starting_pouch": [
			{"item_type": "GoldCoin", "metal_type": 2, "amount": 20}
		]
	}
}

static func get_spawn_options() -> PackedStringArray:
	var options := PackedStringArray(DATA.keys())
	options.sort()
	options.append("latejoin")
	options.append("antag latejoin")
	return options
