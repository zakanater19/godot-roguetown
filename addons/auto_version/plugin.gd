@tool
extends EditorPlugin

const VERSION_FILE := "res://scripts/net/game_version.gd"

var _export_plugin: _AutoVersionExport


func _enter_tree() -> void:
	_export_plugin = _AutoVersionExport.new(self)
	add_export_plugin(_export_plugin)
	_stamp(false)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


func _stamp(from_export: bool) -> void:
	var v: String = _get_version(from_export)
	_patch_version(v)
	print("AutoVersion: APP_VERSION = %s  (%s)" % [v, "export" if from_export else "editor load"])


func _get_version(force_timestamp: bool) -> String:
	if not force_timestamp:
		# In-editor: stable git hash so version doesn't change mid-session.
		var output: Array = []
		var ret: int = OS.execute("git", ["rev-parse", "--short", "HEAD"], output, true)
		if ret == 0 and output.size() > 0:
			var hash: String = (output[0] as String).strip_edges()
			if hash.length() >= 4:
				return hash
	# Export (or no git): fresh timestamp — every export is a unique version.
	return str(int(Time.get_unix_time_from_system()))


func _patch_version(version: String) -> void:
	var fa := FileAccess.open(VERSION_FILE, FileAccess.READ)
	if fa == null:
		push_error("AutoVersion: cannot open %s" % VERSION_FILE)
		return
	var text: String = fa.get_as_text()
	fa.close()

	var rx := RegEx.new()
	rx.compile('(const APP_VERSION: String = ")[^"]*(")')
	if rx.search(text) == null:
		push_error("AutoVersion: APP_VERSION line not found in %s" % VERSION_FILE)
		return

	text = rx.sub(text, "${1}" + version + "${2}")

	fa = FileAccess.open(VERSION_FILE, FileAccess.WRITE)
	if fa == null:
		push_error("AutoVersion: cannot write %s" % VERSION_FILE)
		return
	fa.store_string(text)
	fa.close()


class _AutoVersionExport extends EditorExportPlugin:
	var _plugin: Node

	func _init(plugin: Node) -> void:
		_plugin = plugin

	func _get_name() -> String:
		return "AutoVersion"

	func _export_begin(_features: PackedStringArray, _is_debug: bool,
			_path: String, _flags: int) -> void:
		_plugin._stamp(true)
