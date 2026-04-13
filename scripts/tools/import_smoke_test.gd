class_name ImportSmokeTest
extends RefCounted

const PROJECT_ROOT := "res://"
const ITEMS_DIR := "res://items"
const RECIPES_DIR := "res://recipes"
const MATERIALS_DIR := "res://materials"

# Scenes registered with MultiplayerSpawner.add_spawnable_scene() in Host.gd.
const NET_SPAWNABLE_SCENES: Array[String] =[
	"res://scenes/player.tscn",
	"res://core/ghost.tscn",
]

# Scenes that must contain a MultiplayerSynchronizer with a valid replication_config.
# Each configured property NodePath must resolve to a real property on the target node.
const NET_SYNCED_SCENES: Array[String] =[
	"res://scenes/player.tscn",
	"res://npcs/spider.tscn",
]

var _errors: Array[String] =[]
var _warnings: Array[String] =[]
var _validated_script_paths: Dictionary = {}
var _validated_scene_paths: Dictionary = {}
var _validated_texture_paths: Dictionary = {}

var _section_results: Array[Dictionary] =[]
var _section_name: String = ""
var _section_error_start: int = 0

# Injected by the runner to allow async integration testing
var scene_tree: SceneTree = null

class _SmokeBodyStub:
	extends RefCounted

	var limb_hp := {"chest": 80}
	var limb_broken := {"chest": false}


class _SmokePlayerStub:
	extends Node2D

	var is_possessed: bool = true
	var z_level: int = 3
	var health: int = 100
	var dead: bool = false
	var body = _SmokeBodyStub.new()
	var hands: Array =[null, null]
	var equipped: Dictionary = {}
	var equipped_data: Dictionary = {}
	var is_lying_down: bool = false
	var is_sneaking: bool = false
	var sneak_alpha: float = 1.0
	var stamina: int = 100


class _SmokeReconnectStub:
	extends RefCounted

	func capture_player_state(node: Node2D) -> Dictionary:
		return (node.get_meta("smoke_capture_state", {}) as Dictionary).duplicate(true)

	func capture_hands_state(node: Node2D) -> Array:
		return (node.get_meta("smoke_hand_state",[]) as Array).duplicate(true)

	func capture_equipped_state(node: Node2D) -> Dictionary:
		return (node.get_meta("smoke_equipped_state", {}) as Dictionary).duplicate(true)

	func restore_player_state(node: Node2D, player_state: Dictionary) -> void:
		node.set_meta("smoke_restored_state", player_state.duplicate(true))

	func _recreate_hand_item(hand_state: Dictionary) -> Node:
		var item := Node2D.new()
		item.name = str(hand_state.get("name", "SmokeHandItem"))
		var entity_id := str(hand_state.get("entity_id", ""))
		if entity_id != "":
			World.register_entity(item, entity_id)
		return item


class _SmokeLateJoinStub:
	extends Node

	var _world_state: Dictionary = {
		"tiles": {},
		"objects": {},
		"players": {},
	}
	var _reconnect = null
	var players_by_peer: Dictionary = {}

	func _find_player_by_peer(peer_id: int) -> Node:
		return players_by_peer.get(peer_id, null)


class _SmokeSyncObjectStub:
	extends Node2D

	var z_level: int = 3
	var hits: int = 0
	var state: String = "closed"
	var is_on: bool = false
	var contents: Dictionary = {}
	var amount: int = 0
	var metal_type: int = 0
	var stored_balance: int = 0
	var key_id: String = ""
	var is_locked: bool = false
	var tree_id: String = ""
	var piece_kind: String = ""
	var support_segment_name: String = ""
	var hits_to_break: int = 0
	var drop_count: int = 0
	var atlas_index: int = 0
	var solid_piece: bool = false
	var blocks_fov: bool = false
	var decor_configs: Dictionary = {}
	var sprite_updates: int = 0
	var solidity_updates: int = 0
	var rebuild_calls: int = 0

	func set_hits(value: int) -> void:
		hits = value

	func _update_sprite() -> void:
		sprite_updates += 1

	func _update_solidity() -> void:
		solidity_updates += 1

	func _set_sprite(value: bool) -> void:
		is_on = value

	func rebuild_decor() -> void:
		rebuild_calls += 1

	func _update_merchant_balance(value: int) -> void:
		stored_balance = value

