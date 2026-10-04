extends TestCase
## The data files agree with each other. When Claude (or you) adds an item, a level, a mission or a line of dialogue,
## these tests catch a typo before the game does something confusing.


func test_every_data_file_is_valid_json() -> void:
	for path in _json_files("res://data"):
		var json := JSON.new()
		assert_eq(json.parse(FileAccess.get_file_as_string(path)), OK,
				"%s is not valid JSON (line %d: %s)" % [path, json.get_error_line(), json.get_error_message()])


func test_items_and_pieces_use_real_slots() -> void:
	var slots := GameData.slots()
	for id: String in GameData.items():
		var slot := String(GameData.items()[id].get("slot", ""))
		assert_true(slot == "" or slots.has(slot), "item '%s' uses slot '%s', which is not in data/slots.json" % [id, slot])
	for piece: Dictionary in GameData.pieces().get("pieces", []):
		assert_true(slots.has(piece.get("slot", "")), "build piece '%s' uses an unknown slot" % piece.get("id"))
		for item: String in piece.get("cost", {}):
			assert_true(GameData.items().has(item), "build piece '%s' costs '%s', which is not in data/items.json" % [piece.get("id"), item])


func test_every_slot_has_a_size() -> void:
	for id: String in GameData.slots():
		var size: Array = GameData.slots()[id].get("size_m", [])
		assert_eq(size.size(), 3, "slot '%s' needs size_m [width, height, depth]" % id)


func test_levels_exist_and_have_a_spawn_point() -> void:
	assert_true(GameData.levels().has(GameData.start_level()), "the start level '%s' is a level" % GameData.start_level())
	for id: String in GameData.levels():
		var info: Dictionary = GameData.levels()[id]
		var packed: PackedScene = load(String(info["scene"]))
		assert_true(packed != null, "level '%s': scene %s loads" % [id, info["scene"]])
		if packed == null:
			continue
		var level := packed.instantiate()
		assert_true(Levels.find_spawn(level, "") != null, "level '%s' has a Marker3D in the 'spawn' group" % id)
		for portal in level.find_children("*", "Area3D", true, false):
			if portal is Portal:
				assert_true(GameData.levels().has(portal.to_level), "portal %s in '%s' goes to unknown level '%s'" % [portal.name, id, portal.to_level])
		level.free()


func test_missions_refer_to_things_that_exist() -> void:
	var seen := {}
	for mission: Dictionary in GameData.missions():
		var id := String(mission.get("id", ""))
		assert_false(seen.has(id), "mission id '%s' is used twice" % id)
		seen[id] = true
		assert_false(mission.get("steps", []).is_empty(), "mission '%s' has steps" % id)
		for step: Dictionary in mission.get("steps", []):
			assert_true(step.get("do") in ["collect", "talk", "reach", "build", "defeat", "flag"], "mission '%s': unknown step kind '%s'" % [id, step.get("do")])
			assert_true(step.has("text"), "mission '%s': every step needs a text for the HUD" % id)
			if step.get("do") == "collect":
				assert_true(GameData.items().has(step.get("item", "")), "mission '%s' collects unknown item '%s'" % [id, step.get("item")])
		for item: String in mission.get("reward", {}).get("items", {}):
			assert_true(GameData.items().has(item), "mission '%s' rewards unknown item '%s'" % [id, item])
	for mission: Dictionary in GameData.missions():
		var next := String(mission.get("reward", {}).get("start_mission", ""))
		assert_true(next == "" or seen.has(next), "mission '%s' starts unknown mission '%s'" % [mission.get("id"), next])


func test_dialogue_files_are_well_formed() -> void:
	var missions := {}
	for mission: Dictionary in GameData.missions():
		missions[mission["id"]] = true
	for path in _json_files("res://data/dialogue"):
		var data: Dictionary = GameData.load_json(path)
		assert_eq(String(data.get("id", "")), path.get_file().get_basename(), "%s: id matches the file name" % path)
		for block: Dictionary in [data] + Array(data.get("variants", [])):
			assert_false(block.get("lines", []).is_empty(), "%s: every variant has lines" % path)
			for line: Dictionary in block.get("lines", []):
				assert_true(line.has("speaker") and line.has("text"), "%s: every line has a speaker and text" % path)
			var start := String(block.get("then", {}).get("start_mission", ""))
			assert_true(start == "" or missions.has(start), "%s starts unknown mission '%s'" % [path, start])


func _json_files(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_json_files(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.ends_with(".json"):
			out.append(dir_path.path_join(file))
	return out
