class_name Npc
extends Interactable
## A character you can talk to. Talking opens its dialogue (data/dialogue/<dialogue>.json) in the HUD and
## tells the missions "talked to <npc_id>".

@export var npc_id := "guide"
@export var display_name := "Guide"
@export var dialogue := ""
@export var slot := "npc_guide"


func _ready() -> void:
	prompt = "Talk to %s" % display_name
	super._ready()
	var look := ModelSlot.new()
	look.slot = slot
	add_child(look)
	# A solid body so the player bumps into the character instead of walking through it.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	var size := ModelSlot.slot_size(slot)
	capsule.radius = minf(size.x, size.z) * 0.5
	capsule.height = size.y
	shape.shape = capsule
	shape.position.y = size.y * 0.5
	body.add_child(shape)
	add_child(body)


func _on_interact(by: Node3D) -> void:
	# Face whoever is talking.
	var to := by.global_position - global_position
	if Vector2(to.x, to.z).length() > 0.1:
		rotation.y = atan2(-to.x, -to.z)
	Game.report("talked", {"npc": npc_id})
	if dialogue != "":
		Dialogue.open(dialogue)
