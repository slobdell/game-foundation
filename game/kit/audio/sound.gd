extends Node
## Sound: the game's one door to audio. An autoload (project.godot), so any script can call it.
##
##   Sound.play("pickup")                      a sound with no place (menus, UI, "you got it!")
##   Sound.play("footstep", self)              a 3D sound that follows a Node3D (a Node2D in a 2D game)
##   Sound.play("hit", global_position)        a 3D sound at a spot (Vector3; a Vector2 in a 2D game)
##   Sound.music("lava_theme")                 cross-fade to assets/music/lava_theme.ogg, looping; "" = silence
##   await Sound.voice("guide_hi_1")           a dialogue line from assets/voices/; music ducks under it
##   Sound.set_volume("Music", 0.5)            a settings slider: "Master", "Music", "SFX", "Voice", "UI"
##
## Where sounds come from (_agents/audio.md): assets/audio/sounds.json lists them; `make sounds` (ElevenLabs) or
## `make sounds-placeholders` (free) makes assets/audio/sfx/<id>_v1.ogg, <id>_v2.ogg, ... and play() picks one of
## them at random each time (never the same one twice in a row), with a little pitch wobble so repeats sound alive.
##
## A MISSING sound, track or line is never an error: it prints ONE plain line per id ("Sound: no sound 'x' yet") and
## plays nothing. So a game with half its audio still to make runs fine, and the tests (which fail on any engine
## warning) stay green.
##
## Lessons carried over from Tank Squad (they cost real evenings there):
## - The buses are DECLARED in res://default_bus_layout.tres, never created here. On the web a bus made or re-routed
##   at runtime silenced every sound after it.
## - In the browser (Godot's "Sample" playback) bus EFFECTS do not run: no limiter, no compressor. So the music duck
##   under a voice is a plain bus-volume fade (works everywhere), and the web build trims Master a little instead of
##   relying on the limiter.
## - The Master limiter has no make-up gain: it only catches peaks; it never makes everything louder and squashed.
## - 3D sounds are heard from a third-person camera several metres behind the player: the fall-off starts late and
##   is gentle, and distance muffles only a little, so nearby sounds are full and far ones are still there.

## Emitted whenever a voice line ends (finished, interrupted, or missing). voice() also returns a per-line signal.
signal voice_finished(line_id: String)

## One voice line in flight; voice() returns its `finished` signal so `await Sound.voice(id)` waits for THAT line.
class VoiceLine extends RefCounted:
	signal finished(line_id: String)
	var line_id := ""

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const VOICE_BUS := "Voice"
const UI_BUS := "UI"
## Random pitch each play (+-5 %); sounds.json "pitch" overrides per sound (0 = none).
const PITCH_VARIATION := 0.05
## The same sound asked for again within this many ms is skipped (ten pickups in one frame are one "ding").
const SAME_SOUND_GAP_MS := 30
const UI_PLAYERS := 8
const MAX_SPATIAL := 32
## 3D fall-off (Godot's inverse distance): full volume within UNIT_SIZE metres of the camera, -6 dB at twice that,
## silent past MAX_DISTANCE. A third-person camera sits ~5-10 m from the player, so the player's own sounds are full.
const UNIT_SIZE := 10.0
const MAX_DISTANCE := 150.0
## Distance muffling (Godot's default is -24 dB, which made far sounds vanish in Tank Squad): gentle.
const DISTANCE_FILTER_DB := -6.0
## How hard left/right panning is (1 = Godot's full). Softer suits speakers and a camera behind the player.
const PANNING := 0.5
const MUSIC_FADE_S := 1.5
## The music dips this much while someone speaks, quickly down and gently back up.
const DUCK_DB := -10.0
const DUCK_DOWN_S := 0.15
const DUCK_UP_S := 0.6
## Web (Sample playback) has no limiter: leave a little headroom instead (Tank Squad measured -3..-4 dB was enough).
const WEB_MASTER_TRIM_DB := -3.0

## Where files live. Tests point these at fixtures; call rescan() after changing them.
var sfx_dir := "res://assets/audio/sfx"
var music_dir := "res://assets/music"
var voice_dir := "res://assets/voices"
var sounds_json := "res://assets/audio/sounds.json"
var music_fade_s := MUSIC_FADE_S
var same_sound_gap_ms := SAME_SOUND_GAP_MS
## The id of the music playing now ("" = none).
var music_id := ""