func run() -> Dictionary:
	var item_types := {}
	var material_ids := {}

	_begin_section("autoloads")
	_validate_autoloads()
	_end_section()

	_begin_section("scripts")
	_validate_project_scripts()
	_end_section()

	_begin_section("scenes")
	_validate_project_scenes()
	_end_section()

	_begin_section("items")
	_validate_items(item_types)
	_end_section()

	_begin_section("materials")
	_validate_materials(material_ids)
	_end_section()

	_begin_section("recipes")
	_validate_recipes(item_types)
	_end_section()

	_begin_section("classes")
	_validate_classes(item_types)
	_end_section()

	_begin_section("clothing offsets")
	_validate_clothing_offsets()
	_end_section()

	_begin_section("coin icons")
	_validate_coin_icons()
	_end_section()

	_begin_section("keyring icons")
	_validate_keyring_icons()
	_end_section()

	_begin_section("net: spawnable scenes")
	_validate_spawnable_scenes()
	_end_section()

	_begin_section("net: replication configs")
	_validate_replication_configs()
	_end_section()

	_begin_section("net: resource diff dirs")
	_validate_resource_diff_dirs()
	_end_section()

	_begin_section("net: sync behavior")
	_validate_network_sync_behavior()
	_end_section()

	_begin_section("net: resource patching")
	_validate_resource_patching()
	_end_section()

	if scene_tree != null:
		_begin_section("dynamic: scene instantiation")
		await _validate_all_instantiations()
		_end_section()

		_begin_section("dynamic: live networking")
		await _validate_live_networking()
		_end_section()

	return {
		"errors": _errors.duplicate(),
		"warnings": _warnings.duplicate(),
		"sections": _section_results.duplicate(),
	}

func _begin_section(name: String) -> void:
	_section_name = name
	_section_error_start = _errors.size()

func _end_section() -> void:
	_section_results.append({
		"name": _section_name,
		"errors": _errors.size() - _section_error_start,
	})
	_section_name = ""

# NEW: Automatically pull, scan and test EVERY scene in the project to catch _ready() crashes dynamically.
func _validate_all_instantiations() -> void:
	# Create a safe sandbox container for temporary instantiation
	var sandbox := Node.new()
	sandbox.name = "SmokeTestSandbox"
	scene_tree.root.call_deferred("add_child", sandbox)
	await scene_tree.process_frame

	var scene_paths := _collect_paths(PROJECT_ROOT, ".tscn")
	for path in scene_paths:
		# We exclude main.tscn and main_menu.tscn to prevent test loop overriding / global scene changes
		if path.ends_with("main_menu.tscn") or path.ends_with("main.tscn"):
			continue
			
		var packed := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
		if packed == null:
			_fail("%s: Failed to load packed scene for dynamic instantiation." % path)
			continue
			
		var instance := packed.instantiate()
		if instance == null:
			_fail("%s: Failed to instantiate." % path)
			continue
			
		# Safeguard: Ensure the sandbox hasn't been deleted by a rogue scene
		if not is_instance_valid(sandbox):
			sandbox = Node.new()
			sandbox.name = "SmokeTestSandbox"
			scene_tree.root.call_deferred("add_child", sandbox)
			await scene_tree.process_frame
			
		sandbox.call_deferred("add_child", instance)
		
		# Wait one frame to let _ready() and _enter_tree() process cleanly
		await scene_tree.process_frame 
		
		# Safeguard: Some UI panels free themselves if spawned outside gameplay.
		# Only call queue_free if the instance is still valid.
		if is_instance_valid(instance):
			instance.queue_free()
			
		# Wait another frame to allow the engine to clean it up safely
		await scene_tree.process_frame 

	if is_instance_valid(sandbox):
		sandbox.queue_free()

# NEW: Spins up a headless server and client, validates connection, and cleanly destroys them.
func _validate_live_networking() -> void:
	var port := 12345
	
	var server_peer := ENetMultiplayerPeer.new()
	var err := server_peer.create_server(port, 4)
	if err != OK:
		_fail("Live Network: Failed to create headless test server on port %d (Error %d)." % [port, err])
		return

	var client_peer := ENetMultiplayerPeer.new()
	err = client_peer.create_client("127.0.0.1", port)
	if err != OK:
		_fail("Live Network: Failed to create headless test client (Error %d)." % err)
		server_peer.close()
		return

	var timeout := 2.0
	var elapsed := 0.0
	var client_connected := false
	
	# Poll network until connected or timed out
	while not client_connected and elapsed < timeout:
		server_peer.poll()
		client_peer.poll()
		
		if client_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			client_connected = true
			break
			
		await scene_tree.create_timer(0.1).timeout
		elapsed += 0.1

	if not client_connected:
		_fail("Live Network: Headless client timed out attempting to connect to the local server.")
	
	# KILL headless test clients and cleanup to prevent ghost sessions
	client_peer.close()
	server_peer.close()

