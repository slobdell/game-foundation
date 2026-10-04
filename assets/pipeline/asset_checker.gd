class_name AssetChecker
extends RefCounted
## Enforces the slot contracts (AssetSlots) on every finished model in assets/models/. `make assets-check`.
## Errors break the contract (the check fails); warnings are worth a look but don't fail it.


## One measured model (an AssetInspector report) against its slot's contract.
## Returns {errors: PackedStringArray, warnings: PackedStringArray}.
static func check_report(report: Dictionary, contract: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	if int(report["tris"]) == 0:
		errors.append("it has no triangles")
		return {"errors": errors, "warnings": warnings}
	if int(report["tris"]) > int(contract["tris"]):
		errors.append("%d triangles is over the slot's budget of %d (fit it again: make model-fit)" % [report["tris"], contract["tris"]])
	var aabb: AABB = report["aabb"]
	var size := aabb.size
	var target: Vector3 = contract["size"]
	var tolerance := AssetSlots.SIZE_TOLERANCE
	if String(contract["fit"]) == "stretch":
		for axis in 3:
			if absf(size[axis] - target[axis]) > target[axis] * tolerance:
				errors.append("size %s should be exactly %s" % [_v(size), _v(target)])
				break
	else:
		for axis in 3:
			if size[axis] > target[axis] * (1.0 + tolerance):
				errors.append("size %s is bigger than the slot's %s" % [_v(size), _v(target)])
				break
		var fill := maxf(maxf(size.x / target.x, size.y / target.y), size.z / target.z)
		if fill < 1.0 - tolerance:
			errors.append("size %s is too small: it should touch the slot's %s on at least one side" % [_v(size), _v(target)])
	var near := maxf(AssetSlots.ANCHOR_TOLERANCE, target.y * 0.02)
	if absf(aabb.position.y) > near:
		errors.append("its feet are at y = %.2f; they should be on the ground (y = 0)" % aabb.position.y)
	var center := aabb.get_center()
	if absf(center.x) > maxf(near, target.x * 0.05) or absf(center.z) > maxf(near, target.z * 0.05):
		errors.append("its middle is at (x %.2f, z %.2f); it should be over the origin" % [center.x, center.z])
	for material in report["materials"]:
		for texture in material["textures"]:
			if maxi(texture[1], texture[2]) > int(contract["textures"]):
				errors.append("material '%s' %s is %d×%d (this slot allows %d px)" % [material["name"], texture[0],
						texture[1], texture[2], contract["textures"]])
	for extra in report["extras"]:
		if String(extra).begins_with("collision"):
			errors.append("a model must not bring its own collision (%s): the slot's owner adds that" % extra)
		else:
			warnings.append("unexpected %s" % extra)
	if int(report["surfaces"]) > 4:
		warnings.append("%d materials = %d draw calls each time it's drawn" % [report["surfaces"], report["surfaces"]])
	return {"errors": errors, "warnings": warnings}


## Every model file in assets/models/ (and data/slots.json itself). Returns {errors, warnings, lines}.
static func check_all(slots_path := AssetSlots.SLOTS_PATH) -> Dictionary:
	var errors := AssetSlots.validate(slots_path)
	var warnings := PackedStringArray()
	var lines := PackedStringArray()
	var slots := AssetSlots.all(slots_path)
	var record := AssetIO.read_record()
	for entry in AssetIO.model_files():
		var slot: String = entry[0]
		var path: String = entry[1]
		var label := path.get_file()
		if not slots.has(slot):
			errors.append("%s: there is no slot '%s' in data/slots.json (rename the file, or add the slot)" % [label, slot])
			continue
		var contract := AssetSlots.from_dict(slot, slots[slot])
		var model: Node = AssetIO.load_glb(path) if path.ends_with(".glb") else _instantiate(path)
		if model == null:
			errors.append("%s: can't be read" % label)
			continue
		var report := AssetInspector.inspect(model)
		model.free()
		var aabb: AABB = report["aabb"]
		lines.append("%s: %d / %d tris, %.2f × %.2f × %.2f m, %d draw calls, %.1f MB textures (uncompressed)" % [label,
				report["tris"], contract["tris"], aabb.size.x, aabb.size.y, aabb.size.z, report["surfaces"],
				report["texture_bytes"] / 1048576.0])
		var result := check_report(report, contract)
		for error in result["errors"]:
			errors.append("%s: %s" % [label, error])
		for warning in result["warnings"]:
			warnings.append("%s: %s" % [label, warning])
		if path.ends_with(".glb"):
			if not AssetIO.follows_texture_policy(path):
				errors.append("%s: its .import doesn't keep textures inside as Basis Universal (make assets-textures)" % label)
			if not ResourceLoader.exists(path):
				errors.append("%s: Godot hasn't imported it, so the game can't load it (make import)" % label)
			if not record.has(slot):
				warnings.append("%s: not in assets/models/models.json (where did it come from? fit it with make model-fit)" % label)
	return {"errors": errors, "warnings": warnings, "lines": lines}


static func _instantiate(path: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	return packed.instantiate() if packed != null else null


static func _v(value: Vector3) -> String:
	return "%.2f × %.2f × %.2f" % [value.x, value.y, value.z]
