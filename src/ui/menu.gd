class_name Menu
extends Control
## Title screen. Neon logo, animated grid, and three buttons.

signal start_requested

var _t := 0.0
var _show_controls := false
var _play: Button
var _controls_btn: Button
var _quit: Button
var _logo: Texture2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_logo = _tex("res://icon.svg")
	_build_buttons()
	call_deferred("_layout")


func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _style(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.07, 0.85)
	sb.border_color = col
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 22.0
	sb.content_margin_right = 22.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	return sb


func _build_buttons() -> void:
	var col := Color(0.25, 1.0, 1.0)
	_play = _button("PLAY", col)
	_play.pressed.connect(func() -> void: start_requested.emit())
	_controls_btn = _button("CONTROLS", col)
	_controls_btn.pressed.connect(func() -> void:
		_show_controls = not _show_controls
		_controls_btn.text = "HIDE CONTROLS" if _show_controls else "CONTROLS")
	_quit = _button("QUIT", Color(1.0, 0.3, 0.6))
	_quit.pressed.connect(func() -> void: get_tree().quit())


func _button(text: String, col: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", Color(0.85, 0.97, 1.0))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _style(col))
	b.add_theme_stylebox_override("hover", _style(col.lightened(0.25)))
	b.add_theme_stylebox_override("pressed", _style(col.darkened(0.25)))
	b.add_theme_stylebox_override("focus", _style(col))
	add_child(b)
	return b


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _layout() -> void:
	if _play == null:
		return
	var s := size
	var bw := clampf(s.x * 0.24, 220.0, 340.0)
	var bh := 58.0
	var x := s.x * 0.5 - bw * 0.5
	var y := s.y * 0.56
	for b in [_play, _controls_btn, _quit]:
		b.position = Vector2(x, y)
		b.size = Vector2(bw, bh)
		y += bh + 16.0


func _draw() -> void:
	var s := size
	if s.x < 10.0:
		return
	var font := ThemeDB.fallback_font
	var top := Color(0.02, 0.01, 0.06)
	var bottom := Color(0.12, 0.02, 0.15)
	for i in 30:
		var k := float(i) / 30.0
		draw_rect(Rect2(0.0, s.y * k, s.x, s.y / 30.0 + 1.0), top.lerp(bottom, k))

	# Horizon grid.
	var horizon := s.y * 0.62
	var col := Color(1.0, 0.2, 0.65, 0.20)
	for i in 15:
		var k := float(i) / 14.0
		draw_line(Vector2(s.x * 0.5, horizon),
				Vector2(s.x * 0.5 + (k - 0.5) * s.x * 3.2, s.y), col, 1.4)
	var y := horizon
	var step := 4.0
	for i in 16:
		draw_line(Vector2(0, y), Vector2(s.x, y), col, 1.4)
		y += step
		step *= 1.34

	# Skyline.
	var rng := RandomNumberGenerator.new()
	rng.seed = 66
	var bx := -0.02
	while bx < 1.02:
		var w := rng.randf_range(0.03, 0.08)
		var h := rng.randf_range(0.10, 0.30)
		draw_rect(Rect2(bx * s.x, s.y * (0.62 - h), w * s.x, s.y * h),
				Color(0.015, 0.01, 0.035))
		for k in rng.randi_range(2, 6):
			draw_rect(Rect2((bx + rng.randf_range(0.004, w - 0.01)) * s.x,
					s.y * (0.62 - h) + rng.randf_range(6.0, s.y * h * 0.8),
					3.0, 5.0), Color(0.4, 0.9, 1.0, 0.45))
		bx += w + rng.randf_range(0.004, 0.012)

	if _logo != null:
		var lw := clampf(s.x * 0.11, 84.0, 128.0)
		draw_texture_rect(_logo, Rect2(s.x * 0.5 - lw * 0.5, s.y * 0.06, lw, lw), false)

	var ts := int(clampf(s.x * 0.085, 40.0, 92.0))
	_glow("NEON CITY", Vector2(s.x * 0.5, s.y * 0.36), ts, Color(0.35, 1.0, 1.0))
	_glow("6", Vector2(s.x * 0.5 + s.x * 0.23, s.y * 0.36), int(ts * 1.5),
			Color(1.0, 0.2, 0.62))

	var sub := "AN ORIGINAL OPEN-WORLD DRIVING GAME"
	var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(font, Vector2(s.x * 0.5 - sw * 0.5, s.y * 0.45), sub,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.75, 0.82, 0.95))

	if _show_controls:
		var lines := [
			"WASD / LEFT STICK  —  move, steer and drive",
			"SHIFT / RUN  —  sprint on foot",
			"SPACE / JUMP  —  jump; handbrake while driving",
			"E / USE  —  enter or leave the nearest car",
			"R / FM  —  change radio station",
			"ESC  —  pause      Q  —  quit to menu",
			"Touch: left thumbstick, drag right side to look,",
			"       JUMP / USE / DRIFT / RUN buttons",
		]
		var yy := s.y * 0.80
		for l in lines:
			var w := font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_string(font, Vector2(s.x * 0.5 - w * 0.5, yy), l,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.88, 1.0))
			yy += 22.0

	var foot := "v1.0.0   original art, audio and code   tools/gtaconv.py asset optimiser"
	var fw := font.get_string_size(foot, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, Vector2(s.x * 0.5 - fw * 0.5, s.y - 16.0), foot,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.62, 0.78))


func _glow(text: String, center: Vector2, font_size: int, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pos := Vector2(center.x - w * 0.5, center.y)
	for off in [Vector2(-5, 0), Vector2(5, 0), Vector2(0, -5), Vector2(0, 5)]:
		draw_string(font, pos + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size + 2, Color(col.r, col.g, col.b, 0.14))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
