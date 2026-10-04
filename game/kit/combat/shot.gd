class_name Shot
extends Area3D
## A projectile. Flies straight, hurts the first thing of the OTHER team it touches, disappears on walls.

@export var speed := 22.0
@export var damage := 1
@export var life := 1.5
@export var team := "player"
@export var slot := "shot"


func _ready() -> void:
	add_to_group("shots")
	collision_layer = 0
	# world + whoever is on the other side (player = layer 2, creatures = layer 3)
	collision_mask = 1 | (4 if team == "player" else 2)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	shape.shape = sphere
	add_child(shape)
	var look := ModelSlot.new()
	look.slot = slot
	look.position.y = -ModelSlot.slot_size(slot).y * 0.5
	add_child(look)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += -global_transform.basis.z * speed * delta
	life -= delta
	if life <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	var health := Health.of(body)
	if health != null and health.team == team:
		return
	if health != null:
		health.damage(damage)
		Sound.play("hit", global_position)
	queue_free()
