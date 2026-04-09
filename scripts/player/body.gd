# res://scripts/player/body.gd
extends RefCounted

# ---------------------------------------------------------------------------
# Body / Limb system
# Each limb has its own HP pool. When it reaches 0 it becomes "broken"
# and triggers a gameplay effect.
#
# Limb names match the HUD targeted_limb strings:
#   "head", "r_eye", "l_eye", "chest",
#   "r_arm", "l_arm", "r_hand", "l_hand",
#   "r_leg", "l_leg", "r_foot", "l_foot"
#
# hand index 0 = right hand = r_hand / r_arm
# hand index 1 = left  hand = l_hand / l_arm
# ---------------------------------------------------------------------------

const LIMB_MAX_HP: Dictionary = {
	"head": 70,
	"r_eye": 10,
	"l_eye": 10,
	"chest": 70,
	"r_arm": 70,
	"l_arm": 70,
	"r_hand": 70,
	"l_hand": 70,
	"r_leg": 70,
	"l_leg": 70,
	"r_foot": 70,
	"l_foot": 70,
}

const LIMB_PARENT: Dictionary = {
	"r_hand": "r_arm",
	"l_hand": "l_arm",
	"r_foot": "r_leg",
	"l_foot": "l_leg",
}

var player: Node2D

var limb_hp: Dictionary = LIMB_MAX_HP.duplicate(true)
var limb_broken: Dictionary = {}

func _init(p_player: Node2D) -> void:
	player = p_player
	for limb in LIMB_MAX_HP.keys():
		limb_broken[limb] = false

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
	var was_blind: bool = are_eyes_broken()
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
				if player.hands[0] != null:
					Sidebar.add_message("[color=#ffaaaa]That arm is useless![/color]")
					if player.backend:
						player.backend.drop_item_from_hand(0)

		"l_arm":
			if is_local:
				Sidebar.add_message("[color=#ffaaaa]Your left arm is broken and can no longer be used![/color]")
				if player.hands[1] != null:
					Sidebar.add_message("[color=#ffaaaa]That arm is useless![/color]")
					if player.backend:
						player.backend.drop_item_from_hand(1)

		"r_hand":
			if is_local:
				Sidebar.add_message("[color=#ffaaaa]Your right hand is broken and can no longer be used![/color]")
				if player.hands[0] != null and player.backend:
					player.backend.drop_item_from_hand(0)

		"l_hand":
			if is_local:
				Sidebar.add_message("[color=#ffaaaa]Your left hand is broken and can no longer be used![/color]")
				if player.hands[1] != null and player.backend:
					player.backend.drop_item_from_hand(1)

		"r_leg", "l_leg", "r_foot", "l_foot":
			if is_local:
				var limb_label := "leg" if limb.ends_with("leg") else "foot"
				Sidebar.add_message("[color=#ffaaaa]Your " + limb_label + " is broken! You can only crawl.[/color]")
			# Force the player into the lying-down (crawl) state.
			# receive_damage is already replicated to all peers so we set
			# is_lying_down directly without an additional RPC.
			if not player.is_lying_down:
				player.is_lying_down = true
				player._update_sprite()
				player._update_water_submerge()

		"r_eye", "l_eye":
			if is_local:
				var which_eye := "right" if limb == "r_eye" else "left"
				Sidebar.add_message("[color=#ffaaaa]Your " + which_eye + " eye is broken![/color]")

	if limb in ["r_eye", "l_eye"]:
		if is_local and not was_blind and are_eyes_broken():
			Sidebar.add_message("[color=#ff0000]Both of your eyes are broken! You are blind![/color]")
		_refresh_local_vision_penalty()

# ---------------------------------------------------------------------------
# Limb Healing (Triggered by resting when full HP)
# ---------------------------------------------------------------------------

