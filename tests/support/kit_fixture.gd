class_name KitFixture
## Helpers for tests that need the game's world: a clean game state, a level host and a player.

const PLAYER_SCENE := preload("res://game/kit/player/player.tscn")


## Forget everything (inventory, flags, missions, level) and never write the real save.
static func fresh_state() -> void:
	Game.saving_enabled = false
	Game.reset()
	Levels.current = null
	Levels.current_id = ""


## A host for levels plus a player, added to the test's tree. Returns {"host": Node3D, "player": Player}.
static func world(test: TestCase) -> Dictionary:
	fresh_state()
	var host := Node3D.new()
	test.add_to_tree(host)
	var player: Player = PLAYER_SCENE.instantiate()
	test.add_to_tree(player)
	Levels.host = host
	Levels.player = player
	return {"host": host, "player": player}


## A flat floor to stand on, 40 m square, top at y = 0.
static func floor_body(test: TestCase) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	test.add_to_tree(body)
	return body
