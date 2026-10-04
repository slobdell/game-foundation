class_name Enemy
extends CharacterBody3D
## A simple enemy: wanders near home, chases the player when it sees them, hurts them by touching.
## When defeated it tells the missions ("defeated <enemy_id>") and can drop an item.
## Tune it in the Inspector, or extend this script for special enemies (one that shoots: see fire_shot()).

@export var enemy_id := "slime"
@export var slot := "enemy_basic"
@export var max_hp := 3
@export var speed := 3.0
@export var sight_range := 12.0
@export var touch_damage := 1
@export var wander_radius := 4.0
@export var drop_item := ""
@export var drop_amount := 1
## Stay defeated after it's beaten (remembered in the save).
@export var stays_defeated := true

var health: Health
var home := Vector3.ZERO
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _wander_to := Vector3.ZERO
var _wander_time := 0.0


func _ready() -> void:
	if stays_defeated and Game.get_flag(_defeated_flag()):
		queue_free()
		return
	collision_layer = 4
	collision_mask = 1 | 2
	var size := ModelSlot.slot_size(slot)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = minf(size.x, size.z) * 0.5
	capsule.height = maxf(size.y, capsule.radius * 2.0)
	shape.shape = capsule
	shape.position.y = capsule.height * 0.5
	add_child(shape)
	var look := ModelSlot.new()
	look.slot = slot
	add_child(look)
	health = Health.new()
	health.name = "Health"
	health.max_hp = max_hp
	health.team = "enemy"
	health.invulnerable_time = 0.15
	add_child(health)
	health.died.connect(_on_died)
	home = global_position
	_wander_to = home


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	var target := _target()
	var to := target - global_position
	to.y = 0
	var want := to.normalized() * speed if to.length() > 0.3 else Vector3.ZERO
	velocity.x = move_toward(velocity.x, want.x, speed * 4.0 * delta)
	velocity.z = move_toward(velocity.z, want.z, speed * 4.0 * delta)
	if want.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-want.x, -want.z), 1.0 - exp(-8.0 * delta))
	move_and_slide()
	for i in get_slide_collision_count():
		var body := get_slide_collision(i).get_collider()
		if body is Player:
			var player_health := Health.of(body)
			if player_health != null:
				player_health.damage(touch_damage)


## Fire a Shot from this enemy toward [param at] (for enemies that shoot; call it from your own script).
func fire_shot(at: Vector3) -> void:
	var shot := Shot.new()
	shot.team = "enemy"
	get_parent().add_child(shot)
	shot.global_position = global_position + Vector3.UP * 0.8
	shot.look_at(at + Vector3.UP * 0.8)


func _target() -> Vector3:
	var player := Levels.player
	if player != null and player.is_inside_tree() and global_position.distance_to(player.global_position) < sight_range:
		return player.global_position
	_wander_time -= get_physics_process_delta_time()
	if _wander_time <= 0.0:
		_wander_time = randf_range(2.0, 4.0)
		var angle := randf() * TAU
		_wander_to = home + Vector3(cos(angle), 0, sin(angle)) * randf() * wander_radius
	return _wander_to


func _defeated_flag() -> String:
	var id := str(owner.get_path_to(self)) if owner != null else String(name)
	return "defeated:%s:%s" % [Levels.current_id, id]


func _on_died() -> void:
	if stays_defeated:
		Game.set_flag(_defeated_flag())
	Game.report("defeated", {"enemy": enemy_id})
	Sound.play("defeat", global_position)
	if drop_item != "":
		var drop := Collectible.new()
		drop.item = drop_item
		drop.amount = drop_amount
		drop.name = "Drop_%s" % name
		get_parent().add_child(drop)
		drop.global_position = global_position
	queue_free()
