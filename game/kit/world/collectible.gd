class_name Collectible
extends Area3D
## Walk into it to pick it up: gives [member item] x [member amount], plays a sound, and disappears.
## Remembered in the save, so it stays collected when you come back to the level.

@export var item := "star"
@export var amount := 1
## The visual slot to show; empty = the item's slot from data/items.json.
@export var slot := ""
@export var sound := "pickup"
@export var spin_speed := 2.0

var _look: ModelSlot
var _time := 0.0


func _ready() -> void:
	add_to_group("collectible")
	if Game.get_flag(_taken_flag()):
		queue_free()
		return
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.8
	shape.shape = sphere
	shape.position.y = 0.8
	add_child(shape)
	_look = ModelSlot.new()
	_look.slot = slot if slot != "" else String(GameData.items().get(item, {}).get("slot", "pickup_star"))
	add_child(_look)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	if _look != null:
		_look.rotation.y += spin_speed * delta
		_look.position.y = 0.3 + sin(_time * 2.0) * 0.15


func _taken_flag() -> String:
	var id := str(owner.get_path_to(self)) if owner != null else String(name)
	return "taken:%s:%s" % [Levels.current_id, id]


func _on_body_entered(body: Node3D) -> void:
	if not body is Player:
		return
	Game.set_flag(_taken_flag())
	Game.give(item, amount)
	Game.report("collected", {"item": item, "amount": amount})
	Sound.play(sound, global_position)
	queue_free()