var _settings := {}
var _variants := {}
var _last_index := {}
var _last_played := {}
var _reported := {}
var _ui_players: Array[AudioStreamPlayer] = []
var _spatial: Array[Node] = []
var _music_players: Array[AudioStreamPlayer] = []
var _music_current := -1
var _music_tween: Tween
var _voice_player: AudioStreamPlayer
var _voice_line: VoiceLine
var _pending_lines: Array[VoiceLine] = []
var _duck_tween: Tween
var _ducked := false
var _music_bus_db := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # menus and the pause screen still click
	for i in UI_PLAYERS:
		var player := AudioStreamPlayer.new()
		player.name = "Ui%d" % i
		player.bus = _bus(UI_BUS)
		add_child(player)
		_ui_players.append(player)
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.name = "Music%d" % i
		player.bus = _bus(MUSIC_BUS)
		add_child(player)
		_music_players.append(player)
	_voice_player = AudioStreamPlayer.new()
	_voice_player.name = "Voice"
	_voice_player.bus = _bus(VOICE_BUS)
	_voice_player.finished.connect(_on_voice_done)
	add_child(_voice_player)
	var music_bus := AudioServer.get_bus_index(MUSIC_BUS)
	_music_bus_db = AudioServer.get_bus_volume_db(music_bus) if music_bus >= 0 else 0.0
	if OS.has_feature("web") and int(ProjectSettings.get_setting("audio/general/default_playback_type.web", 1)) == 1:
		AudioServer.set_bus_volume_db(0, WEB_MASTER_TRIM_DB)
	rescan()


func _exit_tree() -> void:
	for tween in [_music_tween, _duck_tween]:
		if tween != null and tween.is_valid():
			tween.kill()
	_set_music_bus_db(_music_bus_db)


## Forget what was found on disk (after new sounds were made, or the folders changed) and re-read sounds.json.
func rescan() -> void:
	_variants.clear()
	_last_index.clear()
	_settings.clear()
	if not FileAccess.file_exists(sounds_json):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(sounds_json)) != OK or not json.data is Array:
		_report("settings", sounds_json, "sounds.json did not parse: %s; using defaults" % json.get_error_message())
		return
	for entry: Variant in json.data:
		if entry is Dictionary and entry.has("id"):
			_settings[String(entry["id"])] = entry


## Play sound `id`. `at`: null = no position (UI); a Vector3 or Node3D = 3D (a Node3D is followed); a Vector2 or
## Node2D = 2D positional. Returns the player node (so a looping sound can be stopped with stop()), or null.
func play(id: String, at: Variant = null) -> Node:
	var streams := _streams(id)
	if streams.is_empty():
		_report("sound", id, "add it to assets/audio/sounds.json, then make sounds-placeholders (free) or make sounds")
		return null
	var now := Time.get_ticks_msec()
	if _last_played.has(id) and now - int(_last_played[id]) < same_sound_gap_ms:
		return null
	_last_played[id] = now
	var settings: Dictionary = _settings.get(id, {})
	var stream: AudioStream = streams[_pick_index(id, streams.size())]
	var looping := bool(settings.get("loop", false))
	if looping and "loop" in stream:
		stream.set("loop", true)
	var wobble := float(settings.get("pitch", PITCH_VARIATION))
	var pitch := randf_range(1.0 - wobble, 1.0 + wobble) if wobble > 0.0 else 1.0
	var volume := float(settings.get("volume_db", 0.0))
	var bus := String(settings.get("bus", ""))
	if at is Node and not is_instance_valid(at):
		at = null
	if at is Vector3 or at is Node3D:
		return _play_spatial(AudioStreamPlayer3D.new(), stream, at, volume, pitch, _bus(bus if bus != "" else SFX_BUS), looping)
	if at is Vector2 or at is Node2D:
		return _play_spatial(AudioStreamPlayer2D.new(), stream, at, volume, pitch, _bus(bus if bus != "" else SFX_BUS), looping)
	return _play_flat(stream, volume, pitch, _bus(bus if bus != "" else UI_BUS), looping)


## Stop a sound play() returned (a loop, usually), with a tiny fade so it does not click.
func stop(handle: Node) -> void:
	if handle == null or not is_instance_valid(handle):
		return
	var tween := create_tween()
	tween.tween_property(handle, "volume_linear", 0.0, 0.08)
	if handle in _ui_players:
		tween.tween_callback(handle.stop)
	else:
		tween.tween_callback(handle.queue_free)


## Cross-fade to music `id` (assets/music/<id>.ogg), looping. The same id again does nothing; "" fades to silence.
## A missing track leaves the current music playing.
func music(id: String) -> void:
	if id == music_id:
		return
	if id == "":
		music_id = ""
		_crossfade(-1)
		return
	var stream := _load(music_dir.path_join(id + ".ogg"))
	if stream == null:
		_report("music", id, "make a Suno track, then make music-import IN=<file> ID=%s" % id)
		return
	if "loop" in stream:
		stream.set("loop", true)
	music_id = id
	var incoming := 0 if _music_current != 0 else 1
	var player := _music_players[incoming]
	player.stop()
	player.stream = stream
	player.volume_linear = 0.0
	player.play()
	_crossfade(incoming)


