class_name Intro
extends Control
## Original animated title sequence: a neon skyline, palms, a perspective
## grid and the NEON CITY 6 logo. Skippable with a tap or any key.

signal finished

const DURATION := 14.0

var t := 0.0
var _done := false
var _skyline: Array[Rect2] = []
var _windows: Array[Rect2] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.seed = 666
	_build_skyline()


func _build_skyline() -> void:
	var x := -0.02
	while x < 1.02:
		var w := _rng.randf_range(0.025, 0.075)
		var h := _rng.randf_range(0.08, 0.34)
		_skyline.append(Rect2(x, 1.0 - h, w, h))
		for k in _rng.randi_range(2, 7):
			_windows.append(Rect2(
				x + _rng.randf_range(0.004, w - 0.012),
				1.0 - h + _rng.randf_range(0.01, h - 0.02),
				0.006, 0.012))
		x += w + _rng.randf_range(0.004, 0.014)


func _input(event: InputEvent) -> void:
	if _done or t < 0.7:
		return
	if event is InputEventScreenTouch and event.pressed:
		_finish()
	elif event is InputEventMouseButton and event.pressed:
		_finish()
	elif event is InputEventKey and event.pressed:
		_finish()


func _process(delta: float) -> void:
	if _done:
		return
	t += delta
	queue_redraw()
	if t >= DURATION:
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()


func _fade(start: float, end: float) -> float:
	if t < start or t > end:
		return 0.0
	return clampf(minf((t - start) / 0.7, (end - t) / 0.7), 0.0, 1.0)


func _draw() -> void:
	var s := size
	if s.x < 10.0:
		return
	var font := ThemeDB.fallback_font
	_draw_background(s)

	var city_a := _fade(0.8, 12.8)
	var rise := clampf((t - 0.8) / 2.2, 0.0, 1.0)
	_draw_skyline(s, (1.0 - rise) * 120.0, city_a)
	_draw_grid(s, _fade(1.6, 12.8) * 0.8)
	_draw_palms(s, city_a)

	var present := _fade(0.2, 2.6)
	if present > 0.0:
		_glow_text(s, "MDMUNTAKIM  PRESENTS", Vector2(s.x * 0.5, s.y * 0.28),
				18, Color(0.8, 0.9, 1.0, present * 0.8), 0.0)

	var title_a := _fade(2.8, 12.5)
	if title_a > 0.0:
		var flick := 1.0
		if sin(t * 31.0) > 0.965 or sin(t * 7.0) > 0.992:
			flick = 0.35
		var ts := int(minf(s.x * 0.115, s.y * 0.185))
		var six := int(ts * 1.85)
		var col := Color(0.35, 1.0, 1.0, title_a * flick)
		var pink := Color(1.0, 0.2, 0.62, title_a * flick)
		var title := "NEON CITY"
		var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x
		var sw := font.get_string_size("6", HORIZONTAL_ALIGNMENT_LEFT, -1, six).x
		var gap := ts * 0.22
		var left := s.x * 0.5 - (tw + gap + sw) * 0.5
		var base_y := s.y * 0.53
		_glow_text_at(title, Vector2(left, base_y), ts, col, 1.0)
		var six_pos := Vector2(left + tw + gap, base_y)
		_glow_text_at("6", six_pos, six, pink, 1.0)
		_glow_text_at("6", six_pos + Vector2(-5.0, 0.0), six,
				Color(0.2, 0.95, 1.0, title_a * flick * 0.5), 0.0)

	var tag := _fade(8.0, 12.6)
	if tag > 0.0:
		_glow_text(s, "OWN  THE  NIGHT", Vector2(s.x * 0.5, s.y * 0.86),
				24, Color(1.0, 0.85, 0.55, tag), 0.0)

	var fade := clampf((t - 12.6) / 1.4, 0.0, 1.0)
	if fade > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.0, 0.0, 0.02, fade))

	for y in range(0, int(s.y), 4):
		draw_line(Vector2(0, y), Vector2(s.x, y), Color(0, 0, 0, 0.045))


func _draw_background(s: Vector2) -> void:
	var top := Color(0.02, 0.01, 0.07)
	var bottom := Color(0.16, 0.02, 0.16)
	var strips := 28
	for i in strips:
		var k := float(i) / strips
		draw_rect(Rect2(0.0, s.y * k, s.x, s.y / strips + 1.0),
				top.lerp(bottom, k))
	var glow := Color(0.5, 0.05, 0.35, 0.10)
	draw_circle(Vector2(s.x * 0.5, s.y * 0.55), s.y * 0.7, glow)


func _draw_skyline(s: Vector2, drop: float, alpha: float) -> void:
	if alpha <= 0.0:
		return
	for r in _skyline:
		var rect := Rect2(r.position.x * s.x, r.position.y * s.y + drop,
				r.size.x * s.x, r.size.y * s.y)
		draw_rect(rect, Color(0.015, 0.01, 0.04, alpha * 0.95))
	for w in _windows:
		draw_rect(Rect2(w.position.x * s.x, w.position.y * s.y + drop,
				w.size.x * s.x, w.size.y * s.y),
				Color(0.4, 0.9, 1.0, alpha * 0.5))


func _draw_grid(s: Vector2, alpha: float) -> void:
	if alpha <= 0.0:
		return
	var horizon := s.y * 0.66
	var cx := s.x * 0.5
	var col := Color(1.0, 0.2, 0.65, alpha * 0.35)
	for i in 15:
		var k := float(i) / 14.0
		var x := cx + (k - 0.5) * s.x * 3.2
		draw_line(Vector2(cx, horizon), Vector2(x, s.y), col, 1.5)
	var y := horizon
	var step := 4.0
	for i in 18:
		draw_line(Vector2(0, y), Vector2(s.x, y), col, 1.5)
		y += step
		step *= 1.32


func _draw_palms(s: Vector2, alpha: float) -> void:
	if alpha <= 0.0:
		return
	_palm(Vector2(s.x * 0.06, s.y), s.y * 0.42, alpha, -0.12)
	_palm(Vector2(s.x * 0.94, s.y), s.y * 0.48, alpha, 0.14)


func _palm(base: Vector2, height: float, alpha: float, lean: float) -> void:
	var top := base + Vector2(lean * height, -height)
	var col := Color(0.01, 0.01, 0.03, alpha)
	draw_line(base, top, col, maxf(4.0, height * 0.03))
	for i in 7:
		var ang := -PI * 0.95 + i * (PI * 0.95 / 6.0)
		var tip := top + Vector2(cos(ang), sin(ang) * 0.55) * height * 0.36
		draw_line(top, tip, col, maxf(3.0, height * 0.022))
		draw_line(top + Vector2(0, 4), tip + Vector2(0, 10), col, maxf(1.5, height * 0.012))


func _glow_text(s: Vector2, text: String, center: Vector2, font_size: int,
		col: Color, glow: float) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_glow_text_at(text, Vector2(center.x - w * 0.5, center.y), font_size, col, glow)


func _glow_text_at(text: String, pos: Vector2, font_size: int,
		col: Color, glow: float) -> void:
	var font := ThemeDB.fallback_font
	if glow > 0.0:
		var gc := Color(col.r, col.g, col.b, col.a * 0.16 * glow)
		for off in [Vector2(-5, 0), Vector2(5, 0), Vector2(0, -5), Vector2(0, 5),
				Vector2(-9, 0), Vector2(9, 0)]:
			draw_string(font, pos + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
					font_size + 2, gc)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
