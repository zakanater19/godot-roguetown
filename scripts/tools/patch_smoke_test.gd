extends Node

# run_patch_smoketest.ps1 supplies an isolated project, export and user data.
var _test_root: String
var _deadline: int
var _server: bool
var _boot: int = 0
var _expected: String = ""


func _ready() -> void:
	_test_root = OS.get_environment("ROGUETOWN_PATCH_TEST_ROOT")
	if _test_root.is_empty():
		get_tree().quit(1)
		return
	_deadline = Time.get_ticks_msec() + 180000
	_server = OS.get_cmdline_user_args().has("--patch-smoke-server")
	set_process(false)
	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--patch-smoke-invalid"):
		if PatchBoot.boot_error.is_empty() or GameVersion.patch_applied:
			_fail("A missing/damaged saved update was not rejected before loading gameplay.")
			return
		print("PATCH_SMOKE_PASS: invalid saved update falls back to the base game")
		get_tree().quit()
		return
	# Exercise the real menu reconnect and BootstrapNet RPCs without loading a
	# world: these checks concern boot/patch transport, not world replication.
	LateJoin.set_process(false)
	var menu := get_tree().current_scene
	if multiplayer.connected_to_server.is_connected(menu._on_connected_to_server):
		multiplayer.connected_to_server.disconnect(menu._on_connected_to_server)
	multiplayer.connected_to_server.connect(_connected_without_world.bind(menu))
	var port := int(FileAccess.get_file_as_string(_test_root.path_join("port.txt")))
	if _server:
		var peer := ENetMultiplayerPeer.new()
		if peer.create_server(port, 8, 3) != OK:
			_fail("Could not start the test server.")
			return
		Host.is_host_mode = true
		multiplayer.multiplayer_peer = peer
		if GameVersion.generate_server_pck() != OK:
			_fail("Could not generate the server bundle.")
			return
		PatchBoot.write_json(_test_root.path_join("server_ready.json"), {"version": GameVersion.get_version()})
	else:
		var previous := PatchBoot.read_json("user://patch_smoke_boots.json")
		_boot = int(previous.get("boots", 0)) + 1
		PatchBoot.write_json("user://patch_smoke_boots.json", {"boots": _boot})
		_expected = str(PatchBoot.read_json(_test_root.path_join("server_ready.json")).get("version", ""))
		if _expected.is_empty() or _boot > 3:
			_fail("Missing server version or a repeated patch/restart loop.")
			return
		if _boot > 1:
			if not GameVersion.patch_applied or GameVersion.get_version() != _expected:
				_fail("The downloaded version did not survive startup.")
				return
			var resource: Resource = ItemRegistry.get_script().get_script_constant_map().get("PATCH_SMOKE_RESOURCE")
			if resource == null or resource.get("label") != "new class from patch" or not resource.get("texture") is Texture2D:
				_fail("The updated early autoload/new class/imported texture did not load.")
				return
			if ResourceLoader.exists("res://scripts/tools/patch_smoke_obsolete.gd"):
				_fail("A removed file from the old export is still visible.")
				return
		# The replacement boot reconnects through the real saved menu marker.
		# The initial and later manual launches use the menu's normal join path.
		if _boot != 2:
			menu._begin_client_connection("127.0.0.1", port)
	set_process(true)


func _connected_without_world(menu: Node) -> void:
	menu._is_connecting = false


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > _deadline:
		_fail("Timed out waiting for the download/restart/reconnect.")
		return
	if _server:
		return
	if _boot > 1 and BootstrapNet._pck_total_chunks > 0:
		_fail("The already patched client tried to download again.")
		return
	if BootstrapNet.version_checked:
		if _boot == 1 or GameVersion.get_version() != _expected:
			_fail("The server accepted an outdated client.")
			return
		PatchBoot.write_json(_test_root.path_join("client_pass_%d.json" % _boot), {
			"version": GameVersion.get_version(), "boot": _boot, "pid": OS.get_process_id(),
		})
		print("PATCH_SMOKE_PASS: boot ", _boot)
		set_process(false)
		get_tree().quit()


func _fail(message: String) -> void:
	PatchBoot.write_json(_test_root.path_join("failure.json"), {"message": message, "boot": _boot})
	push_error("PATCH_SMOKE_FAIL: " + message)
	set_process(false)
	get_tree().quit(1)
