class_name Health
extends Node
## Hit points. Put one under anything that can be hurt (the player, an enemy, a breakable crate).
## Shots and enemies look for a child called "Health" and call damage().

signal changed(hp: int, max_hp: int)
signal died

@export var max_hp := 5
## Seconds of safety after a hit, so one touch doesn't take all your hearts at once.
@export var invulnerable_time := 0.6
## "player" or "enemy": shots never hurt their own team.
@export var team := "enemy"

var hp := 0
var _safe_until := 0.0


func _ready() -> void:
	hp = max_hp


static func of(node: Node) -> Health:
	return node.get_node_or_null("Health") as Health if node != null else null


## Returns whether the hit landed.
func damage(amount: int) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if hp <= 0 or now < _safe_until:
		return false
	hp = maxi(0, hp - amount)
	_safe_until = now + invulnerable_time
	changed.emit(hp, max_hp)
	if hp == 0:
		died.emit()
	return true


func heal(amount: int) -> void:
	hp = mini(max_hp, hp + amount)
	changed.emit(hp, max_hp)


func refill() -> void:
	hp = max_hp
	_safe_until = 0.0
	changed.emit(hp, max_hp)


## No damage for [param seconds] (after respawning, so you aren't hit again straight away).
func grace(seconds: float) -> void:
	_safe_until = Time.get_ticks_msec() / 1000.0 + seconds
