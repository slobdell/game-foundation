class_name AssetNormalizer
extends RefCounted
## Fits any model to a visual slot (AssetSlots), so new art can never change how the game plays:
##   1. turns it so its front faces −Z and its top faces +Y (tell it which way the source faces),
##   2. scales it to the slot's size_m ("contain": evenly, until it just fits; "stretch": each axis exactly),
##   3. stands it on the ground: bottom at y = 0, centred on x and z,
##   4. bakes every transform into the vertices and merges surfaces that share a material (one draw call each),
##   5. decimates to the slot's triangle budget (Godot's meshoptimizer LODs),
##   6. shrinks textures to the slot's limit (detail maps to half of it), and turns off material features the
##      web (Compatibility) renderer doesn't have.
## The result is one Node3D with one MeshInstance3D, ready for GLTFDocument export.

const AXES := {
	"+x": Vector3.RIGHT, "-x": Vector3.LEFT, "+y": Vector3.UP, "-y": Vector3.DOWN,
	"+z": Vector3.BACK, "-z": Vector3.FORWARD,
}
## Normal, roughness, metallic and ORM maps barely show at game distance and are most of a model's download:
## they are capped at half the slot's texture limit (Tank Squad measured them at a third of each unit's web size).
const DETAIL_TEXTURES := ["normal_texture", "orm_texture", "roughness_texture", "metallic_texture", "ao_texture"]
## Surfaces this small are decimated only if nothing else is left to reduce (a 2-triangle sign collapses).
const SMALL_SURFACE_TRIS := 64


## contract: from AssetSlots.contract() / from_dict().
## options:
##   forward ("+z")  which way the SOURCE model faces (glTF and most generators: +z)   up ("+y")  its up axis
##   turn (0)        extra turn in degrees about the vertical axis, after forward/up (e.g. 45 for a diagonal model)
##   tris (0)        override the slot's triangle budget
##   emission_map    a Texture2D to make the model glow with (Meshy's emission map, delivered beside the GLB)
##   glow (0)        emission energy for glowing materials (generated emission maps come in dim; 2-4 is typical)
## Returns {scene: Node3D or null, notes: PackedStringArray, scale: Vector3}.
static func normalize(source: Node, contract: Dictionary, options: Dictionary = {}) -> Dictionary:
	var notes := PackedStringArray()
	if contract.is_empty():
		notes.append("unknown slot")
		return {"scene": null, "notes": notes}
	var orient := orientation_basis(options.get("forward", "+z"), options.get("up", "+y"))
	orient = Basis(Vector3.UP, deg_to_rad(float(options.get("turn", 0.0)))) * orient
	var parts := []  # [MeshInstance3D, oriented transform]
	for entry in AssetInspector.mesh_instances(source):
		parts.append([entry[0], Transform3D(orient, Vector3.ZERO) * (entry[1] as Transform3D)])
	if parts.is_empty():
		notes.append("the model has no meshes")
		return {"scene": null, "notes": notes}
	var bounds := _bounds(parts)
	if bounds.size.length() < 1e-6:
		notes.append("the model has no size")
		return {"scene": null, "notes": notes}
	var fit := fit_transform(bounds, contract, notes)
	var groups := _merge_by_material(parts, fit["transform"], notes)
	var budget := int(options.get("tris", 0)) if int(options.get("tris", 0)) > 0 else int(contract["tris"])
	var mesh := _merge_surfaces_by_material(_build_mesh(groups, budget, notes))
	_refit(mesh, contract, notes)  # decimation can shave an outer tip off: put the feet back on the ground
	_prepare_materials(mesh, int(contract["textures"]), notes, options.get("emission_map", null), float(options.get("glow", 0.0)))

	var root := Node3D.new()
	root.name = String(contract["name"]).to_pascal_case()
	var instance := MeshInstance3D.new()
	instance.name = "Mesh"
	instance.mesh = mesh
	root.add_child(instance)
	instance.owner = root
	return {"scene": root, "notes": notes, "scale": fit["scale"]}


