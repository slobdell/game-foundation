class_name Player
extends CharacterBody3D
## The character the player controls. It never reads the keyboard: a controller (player_input.gd, autopilot.gd,
## or a test) sets `command` every physics tick and this script carries it out.

signal jumped
signal landed
## Health ran out; the player is put back at the level's spawn point with full health.
signal downed

@export var walk_speed := 5.0
@export var sprint_speed := 9.0
@export var jump_velocity := 6.0
## How fast the character turns to face where it is going (higher = snappier).
@export var turn_speed := 12.0
## Metres between footstep sounds at walking speed.
@export var step_length := 1.6
## Seconds between shots when attacking.
@export var attack_cooldown := 0.35
## Set false for a game with no fighting: the attack button then does nothing.
@export var can_attack := true

var command := MoveCommand.new()
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
## The interactable the player would use by pressing interact (the HUD shows its prompt).
var focus: Interactable
var frozen := false

var _stride := 0.0
var _was_on_floor := true
var _attack_ready_at := 0.0
@onready var _reach: Area3D = $Reach
@onready var health: Health = $Health


func _ready() -> void:
	health.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	var cmd := command if not frozen else MoveCommand.new()
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif cmd.jump:
		velocity.y = jump_velocity
		jumped.emit()
		Sound.play("jump", self)
	var speed := sprint_speed if cmd.sprint else walk_speed
	var wish := cmd.direction.limit_length(1.0) * speed
	var blend := 1.0 - exp(-(10.0 if is_on_floor() else 2.5) * delta)
	velocity.x = lerpf(velocity.x, wish.x, blend)
	velocity.z = lerpf(velocity.z, wish.z, blend)
	if cmd.direction.length() > 0.05:
		var target_yaw := atan2(-cmd.direction.x, -cmd.direction.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))
	move_and_slide()
	_footsteps(delta)
	if is_on_floor() and not _was_on_floor:
		landed.emit()
	_was_on_floor = is_on_floor()
	focus = _nearest_interactable()
	if cmd.interact and focus != null:
		focus.interact(self)
	if cmd.attack:
		attack()


## Fire a Shot the way the player faces (if the cooldown allows). Returns the shot, or null.
func attack() -> Shot:
	var now := Time.get_ticks_msec() / 1000.0
	if not can_attack or frozen or now < _attack_ready_at:
		return null
	_attack_ready_at = now + attack_cooldown
	var shot := Shot.new()
	shot.team = "player"
	(Levels.current if Levels.current != null else get_parent()).add_child(shot)
	# Knee-to-waist height, so it hits small creatures as well as tall ones.
	shot.global_transform = Transform3D(global_transform.basis, global_position + Vector3.UP * 0.6 - global_transform.basis.z * 0.6)
	Sound.play("attack", self)
	return shot


func _on_died() -> void:
	Sound.play("player_down")
	var spawn := Levels.find_spawn(Levels.current, "") if Levels.current != null else null
	if spawn != null:
		global_transform = spawn.global_transform
		reset_physics_interpolation()
	velocity = Vector3.ZERO
	health.refill()
	health.grace(2.0)
	Game.report("player_down")
	downed.emit()


func _footsteps(delta: float) -> void:
	var flat := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or flat < 0.5:
		return
	_stride += flat * delta
	if _stride >= step_length:
		_stride = 0.0
		Sound.play("footstep", self)


func _nearest_interactable() -> Interactable:
	var best: Interactable = null
	var best_distance := INF
	for area in _reach.get_overlapping_areas():
		if area is Interactable and area.enabled:
			var d := global_position.distance_squared_to(area.global_position)
			if d < best_distance:
				best = area
				best_distance = d
	return best
