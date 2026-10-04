class_name BuildMode
extends Node3D
## Build mode: press B, a see-through piece appears in front of the player snapped to a grid. Q picks the next
## piece, R turns it, E places it (paying its cost from data/pieces.json). B again to stop building.
## What you build is saved per level in Game.placed and rebuilt whenever that level loads.

signal toggled(on: bool)
signal placed_piece(piece: String, at: Vector3)

@export var player: Player
var active := false
var piece_index := 0
var turns := 0
var _ghost: ModelSlot


func _ready() -> void:
	Levels.level_changed.connect(func(_id: String) -> void: rebuild_level())


func _unhandled_input(event: InputEvent) -> void:
	if Dialogue.is_open:
		return
	if event.is_action_pressed("build_mode"):
		set_active(not active)
	elif active and event.is_action_pressed("build_next"):
		piece_index = (piece_index + 1) % maxi(1, pieces().size())
		_refresh_ghost()
	elif active and event.is_action_pressed("build_rotate"):
		turns = (turns + 1) % 4
	elif active and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		place(current_piece(), target_position(), turns)


func set_active(on: bool) -> void:
	active = on
	_refresh_ghost()
	toggled.emit(on)


func pieces() -> Array:
	return GameData.pieces().get("pieces", [])


func current_piece() -> String:
	var list := pieces()
	return String(list[piece_index % list.size()]["id"]) if not list.is_empty() else ""


func grid() -> float:
	return float(GameData.pieces().get("grid_m", 2.0))


## Where the piece would go: one grid step in front of the player, snapped.
func target_position() -> Vector3:
	if player == null:
		return Vector3.ZERO
	var ahead := player.global_position - player.global_transform.basis.z * grid() * 1.5
	return snap(ahead)


func snap(at: Vector3) -> Vector3:
	var g := grid()
	return Vector3(roundf(at.x / g) * g, maxf(0.0, roundf(at.y / g) * g), roundf(at.z / g) * g)


## Place [param piece] at [param at] if the player can pay for it. Returns whether it was placed.
func place(piece: String, at: Vector3, piece_turns: int = 0) -> bool:
	var info := _piece_info(piece)
	if info.is_empty():
		push_error("no build piece called '%s' in data/pieces.json" % piece)
		return false
	var cost: Dictionary = info.get("cost", {})
	for item: String in cost:
		if Game.count(item) < int(cost[item]):
			Sound.play("build_denied")
			return false
	for item: String in cost:
		Game.take(item, int(cost[item]))
	var level := Levels.current_id
	if not Game.placed.has(level):
		Game.placed[level] = []
	Game.placed[level].append({"piece": piece, "pos": [at.x, at.y, at.z], "turns": piece_turns})
	_spawn(info, at, piece_turns)
	Sound.play("build_place", at)
	Game.report("built", {"piece": piece})
	placed_piece.emit(piece, at)
	return true


## Re-create everything built in the current level (called when a level loads).
func rebuild_level() -> void:
	if Levels.current == null:
		return
	for entry: Dictionary in Game.placed.get(Levels.current_id, []):
		var info := _piece_info(String(entry["piece"]))
		if not info.is_empty():
			var p: Array = entry["pos"]
			_spawn(info, Vector3(p[0], p[1], p[2]), int(entry.get("turns", 0)))


func _process(_delta: float) -> void:
	if _ghost != null:
		_ghost.global_position = target_position()
		_ghost.rotation.y = turns * PI / 2


func _spawn(info: Dictionary, at: Vector3, piece_turns: int) -> void:
	var prop := Prop.new()
	prop.slot = String(info["slot"])
	prop.name = "Built_%s" % info["id"]
	Levels.current.add_child(prop)
	prop.global_position = at
	prop.rotation.y = piece_turns * PI / 2


func _piece_info(piece: String) -> Dictionary:
	for info: Dictionary in pieces():
		if info.get("id") == piece:
			return info
	return {}


func _refresh_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	if not active or current_piece() == "":
		return
	_ghost = ModelSlot.new()
	_ghost.slot = String(_piece_info(current_piece())["slot"])
	add_child(_ghost)
	for mesh in _ghost.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).transparency = 0.5