## Rotation taking the source's forward/up axes to Godot's −Z/+Y.
static func orientation_basis(forward: String, up: String) -> Basis:
	var f: Vector3 = AXES.get(forward, Vector3.BACK)
	var u: Vector3 = AXES.get(up, Vector3.UP)
	if absf(f.dot(u)) > 0.5:
		push_error("forward (%s) and up (%s) must be different axes" % [forward, up])
		return Basis()
	var right := f.cross(u)
	# Columns map Godot's X/Y/Z onto the source axes; the inverse (transpose) maps source into Godot.
	return Basis(right, u, -f).transposed()


## Scale + offset that take [param bounds] (already oriented) into the slot: sized, feet on the ground, centred.
static func fit_transform(bounds: AABB, contract: Dictionary, notes: PackedStringArray) -> Dictionary:
	var size := bounds.size
	var safe := Vector3(maxf(size.x, 1e-6), maxf(size.y, 1e-6), maxf(size.z, 1e-6))
	var target: Vector3 = contract["size"]
	var scale: Vector3
	if String(contract["fit"]) == "stretch":
		scale = target / safe
		var distortion := maxf(maxf(scale.x, scale.y), scale.z) / minf(minf(scale.x, scale.y), scale.z)
		if distortion > 2.0:
			notes.append("stretched %.1f× out of proportion to fill the slot exactly: check it still looks right" % distortion)
	else:
		var s := minf(minf(target.x / safe.x, target.y / safe.y), target.z / safe.z)
		scale = Vector3(s, s, s)
		var filled := size * s / target
		var thin := PackedStringArray()
		for axis in 3:
			if filled[axis] < 0.6:
				thin.append("%s %d%%" % [["width", "height", "depth"][axis], int(filled[axis] * 100)])
		if not thin.is_empty():
			notes.append("kept its proportions, so it fills only %s of the slot (fine, or change size_m)" % ", ".join(thin))
	var scaled := AABB(bounds.position * scale, bounds.size * scale)
	var center := scaled.get_center()
	var offset := Vector3(-center.x, -scaled.position.y, -center.z)
	return {"transform": Transform3D(Basis.from_scale(scale), offset), "scale": scale}


