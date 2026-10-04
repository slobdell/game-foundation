extends TestCase
## Sound.music() cross-fades and loops; Sound.voice() plays a line, ducks the music under it and tells the dialogue
## when it is done (also when the line is missing or cut off). Fixtures: game/kit/audio/fixtures.

const SoundScript := preload("res://game/kit/audio/sound.gd")
const FIXTURES := "res://game/kit/audio/fixtures"

var _music_bus_before := 0.0


func _sound() -> Node:
	_music_bus_before = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	var sound: Node = SoundScript.new()
	sound.sfx_dir = FIXTURES.path_join("sfx")
	sound.music_dir = FIXTURES.path_join("music")
	sound.voice_dir = FIXTURES.path_join("voices")
	sound.sounds_json = "res://nowhere/sounds.json"
	sound.music_fade_s = 0.2
	add_to_tree(sound)
	return sound


func teardown() -> void:
	super.teardown()
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), _music_bus_before)


func _playing_music(sound: Node) -> Array:
	var names := []
	for player: AudioStreamPlayer in sound._music_players:
		if player.playing:
			names.append(player.stream.resource_path.get_file().get_basename())
	return names


func test_music_crossfades_and_loops() -> void:
	var sound := _sound()
	sound.music("tune_a")
	assert_eq(sound.music_id, "tune_a", "the music is tune_a")
	assert_eq(_playing_music(sound), ["tune_a"], "tune_a plays")
	var a: AudioStreamPlayer = sound._music_players[sound._music_current]
	assert_true(a.volume_linear < 0.5, "it starts quiet (fading in)")
	assert_true(bool(a.stream.get("loop")), "music loops")
	await _wait(0.35)
	assert_near(a.volume_linear, 1.0, 0.01, "and is fully in after the fade")
	sound.music("tune_b")
	await _wait(0.08)
	var both := _playing_music(sound)
	both.sort()
	assert_eq(both, ["tune_a", "tune_b"], "mid-fade both play")
	var b: AudioStreamPlayer = sound._music_players[sound._music_current]
	assert_true(a.volume_linear < 1.0 and b.volume_linear > 0.0, "one fading out while the other fades in")
	await _wait(0.35)
	assert_eq(_playing_music(sound), ["tune_b"], "after the fade only tune_b plays")
	await _wait(1.2)
	assert_true(b.playing, "a 1 s track is still playing after 1.5 s: it loops")
	sound.music("tune_b")
	assert_eq(_playing_music(sound), ["tune_b"], "asking for the same music again changes nothing")
	sound.music("")
	assert_eq(sound.music_id, "", "\"\" means no music")
	await _wait(0.35)
	assert_eq(_playing_music(sound), [], "and it fades to silence")


func test_missing_music_keeps_the_current_track() -> void:
	var sound := _sound()
	sound.music("tune_a")
	sound.music("not_made_yet")
	assert_eq(sound.music_id, "tune_a", "a missing track leaves the music alone")
	assert_eq(sound.reported_count(), 1, "and says so once")


func test_voice_ducks_the_music_and_signals_when_done() -> void:
	var sound := _sound()
	var music_bus := AudioServer.get_bus_index("Music")
	var base := AudioServer.get_bus_volume_db(music_bus)
	sound.music("tune_a")
	var done := []
	sound.voice("hello").connect(func(id: String) -> void: done.append(id))
	assert_true(sound.is_voice_playing(), "the line plays")
	assert_eq(sound._voice_player.bus, "Voice", "on the Voice bus")
	await _wait(0.2)
	assert_near(AudioServer.get_bus_volume_db(music_bus), base + SoundScript.DUCK_DB, 0.5, "the music dips under the voice")
	await _wait_until(func() -> bool: return not done.is_empty(), 2.0)
	assert_eq(done, ["hello"], "the line's signal fires once, with its id, when it ends")
	assert_false(sound.is_voice_playing(), "nothing is speaking now")
	await _wait(SoundScript.DUCK_UP_S + 0.2)
	assert_near(AudioServer.get_bus_volume_db(music_bus), base, 0.2, "the music comes back up")


func test_await_voice_waits_for_the_line() -> void:
	var sound := _sound()
	var started := Time.get_ticks_msec()
	var id: String = await sound.voice("hello")
	await tree.process_frame
	var took := (Time.get_ticks_msec() - started) / 1000.0
	assert_eq(id, "hello", "await gives the line id")
	assert_true(took > 0.25, "await lasted about as long as the 0.4 s line (%.2f s)" % took)


func test_missing_voice_is_silent_and_does_not_hang_the_dialogue() -> void:
	var sound := _sound()
	var id: String = await sound.voice("never_recorded")
	await tree.process_frame  # an await resumes INSIDE Sound's signal emission; let it unwind before teardown frees it
	assert_eq(id, "never_recorded", "await returns at once for a line with no recording")
	assert_false(sound.is_voice_playing(), "nothing plays")
	assert_eq(sound.reported_count(), 1, "one plain line about it")


func test_a_new_line_cuts_off_the_old_one() -> void:
	var sound := _sound()
	var ended := []
	sound.voice_finished.connect(func(id: String) -> void: ended.append(id))
	var first_done := []
	sound.voice("long_line").connect(func(id: String) -> void: first_done.append(id))
	await _wait(0.1)
	var second_done := []
	sound.voice("hello").connect(func(id: String) -> void: second_done.append(id))
	await _wait(0.05)
	assert_eq(first_done, ["long_line"], "the cut-off line reports finished")
	assert_eq(second_done, [], "and does not finish the new line early")
	assert_true(sound.is_voice_playing(), "the new line plays")
	await _wait_until(func() -> bool: return not second_done.is_empty(), 2.0)
	assert_eq(second_done, ["hello"], "the new line finishes on its own")
	assert_eq(ended, ["long_line", "hello"], "voice_finished saw both, in order")


func test_volume_settings() -> void:
	var sound := _sound()
	var sfx := AudioServer.get_bus_index("SFX")
	var before := AudioServer.get_bus_volume_db(sfx)
	sound.set_volume("SFX", 0.5)
	assert_near(sound.get_volume("SFX"), 0.5, 0.001, "SFX at half")
	sound.set_volume("Music", 0.25)
	assert_near(sound.get_volume("Music"), 0.25, 0.001, "Music at a quarter")
	sound.set_volume("Nope", 1.0)
	assert_eq(sound.reported_count(), 1, "an unknown bus is reported, not an error")
	AudioServer.set_bus_volume_db(sfx, before)


func _wait(seconds: float) -> void:
	await _wait_until(func() -> bool: return false, seconds)


func _wait_until(condition: Callable, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline and not condition.call():
		await tree.process_frame