func _validate_items(item_types: Dictionary) -> void:
	const VALID_SLOTS: Array[String] =[
		"head", "face", "cloak", "armor", "backpack",
		"gloves", "waist", "clothing", "trousers", "feet",
		"pocket_l", "pocket_r",
	]
	const VALID_TOOL_TYPES: Array[String] =["slashing", "stabbing", "pickaxe"]

	for path in _collect_paths(ITEMS_DIR, ".tres"):
		var item := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as ItemData
		if item == null:
			_fail("%s: failed to load as ItemData." % path)
			continue
		if item.item_type.is_empty():
			_fail("%s: item_type is empty." % path)
		elif item_types.has(item.item_type):
			_fail("%s: duplicate item_type '%s' also used by %s." %[path, item.item_type, item_types[item.item_type]["path"]])
		else:
			item_types[item.item_type] = {
				"path": path,
				"scene_path": item.scene_path,
			}

		if item.scene_path.is_empty():
			_fail("%s: scene_path is empty." % path)
		else:
			_validate_packed_scene(item.scene_path, "%s scene_path" % path)

		if not item.hud_texture_path.is_empty():
			_validate_texture(item.hud_texture_path, "%s hud_texture_path" % path)
		if not item.mob_texture_path.is_empty():
			_validate_texture(item.mob_texture_path, "%s mob_texture_path" % path)

		if not item.slot.is_empty() and item.slot not in VALID_SLOTS:
			_fail("%s: slot '%s' is not a valid Defs slot." %[path, item.slot])
		if not item.tool_type.is_empty() and item.tool_type not in VALID_TOOL_TYPES:
			_fail("%s: tool_type '%s' is not a valid Defs tool type." % [path, item.tool_type])
		if item.has_inventory and item.inventory_slots <= 0:
			_fail("%s: has_inventory is true but inventory_slots is %d." %[path, item.inventory_slots])

func _validate_materials(material_ids: Dictionary) -> void:
	for path in _collect_paths(MATERIALS_DIR, ".tres"):
		var material := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as MaterialData
		if material == null:
			_fail("%s: failed to load as MaterialData." % path)
			continue
		if material.material_id.is_empty():
			_fail("%s: material_id is empty." % path)
		elif material_ids.has(material.material_id):
			_fail("%s: duplicate material_id '%s' also used by %s." %[path, material.material_id, material_ids[material.material_id]])
		else:
			material_ids[material.material_id] = path

		for tool_type in material.tool_efficiencies.keys():
			var value: Variant = material.tool_efficiencies[tool_type]
			if not (value is int or value is float):
				_fail("%s: tool_efficiencies['%s'] must be numeric." %[path, tool_type])

func _validate_autoloads() -> void:
	for property_info in ProjectSettings.get_property_list():
		var property_name := String(property_info.get("name", ""))
		if not property_name.begins_with("autoload/"):
			continue
		var autoload_value := String(ProjectSettings.get_setting(property_name, ""))
		var resource_path := autoload_value.trim_prefix("*")
		if resource_path.is_empty():
			_fail("%s: autoload path is empty." % property_name)
			continue
		if resource_path.ends_with(".gd"):
			_validate_script(resource_path, "%s autoload" % property_name)
		elif resource_path.ends_with(".tscn"):
			_validate_packed_scene(resource_path, "%s autoload" % property_name)
		else:
			_fail("%s: unsupported autoload path %s." % [property_name, resource_path])

func _validate_project_scripts() -> void:
	for path in _collect_paths(PROJECT_ROOT, ".gd"):
		_validate_script(path, "project script")

func _validate_project_scenes() -> void:
	for path in _collect_paths(PROJECT_ROOT, ".tscn"):
		_validate_packed_scene(path, "project scene")

func _validate_recipes(item_types: Dictionary) -> void:
	var recipe_ids := {}
	for path in _collect_paths(RECIPES_DIR, ".tres"):
		var recipe := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as RecipeData
		if recipe == null:
			_fail("%s: failed to load as RecipeData." % path)
			continue
		if recipe.recipe_id.is_empty():
			_fail("%s: recipe_id is empty." % path)
		elif recipe_ids.has(recipe.recipe_id):
			_fail("%s: duplicate recipe_id '%s' also used by %s." %[path, recipe.recipe_id, recipe_ids[recipe.recipe_id]])
		else:
			recipe_ids[recipe.recipe_id] = path

		var req_item_type := recipe.get_required_item_type()
		if req_item_type.is_empty():
			_fail("%s: req_item_data is missing or has an empty item_type." % path)
		elif not item_types.has(req_item_type):
			_fail("%s: required item '%s' was not found in %s." %[path, req_item_type, ITEMS_DIR])

		match recipe.result_type:
			Defs.RECIPE_RESULT_ITEM:
				var result_item_type := recipe.get_result_item_type()
				if result_item_type.is_empty():
					_fail("%s: result_item_data is missing or has an empty item_type." % path)
				elif not item_types.has(result_item_type):
					_fail("%s: result item '%s' was not found in %s." %[path, result_item_type, ITEMS_DIR])
				else:
					var scene_path := str(item_types[result_item_type].get("scene_path", ""))
					if scene_path.is_empty():
						_fail("%s: could not resolve scene for result item '%s'." %[path, result_item_type])
					else:
						_validate_packed_scene(scene_path, "%s result item" % path)
			Defs.RECIPE_RESULT_TILE:
				pass
			_:
				_fail("%s: unsupported result_type '%s'." %[path, recipe.result_type])

