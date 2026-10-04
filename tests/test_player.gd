extends TestCase


func _player_on_floor() -> Player:
	KitFixture.floor_body(self)
	var parts := KitFixture.world(self)
	var player: Player = parts["player"]
	player.global_position = Vector3(0, 0.1, 0)
	return player


func test_walks_where_the_command_says() -> void:
	var player := _player_on_floor()
	await wait_physics_frames(10)
	var cmd := MoveCommand.new()
	cmd.direction = Vector3(0, 0, -1)
	player.command = cmd
	await wait_physics_frames(60)
	assert_true(player.global_position.z < -3.0, "walked 1 s toward -Z, got z=%.2f" % player.global_position.z)
	assert_near(player.global_position.x, 0.0, 0.1, "did not drift sideways")
	assert_near(player.rotation.y, 0.0, 0.2, "turned to face -Z")


func test_jump_leaves_the_ground_and_lands() -> void:
	var player := _player_on_floor()
	await wait_physics_frames(10)
	assert_true(player.is_on_floor(), "standing on the floor")
	var cmd := MoveCommand.new()
	cmd.jump = true
	player.command = cmd
	await wait_physics_frames(2)
	player.command = MoveCommand.new()
	await wait_physics_frames(15)
	assert_true(player.global_position.y > 0.8, "in the air, y=%.2f" % player.global_position.y)
	await wait_physics_frames(90)
	assert_true(player.is_on_floor(), "landed again")


func test_walking_into_a_collectible_picks_it_up() -> void:
	var player := _player_on_floor()
	var star := Collectible.new()
	star.item = "star"
	add_to_tree(star)
	star.global_position = Vector3(0, 0, -3)
	await wait_physics_frames(10)
	var cmd := MoveCommand.new()
	cmd.direction = Vector3(0, 0, -1)
	player.command = cmd
	await wait_physics_frames(60)
	assert_eq(Game.count("star"), 1, "picked up the star")
	assert_false(is_instance_valid(star) and star.is_inside_tree() and not star.is_queued_for_deletion(), "the star is gone")


func test_interact_talks_to_an_npc() -> void:
	var player := _player_on_floor()
	var npc := Npc.new()
	npc.npc_id = "guide"
	add_to_tree(npc)
	npc.global_position = Vector3(0, 0, -1.5)
	var talked := []
	var listen := func(kind: String, data: Dictionary) -> void:
		if kind == "talked":
			talked.append(data["npc"])
	Game.event.connect(listen)
	await wait_physics_frames(5)
	assert_eq(player.focus, npc, "the NPC is in reach")
	var cmd := MoveCommand.new()
	cmd.interact = true
	player.command = cmd
	await wait_physics_frames(1)
	player.command = MoveCommand.new()
	Game.event.disconnect(listen)
	assert_eq(talked, ["guide"], "pressing interact talked to the guide")
