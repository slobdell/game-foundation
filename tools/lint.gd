extends SceneTree
## `make lint`: compile every GDScript file in the project and report any that fail.
##
## Runs INSIDE the project (so autoloads like Game and Sound exist, which `godot --check-only` cannot see).
## A checker that never reports anything cannot be told from a checker that did not look (Tank Squad, 2026-09-20:
## lint said "all scripts parse" on a tree that could not compile). So every run ALSO compiles a deliberately broken
## probe file and FAILS unless that probe is caught. A gate that cannot be shown to fail is not a gate.

const SKIP := ["res://.godot", "res://.tools", "res://build", "res://node_modules"]
const PROBE := "res://build/lint/probe_broken.gd"


class Collector extends Logger:
	var messages: PackedStringArray = []
	var _mutex := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		messages.append("%s:%d %s" % [file, line, rationale if rationale != "" else code])
		_mutex.unlock()

	func take() -> PackedStringArray:
		_mutex.lock()
		var out := messages
		messages = []
		_mutex.unlock()
		return out


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var log := Collector.new()
	OS.add_logger(log)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROBE.get_base_dir()))
	var probe := FileAccess.open(PROBE, FileAccess.WRITE)
	probe.store_string("extends Node\nfunc _ready() -> void:\n\tvar x: int = \"not a number\"\n")
	probe.close()
	if _compiles(PROBE, log).is_empty():
		print("lint FAILED: the deliberately broken probe compiled cleanly, so the checker cannot see errors right now.")
		quit(1)
		return
	var files := _discover("res://")
	var bad := 0
	for path in files:
		var problems := _compiles(path, log)
		if not problems.is_empty():
			bad += 1
			print("  %s" % path)
			for p in problems.slice(0, 6):
				print("      ", p)
	if bad > 0:
		print("lint FAILED: %d of %d scripts have errors (above)" % [bad, files.size()])
		quit(1)
		return
	print("lint: all %d scripts compile (and the broken probe was caught)" % files.size())
	quit(0)


## The errors compiling [param path] produced (empty = fine).
func _compiles(path: String, log: Collector) -> PackedStringArray:
	log.take()
	var script := ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
	var problems := log.take()
	if script == null and problems.is_empty():
		problems.append("did not load")
	elif script != null and not script.can_instantiate() and problems.is_empty():
		problems.append("does not compile")
	return problems


func _discover(dir_path: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for skip: String in SKIP:
		if dir_path.trim_suffix("/") == skip:
			return found
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	if dir.file_exists(".gdignore"):
		return found
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			found.append_array(_discover(dir_path.path_join(sub)))
	for file in dir.get_files():
		# Not this script itself: re-compiling the running script crashes the engine.
		if file.ends_with(".gd") and dir_path.path_join(file) != get_script().resource_path:
			found.append(dir_path.path_join(file))
	found.sort()
	return found
