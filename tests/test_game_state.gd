extends TestCase


func test_give_take_and_count() -> void:
	KitFixture.fresh_state()
	Game.give("star", 3)
	assert_eq(Game.count("star"), 3, "gave 3 stars")
	assert_true(Game.take("star", 2), "can take 2 of 3")
	assert_eq(Game.count("star"), 1, "1 left")
	assert_false(Game.take("star", 5), "cannot take more than you have")
	assert_eq(Game.count("star"), 1, "a refused take changes nothing")


func test_save_round_trip() -> void:
	KitFixture.fresh_state()
	Game.saving_enabled = true
	var path := "user://test_save_round_trip.json"
	Game.give("star", 4)
	Game.set_flag("met_guide")
	Game.placed["meadow"] = [{"piece": "block", "pos": [2.0, 0.0, 4.0], "turns": 1}]
	assert_true(Game.save(path), "saved")
	Game.reset()
	assert_eq(Game.count("star"), 0, "reset empties the inventory")
	Game.load_save(path)
	assert_eq(Game.count("star"), 4, "stars came back")
	assert_true(Game.get_flag("met_guide"), "flag came back")
	assert_eq(Game.placed["meadow"][0]["piece"], "block", "built pieces came back")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Game.saving_enabled = false


func test_saving_disabled_writes_nothing() -> void:
	KitFixture.fresh_state()
	var path := "user://test_should_not_exist.json"
	assert_false(Game.save(path), "save refuses when saving is off")
	assert_false(FileAccess.file_exists(path), "and no file appears")
