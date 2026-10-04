class_name FollowCamera
extends Node3D
## A third-person camera that follows [member target] and orbits around it with the mouse (click the game window
## first to capture the mouse; Esc frees it) or the right stick. A SpringArm pulls it in front of walls.

@export var target: Node3D
@export var distance := 6.0
@export var height := 1.5
@export var mouse_sensitivity := 0.004
@export var stick_speed := 2.5
@export var min_pitch := deg_to_rad(-60.0)
@export var max_pitch := deg_to_rad(20.0)

var yaw := 0.0
var pitch := deg_to_rad(-20.0)
var camera: Camera3D
var _arm: SpringArm3D


func _ready() -> void:
	_arm = SpringArm3D.new()
	_arm.spring_length = distance
	_arm.margin = 0.3
	_arm.collision_mask = 1
	add_child(_arm)
	camera = Camera3D.new()
	camera.current = true
	_arm.add_child(camera)
	if target is CollisionObject3D:
		_arm.add_excluded_object(target.get_rid())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clampf(pitch - event.relative.y * mouse_sensitivity, min_pitch, max_pitch)


func _process(delta: float) -> void:
	var stick := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	yaw -= stick.x * stick_speed * delta
	pitch = clampf(pitch - stick.y * stick_speed * delta, min_pitch, max_pitch)
	if target != null:
		global_position = target.get_global_transform_interpolated().origin + Vector3.UP * height
	rotation = Vector3(pitch, yaw, 0)
	_arm.spring_length = distance
