extends SceneTree
## Pictures of models, so you (and the kid) can SEE what the pipeline made. Needs a display; `make model-look`.
##
##   godot --path . --resolution 1280x720 --script res://assets/pipeline/model_look.gd -- <mode> --out=<abs.png>
##   --slot=<slot>   a finished model as the game loads it (assets/models/<slot>.tscn, else .glb), from four sides,
##                   inside a see-through box the size of its slot, with a FRONT arrow (−Z) and a 1.7 m person for scale
##   --in=<glb>      a raw download BEFORE fitting, with its +X and +Z axes drawn, to decide FORWARD= for model-fit
##   --all           every slot in a row: its model, or the placeholder shape if it has none yet
## Prints MODEL_LOOK saved <path> (or MODEL_LOOK FAILED ...) and quits.

const PERSON_HEIGHT := 1.7
const VIEWS := {  # direction FROM the model TO the camera; the model's front faces −Z; all on +X: the person stands at −X
	"front": Vector3(0.0, 0.25, -1.0), "3/4 front": Vector3(0.8, 0.5, -1.0),
	"side": Vector3(1.0, 0.2, 0.0), "back 3/4": Vector3(0.8, 0.45, 1.0),
}
const RAW_VIEWS := {"from +X +Z": Vector3(1.0, 0.6, 1.0), "from -X -Z": Vector3(-1.0, 0.6, -1.0),
		"from +X": Vector3(1.0, 0.15, 0.0), "from +Z": Vector3(0.0, 0.15, 1.0)}

var _bounds := AABB()
var _labels := []  # [text, position, pixel size]: made once the scene's size is known
var _caption: Label


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	var out := String(args.get("out", ""))
	if out == "":
		_fail("needs --out=<absolute png path>")
		return
	_add_environment()
	var shots: Dictionary
	var title: String
	if args.has("slot"):
		var slot: String = args["slot"]
		var contract := AssetSlots.contract(slot)
		if contract.is_empty():
			_fail("no slot '%s' in data/slots.json" % slot)
			return
		var model := _load_slot_model(slot)
		if model == null:
			_fail("slot '%s' has no model yet (make model-fit SLOT=%s); the game shows its placeholder" % [slot, slot])
			return
		root.add_child(model)
		_grow_with(model, Vector3.ZERO)
		_add_ghost(contract["size"], Vector3.ZERO, Color(1.0, 0.85, 0.2, 0.08))
		_add_front_arrow(contract["size"])
		if (contract["size"] as Vector3).y >= 0.8:  # next to a pebble the person would fill the picture
			_add_person(Vector3(-(contract["size"] as Vector3).x / 2.0 - 0.6, 0.0, 0.0))
		var report := AssetInspector.inspect(model)
		var size: Vector3 = (report["aabb"] as AABB).size
		title = "%s   %d / %d triangles   %.2f × %.2f × %.2f m (slot %.2f × %.2f × %.2f)" % [slot, report["tris"],
				contract["tris"], size.x, size.y, size.z, contract["size"].x, contract["size"].y, contract["size"].z]
		shots = VIEWS
	elif args.has("in"):
		var model := AssetIO.load_glb(args["in"])
		if model == null:
			_fail("could not read %s" % args["in"])
			return
		root.add_child(model)
		var report := AssetInspector.inspect(model)
		print(AssetInspector.summary(report))
		_grow_with(model, Vector3.ZERO)
		_add_axes(report["aabb"])
		title = "%s (raw: before fitting)   %d triangles" % [String(args["in"]).get_file(), report["tris"]]
		shots = RAW_VIEWS
	elif args.has("all"):
		title = _add_all_slots()
		shots = {"all slots": Vector3(0.0, 0.45, -1.0)}
	else:
		_fail("give --slot=<slot>, --in=<glb> or --all")
		return
	_add_caption()
	_make_labels()
	var camera := Camera3D.new()
	camera.fov = 35.0
	root.add_child(camera)
	camera.current = true
	var images := []
	for view in shots:
		_frame(camera, (shots[view] as Vector3).normalized())
		_caption.text = "%s\n%s" % [title, view]
		for frame in 6:
			await RenderingServer.frame_post_draw
		images.append(root.get_viewport().get_texture().get_image())
	var sheet: Image = images[0]
	if images.size() > 1:
		var w: int = images[0].get_width()
		var h: int = images[0].get_height()
		sheet = Image.create(w * 2, h * 2, false, images[0].get_format())
		for i in images.size():
			sheet.blit_rect(images[i], Rect2i(0, 0, w, h), Vector2i((i % 2) * w, (i / 2) * h))
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var error := sheet.save_png(out)
	print("MODEL_LOOK %s %s" % ["saved" if error == OK else "FAILED to save", out])
	quit(0 if error == OK else 1)


