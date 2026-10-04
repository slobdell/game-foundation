extends TestCase


func test_placeholder_has_the_slot_size_with_feet_at_the_origin() -> void:
	for slot: String in GameData.slots():
		if ModelSlot.model_path(slot) != "":
			continue  # a real model is fitted by the asset pipeline and checked by make assets-check
		var look := ModelSlot.new()
		look.slot = slot
		add_to_tree(look)
		var box := _bounds(look)
		var size := ModelSlot.slot_size(slot)
		assert_near(box.size.y, size.y, size.y * 0.05, "slot '%s' placeholder height" % slot)
		assert_near(box.position.y, 0.0, 0.05, "slot '%s' placeholder stands on the origin" % slot)


func test_unknown_slot_is_a_loud_error() -> void:
	expect_error("visual slot 'dragon_king' is not in data/slots.json")
	var look := ModelSlot.new()
	look.slot = "dragon_king"
	add_to_tree(look)


func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var m := mesh as MeshInstance3D
		var b := node.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