# GAMEPLAY: every item_type referenced in Classes.DATA equipment must exist.
func _validate_classes(item_types: Dictionary) -> void:
	for class_key: String in Classes.DATA:
		var equipment: Dictionary = Classes.DATA[class_key].get("equipment", {})
		for slot_key: String in equipment:
			var item_type: String = str(equipment[slot_key])
			if not item_types.has(item_type):
				_fail("Classes['%s'].equipment['%s']: item_type '%s' not found in %s." %[class_key, slot_key, item_type, ITEMS_DIR])

# GAMEPLAY: clothing_offsets.json must parse and have a complete entry (all 4
# directions, valid offset array and positive scale) for every item_type key.
func _validate_clothing_offsets() -> void:
	const OFFSETS_PATH := "res://clothing/clothing_offsets.json"
	const DIRECTIONS: Array[String] =["north", "south", "east", "west"]
	if not ResourceLoader.exists(OFFSETS_PATH):
		_fail("%s: file missing." % OFFSETS_PATH)
		return
	var file := FileAccess.open(OFFSETS_PATH, FileAccess.READ)
	if file == null:
		_fail("%s: could not open." % OFFSETS_PATH)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		_fail("%s: JSON parse error at line %d: %s." %[OFFSETS_PATH, json.get_error_line(), json.get_error_message()])
		return
	var data: Variant = json.get_data()
	if not data is Dictionary:
		_fail("%s: root must be a JSON object." % OFFSETS_PATH)
		return
	for item_type: String in (data as Dictionary):
		var entry: Variant = data[item_type]
		if not entry is Dictionary:
			_fail("%s: entry for '%s' must be an object." %[OFFSETS_PATH, item_type])
			continue
		for dir in DIRECTIONS:
			if not (entry as Dictionary).has(dir):
				_fail("%s: '%s' missing direction '%s'." %[OFFSETS_PATH, item_type, dir])
				continue
			var d: Variant = (entry as Dictionary)[dir]
			if not d is Dictionary:
				_fail("%s: '%s.%s' must be an object." %[OFFSETS_PATH, item_type, dir])
				continue
			var offset: Variant = (d as Dictionary).get("offset")
			if not offset is Array or (offset as Array).size() != 2:
				_fail("%s: '%s.%s.offset' must be a 2-element array." % [OFFSETS_PATH, item_type, dir])
			var scale_val: Variant = (d as Dictionary).get("scale")
			if not (scale_val is float or scale_val is int) or float(scale_val) <= 0.0:
				_fail("%s: '%s.%s.scale' must be a positive number." % [OFFSETS_PATH, item_type, dir])

# GAMEPLAY: all coin stack icon images referenced by Defs helpers must exist.
func _validate_coin_icons() -> void:
	for threshold: int in Defs.COIN_STACK_ICON_THRESHOLDS:
		for suffix: String in Defs.COIN_METAL_SUFFIXES:
			var tex_path := "res://objects/coins/%d%s.png" % [threshold, suffix]
			_validate_texture(tex_path, "coin icon")

# GAMEPLAY: keyring icons keyring0.png .. keyringN.png must all exist.
func _validate_keyring_icons() -> void:
	for i in range(Defs.KEYRING_MAX_KEYS + 1):
		var tex_path := "res://objects/keys/keyring%d.png" % i
		_validate_texture(tex_path, "keyring icon")

# Every scene registered with MultiplayerSpawner must exist and instantiate cleanly.
func _validate_spawnable_scenes() -> void:
	for scene_path in NET_SPAWNABLE_SCENES:
		_validate_packed_scene(scene_path, "spawnable scene")

# Every scene in NET_SYNCED_SCENES must have a MultiplayerSynchronizer whose
# replication_config property paths all resolve to real properties on their
# target nodes.  A path like NodePath(".:tile_pos") breaks silently at runtime
# when the property is renamed; this check catches that at import time.
func _validate_replication_configs() -> void:
	for scene_path in NET_SYNCED_SCENES:
		if not ResourceLoader.exists(scene_path):
			continue
		var packed := ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
		if packed == null:
			continue
		var instance := packed.instantiate()
		if instance == null:
			continue

		var sync_node := _find_multiplayer_synchronizer(instance)
		if sync_node == null:
			_fail("%s: expected a MultiplayerSynchronizer but none found." % scene_path)
			instance.free()
			continue

		var config: SceneReplicationConfig = sync_node.get("replication_config")
		if config == null:
			_fail("%s: MultiplayerSynchronizer '%s' has no replication_config." %[scene_path, sync_node.name])
			instance.free()
			continue

		for prop_path: NodePath in config.get_properties():
			_validate_replication_property(scene_path, instance, prop_path)

		instance.free()