func _fail(message: String) -> void:
	printerr("MODEL_LOOK FAILED: %s" % message)
	quit(1)


## What ModelSlot would show: <slot>.tscn first, else <slot>.glb (imported), else the raw GLB file.
func _load_slot_model(slot: String) -> Node3D:
	for path in ["%s/%s.tscn" % [AssetIO.MODELS_DIR, slot], AssetIO.model_path(slot)]:
		if ResourceLoader.exists(path):
			var packed := load(path) as PackedScene
			if packed != null:
				return packed.instantiate() as Node3D
	if FileAccess.file_exists(AssetIO.model_path(slot)):
		print("note: %s isn't imported yet (make import); showing the file directly" % AssetIO.model_path(slot))
		return AssetIO.load_glb(AssetIO.model_path(slot))
	return null


func _add_all_slots() -> String:
	var slots := AssetSlots.all()
	var x := 0.0
	var made := 0
	var tallest := 0.0
	for slot in slots:
		tallest = maxf(tallest, (AssetSlots.from_dict(slot, slots[slot])["size"] as Vector3).y)
	var index := 0
	var with_models := PackedStringArray()
	for slot in slots:
		var contract := AssetSlots.from_dict(slot, slots[slot])
		var size: Vector3 = contract["size"]
		var at := Vector3(-(x + size.x / 2.0), 0.0, 0.0)  # seen from the front (−Z), −X runs left to right
		var model := _load_slot_model(slot)
		if model != null:
			model.position = at
			made += 1
			with_models.append(slot)
		else:
			model = _placeholder(contract)
			model.position = at
		root.add_child(model)
		_grow_with(model, at)
		_add_ghost(size, at, Color(1.0, 0.85, 0.2, 0.06))
		# staggered rows of names above the tallest slot, so neighbours' names never overlap
		_add_label(slot, Vector3(at.x, tallest + 0.5 + (index % 2) * 0.5, 0.0), 0.007)
		x += maxf(size.x, 1.6) + 0.8
		index += 1
	_add_person(Vector3(1.0, 0.0, 0.0))
	return "every slot, left to right as in data/slots.json: %d with a model (%s), %d still placeholders" % [made,
			", ".join(with_models) if made > 0 else "none yet", slots.size() - made]


func _placeholder(contract: Dictionary) -> Node3D:
	var size: Vector3 = contract["size"]
	var mesh: PrimitiveMesh
	match String(contract["placeholder"]):
		"capsule":
			var capsule := CapsuleMesh.new()
			capsule.radius = minf(size.x, size.z) / 2.0
			capsule.height = size.y
			mesh = capsule
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = minf(size.x, size.z) / 2.0
			cylinder.bottom_radius = cylinder.top_radius
			cylinder.height = size.y
			mesh = cylinder
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = minf(minf(size.x, size.z), size.y) / 2.0
			sphere.height = sphere.radius * 2.0
			mesh = sphere
		"prism":
			var prism := PrismMesh.new()
			prism.size = size
			mesh = prism
		_:
			var box := BoxMesh.new()
			box.size = size
			mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.from_string(String(contract["color"]), Color.GRAY)
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position.y = size.y / 2.0
	var holder := Node3D.new()
	holder.add_child(instance)
	return holder


