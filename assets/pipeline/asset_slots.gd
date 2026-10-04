class_name AssetSlots
extends RefCounted
## The visual slot contracts from data/slots.json, as the asset pipeline uses them (_agents/assets.md).
##
## Every slot in data/slots.json has: kind, size_m [width, height, depth] in metres, placeholder, color, tris.
## The pipeline adds defaults for two optional fields a slot may also set:
##   fit       "contain": scale evenly until the model just fits inside size_m (keeps its proportions; most slots)
##             "stretch": scale each axis to exactly size_m (build pieces must tile on the grid)
##   textures  the largest texture edge in pixels (web-friendly: 1024 for characters, 512 for everything else)
## Every finished model stands with its feet at the origin (bottom at y = 0, centred on x/z) and faces −Z.

const SLOTS_PATH := "res://data/slots.json"
const FITS := ["contain", "stretch"]
## A finished model is "the right size" when its bounds are within this fraction of size_m.
const SIZE_TOLERANCE := 0.05
## Its feet must be within this many metres of the ground, and its middle within this of the origin.
const ANCHOR_TOLERANCE := 0.05


## Every slot, as {name: raw dictionary} (keys starting with "_" are comments and are skipped).
static func all(path := SLOTS_PATH) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text) if text != "" else null
	if not parsed is Dictionary:
		return {}
	var slots := {}
	for key in parsed:
		if not String(key).begins_with("_") and parsed[key] is Dictionary:
			slots[key] = parsed[key]
	return slots


## One slot as a contract, with defaults filled in, or {} if there is no such slot.
static func contract(slot: String, path := SLOTS_PATH) -> Dictionary:
	var slots := all(path)
	if not slots.has(slot):
		return {}
	return from_dict(slot, slots[slot])


## Builds a contract from a raw slot dictionary (tests use this so they don't depend on the game's own slots).
static func from_dict(slot: String, raw: Dictionary) -> Dictionary:
	var size_m: Array = raw.get("size_m", [1.0, 1.0, 1.0])
	var kind := String(raw.get("kind", "prop"))
	return {
		"name": slot,
		"kind": kind,
		"size": Vector3(float(size_m[0]), float(size_m[1]), float(size_m[2])) if size_m.size() == 3 else Vector3.ONE,
		"tris": int(raw.get("tris", 3000)),
		"fit": String(raw.get("fit", "stretch" if kind == "build" else "contain")),
		"textures": int(raw.get("textures", 1024 if kind == "character" else 512)),
		"placeholder": String(raw.get("placeholder", "box")),
		"color": String(raw.get("color", "#888888")),
		"notes": String(raw.get("notes", "")),
	}


## Problems with data/slots.json itself (a typo there would make every check meaningless).
static func validate(path := SLOTS_PATH) -> PackedStringArray:
	var errors := PackedStringArray()
	if not FileAccess.file_exists(path):
		errors.append("%s is missing" % path)
		return errors
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		errors.append("%s is not a JSON object (a missing comma or quote?)" % path)
		return errors
	for slot in parsed:
		if String(slot).begins_with("_"):
			continue
		var raw = parsed[slot]
		if not raw is Dictionary:
			errors.append("slot '%s' is not an object" % slot)
			continue
		if not String(slot).is_valid_identifier() or String(slot) != String(slot).to_lower():
			errors.append("slot '%s': names are lower_case_with_underscores (they become file names)" % slot)
		var size_m = raw.get("size_m")
		if not size_m is Array or size_m.size() != 3:
			errors.append("slot '%s': size_m must be [width, height, depth] in metres" % slot)
		else:
			for value in size_m:
				if not (value is float or value is int) or float(value) <= 0.0:
					errors.append("slot '%s': size_m values must be positive numbers" % slot)
					break
		if not (raw.get("tris") is float or raw.get("tris") is int) or int(raw.get("tris", 0)) <= 0:
			errors.append("slot '%s': tris (the triangle budget) must be a positive number" % slot)
		if raw.has("fit") and not String(raw["fit"]) in FITS:
			errors.append("slot '%s': fit must be one of %s" % [slot, ", ".join(FITS)])
		for field in ["kind", "placeholder", "color"]:
			if not raw.has(field):
				errors.append("slot '%s' lacks '%s'" % [slot, field])
	return errors
