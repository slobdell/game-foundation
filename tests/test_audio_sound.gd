extends TestCase
## Sound.play(): variants are found, missing ids are silent and warning-free, 2D/3D placement, the bus layout.
## Uses a fresh Sound pointed at tiny fixtures (game/kit/audio/fixtures), never the autoload's real assets.

const SOUND_SCRIPT := "res://game/kit/audio/sound.gd"
const SoundScript := preload("res://game/kit/audio/sound.gd")
const FIXTURES := "res://game/kit/audio/fixtures"


func _sound() -> Node:
	var sound: Node = load(SOUND_SCRIPT).new()
	sound.sfx_dir = FIXTURES.path_join("sfx")
	sound.music_dir = FIXTURES.path_join("music")
	sound.voice_dir = FIXTURES.path_join("voices")
	sound.sounds_json = "res://nowhere/sounds.json"
	sound.same_sound_gap_ms = 0
	add_to_tree(sound)
	return sound


func test_missing_ids_are_silent_and_warning_free() -> void:
	var sound := _sound()
	assert_eq(sound.play("no_such_sound"), null, "a missing sound plays nothing")
	assert_eq(sound.play("no_such_sound", Vector3.ZERO), null, "a missing 3D sound plays nothing")
	assert_eq(sound.play("no_such_sound", Vector2.ZERO), null, "a missing 2D sound plays nothing")
	sound.music("no_such_track")
	assert_eq(sound.music_id, "", "a missing track does not become the music")
	assert_eq(sound.reported_count(), 2, "one report per missing thing, however often it is asked for")
	sound.sfx_dir = "res://no/such/folder"
	sound.rescan()
	assert_eq(sound.play("blip"), null, "a missing folder is just missing sounds")
	# The runner fails this test on ANY engine warning or error, which is the real assertion here.


func test_variants_are_found_and_only_the_right_ones() -> void:
	var sound := _sound()
	assert_eq(sound._streams("blip").size(), 3, "blip.ogg, blip_v1.ogg, blip_v2.ogg (not blip_long_v1 or blipx)")
	assert_eq(sound._streams("blip_long").size(), 1, "blip_long_v1.ogg is its own sound")
	assert_eq(sound._streams("blipx").size(), 1, "blipx.ogg is its own sound")


func test_play_rotates_variants_and_wobbles_pitch() -> void:
	var sound := _sound()
	var streams := {}
	var pitches := {}
	var last: AudioStream = null
	var repeats := 0
	for i in 12:
		var player: AudioStreamPlayer = sound.play("blip")
		assert_true(player != null and player.playing, "a UI sound plays")
		if player == null:
			return
		streams[player.stream] = true
		pitches[snappedf(player.pitch_scale, 0.0001)] = true
		assert_true(absf(player.pitch_scale - 1.0) <= SoundScript.PITCH_VARIATION + 0.0001, "pitch stays within the wobble")
		assert_eq(player.bus, "UI", "a placeless sound goes to the UI bus")
		if player.stream == last:
			repeats += 1
		last = player.stream
	assert_eq(streams.size(), 3, "every variant gets played")
	assert_eq(repeats, 0, "never the same take twice in a row")
	assert_true(pitches.size() > 3, "the pitch varies from play to play")


func test_same_sound_in_one_instant_plays_once() -> void:
	var sound := _sound()
	sound.same_sound_gap_ms = 1000
	assert_true(sound.play("blip") != null, "the first one plays")
	assert_eq(sound.play("blip"), null, "the same sound again within the gap is skipped")
	assert_true(sound.play("blipx") != null, "a different sound is not")