func _add_ghost(size: Vector3, at: Vector3, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	box.material = material
	var ghost := MeshInstance3D.new()
	ghost.mesh = box
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.position = at + Vector3(0, size.y / 2.0, 0)
	root.add_child(ghost)
	_grow(AABB(at - Vector3(size.x / 2.0, 0, size.z / 2.0), size))


## A flat red arrow on the ground pointing −Z (the way every model must face) and the word FRONT.
func _add_front_arrow(size: Vector3) -> void:
	var length := maxf(0.6, size.z * 0.6)
	var arrow := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(length * 0.5, length, 0.02)
	var red := StandardMaterial3D.new()
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.albedo_color = Color(0.95, 0.15, 0.1)
	prism.material = red
	arrow.mesh = prism
	arrow.rotation_degrees = Vector3(-90, 0, 0)  # lie flat, tip toward −Z
	arrow.position = Vector3(0, 0.01, -size.z / 2.0 - length * 0.6)
	root.add_child(arrow)
	_add_label("FRONT", arrow.position + Vector3(0, 0.05, -length * 0.7))
	_grow(AABB(arrow.position - Vector3(length, 0, length), Vector3(length * 2, 0.1, length * 2)))


## A plain grey 1.7 m figure, so size reads at a glance.
func _add_person(at: Vector3) -> void:
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.22
	capsule.height = PERSON_HEIGHT
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.55, 0.57, 0.6)
	capsule.material = grey
	var person := MeshInstance3D.new()
	person.mesh = capsule
	person.position = at + Vector3(0, PERSON_HEIGHT / 2.0, 0)
	root.add_child(person)
	_add_label("1.7 m", at + Vector3(0, PERSON_HEIGHT + 0.25, 0))
	_grow(AABB(at - Vector3(0.25, 0, 0.25), Vector3(0.5, PERSON_HEIGHT, 0.5)))


## Coloured axis lines through a raw model's middle: red +X, blue +Z (glTF models usually face +Z).
func _add_axes(aabb: AABB) -> void:
	var reach := maxf(aabb.size.x, aabb.size.z) * 0.75 + 0.2
	var center := Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
	for axis in [[Vector3.RIGHT, Color(0.95, 0.2, 0.2), "+X"], [Vector3.BACK, Color(0.2, 0.45, 1.0), "+Z"]]:
		var bar := MeshInstance3D.new()
		var box := BoxMesh.new()
		var direction: Vector3 = axis[0]
		box.size = Vector3(reach, 0.03 * reach, 0.03 * reach) if direction.x != 0.0 else Vector3(0.03 * reach, 0.03 * reach, reach)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = axis[1]
		box.material = material
		bar.mesh = box
		bar.position = center + direction * reach / 2.0
		root.add_child(bar)
		_add_label(axis[2], center + direction * (reach + 0.1 * reach), reach * 0.01)


func _add_label(text: String, at: Vector3, pixel := 0.0) -> void:
	_labels.append([text, at, pixel])


func _make_labels() -> void:
	var scale := clampf(_bounds.size.length() * 0.0009, 0.002, 0.03)
	for entry in _labels:
		var label := Label3D.new()
		label.text = entry[0]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = entry[2] if entry[2] > 0.0 else scale
		label.font_size = 48
		label.outline_size = 10
		label.position = entry[1]
		root.add_child(label)


func _add_caption() -> void:
	var layer := CanvasLayer.new()
	_caption = Label.new()
	_caption.position = Vector2(16, 12)
	_caption.add_theme_font_size_override("font_size", 22)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 6)
	layer.add_child(_caption)
	root.add_child(layer)


func _add_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.32, 0.34, 0.38)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	environment.ambient_light_energy = 0.7
	var world := WorldEnvironment.new()
	world.environment = environment
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 150, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.24, 0.26, 0.29)
	plane.material = floor_material
	ground.mesh = plane
	root.add_child(ground)


func _grow_with(model: Node3D, at: Vector3) -> void:
	var aabb: AABB = AssetInspector.inspect(model)["aabb"]
	_grow(AABB(aabb.position + at, aabb.size))


func _grow(box: AABB) -> void:
	_bounds = box if _bounds.size == Vector3.ZERO else _bounds.merge(box)


func _frame(camera: Camera3D, direction: Vector3) -> void:
	var center := _bounds.get_center()
	var radius := maxf(_bounds.size.length() * 0.5, 0.5)
	var aspect := root.get_viewport().get_visible_rect().size.aspect()
	var distance := radius / tan(deg_to_rad(camera.fov * 0.5)) * (1.0 if aspect >= 1.0 else 1.0 / aspect) * 1.05
	if _bounds.size.x > _bounds.size.y * aspect * 1.5:  # a long row (the gallery): fit its width, not its diagonal
		var half_width := atan(tan(deg_to_rad(camera.fov * 0.5)) * aspect)
		distance = (_bounds.size.x * 0.55) / tan(half_width) + _bounds.size.z * 0.5
	camera.position = center + direction * distance
	camera.look_at(center, Vector3.UP)
