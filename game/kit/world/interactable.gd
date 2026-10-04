class_name Interactable
extends Area3D
## Something the player can use by walking up to it and pressing interact (E / gamepad X).
## The HUD shows "[E] <prompt>". Connect to `interacted`, or extend this script and override `_on_interact`.
## Lives on physics layer 4 ("pickups"), which the player's Reach area watches.

signal interacted(by: Node3D)

@export var prompt := "Use"
@export var enabled := true
## Radius of the zone in which the player can use it (metres).
@export var reach_radius := 1.5


func _ready() -> void:
	collision_layer = 8
	collision_mask = 0
	monitoring = false
	if get_children().filter(func(c: Node) -> bool: return c is CollisionShape3D).is_empty():
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = reach_radius
		shape.shape = sphere
		shape.position.y = 1.0
		add_child(shape)


func interact(by: Node3D) -> void:
	if not enabled:
		return
	_on_interact(by)
	interacted.emit(by)


func _on_interact(_by: Node3D) -> void:
	pass
