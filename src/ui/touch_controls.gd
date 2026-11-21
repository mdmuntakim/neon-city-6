class_name TouchControls
extends Control
## Multitouch overlay: left thumbstick, right-side drag look, and action
## buttons. Mouse input is emulated as touch by project.godot, so the same
## code drives desktop testing and phones.

signal move_changed(v: Vector2)
signal look_delta(d: Vector2)
signal jump_pressed
signal interact_pressed
signal brake_changed(on: bool)
signal sprint_changed(on: bool)
signal pause_pressed
signal radio_pressed

var move := Vector2.ZERO
var brake := false
var sprint := false

var _stick_id := -1
var _look_id := -1
var _brake_id := -1
var _sprint_id := -1
var _jump_id := -1
var _interact_id := -1
var _look_last := Vector2.ZERO
var _stick_center := Vector2.ZERO
var _stick_radius := 92.0
var _labels: Array[Dictionary] = []
var _pressed: Array[String] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _layout() -> void:
	var s := size
	_stick_center = Vector2(150.0, s.y - 160.0)
	_stick_radius = clampf(minf(s.x, s.y) * 0.13, 70.0, 110.0)
	_labels = [
		{"id": "jump", "pos": Vector2(s.x - 110.0, s.y - 130.0), "r": 54.0, "text": "JUMP"},
		{"id": "interact", "pos": Vector2(s.x - 225.0, s.y - 190.0), "r": 44.0, "text": "USE"},
		{"id": "brake", "pos": Vector2(s.x - 110.0, s.y - 265.0), "r": 40.0, "text": "DRIFT"},
		{"id": "sprint", "pos": Vector2(s.x - 330.0, s.y - 120.0), "r": 40.0, "text": "RUN"},
		{"id": "pause", "pos": Vector2(s.x - 52.0, 48.0), "r": 30.0, "text": "II"},
		{"id": "radio", "pos": Vector2(s.x - 125.0, 48.0), "r": 30.0, "text": "FM"},
	]


func _process(_delta: float) -> void:
	queue_redraw()


func _button_at(p: Vector2) -> String:
	for b in _labels:
		if p.distance_to(b["pos"]) <= b["r"] + 10.0:
			return str(b["id"])
	return ""


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_on_press(t.index, t.position)
		else:
			_on_release(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_on_drag(d.index, d.position)


func _on_press(id: int, p: Vector2) -> void:
	var btn := _button_at(p)
	if btn == "pause":
		pause_pressed.emit()
		return
	if btn == "radio":
		radio_pressed.emit()
		return
	if btn == "jump":
		_jump_id = id
		jump_pressed.emit()
		return
	if btn == "interact":
		_interact_id = id
		interact_pressed.emit()
		return
	if btn == "brake":
		_brake_id = id
		brake = true
		brake_changed.emit(true)
		return
	if btn == "sprint":
		_sprint_id = id
		sprint = true
		sprint_changed.emit(true)
		return
	if p.x < size.x * 0.46 and p.y > size.y * 0.30:
		if _stick_id == -1:
			_stick_id = id
			_update_stick(p)
	elif p.x > size.x * 0.46:
		if _look_id == -1:
			_look_id = id
			_look_last = p


func _on_release(id: int) -> void:
	if id == _stick_id:
		_stick_id = -1
		move = Vector2.ZERO
		move_changed.emit(move)
	elif id == _look_id:
		_look_id = -1
	elif id == _brake_id:
		_brake_id = -1
		brake = false
		brake_changed.emit(false)
	elif id == _sprint_id:
		_sprint_id = -1
		sprint = false
		sprint_changed.emit(false)
	elif id == _jump_id:
		_jump_id = -1
	elif id == _interact_id:
		_interact_id = -1


func _on_drag(id: int, p: Vector2) -> void:
	if id == _stick_id:
		_update_stick(p)
	elif id == _look_id:
		look_delta.emit(p - _look_last)
		_look_last = p


func _update_stick(p: Vector2) -> void:
	var v := (p - _stick_center) / _stick_radius
	if v.length() > 1.0:
		v = v.normalized()
	move = v
	move_changed.emit(move)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var dim := Color(0.02, 0.02, 0.05, 0.35)
	var edge := Color(0.2, 0.95, 1.0, 0.65)

	draw_circle(_stick_center, _stick_radius, Color(0.05, 0.06, 0.1, 0.35))
	draw_arc(_stick_center, _stick_radius, 0.0, TAU, 48, edge, 3.0, true)
	draw_circle(_stick_center + move * _stick_radius, _stick_radius * 0.38,
			Color(0.2, 0.95, 1.0, 0.55))

	for b in _labels:
		var p: Vector2 = b["pos"]
		var r: float = b["r"]
		draw_circle(p, r, dim)
		draw_arc(p, r, 0.0, TAU, 36, edge, 2.5, true)
		var txt: String = b["text"]
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string(font, p + Vector2(-w * 0.5, 6.0), txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.85, 0.95, 1.0))
