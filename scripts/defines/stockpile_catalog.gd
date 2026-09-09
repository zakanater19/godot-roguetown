class_name StockpileCatalog
extends Resource

## Canonical item type -> copper payout mapping for one kind of stockpile vendor.
## Assign another catalogue to a vendor scene to add a new market without
## changing the sale or networking implementation.
@export var payouts: Dictionary = {}

## Optional item type -> player-facing name mapping used in sale messages.
@export var item_names: Dictionary = {}

func accepts(item_type: String) -> bool:
	return get_payout(item_type) > 0

func get_payout(item_type: String) -> int:
	return maxi(0, int(payouts.get(item_type, 0)))

func get_item_name(item_type: String) -> String:
	return str(item_names.get(item_type, item_type))
