# project\classes.gd
class_name Classes

const DATA: Dictionary = {
	"peasant": {
		"stats": {
			"strength": 8,
			"agility": 7
		},
		"skills": {
			"sword_fighting": 0,
			"blacksmithing": 0
		},
		"equipment": {
			"clothing": "Undershirt",
			"trousers": "LeatherTrousers",
			"feet": "LeatherBoots"
		}
	},
	"merchant": {
		"stats": {
			"strength": 10,
			"agility": 10
		},
		"skills": {
			"sword_fighting": 1,
			"blacksmithing": 0
		},
		"prices_shown": true,
		"equipment": {
			"clothing": "Undershirt",
			"trousers": "LeatherTrousers",
			"feet": "LeatherBoots",
			"armor": "Merchantrobe"
		}
	},
	"bandit": {
		"stats": {
			"strength": 13,
			"agility": 11
		},
		"skills": {
			"sword_fighting": 2,
			"blacksmithing": 0
		},
		"equipment": {
			"clothing": "Blackshirt",
			"trousers": "LeatherTrousers",
			"feet": "LeatherBoots",
			"armor": "IronChestplate",
			"waist": "Sword"
		}
	},
	"adventurer": {
		"stats": {
			"strength": 10,
			"agility": 10
		},
		"skills": {
			"sword_fighting": 0,
			"blacksmithing": 0
		},
		"equipment": {
			"clothing": "Undershirt",
			"trousers": "LeatherTrousers",
			"feet": "LeatherBoots"
		}
	},
	"swordsman": {
		"stats": {
			"strength": 11,
			"agility": 11
		},
		"skills": {
			"sword_fighting": 3,
			"blacksmithing": 0
		},
		"equipment": {
			"clothing": "Undershirt",
			"trousers": "LeatherTrousers",
			"feet": "LeatherBoots",
			"waist": "Sword"
		}
	},
	"miner": {
		"stats": {
			"strength": 12,
			"agility": 10
		},
		"skills": {
			"sword_fighting": 1,
			"blacksmithing": 2
		},
		"equipment": {
			"clothing": "Undershirt",
			"trousers": "LeatherTrousers",
			"feet": "LeatherBoots",
			"waist": "Pickaxe"
		}
	},
	"king": {
		"stats": {
			"strength": 10,
			"agility": 10
		},
		"skills": {
			"sword_fighting": 2,
			"blacksmithing": 0
		},
		"equipment": {
			"clothing": "Apothshirt",
			"trousers": "LeatherTrousers",
			"feet": "LeatherBoots",
			"cloak": "KingCloak",
			"head": "Crown"
		}
	}
}