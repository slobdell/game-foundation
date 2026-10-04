@tool
class_name ModelSlot
extends Node3D
## Shows whatever model fills a visual slot (data/slots.json), or a coloured placeholder shape until one exists.
##
## The art and the game are kept apart on purpose: gameplay never depends on what a model looks like, so you can
## swap in a new model (make-model skill) at any time and nothing about how the game plays can change.
## Models are fitted by the asset pipeline: feet at this node's origin, facing -Z, already the slot's size.
## Lookup order: res://assets/models/<slot>.tscn, then .glb, then the placeholder.

@export var slot := "":
	set(value):
		slot = value
		if is_inside_tree():
			rebuild()

const MODELS_DIR := "res://assets/models/"
var model: Node3D


func _ready() -> void:
	rebuild()


static func model_path(slot_id: String) -> String:
	for ext in ["tscn", "glb"]:
		var path: String = MODELS_DIR + slot_id + "." + ext
		if ResourceLoader.exists(path):
			return path
	return ""


## The slot's size in metres [width, height, depth] as a Vector3 (1,1,1 if unknown).
static func slot_size(slot_id: String) -> Vector3:
	var info: Dictionary = GameData.slots().get(slot_id, {})
	var s: Array = info.get("size_m", [1, 1, 1])
	return Vector3(s[0], s[1], s[2])


func rebuild() -> void:
	if model != null:
		model.free()
		model = null
	if slot == "":
		return
	var info: Dictionary = GameData.slots().get(slot, {})
	if info.is_empty():
		push_error("visual slot '%s' is not in data/slots.json" % slot)
		return
	var path := model_path(slot)
	if path != "":
		var packed: PackedScene = load(path)
		model = packed.instantiate() if packed != null else null
	if model == null:
		model = _placeholder(info)
	model.name = "Model"
	add_child(model)


func _placeholder(info: Dictionary) -> Node3D:
	var size := slot_size(slot)
	var color := Color(String(info.get("color", "#cccccc")))
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	var mesh: Mesh
	match String(info.get("placeholder", "box")):
		"capsule":
			var capsule := CapsuleMesh.new()
			capsule.radius = minf(size.x, size.z) * 0.5
			capsule.height = size.y
			mesh = capsule
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = size.x * 0.25
			cylinder.bottom_radius = size.x * 0.5
			cylinder.height = size.y
			mesh = cylinder
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = size.x * 0.5
			sphere.height = size.y
			mesh = sphere
		"prism":
			var prism := PrismMesh.new()
			prism.size = size
			mesh = prism
		_:
			var box := BoxMesh.new()
			box.size = size
			mesh = box
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.material_override = material
	body.position.y = size.y * 0.5
	root.add_child(body)
	if info.get("kind") == "character":
		# A nose, so you can see which way a placeholder character is facing (-Z is forward).
		var nose := MeshInstance3D.new()
		var nose_mesh := BoxMesh.new()
		nose_mesh.size = Vector3(0.2, 0.2, 0.3)
		nose.mesh = nose_mesh
		var nose_material := StandardMaterial3D.new()
		nose_material.albedo_color = color.darkened(0.5)
		nose.material_override = nose_material
		nose.position = Vector3(0, size.y * 0.8, -minf(size.x, size.z) * 0.5)
		root.add_child(nose)
	return root
