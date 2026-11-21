class_name HUD
extends Control
## All gameplay UI is drawn in one pass: minimap, cash, heat stars, health,
## mission tracker, speedometer and toasts. No external UI assets.

var game


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _map_rect() -> Rect2:
	var s := size
	var m := clampf(minf(s.x, s.y) * 0.235, 128.0, 210.0)
	return Rect2(18.0, 18.0, m, m)


func _w2m(p: Vector3) -> Vector2:
	var r := _map_rect()
	var sc := r.size.x / (City.EXTENT * 2.0 + 24.0)
	return r.position + r.size * 0.5 + Vector2(p.x, p.z) * sc


func _draw() -> void:
	if game == null:
		return
	var s := size
	var font := ThemeDB.fallback_font
	_draw_minimap(font)
	_draw_status(font, s)
	if game.active_vehicle != null:
		_draw_speed(font, s)
	if game.missions != null and game.missions.active:
		_draw_mission(font)
	_draw_toast(font, s)
	_draw_hint(font, s)
	if game.paused:
		_draw_pause(font, s)


func _draw_minimap(font: Font) -> void:
	var r := _map_rect()
	draw_rect(r, Color(0.02, 0.03, 0.07, 0.78))
	draw_rect(r, Color(0.2, 0.95, 1.0, 0.55), false, 2.0)

	# Roads of the procedural grid.
	for i in City.GRID + 1:
		var c := (i - City.GRID * 0.5) * City.CELL
		var a := _w2m(Vector3(c, 0.0, -City.EXTENT))
		var b := _w2m(Vector3(c, 0.0, City.EXTENT))
		draw_line(a, b, Color(0.25, 0.3, 0.4, 0.85), 2.0)
		var a2 := _w2m(Vector3(-City.EXTENT, 0.0, c))
		var b2 := _w2m(Vector3(City.EXTENT, 0.0, c))
		draw_line(a2, b2, Color(0.25, 0.3, 0.4, 0.85), 2.0)

	if game.missions != null:
		for m in game.missions.markers:
			if is_instance_valid(m) and m.visible:
				draw_circle(_w2m(m.global_position), 3.0, Color(1.0, 0.85, 0.2))
		if game.missions.active:
			var t: Vector3 = game.missions.target_position()
			draw_circle(_w2m(t), 4.0, Color(1.0, 0.3, 0.6))

	for v in game.vehicles:
		if not is_instance_valid(v) or v == game.active_vehicle:
			continue
		var col := Color(0.85, 0.9, 1.0, 0.8)
		if v.police:
			col = Color(1.0, 0.2, 0.25)
		draw_circle(_w2m(v.global_position), 1.7, col)

	var focus: Node3D = game.active_vehicle if game.active_vehicle != null else game.player
	if focus != null:
		var p := _w2m(focus.global_position)
		var yaw: float = game.cam.yaw if game.cam != null else 0.0
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var right := Vector2(-fwd.y, fwd.x)
		var tri := PackedVector2Array([
			p + fwd * 7.0,
			p - fwd * 4.0 + right * 4.0,
			p - fwd * 4.0 - right * 4.0,
		])
		draw_colored_polygon(tri, Color(0.3, 1.0, 1.0))
		draw_polyline(tri + PackedVector2Array([tri[0]]), Color(0.01, 0.05, 0.08), 1.5)


