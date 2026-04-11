extends Node

const LOG_PATH := "res://import_smoke_test.log"
const FLAG_PATH := "res://run_import_smoke_test.flag"
const VALIDATOR_SCRIPT := "res://scripts/tools/import_smoke_test.gd"

func _ready() -> void:
	var should_run := OS.get_cmdline_user_args().has("--validate-imports") or OS.get_environment("CODEX_VALIDATE_IMPORTS") == "1" or FileAccess.file_exists(ProjectSettings.globalize_path(FLAG_PATH))
	if not should_run:
		return

	var validator_script := load(VALIDATOR_SCRIPT)
	if validator_script == null:
		push_error("Import smoke test failed: could not load %s." % VALIDATOR_SCRIPT)
		_clear_flag()
		get_tree().quit(1)
		return

	var validator = validator_script.new()
	var result: Dictionary = validator.run()
	var warnings: Array = result.get("warnings", [])
	var errors: Array = result.get("errors", [])
	var log_lines: PackedStringArray = []

	log_lines.append("Import smoke test started.")
	log_lines.append("User args: %s" % str(OS.get_cmdline_user_args()))

	if warnings.size() > 0:
		print("Import smoke test warnings:")
		log_lines.append("Warnings:")
		for warning in warnings:
			print("  WARN: %s" % str(warning))
			log_lines.append("WARN: %s" % str(warning))

	if errors.size() > 0:
		push_error("Import smoke test failed with %d error(s)." % errors.size())
		log_lines.append("FAILED with %d error(s)." % errors.size())
		for err in errors:
			push_error("  %s" % str(err))
			log_lines.append("ERROR: %s" % str(err))
		_write_log(log_lines)
		_clear_flag()
		get_tree().quit(1)
		return

	print("Import smoke test passed.")
	log_lines.append("PASSED")
	_write_log(log_lines)
	_clear_flag()
	get_tree().quit(0)

func _write_log(lines: PackedStringArray) -> void:
	var file := FileAccess.open(ProjectSettings.globalize_path(LOG_PATH), FileAccess.WRITE)
	if file == null:
		return
	for line in lines:
		file.store_line(line)

func _clear_flag() -> void:
	var flag_path := ProjectSettings.globalize_path(FLAG_PATH)
	if FileAccess.file_exists(flag_path):
		DirAccess.remove_absolute(flag_path)
