extends TestCase


func test_every_level_loads_and_places_the_player_at_a_spawn() -> void:
	var parts := KitFixture.world(self)
	var player: Player = parts["player"]
	for id: String in GameData.levels():
		assert_true(Levels.go(id), "went to level '%s'" % id)
		assert_eq(Levels.current_id, id, "current level is '%s'" % id)
		var spawn := Levels.find_spawn(Levels.current, "")
		assert_true(player.global_position.distance_to(spawn.global_position) < 0.01, "player at the spawn in '%s'" % id)
		await wait_physics_frames(30)
		assert_true(player.global_position.y > -1.0, "player did not fall through the floor in '%s' (y=%.2f)" % [id, player.global_position.y])
	Levels.current.free()
	Levels.current = null


func test_named_spawn_is_used() -> void:
	var parts := KitFixture.world(self)
	assert_true(Levels.go("meadow", "from_hilltop"), "went to the meadow")
	var marker := Levels.find_spawn(Levels.current, "from_hilltop")
	assert_true((parts["player"] as Node3D).global_position.distance_to(marker.global_position) < 0.01, "arrived at from_hilltop")
	Levels.current.free()
	Levels.current = null


func test_unknown_level_is_a_loud_error() -> void:
	KitFixture.world(self)
	expect_error("no level called 'atlantis'")
	assert_false(Levels.go("atlantis"), "refused")
