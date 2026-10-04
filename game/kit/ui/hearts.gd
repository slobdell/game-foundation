class_name Hearts
extends Control
## Health as heart shapes, drawn rather than typed: the browser build's default font has no ♥ character
## (it showed empty boxes), and a drawn shape looks the same everywhere.

var hp := 0
var max_hp := 0
var size_px := 26.0
var full_color := Color("#ff4d6d")
var empty_color := Color(1, 1, 1, 0.35)


func set_health(current: int, maximum: int) -> void:
	if current != hp or maximum != max_hp:
		hp = current
		max_hp = maximum
		custom_minimum_size = Vector2(maximum * (size_px + 6), size_px)
		queue_redraw()


func _draw() -> void:
	for i in max_hp:
		var origin := Vector2(i * (size_px + 6), 0)
		var color := full_color if i < hp else empty_color
		draw_colored_polygon(_heart(origin, size_px + 4), Color(0, 0, 0, 0.6))
		draw_colored_polygon(_heart(origin + Vector2(2, 2), size_px), color)


static func _heart(origin: Vector2, s: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for step in 32:
		var t := step / 32.0 * TAU
		var x := 16.0 * pow(sin(t), 3)
		var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
		points.append(origin + Vector2(x / 34.0 + 0.5, y / 34.0 + 0.45) * s)
	return points