# NETCODE/PATCHING: every directory in GameVersion.RESOURCE_DIFF_DIRS must exist.
# If one is missing, build_manifest() silently skips it and clients never receive
# diffs for that content type — a silent desync on every server restart.
func _validate_resource_diff_dirs() -> void:
	for dir_path: String in GameVersion.RESOURCE_DIFF_DIRS:
		if DirAccess.open(dir_path) == null:
			_fail("GameVersion.RESOURCE_DIFF_DIRS: directory missing or inaccessible: %s." % dir_path)

func _validate_network_sync_behavior() -> void:
	var previous_main_scene := World.main_scene
	var previous_laws := World.current_laws.duplicate(true)
	var temp_root := Node.new()
	temp_root.name = "__SmokeNetRoot"

	var latejoin := _SmokeLateJoinStub.new()
	latejoin._reconnect = _SmokeReconnectStub.new()
	temp_root.add_child(latejoin)

	var sync = preload("res://scripts/net/latejoin_sync.gd").new(latejoin)
	var main_node := Node2D.new()
	main_node.name = "__SmokeMain"
	temp_root.add_child(main_node)
	World.register_main(main_node)
	World.current_laws =["Smoke law"]

	var loose_obj := _SmokeSyncObjectStub.new()
	loose_obj.name = "LooseObject"
	loose_obj.position = Vector2(12, 18)
	loose_obj.add_to_group("pickable")
	main_node.add_child(loose_obj)
	var loose_id := World.register_entity(loose_obj, "smoke:loose")

	var held_obj := _SmokeSyncObjectStub.new()
	held_obj.name = "HeldObject"
	held_obj.add_to_group("pickable")
	main_node.add_child(held_obj)
	var held_id := World.register_entity(held_obj, "smoke:held")

	var remote_hand := Node2D.new()
	remote_hand.name = "RemoteHand"
	temp_root.add_child(remote_hand)
	var remote_hand_id := World.register_entity(remote_hand, "smoke:remote_hand")

	var remote_player := _SmokePlayerStub.new()
	remote_player.name = "RemotePlayer"
	remote_player.position = Vector2(32, 48)
	remote_player.z_level = 4
	remote_player.health = 81
	remote_player.hands =[remote_hand, null]
	remote_player.equipped_data = {"head": {"item_type": "hood"}}
	remote_player.set_meta("smoke_hand_state",[{"entity_id": remote_hand_id, "name": "RemoteHand"}, null])
	remote_player.set_meta("smoke_equipped_state", {"head": {"item_type": "hood"}})
	remote_player.add_to_group("player")
	remote_player.set_multiplayer_authority(22)
	temp_root.add_child(remote_player)
	latejoin.players_by_peer[22] = remote_player

	var joining_player := _SmokePlayerStub.new()
	joining_player.name = "JoiningPlayer"
	joining_player.hands =[held_obj, null]
	joining_player.add_to_group("player")
	joining_player.set_multiplayer_authority(77)
	temp_root.add_child(joining_player)
	latejoin.players_by_peer[77] = joining_player

	var corpse := _SmokePlayerStub.new()
	corpse.name = "CorpsePlayer"
	corpse.is_possessed = false
	corpse.dead = true
	corpse.health = 0
	corpse.position = Vector2(80, 96)
	corpse.set_meta("smoke_capture_state", {
		"position": corpse.position,
		"health": corpse.health,
		"dead": corpse.dead,
	})
	corpse.add_to_group("player")
	temp_root.add_child(corpse)
	var corpse_id := World.register_entity(corpse, "smoke:corpse")

	latejoin._world_state["tiles"] = {
		"0_0_3": {
			"tile_pos": Vector2i.ZERO,
			"z_level": 3,
			"source_id": 1,
			"atlas_coords": Vector2i.ZERO,
		},
	}
	latejoin._world_state["objects"] = {
		"smoke/object/path": {"hits": 2},
	}

	var player_payload := sync._build_player_sync_state(remote_player)
	var built_hand_ids: Array = player_payload.get("hands",[])
	if built_hand_ids.is_empty() or str(built_hand_ids[0]) != remote_hand_id:
		_fail("LateJoinSync._build_player_sync_state: remote hand entity IDs were not captured correctly.")
	var equipped_payload: Dictionary = player_payload.get("equipped", {})
	var head_payload: Dictionary = equipped_payload.get("head", {})
	if str(head_payload.get("item_type", "")) != "hood":
		_fail("LateJoinSync._build_player_sync_state: equipped item payload did not round-trip reconnect capture data.")
	if player_payload.get("equipped_data", {}).get("head", {}).get("item_type", "") != "hood":
		_fail("LateJoinSync._build_player_sync_state: equipped_data was not copied from the player.")

	if sync._resolve_player_sync_target(22) != remote_player:
		_fail("LateJoinSync._resolve_player_sync_target: peer lookup did not resolve the possessed player.")
	if sync._resolve_player_sync_target(corpse_id) != corpse:
		_fail("LateJoinSync._resolve_player_sync_target: entity lookup did not resolve the corpse by stable ID.")

	sync._apply_synced_player_state(corpse, {
		"health": 13,
		"dead": false,
		"position": Vector2(5, 6),
	}, false)
	var restored_corpse_state: Dictionary = corpse.get_meta("smoke_restored_state", {})
	if int(restored_corpse_state.get("health", -1)) != 13:
		_fail("LateJoinSync._apply_synced_player_state: reconnect restore path did not receive the synced payload.")

	var loose_data := sync.get_object_sync_data(loose_obj)
	if str(loose_data.get("entity_id", "")) != loose_id:
		_fail("LateJoinSync.get_object_sync_data: loose object entity ID was not captured.")
	var loose_groups: Array = loose_data.get("groups",[])
	if not loose_groups.has("pickable"):
		_fail("LateJoinSync.get_object_sync_data: object groups were not captured.")

	var pre_add_payload := {
		"z_level": 5,
		"tree_id": "oak",
		"decor_configs": {"ivy": true},
	}
	sync._apply_pre_add_object_state(loose_obj, pre_add_payload)
	if loose_obj.z_level != 5 or loose_obj.tree_id != "oak":
		_fail("LateJoinSync._apply_pre_add_object_state: scalar pre-add state was not applied.")
	if loose_obj.decor_configs.get("ivy", false) != true:
		_fail("LateJoinSync._apply_pre_add_object_state: dictionary pre-add state was not applied.")
	pre_add_payload["decor_configs"]["ivy"] = false
	if loose_obj.decor_configs.get("ivy", false) != true:
		_fail("LateJoinSync._apply_pre_add_object_state: dictionary pre-add state was not deep-copied.")

	var existing_obj := _SmokeSyncObjectStub.new()
	existing_obj.name = "ExistingObject"
	existing_obj.z_level = 2
	existing_obj.z_index = 25
	existing_obj.contents = {"coins": 1}
	existing_obj.decor_configs = {"ivy": false}
	main_node.add_child(existing_obj)
	World.register_entity(existing_obj, "smoke:existing")

	var obj_data := {
		"name": "ExistingObject",
		"entity_id": "smoke:existing",
		"position": Vector2(90, 70),
		"z_level": 4,
		"z_index": 815,
		"hits": 7,
		"state": "open",
		"is_on": true,
		"stored_balance": 42,
		"contents": {"coins": 3},
		"decor_configs": {"ivy": true},
	}
	sync.handle_spawn_object_for_late_join(obj_data)

	if existing_obj.position != Vector2(90, 70):
		_fail("LateJoinSync.handle_spawn_object_for_late_join: existing object position was not updated.")
	if existing_obj.z_level != 4 or existing_obj.z_index != 815:
		_fail("LateJoinSync.handle_spawn_object_for_late_join: existing object z state was not updated.")
	if existing_obj.hits != 7 or existing_obj.state != "open":
		_fail("LateJoinSync.handle_spawn_object_for_late_join: existing object state fields were not applied.")
	if existing_obj.stored_balance != 42:
		_fail("LateJoinSync.handle_spawn_object_for_late_join: merchant balance was not restored.")
	if existing_obj.contents.get("coins", -1) != 3:
		_fail("LateJoinSync.handle_spawn_object_for_late_join: contents were not restored.")
	if existing_obj.decor_configs.get("ivy", false) != true:
		_fail("LateJoinSync.handle_spawn_object_for_late_join: decor configs were not restored.")
	if existing_obj.rebuild_calls <= 0:
		_fail("LateJoinSync.handle_spawn_object_for_late_join: decor rebuild hook was not triggered.")
	if existing_obj.sprite_updates <= 0:
		_fail("LateJoinSync.handle_spawn_object_for_late_join: sprite refresh hook was not triggered.")
	if existing_obj.solidity_updates <= 0:
		_fail("LateJoinSync.handle_spawn_object_for_late_join: solidity refresh hook was not triggered.")

	obj_data["contents"]["coins"] = 9
	obj_data["decor_configs"]["ivy"] = false
	if existing_obj.contents.get("coins", -1) != 3:
		_fail("LateJoinSync.handle_spawn_object_for_late_join: contents were not deep-copied from the incoming payload.")
	if existing_obj.decor_configs.get("ivy", false) != true:
		_fail("LateJoinSync.handle_spawn_object_for_late_join: decor configs were not deep-copied from the incoming payload.")

	World.current_laws = previous_laws
	if previous_main_scene != null:
		World.register_main(previous_main_scene)
	else:
		World.unregister_main()
	temp_root.free()

