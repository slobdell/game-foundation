extends CanvasLayer
## AUTOLOAD `Dialogue`: the conversation box at the bottom of the screen.
##
## A dialogue file (data/dialogue/<id>.json):
##   {"id": "guide_hello",
##    "lines": [{"speaker": "Guide", "text": "Welcome!", "voice": "guide_hello_1"}],
##    "then": {"start_mission": "first_steps", "set_flag": "met_guide", "give": {"star": 1}},
##    "variants": [{"when": {"mission_done": "first_steps"}, "lines": [...], "then": {...}}]}
## The first variant whose "when" is true is used instead of the main lines. "when" can test
## mission_done, mission_active, flag, or has_item ({"has_item": {"star": 5}}).
## A line with "voice" plays assets/voices/<voice>.ogg (see the make-sound skill). Interact / Space / click
## moves on; after the last line the "then" actions happen.

signal opened(id: String)
signal closed(id: String)

var is_open := false
var current_id := ""
var _lines: Array = []
var _then: Dictionary = {}
var _index := 0
var _opened_frame := -1
var _panel: PanelContainer
var _speaker: Label
var _text: Label


func _ready() -> void:
	layer = 10
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.1
	_panel.anchor_right = 0.9
	_panel.anchor_top = 0.72
	_panel.anchor_bottom = 0.95
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.85)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", 22)
	_speaker.add_theme_color_override("font_color", Color("#ffd23f"))
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 24)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var hint := Label.new()
	hint.text = "[E] / Space / click to continue"
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(1, 1, 1, 0.6)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_speaker)
	box.add_child(_text)
	box.add_child(hint)
	_panel.add_child(box)
	_panel.visible = false
	add_child(_panel)


## Open dialogue [param id]. Returns false if the file has no lines to say.
func open(id: String) -> bool:
	var chosen := choose(GameData.dialogue(id))
	_lines = chosen.get("lines", [])
	if _lines.is_empty():
		push_error("dialogue '%s' has no lines (data/dialogue/%s.json)" % [id, id])
		return false
	_then = chosen.get("then", {})
	current_id = id
	_index = 0
	is_open = true
	_opened_frame = Engine.get_process_frames()
	_panel.visible = true
	_show_line()
	opened.emit(id)
	return true


## Move to the next line, or finish. (Also what the continue button does.)
func next() -> void:
	if not is_open:
		return
	_index += 1
	if _index < _lines.size():
		_show_line()
	else:
		_finish()


## Which lines and actions apply right now: the first variant whose "when" holds, else the main ones.
static func choose(data: Dictionary) -> Dictionary:
	for variant: Dictionary in data.get("variants", []):
		if condition_holds(variant.get("when", {})):
			return variant
	return data


static func condition_holds(when: Dictionary) -> bool:
	if when.has("mission_done") and not Missions.is_done(String(when["mission_done"])):
		return false
	if when.has("mission_active") and not Missions.is_active(String(when["mission_active"])):
		return false
	if when.has("flag") and not bool(Game.get_flag(String(when["flag"]))):
		return false
	for item: String in when.get("has_item", {}):
		if Game.count(item) < int(when["has_item"][item]):
			return false
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not is_open or Engine.get_process_frames() == _opened_frame:
		return
	var pressed: bool = event.is_action_pressed("interact") or event.is_action_pressed("jump") \
			or (event is InputEventMouseButton and event.pressed)
	if pressed:
		get_viewport().set_input_as_handled()
		next()


func _show_line() -> void:
	var line: Dictionary = _lines[_index]
	_speaker.text = String(line.get("speaker", ""))
	_text.text = String(line.get("text", ""))
	if line.has("voice"):
		Sound.voice(String(line["voice"]))


func _finish() -> void:
	is_open = false
	_panel.visible = false
	var id := current_id
	if _then.has("give"):
		for item: String in _then["give"]:
			Game.give(item, int(_then["give"][item]))
	if _then.has("set_flag"):
		Game.set_flag(String(_then["set_flag"]))
	if _then.has("start_mission"):
		Missions.start(String(_then["start_mission"]))
	closed.emit(id)
