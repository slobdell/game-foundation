extends TestCase
## The asset pipeline (assets/pipeline/): a real downloaded model is fitted into a slot (size, feet on the ground,
## facing −Z, triangle budget, texture limit) and the checker accepts it, and rejects what breaks the contract.
## Contracts are built inline, so these tests don't change when a game edits data/slots.json.

const FIXTURE := "res://tests/fixtures/models/broken_car.glb"  # Quaternius CC0: 2.64 × 1.76 × 5.49 m, 5432 tris, faces +Z


func _contract(size: Array, tris: int, kind := "prop", extra := {}) -> Dictionary:
	var raw := {"kind": kind, "size_m": size, "placeholder": "box", "color": "#888888", "tris": tris}
	raw.merge(extra, true)
	return AssetSlots.from_dict("test_slot", raw)


func _fit(source: Node, contract: Dictionary, options := {}) -> Dictionary:
	var result := AssetNormalizer.normalize(source, contract, options)
	source.free()
	var report := AssetInspector.inspect(result["scene"]) if result["scene"] != null else {}
	if result["scene"] != null:
		result["scene"].free()
	return {"report": report, "notes": result["notes"]}


func test_a_real_model_is_fitted_into_its_slot() -> void:
	var source := AssetIO.load_glb(FIXTURE)
	assert_true(source != null, "the fixture loads")
	if source == null:
		return
	var contract := _contract([2.0, 2.0, 3.0], 3000)
	var fitted := _fit(source, contract)
	var report: Dictionary = fitted["report"]
	var aabb: AABB = report["aabb"]
	assert_near(aabb.size.z, 3.0, 0.03, "contain: the longest side (depth) touches the slot")
	assert_near(aabb.size.x / aabb.size.z, 2.64 / 5.49, 0.02, "contain keeps the proportions")
	assert_near(aabb.position.y, 0.0, 0.01, "feet on the ground")
	assert_near(aabb.get_center().x, 0.0, 0.01, "centred on x")
	assert_near(aabb.get_center().z, 0.0, 0.01, "centred on z")
	assert_true(int(report["tris"]) <= 3000, "decimated to the budget (got %d)" % report["tris"])
	assert_true(int(report["tris"]) > 1000, "but not to nothing (got %d)" % report["tris"])
	var check := AssetChecker.check_report(report, contract)
	assert_eq(check["errors"].size(), 0, "the checker accepts it: %s" % ", ".join(check["errors"]))


func test_forward_turns_the_model_to_face_minus_z() -> void:
	# The car is long along Z. Told it faces +X, its long side must end up along X.
	var fitted := _fit(AssetIO.load_glb(FIXTURE), _contract([4.0, 2.0, 4.0], 10000), {"forward": "+x"})
	var aabb: AABB = fitted["report"]["aabb"]
	assert_true(aabb.size.x > aabb.size.z * 1.5, "long axis moved to x (size %s)" % aabb.size)
	var basis := AssetNormalizer.orientation_basis("+z", "+y")
	assert_true((basis * Vector3.BACK).is_equal_approx(Vector3.FORWARD), "a +Z-facing model is turned to face -Z")
	basis = AssetNormalizer.orientation_basis("+x", "+y")
	assert_true((basis * Vector3.RIGHT).is_equal_approx(Vector3.FORWARD), "a +X-facing model is turned to face -Z")
	assert_true((basis * Vector3.UP).is_equal_approx(Vector3.UP), "up stays up")


func test_stretch_fills_the_slot_exactly() -> void:
	var contract := _contract([2.0, 0.2, 2.0], 10000, "build")
	assert_eq(contract["fit"], "stretch", "build pieces stretch by default (they must tile)")
	var fitted := _fit(AssetIO.load_glb(FIXTURE), contract)
	var aabb: AABB = fitted["report"]["aabb"]
	assert_true(aabb.size.is_equal_approx(Vector3(2.0, 0.2, 2.0)), "exactly the slot size (got %s)" % aabb.size)
	assert_eq(AssetChecker.check_report(fitted["report"], contract)["errors"].size(), 0, "and it passes")


func test_textures_are_capped_for_the_web() -> void:
	var contract := _contract([1.0, 1.0, 1.0], 1000, "pickup")
	assert_eq(contract["textures"], 512, "non-characters default to 512 px")
	var mesh := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(Image.create(2048, 2048, false, Image.FORMAT_RGBA8))
	material.normal_enabled = true
	material.normal_texture = ImageTexture.create_from_image(Image.create(2048, 2048, false, Image.FORMAT_RGBA8))
	mesh.material = material
	var source := Node3D.new()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	source.add_child(instance)
	var fitted := _fit(source, contract)
	var sizes := {}
	for entry in fitted["report"]["materials"][0]["textures"]:
		sizes[entry[0]] = entry[1]
	assert_eq(sizes.get("albedo_texture"), 512, "albedo capped at the slot's limit")
	assert_eq(sizes.get("normal_texture"), 256, "detail maps capped at half of it")


func test_the_checker_rejects_an_unfitted_model() -> void:
	var source := AssetIO.load_glb(FIXTURE)
	var report := AssetInspector.inspect(source)
	source.free()
	var errors: PackedStringArray = AssetChecker.check_report(report, _contract([1.6, 1.0, 1.4], 3000))["errors"]
	var text := " | ".join(errors)
	assert_true(text.contains("over the slot's budget"), "too many triangles: " + text)
	assert_true(text.contains("bigger than the slot"), "too big: " + text)
	assert_true(text.contains("feet"), "floating 0.1 m below the ground: " + text)


func test_slots_json_mistakes_are_caught() -> void:
	var path := "user://test_bad_slots.json"
	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_string(JSON.stringify({"_about": "x", "Bad Name": {"kind": "prop", "size_m": [1, 1], "placeholder": "box",
			"color": "#fff", "tris": 0}, "ok_slot": {"kind": "prop", "size_m": [1, 2, 1], "placeholder": "box",
			"color": "#fff", "tris": 100, "fit": "squash"}}))
	handle.close()
	var text := " | ".join(AssetSlots.validate(path))
	assert_true(text.contains("lower_case"), "names: " + text)
	assert_true(text.contains("size_m must be"), "size: " + text)
	assert_true(text.contains("tris"), "budget: " + text)
	assert_true(text.contains("fit must be"), "fit: " + text)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_eq(AssetSlots.validate().size(), 0, "the game's own data/slots.json is valid")