func _validate_resource_patching() -> void:
	var item_paths := _collect_paths(ITEMS_DIR, ".tres")
	var material_paths := _collect_paths(MATERIALS_DIR, ".tres")
	var recipe_paths := _collect_paths(RECIPES_DIR, ".tres")
	if item_paths.is_empty() or material_paths.is_empty() or recipe_paths.is_empty():
		_fail("GameVersion patch smoke: expected at least one item, material, and recipe resource.")
		return

	var item_path := item_paths[0]
	var material_path := material_paths[0]
	var recipe_path := recipe_paths[0]

	var item_original := ResourceLoader.load(item_path, "", ResourceLoader.CACHE_MODE_REPLACE) as ItemData
	var material_original := ResourceLoader.load(material_path, "", ResourceLoader.CACHE_MODE_REPLACE) as MaterialData
	var recipe_original := ResourceLoader.load(recipe_path, "", ResourceLoader.CACHE_MODE_REPLACE) as RecipeData
	if item_original == null or material_original == null or recipe_original == null:
		_fail("GameVersion patch smoke: failed to load baseline item/material/recipe resources.")
		return

	var baseline_item := ItemRegistry.get_by_type(item_original.item_type)
	var baseline_material := MaterialRegistry.get_material(material_original.material_id)
	var baseline_recipe := RecipeRegistry.get_recipe(recipe_original.recipe_id)
	if baseline_item == null or baseline_material == null or baseline_recipe == null:
		_fail("GameVersion patch smoke: registries were missing baseline resources before patching.")
		return

	var manifest := GameVersion.build_manifest()
	if not manifest.has(item_path):
		_fail("GameVersion.build_manifest: item resource %s was not included in the manifest." % item_path)
	var client_manifest := manifest.duplicate(true)
	client_manifest[item_path] = "__smoke_mismatch__"
	var built_diff := GameVersion.build_diff(manifest, client_manifest)
	if not built_diff.has(item_path):
		_fail("GameVersion.build_diff: changed item resource %s did not produce a diff." % item_path)
	else:
		var serialized_item: Dictionary = built_diff[item_path]
		if str(serialized_item.get("item_type", "")) != item_original.item_type:
			_fail("GameVersion.build_diff: serialized item payload lost the item_type for %s." % item_path)

	var patched_item_description := "smoke patched: " + baseline_item.description
	var patched_material_name := "Smoke " + baseline_material.display_name
	var patched_recipe_name := "Smoke " + baseline_recipe.display_name
	var patched_efficiencies := baseline_material.tool_efficiencies.duplicate(true)
	patched_efficiencies["smoke_tool"] = 1.25

	GameVersion.apply_resource_diff({
		item_path: {
			"item_type": item_original.item_type,
			"scene_path": item_original.scene_path,
			"description": patched_item_description,
			"material_data": material_path,
			"pickable": item_original.pickable,
		},
		material_path: {
			"material_id": material_original.material_id,
			"display_name": patched_material_name,
			"tool_efficiencies": patched_efficiencies,
		},
		recipe_path: {
			"recipe_id": recipe_original.recipe_id,
			"display_name": patched_recipe_name,
			"result_type": recipe_original.result_type,
		},
	})

	var patched_item := ItemRegistry.get_by_type(item_original.item_type)
	if patched_item == null or patched_item.description != patched_item_description:
		_fail("GameVersion.apply_resource_diff: item registry was not updated for %s." % item_original.item_type)
	elif patched_item.material_data == null or patched_item.material_data.resource_path != material_path:
		_fail("GameVersion.apply_resource_diff: item resource path properties were not reloaded correctly for %s." % item_original.item_type)

	var patched_material := MaterialRegistry.get_material(material_original.material_id)
	if patched_material == null or patched_material.display_name != patched_material_name:
		_fail("GameVersion.apply_resource_diff: material registry was not updated for %s." % material_original.material_id)
	elif not is_equal_approx(float(patched_material.tool_efficiencies.get("smoke_tool", 0.0)), 1.25):
		_fail("GameVersion.apply_resource_diff: material dictionary fields were not applied for %s." % material_original.material_id)

	var patched_recipe := RecipeRegistry.get_recipe(recipe_original.recipe_id)
	if patched_recipe == null or patched_recipe.display_name != patched_recipe_name:
		_fail("GameVersion.apply_resource_diff: recipe registry was not updated for %s." % recipe_original.recipe_id)

	ItemRegistry.reload()
	MaterialRegistry.reload()
	RecipeRegistry.reload()

	var restored_item := ItemRegistry.get_by_type(item_original.item_type)
	var restored_material := MaterialRegistry.get_material(material_original.material_id)
	var restored_recipe := RecipeRegistry.get_recipe(recipe_original.recipe_id)
	if restored_item == null or restored_item.description != baseline_item.description:
		_fail("GameVersion patch smoke: ItemRegistry.reload() did not restore on-disk item data.")
	if restored_material == null or restored_material.display_name != baseline_material.display_name:
		_fail("GameVersion patch smoke: MaterialRegistry.reload() did not restore on-disk material data.")
	if restored_recipe == null or restored_recipe.display_name != baseline_recipe.display_name:
		_fail("GameVersion patch smoke: RecipeRegistry.reload() did not restore on-disk recipe data.")

