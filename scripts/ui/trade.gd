# res://scripts/ui/trade.gd
# AutoLoad singleton - registered as "Trade" in project.godot
extends Node

const PRICES: Dictionary = {
	"Apothshirt": 4,
	"Blackshirt": 3,
	"BrownKey": 1,
	"ChainGloves": 30,
	"Coal": 1,
	"Crown": 100,
	"Dirk": 12,
	"Furnace": 25,
	"Hood": 7,
	"IronChestplate": 60,
	"IronHelmet": 45,
	"IronIngot": 10,
	"IronOre": 2,
	"Keyring": 2,
	"KingCloak": 25,
	"Lamp": 8,
	"LeatherBoots": 2,
	"LeatherTrousers": 3,
	"Log": 3,
	"Merchantrobe": 3,
	"Pebble": 1,
	"Pickaxe": 15,
	"Plate": 150,
	"Satchel": 8,
	"Sword": 25,
	"Undershirt": 3,
}

const RESTRICTED_ITEM_TYPES: PackedStringArray = [
	"BrownKey",
	"Coal",
	"CopperCoin",
	"Furnace",
	"SilverCoin",
	"GoldCoin",
	"Crown",
	"IronOre",
	"KingCloak",
	"Merchantrobe",
	"MerchantVendor",
	"Rock",
	"Tree1",
	"Tree2",
]

func get_price(item_type: String) -> int:
	return PRICES.get(item_type, 0)

func is_restricted(item_type: String) -> bool:
	return RESTRICTED_ITEM_TYPES.has(item_type)

func is_buyable(item_type: String) -> bool:
	if item_type.is_empty() or is_restricted(item_type):
		return false
	if get_price(item_type) <= 0:
		return false
	return ItemRegistry.get_by_type(item_type) != null

func get_buyable_catalog() -> Array[Dictionary]:
	var catalog: Array[Dictionary] = []
	for item_type in PRICES.keys():
		if not is_buyable(item_type):
			continue
		var entry := _make_catalog_entry(item_type)
		if not entry.is_empty():
			catalog.append(entry)
	catalog.sort_custom(_sort_catalog_entries)
	return catalog

func get_restricted_catalog() -> Array[Dictionary]:
	var catalog: Array[Dictionary] = []
	for item_type in RESTRICTED_ITEM_TYPES:
		var entry := _make_catalog_entry(item_type)
		if not entry.is_empty():
			catalog.append(entry)
	catalog.sort_custom(_sort_catalog_entries)
	return catalog

func get_item_type_from_node(item: Node) -> String:
	if item == null or not is_instance_valid(item):
		return ""
	var raw_item_type: Variant = item.get("item_type")
	if raw_item_type != null and str(raw_item_type) != "":
		return str(raw_item_type)
	return item.name.get_slice("@", 0)

func get_value_for_node(item: Node) -> int:
	if item == null or not is_instance_valid(item):
		return 0
	if item.get("is_coin_stack") == true:
		var amount := _get_node_int(item, "amount", 0)
		var metal_type := _get_node_int(item, "metal_type", -1)
		return amount * Defs.get_coin_value(metal_type)
	return get_price(get_item_type_from_node(item))

func _make_catalog_entry(item_type: String) -> Dictionary:
	var item_data := ItemRegistry.get_by_type(item_type)
	if item_data == null:
		return {}
	return {
		"item_type": item_type,
		"description": item_data.description,
		"icon": ItemRegistry.get_item_icon(item_type),
		"price": get_price(item_type),
	}

func _sort_catalog_entries(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("item_type", "")).nocasecmp_to(str(b.get("item_type", ""))) < 0

func _get_node_int(node: Node, property_name: String, default_value: int) -> int:
	if node == null or not is_instance_valid(node):
		return default_value
	var value = node.get(property_name)
	return int(value) if value != null else default_value
