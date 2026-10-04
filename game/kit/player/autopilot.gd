class_name Autopilot
extends Node
## Drives the player by itself: walks to each target in turn. Used by `make shots`, by tests, and as a demo.
## Targets are world positions; with none given it visits every Collectible in the level, nearest first.

@export var player: Player
var targets: Array[Vector3] = []
## Close enough to count as arrived (metres).
var arrive_distance := 0.6
var auto_collect := true


func _physics_process(_delta: float) -> void:
	if player == null:
		return
	if targets.is_empty() and auto_collect:
		_target_nearest_collectible()
	var cmd := MoveCommand.new()
	if not targets.is_empty():
		var to := targets[0] - player.global_position
		to.y = 0
		if to.length() < arrive_distance:
			targets.pop_front()
		else:
			cmd.direction = to.normalized()
	player.command = cmd


func _target_nearest_collectible() -> void:
	var best: Node3D = null
	for node in player.get_tree().get_nodes_in_group("collectible"):
		if node is Node3D and (best == null or player.global_position.distance_to(node.global_position)
				< player.global_position.distance_to(best.global_position)):
			best = node
	if best != null:
		targets.append(best.global_position)
