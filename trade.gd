# res://trade.gd
# AutoLoad singleton — registered as "Trade" in project.godot
extends Node

const PRICES: Dictionary = {
	"Pebble": 1,
	"Coal": 1,
	"Log": 1,
	"IronOre": 2,
	"IronIngot": 10,
	"Pickaxe": 15,
	"Sword": 15,
	"Dirk": 10,
	
	"Apothshirt": 3,
	"Blackshirt": 3,
	"Undershirt": 3,
	"Merchantrobe": 3,
	"LeatherTrousers": 3,
	
	"IronChestplate": 20,
	"IronHelmet": 15,
	"Plate": 50,
	"LeatherBoots": 2
}

func get_price(item_type: String) -> int:
	return PRICES.get(item_type, 0)