func test_3d_sound_at_a_point_and_following_a_node() -> void:
	var sound := _sound()
	var at_point: AudioStreamPlayer3D = sound.play("blip", Vector3(3, 0, 4))
	assert_true(at_point != null and at_point.playing, "a 3D sound at a point plays")
	if at_point == null:
		return
	assert_eq(at_point.global_position, Vector3(3, 0, 4), "it is where it was asked to be")
	assert_eq(at_point.bus, "SFX", "3D sounds go to the SFX bus")
	assert_eq(at_point.unit_size, SoundScript.UNIT_SIZE, "with the gentle fall-off")
	var carrier := Node3D.new()
	add_to_tree(carrier)
	carrier.position = Vector3(10, 0, 0)
	var following: AudioStreamPlayer3D = sound.play("blipx", carrier)
	assert_true(following != null and following.get_parent() == carrier, "a sound given a node rides on it")
	carrier.position = Vector3(20, 0, 0)
	if following != null:
		assert_eq(following.global_position, Vector3(20, 0, 0), "and moves with it")
	var point_id := at_point.get_instance_id()
	await _wait_until(func() -> bool: return not is_instance_id_valid(point_id), 2.0)
	assert_false(is_instance_id_valid(point_id), "a finished one-shot frees itself")


func test_sounds_on_freed_nodes_are_forgotten_cleanly() -> void:
	var sound := _sound()
	for i in 4:
		var carrier := Node3D.new()
		add_to_tree(carrier)
		assert_true(sound.play("blip", carrier) != null, "a sound rides on node %d" % i)
		carrier.free()  # a picked-up star: gone mid-sound
	await wait_frames(3)
	for i in 3:  # each play prunes the freed players: this is where the error used to be
		assert_true(sound.play("blipx", Vector3(i, 0, 0)) != null, "playing after the carriers were freed works")
		await wait_frames(1)
	assert_eq(sound._spatial.size(), 3, "only the live sounds are tracked")


func test_2d_positional_sound() -> void:
	var sound := _sound()
	var player: AudioStreamPlayer2D = sound.play("blip", Vector2(5, 6))
	assert_true(player != null and player.playing, "a 2D sound plays")
	if player != null:
		assert_eq(player.global_position, Vector2(5, 6), "at its point")


func test_stop_a_looping_sound() -> void:
	var sound := _sound()
	sound._settings["blipx"] = {"id": "blipx", "loop": true}
	var player: AudioStreamPlayer = sound.play("blipx")
	assert_true(player != null and player.playing, "the loop plays")
	if player == null:
		return
	assert_false(player in sound._ui_players, "a loop gets its own player, so the pool cannot steal it")
	await _wait_until(func() -> bool: return false, 0.3)
	assert_true(is_instance_valid(player) and player.playing, "and keeps playing past its length")
	var player_id := player.get_instance_id()
	sound.stop(player)
	await _wait_until(func() -> bool: return not is_instance_id_valid(player_id), 1.0)
	assert_false(is_instance_id_valid(player_id), "stop() fades it and frees it")


func test_the_declared_bus_layout() -> void:
	for bus_name in ["Music", "SFX", "Voice", "UI"]:
		var index := AudioServer.get_bus_index(bus_name)
		assert_true(index > 0, "the %s bus is declared in default_bus_layout.tres" % bus_name)
		if index > 0:
			assert_eq(String(AudioServer.get_bus_send(index)), "Master", "%s feeds Master" % bus_name)
	var limiter: AudioEffectHardLimiter = null
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter:
			limiter = AudioServer.get_bus_effect(0, i)
	assert_true(limiter != null, "Master has a limiter")
	if limiter != null:
		assert_eq(limiter.pre_gain_db, 0.0, "with no make-up gain")
		assert_true(limiter.ceiling_db <= -0.5, "and a ceiling under 0 dBFS")


func test_settings_from_sounds_json() -> void:
	var sound := _sound()
	sound._settings["blip"] = {"id": "blip", "volume_db": -7.0, "pitch": 0.0}
	var player: AudioStreamPlayer = sound.play("blip")
	assert_true(player != null, "plays")
	if player != null:
		assert_eq(player.volume_db, -7.0, "volume_db from sounds.json")
		assert_eq(player.pitch_scale, 1.0, "pitch 0 = no wobble")


func test_the_real_sounds_json_parses() -> void:
	var sound: Node = load(SOUND_SCRIPT).new()
	add_to_tree(sound)
	assert_true(sound._settings.has("pickup"), "assets/audio/sounds.json is read at startup")
	assert_eq(sound.reported_count(), 0, "and parses cleanly")


func _wait_until(condition: Callable, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline and not condition.call():
		await tree.process_frame