func _validate_replication_property(scene_path: String, root: Node, prop_path: NodePath) -> void:
	var path_str := str(prop_path)
	var colon_idx := path_str.find(":")
	if colon_idx == -1:
		_fail("%s: replication property '%s' has no ':' separator between node path and property name." %[scene_path, path_str])
		return

	var node_path_str := path_str.substr(0, colon_idx)
	var prop_name := path_str.substr(colon_idx + 1)

	var target: Node
	if node_path_str == "." or node_path_str.is_empty():
		target = root
	else:
		target = root.get_node_or_null(NodePath(node_path_str))

	if target == null:
		_fail("%s: replication property '%s' — node '%s' not found in scene." %[scene_path, path_str, node_path_str])
		return

	var found := false
	for pi: Dictionary in target.get_property_list():
		if pi["name"] == prop_name:
			found = true
			break

	if not found:
		_fail("%s: replication property '%s' — '%s' does not exist on node '%s'." % [scene_path, path_str, prop_name, target.name])

# Returns the first MultiplayerSynchronizer descendant of root, or null.
func _find_multiplayer_synchronizer(root: Node) -> MultiplayerSynchronizer:
	if root is MultiplayerSynchronizer:
		return root as MultiplayerSynchronizer
	for child in root.get_children():
		var result := _find_multiplayer_synchronizer(child)
		if result != null:
			return result
	return null