static func _bounds(parts: Array) -> AABB:
	var aabb := AABB()
	var first := true
	for part in parts:
		var mesh: Mesh = (part[0] as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			for vertex in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var point: Vector3 = part[1] * vertex
				aabb = AABB(point, Vector3.ZERO) if first else aabb.expand(point)
				first = false
	return aabb


## Bakes transforms and concatenates surfaces per material AND source part, so decimation can simplify the big
## parts first; _merge_surfaces_by_material() joins them per material afterwards. Returns [{material, arrays...}].
static func _merge_by_material(parts: Array, fit: Transform3D, notes: PackedStringArray) -> Array:
	var groups := {}
	var order := []
	for index in parts.size():
		var instance: MeshInstance3D = parts[index][0]
		var mesh := instance.mesh
		if mesh == null:
			continue
		var xform: Transform3D = fit * (parts[index][1] as Transform3D)
		var normal_basis := xform.basis.inverse().transposed()
		var mirrored := xform.basis.determinant() < 0.0
		for surface in mesh.get_surface_count():
			if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				notes.append("skipped a surface made of lines or points in %s" % instance.name)
				continue
			var material := instance.get_surface_override_material(surface)
			if material == null:
				material = mesh.surface_get_material(surface)
			var key := "%s#%d" % [material.get_instance_id() if material != null else 0, index]
			if not groups.has(key):
				groups[key] = _new_group(material)
				order.append(key)
			_append_surface(groups[key], mesh.surface_get_arrays(surface), xform, normal_basis, mirrored)
	var merged := []
	for key in order:
		merged.append(groups[key])
	return merged


static func _new_group(material: Material) -> Dictionary:
	return {"material": material, "vertex": PackedVector3Array(), "normal": PackedVector3Array(),
			"tangent": PackedFloat32Array(), "color": PackedColorArray(), "uv": PackedVector2Array(),
			"uv2": PackedVector2Array(), "index": PackedInt32Array(),
			"has_tangent": false, "has_color": false, "has_uv": false, "has_uv2": false}


static func _append_surface(group: Dictionary, arrays: Array, xform: Transform3D, normal_basis: Basis, mirrored: bool) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var count := vertices.size()
	var base: int = group["vertex"].size()
	for vertex in vertices:
		group["vertex"].append(xform * vertex)
	var normals = arrays[Mesh.ARRAY_NORMAL]
	for i in count:
		group["normal"].append((normal_basis * normals[i]).normalized() if normals != null and normals.size() == count else Vector3.UP)
	var tangents = arrays[Mesh.ARRAY_TANGENT]
	var has_tangents: bool = tangents != null and tangents.size() == count * 4
	group["has_tangent"] = group["has_tangent"] or has_tangents
	for i in count:
		if has_tangents:
			var t := (xform.basis * Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])).normalized()
			group["tangent"].append_array([t.x, t.y, t.z, -tangents[i * 4 + 3] if mirrored else tangents[i * 4 + 3]])
		else:
			group["tangent"].append_array([1.0, 0.0, 0.0, 1.0])
	_append_optional(group, "color", "has_color", arrays[Mesh.ARRAY_COLOR], count, Color.WHITE)
	_append_optional(group, "uv", "has_uv", arrays[Mesh.ARRAY_TEX_UV], count, Vector2.ZERO)
	_append_optional(group, "uv2", "has_uv2", arrays[Mesh.ARRAY_TEX_UV2], count, Vector2.ZERO)
	var indices = arrays[Mesh.ARRAY_INDEX]
	if indices == null or indices.size() == 0:
		indices = PackedInt32Array(range(count))
	for tri in range(0, indices.size() - 2, 3):
		if mirrored:  # a mirrored transform flips the winding; swap so faces still point out
			group["index"].append_array([base + indices[tri], base + indices[tri + 2], base + indices[tri + 1]])
		else:
			group["index"].append_array([base + indices[tri], base + indices[tri + 1], base + indices[tri + 2]])


static func _append_optional(group: Dictionary, key: String, flag: String, source, count: int, fallback) -> void:
	if source != null and source.size() == count:
		group[flag] = true
		group[key].append_array(source)
	else:
		for i in count:
			group[key].append(fallback)


static func _group_arrays(group: Dictionary) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = group["vertex"]
	arrays[Mesh.ARRAY_NORMAL] = group["normal"]
	if group["has_tangent"]:
		arrays[Mesh.ARRAY_TANGENT] = group["tangent"]
	if group["has_color"]:
		arrays[Mesh.ARRAY_COLOR] = group["color"]
	if group["has_uv"]:
		arrays[Mesh.ARRAY_TEX_UV] = group["uv"]
	if group["has_uv2"]:
		arrays[Mesh.ARRAY_TEX_UV2] = group["uv2"]
	arrays[Mesh.ARRAY_INDEX] = group["index"]
	return arrays


