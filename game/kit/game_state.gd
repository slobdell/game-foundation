extends Node
## AUTOLOAD `Game`: everything the player has and has done. Inventory, flags, what was built where.
##
## Anything that happens in the world calls `Game.report(kind, data)` ("collected", "talked", "reached", "built"),
## and the mission system listens. Nothing else needs to know about missions, which is why adding a new kind of
## thing to do is easy.
##
## Saves to user://save.json (on Linux: ~/.local/share/godot/app_userdata/<game name>/).

signal inventory_changed(item: String, count: int)
signal flag_changed(flag: String, value: Variant)
## Something happened in the world. Missions listen to this.
signal event(kind: String, data: Dictionary)

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1

var inventory := {}
var flags := {}
## level id -> Array of {"piece": id, "pos": [x, y, z], "turns": int} (see game/kit/build/build_mode.gd)
var placed := {}
## Harness runs (tests, screenshots) turn this off so they never touch the player's real save.
var saving_enabled := true


func give(item: String, amount: int = 1) -> void:
	inventory[item] = count(item) + amount
	inventory_changed.emit(item, count(item))


## Removes [param amount] if the player has it all, and returns whether it did.
func take(item: String, amount: int = 1) -> bool:
	if count(item) < amount:
		return false
	inventory[item] = count(item) - amount
	inventory_changed.emit(item, count(item))
	return true


func count(item: String) -> int:
	return int(inventory.get(item, 0))


func set_flag(flag: String, value: Variant = true) -> void:
	flags[flag] = value
	flag_changed.emit(flag, value)


func get_flag(flag: String, default: Variant = false) -> Variant:
	return flags.get(flag, default)


func report(kind: String, data: Dictionary = {}) -> void:
	event.emit(kind, data)


func reset() -> void:
	inventory.clear()
	flags.clear()
	placed.clear()
	Missions.reset()


func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"inventory": inventory.duplicate(true),
		"flags": flags.duplicate(true),
		"placed": placed.duplicate(true),
		"missions": Missions.to_dict(),
		"level": Levels.current_id,
	}


func from_dict(data: Dictionary) -> void:
	reset()
	for key: String in data.get("inventory", {}):
		inventory[key] = int(data["inventory"][key])
	flags = data.get("flags", {}).duplicate(true)
	placed = data.get("placed", {}).duplicate(true)
	Missions.from_dict(data.get("missions", {}))


func save(path: String = SAVE_PATH) -> bool:
	if not saving_enabled:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("could not save to %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(to_dict(), "  "))
	return true


## Loads a save if there is one. Returns the level the player was in ("" if no save).
func load_save(path: String = SAVE_PATH) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		print("save file %s is unreadable; starting fresh" % path)
		return ""
	from_dict(data)
	return String(data.get("level", ""))