## Say dialogue line `line_id` (assets/voices/<line_id>.ogg) with the music ducked under it. A new line cuts off the
## one playing. Returns a signal that fires when THIS line ends (at once, next frame, if it has no recording):
##   await Sound.voice("guide_hi_1")
func voice(line_id: String) -> Signal:
	_end_voice()
	var line := VoiceLine.new()
	line.line_id = line_id
	var stream := _load(voice_dir.path_join(line_id + ".ogg")) if line_id != "" else null
	if stream == null:
		if line_id != "":
			_report("voice", line_id, "make voices records every line with a \"voice\" id")
		_finish_later(line)
		return line.finished
	_voice_line = line
	_voice_player.stream = stream
	_voice_player.play()
	_duck(true)
	return line.finished


func stop_voice() -> void:
	_end_voice()


func is_voice_playing() -> bool:
	return _voice_line != null


## A volume slider: `linear` 0..1 (1 = as mixed). bus_name: "Master", "Music", "SFX", "Voice" or "UI".
func set_volume(bus_name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		_report("bus", bus_name, "the buses are Master, Music, SFX, Voice, UI")
		return
	var db := linear_to_db(maxf(linear, 0.0001))
	if bus_name == MUSIC_BUS:
		_music_bus_db = db
		if _duck_tween != null and _duck_tween.is_valid():
			_duck_tween.kill()
		_set_music_bus_db(db + (DUCK_DB if _ducked else 0.0))
	else:
		AudioServer.set_bus_volume_db(index, db)


func get_volume(bus_name: String) -> float:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return 0.0
	return db_to_linear(_music_bus_db if bus_name == MUSIC_BUS else AudioServer.get_bus_volume_db(index))


# ---- sounds -----------------------------------------------------------------------------------------------------------

## Every file of sound `id`: <id>.ogg and <id>_v<number>.ogg in sfx_dir (cached; rescan() forgets).
func _streams(id: String) -> Array:
	if _variants.has(id):
		return _variants[id]
	var found: Array = []
	var prefix := id + "_v"
	for file_name in _list(sfx_dir):
		var is_variant := file_name.begins_with(prefix) and file_name.ends_with(".ogg") \
				and file_name.trim_prefix(prefix).trim_suffix(".ogg").is_valid_int()
		if file_name == id + ".ogg" or is_variant:
			var stream := _load(sfx_dir.path_join(file_name))
			if stream != null:
				found.append(stream)
	_variants[id] = found
	return found


## A random take, never the same as last time when there is a choice.
func _pick_index(id: String, count: int) -> int:
	if count <= 1:
		return 0
	var index := randi() % (count - 1)
	if index >= int(_last_index.get(id, -1)):
		index += 1
	_last_index[id] = index
	return index


func _play_flat(stream: AudioStream, volume: float, pitch: float, bus: String, looping: bool) -> Node:
	var player: AudioStreamPlayer
	if looping:  # a loop keeps its own player, so the pool never steals it
		player = AudioStreamPlayer.new()
		add_child(player)
	else:
		player = _ui_players[0]
		for candidate in _ui_players:
			if not candidate.playing:
				player = candidate
				break
		if player.playing:  # all busy: take the one that has played longest
			for candidate in _ui_players:
				if candidate.get_playback_position() > player.get_playback_position():
					player = candidate
	player.stream = stream
	player.volume_db = volume
	player.pitch_scale = pitch
	player.bus = bus
	player.play()
	return player


func _play_spatial(player: Node, stream: AudioStream, at: Variant, volume: float, pitch: float, bus: String,
		looping: bool) -> Node:
	# A sound riding on a node is freed with it, so prune by hand: a freed object cannot be passed to a typed
	# lambda parameter, and filter() returns an untyped Array (both errors in a windowed run, round 1).
	var alive: Array[Node] = []
	for node: Variant in _spatial:
		if is_instance_valid(node):
			alive.append(node)
	_spatial = alive
	if _spatial.size() >= MAX_SPATIAL:
		player.free()
		return null
	player.set("stream", stream)
	player.set("volume_db", volume)
	player.set("pitch_scale", pitch)
	player.set("bus", bus)
	if player is AudioStreamPlayer3D:
		var player_3d := player as AudioStreamPlayer3D
		player_3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player_3d.unit_size = UNIT_SIZE
		player_3d.max_db = 0.0
		player_3d.max_distance = MAX_DISTANCE
		player_3d.attenuation_filter_db = DISTANCE_FILTER_DB
		player_3d.panning_strength = PANNING
	if not looping:
		player.connect("finished", player.queue_free)
	_spatial.append(player)
	if at is Node and (at as Node).is_inside_tree():
		var parent := at as Node
		if parent.is_node_ready():
			parent.add_child(player)
			player.call("play")
		else:  # a node still building its children (play() from its _ready) cannot take one yet
			player.set("autoplay", true)
			parent.add_child.call_deferred(player)
	else:
		add_child(player)
		if at is Vector3 or at is Vector2:
			player.set("position", at)
		elif at is Node:
			player.set("position", (at as Node).get("position"))
		player.call("play")
	return player


# ---- music ------------------------------------------------------------------------------------------------------------

## Fade player `to` (-1 = none) up to full and every other music player down to silence, then stop those.
func _crossfade(to: int) -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_current = to
	_music_tween = create_tween().set_parallel(true)
	for index in _music_players.size():
		var player := _music_players[index]
		if index == to:
			_music_tween.tween_property(player, "volume_linear", 1.0, music_fade_s)
		elif player.playing:
			_music_tween.tween_property(player, "volume_linear", 0.0, music_fade_s)
	_music_tween.chain().tween_callback(_stop_silent_music)


func _stop_silent_music() -> void:
	for index in _music_players.size():
		if index != _music_current:
			_music_players[index].stop()


# ---- voices -----------------------------------------------------------------------------------------------------------

func _on_voice_done() -> void:
	if _voice_line == null:
		return
	var line := _voice_line
	_voice_line = null
	_duck(false)
	line.finished.emit(line.line_id)
	voice_finished.emit(line.line_id)


## Cut off the line playing (if any); its signal fires next frame, so an awaiting dialogue resumes cleanly.
func _end_voice() -> void:
	if _voice_line == null:
		return
	var line := _voice_line
	_voice_line = null
	_voice_player.stop()
	_duck(false)
	_finish_later(line)


func _finish_later(line: VoiceLine) -> void:
	_pending_lines.append(line)  # holds the line until its signal has fired
	if _pending_lines.size() == 1:
		_flush_lines.call_deferred()


func _flush_lines() -> void:
	var lines := _pending_lines
	_pending_lines = []
	for line in lines:
		line.finished.emit(line.line_id)
		voice_finished.emit(line.line_id)


## Dip (or restore) the Music bus. A bus VOLUME change, not a compressor: it works in the browser too.
func _duck(on: bool) -> void:
	_ducked = on
	if AudioServer.get_bus_index(MUSIC_BUS) < 0:
		return
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = create_tween()
	var from := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(MUSIC_BUS))
	_duck_tween.tween_method(_set_music_bus_db, from, _music_bus_db + (DUCK_DB if on else 0.0),
			DUCK_DOWN_S if on else DUCK_UP_S)