static func _build_mesh(groups: Array, budget: int, notes: PackedStringArray) -> ArrayMesh:
	var total := 0
	for group in groups:
		total += group["index"].size() / 3
	var importer := ImporterMesh.new()
	for group in groups:
		var material: Material = group["material"]
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, _group_arrays(group), [], {}, material,
				material.resource_name if material != null else "")
	var mesh := ArrayMesh.new()
	if total <= budget:
		for surface in importer.get_surface_count():
			_commit(mesh, importer, surface, importer.get_surface_arrays(surface))
		return mesh
	# Over budget: generate LODs, then step down the LOD of whichever surface has the most triangles until the
	# model fits. Small surfaces (eyes, signs, buttons) are only touched as a last resort.
	importer.generate_lods(25.0, 60.0, [])
	var count := importer.get_surface_count()
	var levels := []
	var protected := []
	for surface in count:
		levels.append(-1)
		protected.append(_lod_indices(importer, surface, -1).size() / 3 <= maxi(SMALL_SURFACE_TRIS, int(total * 0.1)))
	var current := total
	while current > budget:
		var pick := -1
		var pick_tris := 0
		for pass_protected in [false, true]:
			for surface in count:
				if protected[surface] != pass_protected or levels[surface] + 1 >= importer.get_surface_lod_count(surface):
					continue
				var tris := _lod_indices(importer, surface, levels[surface]).size() / 3
				if tris > pick_tris:
					pick = surface
					pick_tris = tris
			if pick >= 0:
				break
		if pick < 0:
			break
		levels[pick] += 1
		current += _lod_indices(importer, pick, levels[pick]).size() / 3 - pick_tris
	for surface in count:
		var arrays := importer.get_surface_arrays(surface)
		arrays[Mesh.ARRAY_INDEX] = _lod_indices(importer, surface, levels[surface])
		_commit(mesh, importer, surface, _compact(arrays))
	notes.append("simplified %d → %d triangles (budget %d)" % [total, current, budget])
	if current > budget:
		notes.append("still over budget after the simplest level: raise the slot's tris or regenerate with fewer")
	return mesh


## One surface per material (one draw call each).
static func _merge_surfaces_by_material(source: ArrayMesh) -> ArrayMesh:
	var groups := {}
	var order := []
	for surface in source.get_surface_count():
		var material := source.surface_get_material(surface)
		var key: Variant = material if material != null else "none"
		if not groups.has(key):
			groups[key] = _new_group(material)
			order.append(key)
		_append_surface(groups[key], source.surface_get_arrays(surface), Transform3D.IDENTITY, Basis(), false)
	var mesh := ArrayMesh.new()
	for key in order:
		var group: Dictionary = groups[key]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _group_arrays(group))
		var index := mesh.get_surface_count() - 1
		mesh.surface_set_material(index, group["material"])
		mesh.surface_set_name(index, (group["material"] as Material).resource_name if group["material"] != null else "")
	return mesh


## Drops vertices no triangle uses any more (decimation leaves them behind; they would skew the bounds).
static func _compact(arrays: Array) -> Array:
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var remap := PackedInt32Array()
	remap.resize(arrays[Mesh.ARRAY_VERTEX].size())
	remap.fill(-1)
	var kept := PackedInt32Array()
	for index in indices:
		if remap[index] < 0:
			remap[index] = kept.size()
			kept.append(index)
	var result := []
	result.resize(Mesh.ARRAY_MAX)
	for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		var source = arrays[channel]
		if source == null:
			continue
		var packed = source.duplicate()
		packed.resize(kept.size())
		for i in kept.size():
			packed[i] = source[kept[i]]
		result[channel] = packed
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		var packed_tangents := PackedFloat32Array()
		packed_tangents.resize(kept.size() * 4)
		for i in kept.size():
			for k in 4:
				packed_tangents[i * 4 + k] = tangents[kept[i] * 4 + k]
		result[Mesh.ARRAY_TANGENT] = packed_tangents
	var new_indices := PackedInt32Array()
	new_indices.resize(indices.size())
	for i in indices.size():
		new_indices[i] = remap[indices[i]]
	result[Mesh.ARRAY_INDEX] = new_indices
	return result


