class_name Game
extends Node3D
## The playable session: procedural city, on-foot player, traffic, police heat,
## missions, radio, day/night cycle and the touch HUD.

signal quit_to_menu

const STATIONS := [
	{"file": "radio_synth", "name": "FM 6.6  NEON WAVE"},
	{"file": "radio_beat", "name": "FM 8.8  STREET BEAT"},
	{"file": "radio_electro", "name": "FM 9.9  VOLT CLUB"},
]
const TIME_SCALE := 1.0 / 600.0   # a full day every ten minutes

var city: City
var player: Player
var cam: CameraRig
var hud: HUD
var touch: TouchControls
var missions: Missions
var audio: AudioBank
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial

var vehicles: Array[Vehicle] = []
var police_cars: Array[Vehicle] = []
var active_vehicle: Vehicle = null
var wanted := 0.0
var cash := 500
var health := 100.0
var paused := false
var notice := ""
var message_timer := 0.0
var radio := 0
var time_of_day := 0.78

var _touch_move := Vector2.ZERO
var _touch_brake := false
var _touch_sprint := false
var _jump_edge := false
var _evade_timer := 0.0
var _spawn_cd := 0.0
var _touch_mode := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 6616
	_touch_mode = DisplayServer.is_touchscreen_available() or OS.get_cmdline_args().has("--touch")
	if audio == null:
		audio = AudioBank.new()
		audio.name = "AudioBank"
		add_child(audio)
	_build_environment()
	_build_city()
	_build_player()
	_build_traffic()
	_build_missions()
	_build_ui()
	if not _touch_mode and DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	audio.play_music(STATIONS[radio]["file"], -20.0)
	message("WELCOME TO NEON CITY 6", 3.0)


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.05, 0.06, 0.14)
	sky_mat.sky_horizon_color = Color(0.55, 0.28, 0.42)
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.05)
	sky_mat.ground_horizon_color = Color(0.2, 0.12, 0.2)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_density = 0.0016
	env.fog_light_color = Color(0.12, 0.08, 0.18)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32.0, 30.0, 0.0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.82, 0.7)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)


func _build_city() -> void:
	city = City.new()
	city.name = "City"
	city.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(city)
	city.build(20261121)


func _build_player() -> void:
	player = Player.new()
	player.name = "Player"
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.teleport(city.spawn_point + Vector3(0.0, 0.5, 0.0))

	cam = CameraRig.new()
	cam.name = "CameraRig"
	cam.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(cam)
	cam.set_target(player)


func _build_traffic() -> void:
	for i in 14:
		_spawn_traffic()
	for i in mini(18, city.parked_spots.size()):
		var v := _make_vehicle(city.parked_spots[i], _random_colour(), false)
		v.rotation.y = city.parked_yaws[i]
		v.is_parked = true


func _spawn_traffic() -> void:
	for attempt in 12:
		var idx := city.random_intersection()
		var p := city.grid_pos(idx.x, idx.y)
		if p.distance_to(city.spawn_point) < 45.0:
			continue
		var v := _make_vehicle(p, _random_colour(), false)
		v.start_traffic(idx)
		return


func _make_vehicle(pos: Vector3, colour: Color, is_police: bool) -> Vehicle:
	var v := Vehicle.new()
	v.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(v)
	v.setup(city, colour, is_police)
	v.position = pos
	v.crashed.connect(_on_crash.bind(v))
	vehicles.append(v)
	return v


func _random_colour() -> Color:
	var palette := [
		Color(0.85, 0.12, 0.2), Color(0.95, 0.55, 0.1), Color(0.15, 0.5, 0.95),
		Color(0.2, 0.8, 0.55), Color(0.9, 0.9, 0.95), Color(0.1, 0.1, 0.12),
		Color(0.6, 0.2, 0.8), Color(0.95, 0.85, 0.2),
	]
	return palette[_rng.randi_range(0, palette.size() - 1)]


func _build_missions() -> void:
	missions = Missions.new()
	missions.name = "Missions"
	add_child(missions)
	missions.setup(city, self)


func _build_ui() -> void:
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)
	hud = HUD.new()
	hud.game = self
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	hud_layer.add_child(hud)

	var touch_layer := CanvasLayer.new()
	touch_layer.layer = 11
	add_child(touch_layer)
	touch = TouchControls.new()
	touch.process_mode = Node.PROCESS_MODE_ALWAYS
	touch.visible = _touch_mode
	touch_layer.add_child(touch)
	touch.move_changed.connect(_on_touch_move)
	touch.look_delta.connect(_on_touch_look)
	touch.jump_pressed.connect(_on_touch_jump)
	touch.interact_pressed.connect(_interact)
	touch.brake_changed.connect(_on_touch_brake)
	touch.sprint_changed.connect(_on_touch_sprint)
	touch.pause_pressed.connect(_toggle_pause)
	touch.radio_pressed.connect(_next_station)


func _on_touch_move(v: Vector2) -> void:
	_touch_move = v


