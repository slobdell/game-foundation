class_name PlayerInput
extends Node
## Reads the keyboard / gamepad and turns it into a MoveCommand for [member player], relative to where the
## camera looks (pressing "forward" walks away from the camera).

@export var player: Player
@export var camera: FollowCamera
## Off while a dialogue box or a menu has the controls.
var enabled := true


func _physics_process(_delta: float) -> void:
	if player == null:
		return
	var cmd := MoveCommand.new()
	if enabled and not Dialogue.is_open:
		var stick := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var yaw := camera.yaw if camera != null else 0.0
		cmd.direction = Vector3(stick.x, 0, stick.y).rotated(Vector3.UP, yaw)
		cmd.jump = Input.is_action_just_pressed("jump")
		cmd.sprint = Input.is_action_pressed("sprint")
		cmd.interact = Input.is_action_just_pressed("interact")
		cmd.attack = Input.is_action_just_pressed("attack")
	player.command = cmd
