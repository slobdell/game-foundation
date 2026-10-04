extends TestCase


func test_place_records_and_rebuilds_with_the_level() -> void:
	var parts := KitFixture.world(self)
	var build := BuildMode.new()
	build.player = parts["player"]
	add_to_tree(build)
	Levels.go("meadow")
	var at := build.snap(Vector3(3.1, 0, -7.2))
	assert_eq(at, Vector3(4, 0, -8), "snapped to the 2 m grid")
	assert_true(build.place("block", at), "placed a block")
	assert_eq(Game.placed["meadow"].size(), 1, "recorded in the save")
	Levels.go("meadow")
	var built := Levels.current.find_children("Built_block*", "", true, false)
	assert_eq(built.size(), 1, "the block is rebuilt when the level loads again")
	Levels.current.free()
	Levels.current = null


func test_a_piece_you_cannot_afford_is_refused() -> void:
	var parts := KitFixture.world(self)
	var build := BuildMode.new()
	build.player = parts["player"]
	add_to_tree(build)
	Levels.go("meadow")
	# Temporarily give "block" a cost via the cached data, then put it back.
	var pieces: Array = GameData.pieces()["pieces"]
	pieces[0]["cost"] = {"star": 2}
	assert_false(build.place("block", Vector3.ZERO), "no stars: refused")
	Game.give("star", 2)
	assert_true(build.place("block", Vector3.ZERO), "two stars: placed")
	assert_eq(Game.count("star"), 0, "and paid")
	pieces[0]["cost"] = {}
	Levels.current.free()
	Levels.current = null
