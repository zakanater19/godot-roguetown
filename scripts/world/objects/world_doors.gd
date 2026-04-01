# res://scripts/world/objects/world_doors.gd
extends RefCounted

var world: Node

func _init(p_world: Node) -> void:
	world = p_world

func handle_rpc_request_hit_door(sender_id: int, door_path: NodePath) -> void:
	if not world.multiplayer.is_server(): return
	var door = world.get_node_or_null(door_path)
	if door == null: return

	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if player == null or player.dead: return
	if player.body != null and player.body.is_arm_broken(player.active_hand): return
	if not world.utils.is_within_interaction_range(player, door.global_position): return

	var held_item = player.hands[player.active_hand]
	if held_item == null:
		if door.state != door.DoorState.DESTROYED:
			world.rpc_confirm_toggle_door.rpc(door_path)
	else:
		var i_type = held_item.get("item_type")
		var is_sword = (i_type == "Sword") or ("Sword" in held_item.name) or ("sword" in held_item.name.to_lower()) or (i_type == "Dirk") or ("Dirk" in held_item.name) or ("dirk" in held_item.name.to_lower())
		var is_pickaxe = (i_type == "Pickaxe") or ("Pickaxe" in held_item.name) or ("pickaxe" in held_item.name.to_lower())

		if is_sword or (is_pickaxe and player.combat_mode):
			if not world.utils.server_check_action_cooldown(player): return
			door.hits += 1
			if door.hits >= door.HITS_TO_BREAK * 2:
				world.rpc_confirm_remove_door.rpc(door_path)
			elif door.hits == door.HITS_TO_BREAK:
				world.rpc_confirm_destroy_door.rpc(door_path)
			else:
				world.rpc_confirm_hit_door.rpc(door_path)

func handle_rpc_confirm_toggle_door(_door_path: NodePath) -> void:
	var door = world.get_node_or_null(_door_path)
	if door != null:
		door.toggle_door()

func handle_rpc_confirm_hit_door(door_path: NodePath) -> void:
	var door = world.get_node_or_null(door_path)
	if door != null:
		var main = world.get_tree().root.get_node_or_null("Main")
		door.perform_hit(main)

func handle_rpc_confirm_destroy_door(door_path: NodePath) -> void:
	var door = world.get_node_or_null(door_path)
	if door != null:
		var main = world.get_tree().root.get_node_or_null("Main")
		door.perform_hit(main)
		door.destroy_door()

func handle_rpc_confirm_remove_door(door_path: NodePath) -> void:
	var door = world.get_node_or_null(door_path)
	if door != null:
		var main = world.get_tree().root.get_node_or_null("Main")
		door.perform_hit(main)
		door.remove_completely()
