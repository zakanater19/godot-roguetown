extends RefCounted

var world: Node

func _init(p_world: Node) -> void:
	world = p_world

func resolve_interaction(sender_id: int, structure_path: NodePath) -> String:
	if not world.multiplayer.is_server():
		return ""

	var structure = world.get_node_or_null(structure_path)
	if structure == null:
		return ""

	var player: Node2D = world.utils.find_player_by_peer(sender_id) as Node2D
	if not world.utils.can_player_interact(player):
		return ""
	if player.body != null and player.body.is_arm_broken(player.active_hand):
		return ""
	if not world.utils.is_within_interaction_range(player, structure.global_position):
		return ""

	var held_item = player.hands[player.active_hand]
	if structure.has_method("resolve_player_structure_interaction"):
		var interaction = structure.resolve_player_structure_interaction(player, held_item)
		if interaction is Dictionary:
			var message := str(interaction.get("message", ""))
			if message != "":
				world.rpc_send_direct_message.rpc_id(sender_id, message)
			var action := str(interaction.get("action", ""))
			if action != "":
				return action

	if held_item == null:
		if structure.has_method("can_toggle") and structure.can_toggle():
			return "toggle"
		return ""

	var hit_strength := MaterialRegistry.get_tool_efficiency(structure, held_item)
	if hit_strength <= 0.0:
		return ""
	if not world.utils.server_check_action_cooldown(player):
		return ""
	if not structure.has_method("apply_structure_damage"):
		return ""
	return structure.apply_structure_damage(hit_strength)

func confirm_toggle(structure_path: NodePath) -> void:
	var structure = world.get_node_or_null(structure_path)
	if structure != null and structure.has_method("toggle_structure"):
		structure.toggle_structure()

func confirm_hit(structure_path: NodePath) -> void:
	var structure = world.get_node_or_null(structure_path)
	if structure != null and structure.has_method("perform_hit"):
		structure.perform_hit(World.main_scene)

func confirm_destroy(structure_path: NodePath) -> void:
	var structure = world.get_node_or_null(structure_path)
	if structure == null:
		return
	confirm_hit(structure_path)
	if structure.has_method("destroy_structure"):
		structure.destroy_structure()

func confirm_remove(structure_path: NodePath) -> void:
	var structure = world.get_node_or_null(structure_path)
	if structure == null:
		return
	confirm_hit(structure_path)
	if structure.has_method("remove_structure"):
		structure.remove_structure()
