extends SceneTree
## Headless test runner: `make test` (FILTER=word runs only tests whose "file::method" contains it; | = or).
##
## Finds res://tests/**/test_*.gd, runs every `test_*` method on a fresh instance, prints PASS/FAIL per test and
## one final line `N passed, M failed`. Exit code 1 if anything failed.
##
## Rules learned the hard way on Tank Squad, each of which once let a broken tree print "all passed":
## - An engine/script error during a test FAILS that test (a crash inside a test records no assertion).
## - A test file that does not load, or has no test_ methods (what a parse error leaves), is a FAILURE.
## - A FILTER that matches nothing is a FAILURE, not "0 passed, 0 failed".

const ALLOWLIST := "res://tests/baselines/engine_expected.txt"
const TEST_ROOT := "res://tests"


class ErrorCollector extends Logger:
	var entries: Array[Dictionary] = []
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		entries.append({
			"warning": error_type == Logger.ERROR_TYPE_WARNING,
			"text": "%s (%s:%d in %s)" % [rationale if rationale != "" else code, file, line, function],
		})
		_mutex.unlock()

	func take() -> Array[Dictionary]:
		_mutex.lock()
		var taken := entries
		entries = []
		_mutex.unlock()
		return taken


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var errors := ErrorCollector.new()
	OS.add_logger(errors)
	var filter_parts := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			for part in arg.trim_prefix("--filter=").split("|", false):
				if part.strip_edges() != "":
					filter_parts.append(part.strip_edges())
	var allowed := _read_allowlist()
	var passed := 0
	var failed := 0
	for path in _discover(TEST_ROOT):
		var stem := path.get_file().get_basename()
		var script: GDScript = load(path)
		if script == null:
			failed += 1
			print("  FAIL  %s::<file>\n          the file did not load (a parse error?)" % stem)
			continue
		var methods: Array[String] = []
		for method in script.get_script_method_list():
			if String(method["name"]).begins_with("test_"):
				methods.append(String(method["name"]))
		if methods.is_empty():
			if _matches(stem, filter_parts):
				failed += 1
				print("  FAIL  %s::<file>\n          no test_ methods: a parse error leaves a script with none" % stem)
			continue
		for method_name in methods:
			var label := "%s::%s" % [stem, method_name]
			if not _matches(label, filter_parts):
				continue
			var case: TestCase = script.new()
			case.tree = self
			errors.take()
			await case.call(method_name)
			await case._teardown()
			var engine: Dictionary = TestCase.reconcile_engine_messages(
					errors.take(), case.expected_warnings, case.expected_errors, allowed)
			case.failures.append_array(PackedStringArray(engine["failures"]))
			if case.failures.is_empty():
				passed += 1
				print("  PASS  ", label)
			else:
				failed += 1
				print("  FAIL  ", label)
				for failure in case.failures:
					print("          ", failure)
	print("\n%d passed, %d failed" % [passed, failed])
	if not filter_parts.is_empty() and passed + failed == 0:
		print("FILTER MATCHED NO TESTS (%s). Zero tests is not a pass." % ", ".join(filter_parts))
		quit(1)
		return
	quit(1 if failed > 0 else 0)


static func _matches(label: String, parts: PackedStringArray) -> bool:
	if parts.is_empty():
		return true
	for part in parts:
		if label.contains(part):
			return true
	return false


func _read_allowlist() -> PackedStringArray:
	var patterns: PackedStringArray = []
	var file := FileAccess.open(ALLOWLIST, FileAccess.READ)
	if file == null:
		return patterns
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line != "" and not line.begins_with("#"):
			patterns.append(line)
	return patterns


func _discover(dir_path: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for sub in dir.get_directories():
		found.append_array(_discover(dir_path.path_join(sub)))
	for file in dir.get_files():
		# test_case.gd is the base class every test extends, not a test itself.
		if file.begins_with("test_") and file.ends_with(".gd") and file != "test_case.gd":
			found.append(dir_path.path_join(file))
	found.sort()
	return found
