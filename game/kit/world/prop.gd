@tool
class_name Prop
extends StaticBody3D
## A solid thing in the world (a rock, a tree, a house) showing a visual slot. Its collision box is the slot's
## size, so swapping in a new model never changes where you can walk.

@export var slot := "prop_rock":
	set(value):
		slot = value
		if is_inside_tree():
			_build()


func _ready() -> void:
	_build()


func _build() -> void:
	for child in get_children():
		if child.has_meta("prop_part"):
			child.free()
	var size := ModelSlot.slot_size(slot)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y * 0.5
	shape.set_meta("prop_part", true)
	add_child(shape)
	var look := ModelSlot.new()
	look.slot = slot
	look.set_meta("prop_part", true)
	add_child(look)
