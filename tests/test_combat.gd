extends TestCase


func teardown() -> void:
	for shot in tree.get_nodes_in_group("shots"):
		shot.free()
	super.teardown()


func _arena() -> Player:
	KitFixture.floor_body(self)
	var player: Player = KitFixture.world(self)["player"]
	player.global_position = Vector3(0, 0.1, 0)
	return player


func _enemy(at: Vector3, hp: int = 2) -> Enemy:
	var enemy := Enemy.new()
	enemy.enemy_id = "slime"
	enemy.max_hp = hp
	enemy.sight_range = 0.0  # stands still unless a test wants it to chase
	enemy.wander_radius = 0.0
	add_to_tree(enemy)
	enemy.global_position = at
	return enemy


func test_shots_defeat_an_enemy_and_missions_hear_it() -> void:
	var player := _arena()
	var enemy := _enemy(Vector3(0, 0, -5), 2)
	var defeated := []
	var listen := func(kind: String, data: Dictionary) -> void:
		if kind == "defeated":
			defeated.append(data["enemy"])
	Game.event.connect(listen)
	await wait_physics_frames(5)
	for i in 2:
		player._attack_ready_at = 0.0
		enemy.health._safe_until = 0.0
		assert_true(player.attack() != null, "shot %d fired" % (i + 1))
		await wait_physics_frames(30)
	Game.event.disconnect(listen)
	assert_eq(defeated, ["slime"], "two hits defeated the slime")
	assert_false(is_instance_valid(enemy) and not enemy.is_queued_for_deletion(), "the slime is gone")


func test_cooldown_limits_fire_rate() -> void:
	var player := _arena()
	await wait_physics_frames(2)
	assert_true(player.attack() != null, "first shot")
	assert_true(player.attack() == null, "a second shot at once is refused")


func test_an_enemy_that_touches_you_hurts_and_you_respawn_when_out_of_hearts() -> void:
	var player := _arena()
	var host: Node3D = Levels.host
	var level := Node3D.new()
	var spawn := Marker3D.new()
	spawn.add_to_group("spawn")
	spawn.position = Vector3(10, 0, 10)
	level.add_child(spawn)
	host.add_child(level)
	Levels.current = level
	var enemy := _enemy(Vector3(0, 0, -3), 50)
	enemy.sight_range = 20.0
	var downs := []
	player.downed.connect(func() -> void: downs.append(true))
	await wait_physics_frames(90)
	assert_true(player.health.hp < player.health.max_hp, "the chasing slime took a heart (hp %d)" % player.health.hp)
	player.health._safe_until = 0.0
	player.health.damage(99)
	await wait_physics_frames(2)
	assert_eq(downs.size(), 1, "out of hearts once")
	assert_eq(player.health.hp, player.health.max_hp, "back to full health")
	assert_true(player.global_position.distance_to(Vector3(10, 0, 10)) < 2.0, "back at the spawn point")
	Levels.current = null


func test_shots_do_not_hurt_their_own_team() -> void:
	var player := _arena()
	await wait_physics_frames(2)
	var shot := Shot.new()
	shot.team = "player"
	add_to_tree(shot)
	shot.global_position = player.global_position + Vector3(0, 1, 2)
	shot.look_at(player.global_position + Vector3(0, 1, 0))
	await wait_physics_frames(10)
	assert_eq(player.health.hp, player.health.max_hp, "the player's own shot passed through them")