func _draw_status(font: Font, s: Vector2) -> void:
	var x := s.x - 26.0
	var y := 34.0
	var cash := "$%d" % game.cash
	var cw := font.get_string_size(cash, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	draw_string(font, Vector2(x - cw, y), cash, HORIZONTAL_ALIGNMENT_LEFT, -1, 26,
			Color(0.45, 1.0, 0.6))

	# Heat stars.
	var stars := int(ceil(game.wanted))
	for i in 5:
		var center := Vector2(x - 18.0 - i * 26.0, 68.0)
		var col := Color(1.0, 0.25, 0.3) if i < stars else Color(0.25, 0.28, 0.35)
		_draw_star(center, 10.0, col)

	# Health.
	var hw := 170.0
	var hx := x - hw
	var hy := 88.0
	draw_rect(Rect2(hx, hy, hw, 12.0), Color(0.1, 0.1, 0.14, 0.8))
	var frac := clampf(game.health / 100.0, 0.0, 1.0)
	var hcol := Color(0.3, 1.0, 0.5).lerp(Color(1.0, 0.2, 0.2), 1.0 - frac)
	draw_rect(Rect2(hx, hy, hw * frac, 12.0), hcol)
	draw_rect(Rect2(hx, hy, hw, 12.0), Color(0.2, 0.95, 1.0, 0.4), false, 1.5)

	var clock: String = game.clock_string()
	draw_string(font, Vector2(x - 100.0, 126.0), clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			Color(0.75, 0.82, 0.95))


func _draw_star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var ang := -PI * 0.5 + i * PI / 5.0
		var rad := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
	draw_colored_polygon(pts, col)


func _draw_speed(font: Font, s: Vector2) -> void:
	var v: Vehicle = game.active_vehicle
	var kmh := int(round(absf(v.speed) * 3.6))
	var txt := "%03d" % kmh
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 54).x
	var base := Vector2(s.x * 0.5 - w * 0.5, s.y - 42.0)
	draw_string(font, base + Vector2(2, 2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 54,
			Color(0.0, 0.0, 0.0, 0.6))
	draw_string(font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 54,
			Color(0.35, 1.0, 1.0))
	draw_string(font, base + Vector2(w + 12.0, -4.0), "km/h",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 0.8, 0.9))
	var station: String = game.station_name()
	draw_string(font, Vector2(s.x * 0.5 - 90.0, s.y - 78.0), station,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.4, 0.75))


func _draw_mission(font: Font) -> void:
	var m = game.missions
	var x := 24.0
	var y := _map_rect().position.y + _map_rect().size.y + 34.0
	var title: String = m.title()
	draw_string(font, Vector2(x, y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
			Color(1.0, 0.4, 0.75))
	var secs := int(ceil(m.time_left))
	draw_string(font, Vector2(x, y + 26.0), "%d:%02d" % [secs / 60, secs % 60],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.4, 1.0, 1.0))
	var d: float = m.target_distance()
	if m.kind != Missions.HEAT:
		draw_string(font, Vector2(x, y + 50.0), "%d m" % int(d),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.85, 0.9, 1.0))
	else:
		draw_string(font, Vector2(x, y + 50.0), "LOSE THE COPS",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.85, 0.9, 1.0))


func _draw_toast(font: Font, s: Vector2) -> void:
	if game.notice == "" or game.message_timer <= 0.0:
		return
	var a := clampf(game.message_timer, 0.0, 1.0)
	var w := font.get_string_size(game.notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	var p := Vector2(s.x * 0.5 - w * 0.5, s.y * 0.2)
	draw_rect(Rect2(p.x - 22.0, p.y - 32.0, w + 44.0, 48.0), Color(0.02, 0.02, 0.06, 0.65 * a))
	draw_string(font, p, game.notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 26,
			Color(1.0, 0.95, 0.7, a))


func _draw_hint(font: Font, s: Vector2) -> void:
	if game.active_vehicle != null:
		return
	var near: Vehicle = game.nearest_vehicle()
	if near == null:
		return
	var txt := "USE / E  —  TAKE THE %s" % ("POLICE CAR" if near.police else "CAR")
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(font, Vector2(s.x * 0.5 - w * 0.5, s.y - 100.0), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.5, 1.0, 1.0))


func _draw_pause(font: Font, s: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.01, 0.01, 0.04, 0.72))
	var title := "PAUSED"
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
	draw_string(font, Vector2(s.x * 0.5 - tw * 0.5, s.y * 0.4), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(0.35, 1.0, 1.0))
	var lines := [
		"WASD / LEFT STICK  —  MOVE + DRIVE",
		"E / USE  —  ENTER OR LEAVE A CAR",
		"SHIFT / RUN  —  SPRINT",
		"SPACE / JUMP  —  JUMP, HANDBRAKE IN A CAR",
		"R / FM  —  NEXT RADIO STATION",
		"ESC  —  RESUME     Q  —  QUIT TO MENU",
	]
	var y := s.y * 0.5
	for l in lines:
		var w := font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string(font, Vector2(s.x * 0.5 - w * 0.5, y), l,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.8, 0.88, 1.0))
		y += 30.0
