extends TestCase


func test_variants_follow_the_mission_state() -> void:
	KitFixture.fresh_state()
	var data := GameData.dialogue("guide_hello")
	assert_eq(Dialogue.choose(data), data, "a new player gets the main lines")
	Missions.start("first_stars")
	assert_true(String(Dialogue.choose(data)["lines"][0]["text"]).begins_with("Still looking"), "while collecting")
	Game.give("star", 5)
	assert_true(String(Dialogue.choose(data)["lines"][0]["text"]).begins_with("Five stars"), "with five stars")


func test_finishing_a_dialogue_runs_its_then() -> void:
	KitFixture.fresh_state()
	assert_true(Dialogue.open("guide_hello"), "opened")
	assert_true(Dialogue.is_open, "is open")
	Dialogue.next()
	Dialogue.next()
	assert_false(Dialogue.is_open, "closed after the last line")
	assert_true(Missions.is_active("first_stars"), "then.start_mission started the mission")
	assert_true(Game.get_flag("met_guide"), "then.set_flag set the flag")