func _set_music_bus_db(db: float) -> void:
	var index := AudioServer.get_bus_index(MUSIC_BUS)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, db)


# ---- files ------------------------------------------------------------------------------------------------------------

## The audio file at `path`, or null (silently) when it is not there.
func _load(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	if path.ends_with(".ogg") and FileAccess.file_exists(path):
		# Made a moment ago and not imported yet (the editor imports on focus; `make import` headless): play it raw.
		return AudioStreamOggVorbis.load_from_file(path)
	return null


## File names in a res:// folder, imported or not, in the editor and in an exported game. [] if there is no folder.
func _list(dir: String) -> PackedStringArray:
	if not DirAccess.dir_exists_absolute(dir):
		return PackedStringArray()
	var names := ResourceLoader.list_directory(dir)
	for file_name in DirAccess.get_files_at(dir):
		if file_name.ends_with(".ogg") and not names.has(file_name):
			names.append(file_name)
	return names


## A bus by name, or Master if the layout lacks it (never created here: see the web lesson above).
func _bus(bus_name: String) -> String:
	return bus_name if AudioServer.get_bus_index(bus_name) >= 0 else "Master"


## One plain line per missing thing, ever. Not push_warning: missing audio is a normal state, not a fault.
func _report(kind: String, id: String, hint: String) -> void:
	var key := kind + ":" + id
	if _reported.has(key):
		return
	_reported[key] = true
	print("Sound: no %s \"%s\" yet, playing nothing (%s)" % [kind, id, hint])


## How many distinct missing things have been reported (tests use it).
func reported_count() -> int:
	return _reported.size()
