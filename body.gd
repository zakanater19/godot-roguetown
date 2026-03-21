# res://body.gd
extends RefCounted

# ---------------------------------------------------------------------------
# Body / Limb system
# Each limb has its own HP pool. When it reaches 0 it becomes "broken"
# and triggers a gameplay effect.
#
# Limb names match the HUD targeted_limb strings:
#   "head", "chest", "r_arm", "l_arm", "r_leg", "l_leg"
#
# hand index 0 = right hand = r_arm
# hand index 1 = left  hand = l_arm
# ---------------------------------------------------------------------------

const LIMB_MAX_HP: int = 70

var player: Node2D

var limb_hp: Dictionary = {
	"head":  70,
	"chest": 70,
	"r_arm": 70,
	"l_arm": 70,
	"r_leg": 70,
	"l_leg": 70,
}

var limb_broken: Dictionary = {
	"head":  false,
	"chest": false,
	"r_arm": false,
	"l_arm": false,
	"r_leg": false,
	"l_leg": false,
}

func _init(p_player: Node2D) -> void:
	player = p_player

# ---------------------------------------------------------------------------
# Called from player.receive_damage for every hit.
# Drains the targeted limb's HP pool; triggers _on_limb_broken at 0.
# Already-broken limbs are ignored.
# ---------------------------------------------------------------------------

func receive_limb_damage(limb: String, amount: int) -> void:
	if not limb_hp.has(limb):
		return
	if limb_broken[limb]:
		return

	limb_hp[limb] = max(0, limb_hp[limb] - amount)

	if limb_hp[limb] <= 0:
		_on_limb_broken(limb)

# ---------------------------------------------------------------------------
# Handle the effect when a limb first breaks.
# receive_damage is call_local + replicated, so this runs on every machine.
# Sidebar messages are gated behind _is_local_authority().
# ---------------------------------------------------------------------------

func _on_limb_broken(limb: String) -> void:
	limb_broken[limb] = true

	var is_local: bool = player._is_local_authority()

	match limb:
		"head":
			if is_local:
				Sidebar.add_message("[color=#ff0000]Your head has been destroyed![/color]")
			# Instant death — set overall health to 0 then trigger die()
			player.health = 0
			if player.combat:
				player.combat.die()

		"chest":
			# Reserved for future effects
			if is_local:
				Sidebar.add_message("[color=#ffaaaa]Your chest has been badly broken![/color]")

		"r_arm":
			if is_local:
				Sidebar.add_message("[color=#ffaaaa]Your right arm is broken and can no longer be used![/color]")

		"l_arm":
			if is_local:
				Sidebar.add_message("[color=#ffaaaa]Your left arm is broken and can no longer be used![/color]")

		"r_leg", "l_leg":
			if is_local:
				Sidebar.add_message("[color=#ffaaaa]Your leg is broken! You can only crawl.[/color]")
			# Force the player into the lying-down (crawl) state.
			# receive_damage is already replicated to all peers so we set
			# is_lying_down directly without an additional RPC.
			if not player.is_lying_down:
				player.is_lying_down = true
				player._update_sprite()
				player._update_water_submerge()

# ---------------------------------------------------------------------------
# Helpers queried by player.gd
# ---------------------------------------------------------------------------

func are_legs_broken() -> bool:
	return limb_broken["r_leg"] or limb_broken["l_leg"]

# hand_idx: 0 = right hand (r_arm), 1 = left hand (l_arm)
func is_arm_broken(hand_idx: int) -> bool:
	if hand_idx == 0:
		return limb_broken["r_arm"]
	return limb_broken["l_arm"]