func _on_touch_look(d: Vector2) -> void:
	if cam != null:
		cam.look(d.x * 1.5, d.y * 1.5)


func _on_touch_jump() -> void:
	_jump_edge = true


func _on_touch_brake(on: bool) -> void:
	_touch_brake = on


func _on_touch_sprint(on: bool) -> void:
	_touch_sprint = on


func _physics_process(delta: float) -> void:
	if paused:
		return
	var move := _read_move()
	var sprint := _touch_sprint or Input.is_key_pressed(KEY_SHIFT)
	var brake := _touch_brake or Input.is_key_pressed(KEY_SPACE)

	if active_vehicle != null:
		active_vehicle.controls = Vector3(-move.y, -move.x, 1.0 if brake else 0.0)
	else:
		player.cam_yaw = cam.yaw
		player.move_input = move
		player.sprinting = sprint
		if _jump_edge:
			player.jump_queued = true
	_jump_edge = false

	_update_police(delta)

	if health < 100.0 and wanted < 0.5:
		health = minf(100.0, health + delta * 2.0)


func _process(delta: float) -> void:
	if paused:
		return
	time_of_day = fposmod(time_of_day + delta * TIME_SCALE, 1.0)
	_update_sky()
	if message_timer > 0.0:
		message_timer = maxf(0.0, message_timer - delta)
		if message_timer == 0.0:
			notice = ""
	if audio != null:
		if active_vehicle != null:
			audio.set_engine(true, active_vehicle.speed_ratio())
		else:
			audio.set_engine(false)
		audio.set_siren(wanted >= 0.5)


func _update_sky() -> void:
	if sun == null:
		return
	var daylight := clampf(sin((time_of_day - 0.25) * TAU), 0.0, 1.0)
	sun.rotation_degrees = Vector3(-78.0 + daylight * 52.0, 30.0 + time_of_day * 360.0, 0.0)
	sun.light_energy = 0.08 + daylight * 1.15
	sun.light_color = Color(1.0, 0.7, 0.5).lerp(Color(1.0, 0.96, 0.9), daylight)
	if sky_mat != null:
		sky_mat.sky_top_color = Color(0.01, 0.01, 0.05).lerp(Color(0.16, 0.34, 0.72), daylight)
		sky_mat.sky_horizon_color = Color(0.12, 0.03, 0.16).lerp(Color(0.95, 0.62, 0.45), daylight)
		sky_mat.ground_horizon_color = Color(0.05, 0.02, 0.08).lerp(Color(0.55, 0.45, 0.4), daylight)
		sky_mat.sun_angle_max = 20.0
	if env != null:
		env.ambient_light_energy = 0.18 + daylight * 0.55
		env.fog_light_color = Color(0.05, 0.03, 0.1).lerp(Color(0.55, 0.45, 0.45), daylight)
		env.fog_density = 0.0016 + (1.0 - daylight) * 0.0012


func _read_move() -> Vector2:
	var m := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		m.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		m.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		m.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		m.y += 1.0
	if Input.get_connected_joypads().size() > 0:
		var jx := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
		var jy := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
		if absf(jx) > 0.18:
			m.x += jx
		if absf(jy) > 0.18:
			m.y += jy
	m += _touch_move
	if m.length() > 1.0:
		m = m.normalized()
	return m


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		match k:
			KEY_E:
				_interact()
			KEY_SPACE:
				if active_vehicle == null:
					_jump_edge = true
			KEY_R:
				_next_station()
			KEY_ESCAPE:
				_toggle_pause()
			KEY_Q:
				if paused:
					_quit_to_menu()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if cam != null and not paused:
			var mm := event as InputEventMouseMotion
			cam.look(mm.relative.x, mm.relative.y)
	elif event is InputEventMouseButton and event.pressed and not _touch_mode:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not paused:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _interact() -> void:
	if paused:
		return
	if active_vehicle != null:
		_exit_vehicle()
		return
	var v := nearest_vehicle()
	if v != null:
		_enter_vehicle(v)


func nearest_vehicle() -> Vehicle:
	var best: Vehicle = null
	var best_d := 6.0
	var from: Node3D = focus_node()
	if from == null:
		return null
	for v in vehicles:
		if not is_instance_valid(v):
			continue
		var d := from.global_position.distance_to(v.global_position)
		if d < best_d:
			best_d = d
			best = v
	return best


func _enter_vehicle(v: Vehicle) -> void:
	active_vehicle = v
	v.driver = player
	v.autopilot = false
	v.is_parked = false
	v.controls = Vector3.ZERO
	v.collision_mask = 3
	player.visible = false
	player.set_physics_process(false)
	player.collision_layer = 0
	player.collision_mask = 0
	cam.set_target(v)
	sfx("enter_car")
	if v.police:
		wanted = minf(5.0, wanted + 1.5)
		message("POLICE CRUISER STOLEN", 2.0)
	else:
		message("ENGINE ON — W / UP TO DRIVE", 2.0)


