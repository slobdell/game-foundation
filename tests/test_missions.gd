extends TestCase


func test_collect_then_talk_completes_with_reward() -> void:
	KitFixture.fresh_state()
	Missions.start("first_stars")
	assert_true(Missions.is_active("first_stars"), "mission started")
	Game.give("star", 4)
	assert_eq(Missions.active["first_stars"], 0, "4 of 5 stars: still on step 1")
	Game.give("star", 1)
	assert_eq(Missions.active["first_stars"], 1, "5 stars: on to step 2")
	Game.report("talked", {"npc": "someone_else"})
	assert_true(Missions.is_active("first_stars"), "talking to the wrong NPC does nothing")
	Game.report("talked", {"npc": "guide"})
	assert_true(Missions.is_done("first_stars"), "talking to the guide finishes it")
	assert_true(Game.get_flag("star_collector"), "reward flag set")
	assert_true(Missions.is_active("summit"), "reward started the next mission")


func test_already_holding_the_items_completes_the_step_at_once() -> void:
	KitFixture.fresh_state()
	Game.give("star", 9)
	Missions.start("first_stars")
	assert_eq(Missions.active["first_stars"], 1, "a collect step is about HAVING the items, so it is met immediately")


func test_reach_and_build_steps() -> void:
	KitFixture.fresh_state()
	Missions.start("summit")
	Game.report("reached", {"place": "hilltop"})
	Game.report("defeated", {"enemy": "slime"})
	assert_eq(Missions.active["summit"], 1, "1 of 2 slimes: still on the defeat step")
	Game.report("defeated", {"enemy": "slime"})
	Game.report("reached", {"place": "summit"})
	assert_eq(Missions.active["summit"], 3, "reach, defeat x2, reach: on the build step")
	assert_true(Missions.step_text("summit").ends_with("(0/1)"), "build step shows progress: " + Missions.step_text("summit"))
	Game.report("built", {"piece": "block"})
	assert_true(Missions.is_done("summit"), "building a block finishes it")
	assert_eq(Game.count("star"), 3, "reward items given")


func test_missions_survive_save_and_load() -> void:
	KitFixture.fresh_state()
	Missions.start("first_stars")
	Game.give("star", 5)
	var saved := Game.to_dict()
	Game.reset()
	Game.from_dict(saved)
	assert_eq(Missions.active.get("first_stars"), 1, "still on step 2 after loading")


func test_unknown_mission_is_a_loud_error() -> void:
	KitFixture.fresh_state()
	expect_error("no mission called 'nope'")
	Missions.start("nope")
	assert_false(Missions.is_active("nope"), "not started")
