class_name Portal
extends Area3D
## Walk in to travel to another level ([member to_level], arriving at spawn point [member to_spawn]).

@export var to_level := ""
@export var to_spawn := ""
@export var slot := "portal"
@export var sound := "portal"


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var size := ModelSlot.slot_size(slot)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y * 0.5
	add_child(shape)
	var look := ModelSlot.new()
	look.slot = slot
	add_child(look)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is Player and to_level != "":
		Sound.play(sound)
		# Deferred: changing level frees this very node, which must not happen inside its own physics callback.
		Levels.go.call_deferred(to_level, to_spawn)
