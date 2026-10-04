extends Node
## AUTOLOAD `Levels`: moving between levels (data/levels.json).
##
## A level is a scene whose root uses game/kit/world/level.gd. The player is NOT part of a level: it lives in
## main.tscn and is moved to a spawn point (a Marker3D in the "spawn" group) when a level loads. That is why
## your inventory and the camera survive a trip through a portal.

signal level_changed(id: String)

## Where levels are added (main.gd sets this to its World node).
var host: Node3D
## The node placed at the spawn point (main.gd sets this to the player).
var player: Node3D
var current_id := ""
var current: Node3D


## Load level [param id] and put the player at the spawn point called [param spawn] (or the first one).
func go(id: String, spawn: String = "") -> bool:
	var info: Dictionary = GameData.levels().get(id, {})
	if info.is_empty():
		push_error("no level called '%s' in data/levels.json" % id)
		return false
	var packed: PackedScene = load(String(info["scene"]))
	if packed == null:
		push_error("level '%s': could not load %s" % [id, info["scene"]])
		return false
	if current != null:
		current.free()
	current = packed.instantiate()
	current_id = id
	host.add_child(current)
	if player != null:
		var marker := find_spawn(current, spawn)
		if marker != null:
			player.global_transform = marker.global_transform
			player.reset_physics_interpolation()
	Sound.music(String(info.get("music", "")))
	level_changed.emit(id)
	Game.report("reached", {"place": id})
	Game.save()
	return true


static func find_spawn(level: Node, spawn: String) -> Node3D:
	var first: Node3D = null
	for node in level.find_children("*", "Marker3D", true, false):
		if not node.is_in_group("spawn"):
			continue
		if first == null:
			first = node
		if spawn == "" or node.name == spawn:
			return node
	return first
