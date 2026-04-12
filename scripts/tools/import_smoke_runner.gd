extends Node

const LOG_PATH := "res://import_smoke_test.log"
const FLAG_PATH := "res://run_import_smoke_test.flag"
const VALIDATOR_SCRIPT := "res://scripts/tools/import_smoke_test.gd"

const DIVIDER := "============================================================"
const THIN := "------------------------------------------------------------"

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
	var sections: Array = result.get("sections", [])

	var passed_count := 0
	var _failed_count := 0
	for section in sections:
		if int(section.get("errors", 1)) == 0:
			passed_count += 1
		else:
			_failed_count += 1

	var log_lines: PackedStringArray = []

	log_lines.append(DIVIDER)
	log_lines.append("  ROGUETOWN SMOKE TEST")
	log_lines.append(DIVIDER)

	for section in sections:
		var section_name: String = section.get("name", "?")
		var errs: int = int(section.get("errors", 0))
		if errs == 0:
			log_lines.append("[ PASS ]  %s" % section_name)
		else:
			log_lines.append("[ FAIL ]  %s  -  %d error(s)" % [section_name, errs])

	log_lines.append(THIN)

	if warnings.size() > 0:
		for warning in warnings:
			log_lines.append("WARN: %s" % str(warning))
		log_lines.append(THIN)

	if errors.size() > 0:
		for err in errors:
			log_lines.append("ERROR: %s" % str(err))
		log_lines.append(THIN)

	var verdict: String
	if errors.size() == 0:
		verdict = "PASSED  -  %d/%d checks passed,  0 error(s)" % [passed_count, sections.size()]
	else:
		verdict = "FAILED  -  %d/%d checks passed,  %d error(s)" % [passed_count, sections.size(), errors.size()]
	log_lines.append(verdict)
	log_lines.append(DIVIDER)

	for line in log_lines:
		if line.begins_with("ERROR:") or line.begins_with("[ FAIL ]"):
			push_error(line)
		else:
			print(line)

	_write_log(log_lines)
	_clear_flag()
	get_tree().quit(1 if errors.size() > 0 else 0)

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
