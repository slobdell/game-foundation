extends Node
## The game starts here (project.godot: run/main_scene = game/main.tscn).
##
## main.tscn is nearly empty on purpose: this script snaps the pieces together. The World holds the current level;
## the player, camera, HUD and build mode live outside it, so they survive moving between levels.
##
## Launch flags (after `--`; every make target that starts the game uses them, see mk/play.mk):
##   --level=<id>             start in this level (default: the save's level, else data/levels.json "start")
##   --spawn=<name>           at this spawn point
##   --new                    ignore the save and start fresh
##   --no-save                never write the save (tests, screenshots, demos)
##   --autopilot              the player walks around by itself collecting things
##   --screenshot=<abs path>  save a PNG after --screenshot-delay seconds (default 3), then quit
##   --quit-after=<seconds>   quit after this long (smoke runs)
##   --strict                 exit with code 1 if any script/engine error happened (screenshots are always strict)

const PLAYER_SCENE := preload("res://game/kit/player/player.tscn")
const SCREENSHOT_DELAY := 3.0

var flags := LaunchFlags.new()
var world: Node3D
var player: Player
var camera: FollowCamera
var hud: Hud
var build: BuildMode
var errors: ErrorWatch


func _ready() -> void:
	if flags.has("strict") or flags.has("screenshot"):
		errors = ErrorWatch.new()
		OS.add_logger(errors)
	Game.saving_enabled = not flags.has("no-save")
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	player = PLAYER_SCENE.instantiate()
	add_child(player)
	camera = FollowCamera.new()
	camera.name = "Camera"
	camera.target = player
	add_child(camera)
	if flags.has("autopilot"):
		var pilot := Autopilot.new()
		pilot.player = player
		add_child(pilot)
	else:
		var input := PlayerInput.new()
		input.player = player
		input.camera = camera
		add_child(input)
	build = BuildMode.new()
	build.name = "BuildMode"
	build.player = player
	add_child(build)
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	build.toggled.connect(func(on: bool) -> void: hud.say("Build mode: Q next piece, R turn, E place, B done" if on else "Build mode off", 2.0))

	Levels.host = world
	# Start each level looking the way the player faces.
	Levels.level_changed.connect(func(_id: String) -> void: camera.yaw = player.global_rotation.y)
	Levels.player = player
	var saved_level := "" if flags.has("new") else Game.load_save()
	var level := flags.text("level", saved_level if saved_level != "" else GameData.start_level())
	if not Levels.go(level, flags.text("spawn")):
		push_error("could not start level '%s'" % level)
		get_tree().quit(1)
		return
	Missions.start_auto()

	if flags.has("screenshot"):
		_screenshot_after(flags.text("screenshot"), flags.number("screenshot-delay", SCREENSHOT_DELAY))
	if flags.has("quit-after"):
		get_tree().create_timer(flags.number("quit-after")).timeout.connect(func() -> void: _quit(0))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Game.save()


func _screenshot_after(path: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := get_viewport().get_texture().get_image().save_png(path)
	if err == OK:
		print("screenshot saved: ", path)
	else:
		push_error("screenshot failed (%s): %s" % [error_string(err), path])
	_quit(0 if err == OK else 1)


## Quit, failing a strict run that logged errors (and saying which, once each).
func _quit(code: int) -> void:
	if errors != null and errors.count() > 0:
		var seen := {}
		for text in errors.errors:
			seen[text] = int(seen.get(text, 0)) + 1
		print("RUNTIME ERRORS: %d (a strict run fails on any):" % errors.count())
		for text: String in seen:
			print("  %dx %s" % [seen[text], text])
		code = 1
	get_tree().quit(code)
