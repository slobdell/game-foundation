class_name AssetIO
extends RefCounted
## Files in and out of the asset pipeline: GLB load/save with GLTFDocument (no editor import needed), the
## finished models in res://assets/models/, their record (models.json: where each came from), and the web
## texture policy for their .import files.

const MODELS_DIR := "res://assets/models"
const RECORD := "res://assets/models/models.json"

## glTF importer option: what to do with images inside a GLB. 1 = extract them beside it as PNGs (Godot's default,
## which leaves stray files to go stale); 2 = keep them inside, compressed as Basis Universal: one file, about
## a quarter of the GPU memory, and it transcodes to whatever the player's GPU or browser supports.
const EMBED_BASIS_UNIVERSAL := 2


static func load_glb(path: String) -> Node3D:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(ProjectSettings.globalize_path(path), state)
	if error != OK:
		push_error("could not read %s (error %d)" % [path, error])
		return null
	var scene := document.generate_scene(state) as Node3D
	if scene != null:
		AssetInspector.bake_skins(scene)
	return scene


static func save_glb(root: Node, path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_scene(root, state)
	if error != OK:
		return error
	error = document.write_to_filesystem(state, ProjectSettings.globalize_path(path))
	if error == OK:
		write_import_settings(path)
	return error


static func model_path(slot: String) -> String:
	return "%s/%s.glb" % [MODELS_DIR, slot]


## Every finished model file: [[slot, res:// path], ...] for each <slot>.glb and <slot>.tscn in assets/models/.
static func model_files() -> Array:
	var found := []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(MODELS_DIR)):
		return found
	for file in DirAccess.get_files_at(MODELS_DIR):
		if file.get_extension() in ["glb", "tscn"]:
			found.append([file.get_basename(), "%s/%s" % [MODELS_DIR, file]])
	return found


## Writes (or fixes) <glb>.import so Godot keeps the GLB's textures inside it as Basis Universal instead of
## extracting PNGs. Returns true if the file changed (Godot must import again).
static func write_import_settings(glb_path: String) -> bool:
	var import_path := glb_path + ".import"
	var config := ConfigFile.new()
	if config.load(import_path) != OK:
		config.set_value("remap", "importer", "scene")
		config.set_value("remap", "importer_version", 1)
		config.set_value("remap", "type", "PackedScene")
	if int(config.get_value("params", "gltf/embedded_image_handling", -1)) == EMBED_BASIS_UNIVERSAL:
		return false
	config.set_value("params", "gltf/embedded_image_handling", EMBED_BASIS_UNIVERSAL)
	config.save(import_path)
	return true


## True when the GLB's import settings follow the texture policy (or it has never been imported yet).
static func follows_texture_policy(glb_path: String) -> bool:
	var config := ConfigFile.new()
	if config.load(glb_path + ".import") != OK:
		return false
	return int(config.get_value("params", "gltf/embedded_image_handling", -1)) == EMBED_BASIS_UNIVERSAL


static func read_record() -> Dictionary:
	if not FileAccess.file_exists(RECORD):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(RECORD))
	return parsed if parsed is Dictionary else {}


static func write_record(record: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MODELS_DIR))
	var handle := FileAccess.open(RECORD, FileAccess.WRITE)
	handle.store_string(JSON.stringify(record, "  ", true) + "\n")
	handle.close()