## After decimation the outermost vertices may be gone: re-centre and re-ground (and for "stretch", re-scale)
## the final geometry so the model still meets its slot exactly.
static func _refit(mesh: ArrayMesh, contract: Dictionary, notes: PackedStringArray) -> void:
	var holder := MeshInstance3D.new()
	holder.mesh = mesh
	var bounds: AABB = AssetInspector.inspect(holder)["aabb"]
	holder.free()
	var xform := Transform3D(Basis(), Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z))
	if String(contract["fit"]) == "stretch":
		xform = fit_transform(bounds, contract, PackedStringArray())["transform"]
	if xform.is_equal_approx(Transform3D.IDENTITY):
		return
	var surfaces := []
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in vertices.size():
			vertices[i] = xform * vertices[i]
		arrays[Mesh.ARRAY_VERTEX] = vertices
		surfaces.append([arrays, mesh.surface_get_material(surface), mesh.surface_get_name(surface)])
	mesh.clear_surfaces()
	for entry in surfaces:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, entry[0])
		mesh.surface_set_material(mesh.get_surface_count() - 1, entry[1])
		mesh.surface_set_name(mesh.get_surface_count() - 1, entry[2])


static func _lod_indices(importer: ImporterMesh, surface: int, level: int) -> PackedInt32Array:
	var count := importer.get_surface_lod_count(surface)
	if level < 0 or count == 0:
		return importer.get_surface_arrays(surface)[Mesh.ARRAY_INDEX]
	return importer.get_surface_lod_indices(surface, mini(level, count - 1))


static func _commit(mesh: ArrayMesh, importer: ImporterMesh, surface: int, arrays: Array) -> void:
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var index := mesh.get_surface_count() - 1
	mesh.surface_set_material(index, importer.get_surface_material(surface))
	mesh.surface_set_name(index, importer.get_surface_name(surface))


## Copies each material, caps its textures, turns off what the web renderer lacks, and applies the glow.
static func _prepare_materials(mesh: ArrayMesh, max_texture: int, notes: PackedStringArray, emission_map: Texture2D,
		glow: float) -> void:
	var resized := {}
	for surface in mesh.get_surface_count():
		var source := mesh.surface_get_material(surface)
		if source == null:
			var fallback := StandardMaterial3D.new()
			fallback.resource_name = "default"
			mesh.surface_set_material(surface, fallback)
			continue
		var material := source.duplicate() as Material
		if material is BaseMaterial3D:
			var base := material as BaseMaterial3D
			if emission_map != null:
				base.emission_enabled = true
				base.emission = Color.WHITE
				base.emission_texture = emission_map
			if glow > 0.0 and base.emission_enabled:
				base.emission_energy_multiplier = glow
			for property in AssetInspector.TEXTURE_PROPERTIES:
				var texture := base.get(property) as Texture2D
				var cap := max_texture / 2 if property in DETAIL_TEXTURES else max_texture
				if texture != null and maxi(texture.get_width(), texture.get_height()) > cap:
					if not resized.has(texture):
						resized[texture] = _shrink(texture, cap)
						notes.append("texture %s %d×%d → %d×%d" % [property, texture.get_width(), texture.get_height(),
								resized[texture].get_width(), resized[texture].get_height()])
					base.set(property, resized[texture])
			for feature in ["subsurf_scatter_enabled", "refraction_enabled", "clearcoat_enabled", "anisotropy_enabled"]:
				if base.get(feature):
					base.set(feature, false)
					notes.append("material '%s': turned off %s (the web renderer doesn't have it)" % [base.resource_name, feature])
		mesh.surface_set_material(surface, material)
	if emission_map != null:
		notes.append("glows with the supplied emission map (energy %.1f)" % (glow if glow > 0.0 else 1.0))


static func _shrink(texture: Texture2D, max_edge: int) -> ImageTexture:
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	var factor := float(max_edge) / maxi(image.get_width(), image.get_height())
	image.resize(maxi(1, int(image.get_width() * factor)), maxi(1, int(image.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
	var result := ImageTexture.create_from_image(image)
	result.resource_name = texture.resource_name
	return result
