extends Node
## AUTOLOAD `Missions`: goals the player works through, defined in data/missions.json.
##
## A mission is a list of steps. Each step waits for one kind of event that `Game.report()` sends:
##   {"do": "collect", "item": "star", "count": 5}     have at least 5 stars
##   {"do": "talk", "to": "guide"}                       talk to the NPC whose npc_id is "guide"
##   {"do": "reach", "place": "lava_fields"}            arrive in a level (or a named Place area)
##   {"do": "build", "piece": "block", "count": 3}      place 3 blocks in build mode
##   {"do": "defeat", "enemy": "slime", "count": 2}     defeat 2 enemies whose enemy_id is "slime"
##   {"do": "flag", "flag": "door_open"}                a flag gets set (by dialogue, a script, anything)
## Every step has a "text" the HUD shows. A mission with "auto_start": true begins when the game starts;
## otherwise dialogue starts it ("then": {"start_mission": "id"}). When it finishes, its "reward" is given:
##   "reward": {"items": {"gem": 1}, "flag": "met_guide", "start_mission": "next_one"}

signal started(id: String)
signal advanced(id: String, step: int)
signal completed(id: String)

## mission id -> index of the current step
var active := {}
var done: Array[String] = []
## How many times things happened while missions were listening: "built:block", "defeated:slime".
var _counts := {}


func _ready() -> void:
	Game.event.connect(_on_event)
	Game.inventory_changed.connect(func(_item: String, _count: int) -> void: _recheck())
	Game.flag_changed.connect(func(_flag: String, _value: Variant) -> void: _recheck())


func reset() -> void:
	active.clear()
	done.clear()
	_counts.clear()


## Start every mission marked auto_start that isn't already active or done.
func start_auto() -> void:
	for mission: Dictionary in GameData.missions():
		if mission.get("auto_start", false):
			start(String(mission["id"]))


func start(id: String) -> void:
	if active.has(id) or done.has(id):
		return
	if definition(id).is_empty():
		push_error("no mission called '%s' in data/missions.json" % id)
		return
	active[id] = 0
	started.emit(id)
	_recheck()


func is_active(id: String) -> bool:
	return active.has(id)


func is_done(id: String) -> bool:
	return done.has(id)


func definition(id: String) -> Dictionary:
	for mission: Dictionary in GameData.missions():
		if mission.get("id") == id:
			return mission
	return {}


func current_step(id: String) -> Dictionary:
	if not active.has(id):
		return {}
	var steps: Array = definition(id).get("steps", [])
	var index: int = active[id]
	return steps[index] if index < steps.size() else {}


## "Collect stars (3/5)": what the HUD shows for a mission.
func step_text(id: String) -> String:
	var step := current_step(id)
	var text := String(step.get("text", ""))
	var need := int(step.get("count", 1))
	match step.get("do"):
		"collect":
			text += " (%d/%d)" % [mini(Game.count(String(step["item"])), need), need]
		"build", "defeat":
			if need > 1 or step.get("do") == "build":
				text += " (%d/%d)" % [mini(_count_for(step), need), need]
	return text


## How many of what a build/defeat step wants have happened so far.
func _count_for(step: Dictionary) -> int:
	match step.get("do"):
		"build":
			return int(_counts.get("built:%s" % step.get("piece", ""), 0))
		"defeat":
			return int(_counts.get("defeated:%s" % step.get("enemy", ""), 0))
	return 0


func to_dict() -> Dictionary:
	return {"active": active.duplicate(), "done": done.duplicate(), "counts": _counts.duplicate()}


func from_dict(data: Dictionary) -> void:
	reset()
	for id: String in data.get("active", {}):
		active[id] = int(data["active"][id])
	for id: String in data.get("done", []):
		done.append(id)
	_counts = data.get("counts", {}).duplicate()


func _on_event(kind: String, data: Dictionary) -> void:
	if kind == "built":
		_bump("built:%s" % data.get("piece", ""))
	elif kind == "defeated":
		_bump("defeated:%s" % data.get("enemy", ""))
	for id: String in active.keys():
		var step := current_step(id)
		if step.get("do") == "talk" and kind == "talked" and data.get("npc") == step.get("to"):
			_advance(id)
		elif step.get("do") == "reach" and kind == "reached" and data.get("place") == step.get("place"):
			_advance(id)
	_recheck()


## Steps that are about STATE (have N items, a flag is set) are checked whenever state changes.
func _recheck() -> void:
	var progressed := true
	while progressed:
		progressed = false
		for id: String in active.keys():
			var step := current_step(id)
			var met := false
			match step.get("do"):
				"collect":
					met = Game.count(String(step["item"])) >= int(step.get("count", 1))
				"build", "defeat":
					met = _count_for(step) >= int(step.get("count", 1))
				"flag":
					met = bool(Game.get_flag(String(step["flag"])))
			if met:
				_advance(id)
				progressed = true


func _bump(key: String) -> void:
	_counts[key] = int(_counts.get(key, 0)) + 1


func _advance(id: String) -> void:
	if not active.has(id):
		return
	active[id] += 1
	var steps: Array = definition(id).get("steps", [])
	if active[id] < steps.size():
		advanced.emit(id, active[id])
		return
	active.erase(id)
	done.append(id)
	var reward: Dictionary = definition(id).get("reward", {})
	for item: String in reward.get("items", {}):
		Game.give(item, int(reward["items"][item]))
	if reward.has("flag"):
		Game.set_flag(String(reward["flag"]))
	completed.emit(id)
	if reward.has("start_mission"):
		start(String(reward["start_mission"]))
