class_name LaunchFlags
## Command-line flags after `--`, e.g. `godot --path . -- --level=meadow --screenshot=/tmp/a.png`.
## Every make target that launches the game passes its options this way, so anything you can do by hand
## you can also script (and so can Claude, to check its own work).

var _values := {}


func _init(args: PackedStringArray = OS.get_cmdline_user_args()) -> void:
	for arg in args:
		if not arg.begins_with("--"):
			continue
		var body := arg.substr(2)
		var eq := body.find("=")
		if eq < 0:
			_values[body] = "true"
		else:
			_values[body.substr(0, eq)] = body.substr(eq + 1)


func has(flag: String) -> bool:
	return _values.has(flag)


func text(flag: String, default: String = "") -> String:
	return String(_values.get(flag, default))


func number(flag: String, default: float = 0.0) -> float:
	return float(_values[flag]) if _values.has(flag) else default