func heal_limbs(amount: int) -> int:
	var leftover = amount
	while leftover > 0:
		var lowest_limb := ""
		var lowest_ratio := 2.0
		
		# Find the most damaged limb by percentage so low-max parts
		# like eyes heal sensibly alongside full-size limbs.
		for limb in limb_hp.keys():
			var limb_max: int = int(LIMB_MAX_HP.get(limb, 70))
			if limb_hp[limb] >= limb_max:
				continue
			var ratio := float(limb_hp[limb]) / float(limb_max)
			if lowest_limb == "" or ratio < lowest_ratio:
				lowest_ratio = ratio
				lowest_limb = limb
				
		# If all limbs are at maximum, break out
		if lowest_limb == "":
			break
			
		var needed = int(LIMB_MAX_HP.get(lowest_limb, 70)) - limb_hp[lowest_limb]
		var heal_this_time = min(leftover, needed)
		var was_broken = limb_broken[lowest_limb]
		
		limb_hp[lowest_limb] += heal_this_time
		leftover -= heal_this_time
		
		# If the limb was broken, but is now back above 0 HP, it's usable again
		if was_broken and limb_hp[lowest_limb] > 0:
			_on_limb_healed(lowest_limb)
			
	return leftover

func _on_limb_healed(limb: String) -> void:
	var was_blind: bool = are_eyes_broken()
	limb_broken[limb] = false
	var is_local: bool = player._is_local_authority()
	
	match limb:
		"r_arm":
			if is_local and not is_limb_disabled(limb):
				Sidebar.add_message("[color=#aaffaa]Your right arm has healed and is usable again![/color]")
		"l_arm":
			if is_local and not is_limb_disabled(limb):
				Sidebar.add_message("[color=#aaffaa]Your left arm has healed and is usable again![/color]")
		"r_hand":
			if is_local and not is_limb_disabled(limb):
				Sidebar.add_message("[color=#aaffaa]Your right hand has healed and is usable again![/color]")
		"l_hand":
			if is_local and not is_limb_disabled(limb):
				Sidebar.add_message("[color=#aaffaa]Your left hand has healed and is usable again![/color]")
		"r_leg", "l_leg", "r_foot", "l_foot":
			if is_local and not are_legs_broken():
				Sidebar.add_message("[color=#aaffaa]Your legs have healed enough to stand up![/color]")
		"chest":
			if is_local:
				Sidebar.add_message("[color=#aaffaa]Your chest has healed![/color]")
		"r_eye", "l_eye":
			if is_local and was_blind and not are_eyes_broken():
				Sidebar.add_message("[color=#aaffaa]You can see again![/color]")

	if limb in ["r_eye", "l_eye"]:
		_refresh_local_vision_penalty()

# ---------------------------------------------------------------------------
# Helpers queried by player.gd
# ---------------------------------------------------------------------------

func are_legs_broken() -> bool:
	return is_limb_disabled("r_leg") or is_limb_disabled("l_leg") or is_limb_disabled("r_foot") or is_limb_disabled("l_foot")

# hand_idx: 0 = right hand (r_hand / r_arm), 1 = left hand (l_hand / l_arm)
func is_arm_broken(hand_idx: int) -> bool:
	if hand_idx == 0:
		return is_limb_disabled("r_hand")
	return is_limb_disabled("l_hand")

func is_limb_disabled(limb: String) -> bool:
	if limb_broken.get(limb, false):
		return true

	var parent_limb: String = LIMB_PARENT.get(limb, "")
	while parent_limb != "":
		if limb_broken.get(parent_limb, false):
			return true
		parent_limb = LIMB_PARENT.get(parent_limb, "")

	return false

func are_eyes_broken() -> bool:
	return limb_broken.get("r_eye", false) and limb_broken.get("l_eye", false)

func _refresh_local_vision_penalty() -> void:
	if not player._is_local_authority():
		return
	if Lighting != null and Lighting.has_method("refresh_local_lighting"):
		Lighting.refresh_local_lighting()
	
