class_name Hud
extends CanvasLayer
## The on-screen display: what you are carrying (top left), your missions (top right), what you can do right now
## (bottom middle, "[E] Talk to Guide"), and short messages ("Mission complete!").

@export var player: Player
var _hearts: Hearts
var _inventory: Label
var _missions: Label
var _prompt: Label
var _toast: Label
var _toast_time := 0.0


func _ready() -> void:
	_hearts = Hearts.new()
	_hearts.position = Vector2(20, 16)
	add_child(_hearts)
	_inventory = _label(24, Vector2(20, 52))
	_missions = _label(20, Vector2(-20, 16))
	_missions.anchor_left = 1.0
	_missions.anchor_right = 1.0
	_missions.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_missions.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_prompt = _centered(26, 0.62)
	_toast = _centered(36, 0.2)
	_toast.add_theme_color_override("font_color", Color("#ffd23f"))
	Game.inventory_changed.connect(func(_i: String, _c: int) -> void: _refresh())
	Missions.started.connect(func(id: String) -> void: _say("New mission: " + String(Missions.definition(id).get("title", id))))
	Missions.advanced.connect(func(_id: String, _s: int) -> void: _refresh())
	Missions.completed.connect(_on_mission_completed)
	_refresh()


## Show a short message in big letters for a few seconds.
func say(text: String, seconds: float = 3.0) -> void:
	_say(text, seconds)


func _process(delta: float) -> void:
	_toast_time -= delta
	_toast.visible = _toast_time > 0.0
	var focus: Interactable = player.focus if player != null else null
	_prompt.visible = focus != null and not Dialogue.is_open
	if focus != null:
		_prompt.text = "[E] " + focus.prompt
	_refresh_missions()
	if player != null and player.health != null:
		_hearts.set_health(player.health.hp, player.health.max_hp)
		_hearts.visible = player.can_attack or player.health.hp < player.health.max_hp


func _refresh() -> void:
	var lines: PackedStringArray = []
	for item: String in Game.inventory:
		if Game.count(item) > 0:
			lines.append("%s  %d" % [GameData.item_name(item, Game.count(item)), Game.count(item)])
	_inventory.text = "\n".join(lines)


func _refresh_missions() -> void:
	var lines: PackedStringArray = []
	for id: String in Missions.active:
		lines.append(String(Missions.definition(id).get("title", id)))
		lines.append("  " + Missions.step_text(id))
	_missions.text = "\n".join(lines)


func _on_mission_completed(id: String) -> void:
	_say("Mission complete: " + String(Missions.definition(id).get("title", id)))
	Sound.play("mission_complete")
	_refresh()


func _say(text: String, seconds: float = 3.0) -> void:
	_toast.text = text
	_toast_time = seconds


func _label(size: int, offset: Vector2) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.position = offset
	add_child(label)
	return label


func _centered(size: int, at_height: float) -> Label:
	var label := _label(size, Vector2.ZERO)
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = at_height
	label.anchor_bottom = at_height
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.visible = false
	return label