func _validate_packed_scene(scene_path: String, context: String) -> void:
	if _validated_scene_paths.has(scene_path):
		return
	_validated_scene_paths[scene_path] = true
	if not ResourceLoader.exists(scene_path):
		_fail("%s: missing scene %s." %[context, scene_path])
		return
	var scene := ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if scene == null:
		_fail("%s: failed to load scene %s." % [context, scene_path])
		return
	var instance := scene.instantiate()
	if instance == null:
		_fail("%s: failed to instantiate scene %s." % [context, scene_path])
		return
	instance.free()

func _validate_texture(texture_path: String, context: String) -> void:
	if _validated_texture_paths.has(texture_path):
		return
	_validated_texture_paths[texture_path] = true
	if not ResourceLoader.exists(texture_path):
		_fail("%s: missing texture %s." % [context, texture_path])
		return
	var texture := ResourceLoader.load(texture_path, "", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D
	if texture == null:
		_fail("%s: failed to load texture %s." %[context, texture_path])

func _validate_script(script_path: String, context: String) -> void:
	if _validated_script_paths.has(script_path):
		return
	_validated_script_paths[script_path] = true
	if not ResourceLoader.exists(script_path):
		_fail("%s: missing script %s." % [context, script_path])
		return
	var script := ResourceLoader.load(script_path, "", ResourceLoader.CACHE_MODE_REPLACE) as Script
	if script == null:
		_fail("%s: failed to load script %s." %[context, script_path])

func _collect_paths(root_path: String, extension: String) -> Array[String]:
	var paths: Array[String] =[]
	_collect_paths_recursive(root_path, extension, paths)
	paths.sort()
	return paths

func _collect_paths_recursive(root_path: String, extension: String, out_paths: Array[String]) -> void:
	var dir := DirAccess.open(root_path)
	if dir == null:
		_fail("Could not open directory %s." % root_path)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name in[".", ".."]:
			name = dir.get_next()
			continue
		var child_path := "%s/%s" %[root_path, name]
		if dir.current_is_dir():
			_collect_paths_recursive(child_path, extension, out_paths)
		elif name.ends_with(extension) or name.ends_with("%s.remap" % extension):
			out_paths.append(child_path.replace(".remap", ""))
		name = dir.get_next()
	dir.list_dir_end()

func _fail(message: String) -> void:
	_errors.append(message)