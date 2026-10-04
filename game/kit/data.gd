class_name GameData
## Reads the game's data files (data/*.json): items, levels, missions, dialogue, slots, build pieces.
##
## The game's CONTENT lives in data files and its RULES live in scripts, so adding a level, an item or a mission
## is usually a data change plus a test, not new code. Files are cached after the first read.

static var _cache := {}


## The parsed JSON at [param path] (a res:// path), or null if it is missing or broken (and says why, loudly).
static func load_json(path: String) -> Variant:
	if _cache.has(path):
		return _cache[path]
	if not FileAccess.file_exists(path):
		push_error("data file missing: %s" % path)
		return null
	var json := JSON.new()
	var err := json.parse(FileAccess.get_file_as_string(path))
	if err != OK:
		push_error("data file %s is not valid JSON: line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	_cache[path] = json.data
	return json.data


## Like load_json but returns {} for a missing file without complaining (for optional files).
static func load_optional(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = load_json(path)
	return data if data is Dictionary else {}


static func clear_cache() -> void:
	_cache.clear()


## Keys starting with "_" are comments ("_about") and are skipped.
static func entries(data: Variant) -> Dictionary:
	var out := {}
	if data is Dictionary:
		for key: String in data:
			if not key.begins_with("_"):
				out[key] = data[key]
	return out


static func items() -> Dictionary:
	return entries(load_json("res://data/items.json"))


static func slots() -> Dictionary:
	return entries(load_json("res://data/slots.json"))


static func levels() -> Dictionary:
	var data: Variant = load_json("res://data/levels.json")
	return entries(data["levels"]) if data is Dictionary and data.has("levels") else {}


static func start_level() -> String:
	var data: Variant = load_json("res://data/levels.json")
	return String(data.get("start", "")) if data is Dictionary else ""


static func missions() -> Array:
	var data: Variant = load_json("res://data/missions.json")
	return data.get("missions", []) if data is Dictionary else []


static func dialogue(id: String) -> Dictionary:
	var data: Variant = load_json("res://data/dialogue/%s.json" % id)
	return data if data is Dictionary else {}


static func pieces() -> Dictionary:
	var data: Variant = load_json("res://data/pieces.json")
	return data if data is Dictionary else {}


## A display name for an item id ("star" -> "Star"), from items.json when it has one.
static func item_name(id: String, count: int = 1) -> String:
	var item: Dictionary = items().get(id, {})
	if count != 1 and item.has("plural"):
		return String(item["plural"])
	return String(item.get("name", id.capitalize()))
