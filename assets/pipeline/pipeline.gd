extends SceneTree
## The asset pipeline's headless commands. Driven by mk/assets.mk (always through $(LOCK)); see _agents/assets.md.
##
##   godot --headless --path . --script res://assets/pipeline/pipeline.gd -- <command> [--flags]
##
##   slots                                   print every slot's contract (size, budget, fit, texture limit)
##   inspect   --in=<glb> [--slot=<slot>]    measure a model; with a slot, also check it against the contract
##   normalize --in=<glb> --slot=<slot>      fit a model into its slot → res://assets/models/<slot>.glb
##             [--forward=+z] [--up=+y]       which way the SOURCE faces / which way is its top (default +z / +y)
##             [--turn=<degrees>]             extra turn about the vertical axis
##             [--glow[=<energy>]]            glow with the emission map beside the input (<name>.emission.png)
##             [--emission-map=<png>]         ...or with this one
##             [--source=<text>] [--prompt=<text>] [--license=<text>]   recorded in assets/models/models.json
##   check                                   every model in assets/models/ meets its slot (exit 1 if not)
##   textures                                give every model's .import the web texture policy (then import again)


func _initialize() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	var status := 0
	match String(args.get("_command", "")):
		"slots":
			status = _slots()
		"inspect":
			status = _inspect(args)
		"normalize":
			status = _normalize(args)
		"check":
			status = _check()
		"textures":
			var changed := 0
			for entry in AssetIO.model_files():
				if String(entry[1]).ends_with(".glb") and AssetIO.write_import_settings(entry[1]):
					print("texture policy applied: %s" % entry[1])
					changed += 1
			print("textures: %d file(s) changed" % changed)
		_:
			printerr("usage: pipeline.gd -- slots|inspect|normalize|check|textures [--flags] (see the file header)")
			status = 2
	quit(status)


func _slots() -> int:
	var slots := AssetSlots.all()
	for error in AssetSlots.validate():
		printerr("  SLOTS: %s" % error)
	print("%-16s %-10s %-22s %7s  %-8s %s" % ["slot", "kind", "size w×h×d (m)", "tris", "fit", "model"])
	for slot in slots:
		var c := AssetSlots.from_dict(slot, slots[slot])
		var size: Vector3 = c["size"]
		var has_model := FileAccess.file_exists("%s/%s.tscn" % [AssetIO.MODELS_DIR, slot]) or FileAccess.file_exists(AssetIO.model_path(slot))
		print("%-16s %-10s %-22s %7d  %-8s %s" % [slot, c["kind"], "%.2f × %.2f × %.2f" % [size.x, size.y, size.z], c["tris"],
				c["fit"], "yes" if has_model else "placeholder (%s)" % c["placeholder"]])
	return 0


func _inspect(args: Dictionary) -> int:
	var model := AssetIO.load_glb(args.get("in", ""))
	if model == null:
		return 1
	var report := AssetInspector.inspect(model)
	model.free()
	print(AssetInspector.summary(report))
	if args.has("slot"):
		var contract := AssetSlots.contract(args["slot"])
		if contract.is_empty():
			printerr("no slot '%s' in data/slots.json (make assets-slots)" % args["slot"])
			return 1
		return _print_result(AssetChecker.check_report(report, contract), args["slot"])
	return 0


func _normalize(args: Dictionary) -> int:
	for required in ["in", "slot"]:
		if String(args.get(required, "")) == "":
			printerr("normalize needs --%s" % required)
			return 2
	var slot: String = args["slot"]
	var contract := AssetSlots.contract(slot)
	if contract.is_empty():
		printerr("no slot '%s' in data/slots.json (make assets-slots lists them; add one there first)" % slot)
		return 1
	var source := AssetIO.load_glb(args["in"])
	if source == null:
		return 1
	var options := {"forward": args.get("forward", "+z"), "up": args.get("up", "+y"), "turn": float(args.get("turn", "0"))}
	var emission_png := String(args.get("emission-map", ""))
	if args.has("glow"):
		options["glow"] = float(args["glow"]) if String(args["glow"]) != "" else 2.0
		if emission_png == "":
			emission_png = String(args["in"]).get_basename() + ".emission.png"
	if emission_png != "":
		var image := Image.load_from_file(ProjectSettings.globalize_path(emission_png))
		if image == null:
			printerr("could not read the emission map %s (Meshy only sends one for some models)" % emission_png)
			source.free()
			return 1
		var texture := ImageTexture.create_from_image(image)
		texture.resource_name = "emission"
		options["emission_map"] = texture
	var before := AssetInspector.inspect(source)
	print("source %s:\n%s" % [args["in"], AssetInspector.summary(before)])
	var result := AssetNormalizer.normalize(source, contract, options)
	source.free()
	for note in result["notes"]:
		print("  note: %s" % note)
	if result["scene"] == null:
		return 1
	var out := AssetIO.model_path(slot)
	var error := AssetIO.save_glb(result["scene"], out)
	var after := AssetInspector.inspect(result["scene"])
	result["scene"].free()
	if error != OK:
		printerr("could not write %s (error %d)" % [out, error])
		return 1
	# generate.py leaves <name>.json beside each download: the concept, the prompt, the Meshy task, the license.
	var sidecar = JSON.parse_string(FileAccess.get_file_as_string(String(args["in"]).get_basename() + ".json"))
	sidecar = sidecar if sidecar is Dictionary else {}
	var record := AssetIO.read_record()
	record[slot] = {
		"source": args.get("source", args["in"]), "concept": sidecar.get("concept", ""),
		"meshy_task": (sidecar.get("task", {}) as Dictionary).get("id", ""),
		"prompt": args.get("prompt", sidecar.get("prompt", "")), "license": args.get("license", sidecar.get("license_note", "")),
		"forward": options["forward"], "up": options["up"], "turn": options["turn"], "glow": options.get("glow", 0.0),
		"scale": snappedf((result["scale"] as Vector3).x, 0.0001), "tris": after["tris"],
		"fitted": Time.get_datetime_string_from_system(true) + "Z",
	}
	AssetIO.write_record(record)
	print("wrote %s:\n%s" % [out, AssetInspector.summary(after)])
	if FileAccess.file_exists("%s/%s.tscn" % [AssetIO.MODELS_DIR, slot]):
		print("  warning: assets/models/%s.tscn exists and the game loads it INSTEAD of this .glb (delete it to use this one)" % slot)
	return _print_result(AssetChecker.check_report(after, contract), slot)


func _check() -> int:
	var result := AssetChecker.check_all()
	for line in result["lines"]:
		print(line)
	for warning in result["warnings"]:
		print("  warning: %s" % warning)
	for error in result["errors"]:
		printerr("  CONTRACT: %s" % error)
	var count := AssetIO.model_files().size()
	if count == 0 and result["errors"].is_empty():
		print("assets-check passed (no models yet: every slot shows its placeholder)")
		return 0
	print("assets-check %s (%d model file(s))" % ["FAILED" if result["errors"].size() > 0 else "passed", count])
	return 1 if result["errors"].size() > 0 else 0


func _print_result(result: Dictionary, slot: String) -> int:
	for warning in result["warnings"]:
		print("  warning: %s" % warning)
	for error in result["errors"]:
		printerr("  CONTRACT: %s" % error)
	print("%s: slot contract %s" % [slot, "FAILED" if result["errors"].size() > 0 else "passed"])
	return 1 if result["errors"].size() > 0 else 0


static func _parse(raw: PackedStringArray) -> Dictionary:
	var args := {}
	for arg in raw:
		if not arg.begins_with("--"):
			args["_command"] = arg
			continue
		var parts := arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	return args
