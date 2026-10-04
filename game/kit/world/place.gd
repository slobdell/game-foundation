class_name Place
extends Area3D
## An invisible zone. When the player walks in, missions hear "reached <place_id>" (a {"do": "reach"} step).
## Give it a CollisionShape3D child for its size; without one it is a 4 m sphere.

@export var place_id := ""
@export var once := true
var _fired := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	if get_children().filter(func(c: Node) -> bool: return c is CollisionShape3D).is_empty():
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 4.0
		shape.shape = sphere
		add_child(shape)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is Player and not (once and _fired):
		_fired = true
		Game.report("reached", {"place": place_id})