func _exit_vehicle() -> void:
	if active_vehicle == null:
		return
	var v := active_vehicle
	active_vehicle = null
	v.driver = null
	v.autopilot = false
	v.collision_mask = 1
	var side := v.global_transform.basis.x.normalized()
	var p := v.global_position + side * 2.6 + Vector3(0.0, 1.0, 0.0)
	player.visible = true
	player.set_physics_process(true)
	player.collision_layer = 2
	player.collision_mask = 1
	player.teleport(p)
	cam.set_target(player)
	sfx("ui_click", -4.0)


func focus_node() -> Node3D:
	return active_vehicle if active_vehicle != null else player


func _update_police(delta: float) -> void:
	var focus := focus_node()
	if focus == null:
		return
	_spawn_cd = maxf(0.0, _spawn_cd - delta)
	var desired := clampi(int(ceil(wanted)), 0, 5)
	if police_cars.size() < desired and _spawn_cd <= 0.0:
		_spawn_police()
		_spawn_cd = 1.6
	while police_cars.size() > desired:
		_remove_farthest_police()

	var nearest := 99999.0
	for p in police_cars:
		if not is_instance_valid(p):
			continue
		p.chase_target = focus
		p.cruise_speed = 24.0
		nearest = minf(nearest, p.global_position.distance_to(focus.global_position))

	if wanted > 0.0:
		if nearest > 70.0:
			_evade_timer += delta
			if _evade_timer > 10.0:
				wanted = maxf(0.0, wanted - delta * 0.4)
		else:
			_evade_timer = 0.0
		if nearest < 8.0:
			health -= delta * 1.6
			wanted = minf(5.0, wanted + delta * 0.03)
	else:
		_evade_timer = 0.0

	if health <= 0.0:
		_busted()


func _spawn_police() -> void:
	var focus := focus_node()
	var best := Vector2i.ZERO
	var best_score := -1.0
	for i in 10:
		var idx := city.random_intersection()
		var p := city.grid_pos(idx.x, idx.y)
		var d := p.distance_to(focus.global_position)
		var score := d if d > 70.0 else d * 0.1
		if score > best_score:
			best_score = score
			best = idx
	var v := _make_vehicle(city.grid_pos(best.x, best.y), Color(0.93, 0.94, 1.0), true)
	v.start_traffic(best)
	v.cruise_speed = 24.0
	v.chase_target = focus
	police_cars.append(v)
	if wanted >= 0.5:
		message("POLICE INBOUND", 1.5)


func _remove_farthest_police() -> void:
	if police_cars.is_empty():
		return
	var focus := focus_node()
	var far: Vehicle = null
	var far_d := -1.0
	for p in police_cars:
		if not is_instance_valid(p):
			continue
		var d := p.global_position.distance_to(focus.global_position)
		if d > far_d:
			far_d = d
			far = p
	if far != null:
		police_cars.erase(far)
		vehicles.erase(far)
		far.queue_free()


func _clear_police() -> void:
	for p in police_cars:
		if is_instance_valid(p):
			vehicles.erase(p)
			p.queue_free()
	police_cars.clear()


func _on_crash(impact: float, v: Vehicle) -> void:
	if v == null or v != active_vehicle:
		return
	if impact > 7.0:
		sfx("crash", -2.0, 0.9 + minf(impact / 60.0, 0.6))
		health -= impact * 0.32
		wanted = minf(5.0, wanted + impact * 0.05)
		message("CRASH", 1.2)


func _busted() -> void:
	message("BUSTED — $300 FINE", 3.0)
	cash = maxi(0, cash - 300)
	health = 100.0
	wanted = 0.0
	if missions != null:
		missions.cancel()
	if active_vehicle != null:
		_exit_vehicle()
	_clear_police()
	player.teleport(city.spawn_point + Vector3(0.0, 1.0, 0.0))
	sfx("mission_fail")


func set_heat(value: float) -> void:
	wanted = clampf(value, 0.0, 5.0)


func add_cash(amount: int) -> void:
	cash += amount


func message(text: String, seconds := 2.5) -> void:
	notice = text
	message_timer = seconds


func sfx(name_: String, db := 0.0, pitch := 1.0) -> void:
	if audio != null:
		audio.sfx(name_, db, pitch)


func _next_station() -> void:
	radio = (radio + 1) % STATIONS.size()
	audio.play_music(STATIONS[radio]["file"], -18.0)
	message(STATIONS[radio]["name"], 2.0)
	sfx("radio_switch", -4.0)


func station_name() -> String:
	return STATIONS[radio]["name"]


func clock_string() -> String:
	var total := int(time_of_day * 24.0 * 60.0)
	var h := (total / 60) % 24
	var m := total % 60
	return "%02d:%02d" % [h, m]


func _toggle_pause() -> void:
	paused = not paused
	get_tree().paused = paused
	if DisplayServer.get_name() != "headless" and not _touch_mode:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED)


func _quit_to_menu() -> void:
	paused = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	quit_to_menu.emit()
