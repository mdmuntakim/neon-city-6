extends SceneTree
## Engine-side test suite. Run with:
##   godot --headless -s tests/run_tests.gd
## Exits 0 on success, 1 on failure.

var failures: Array[String] = []
var checks := 0


class StubGame extends Node3D:
	var cash := 0
	var heat := 0.0
	var last_message := ""
	var sfx_count := 0

	func focus_node() -> Node3D:
		return self

	func message(text: String, _seconds := 2.5) -> void:
		last_message = text

	func sfx(_name: String, _db := 0.0, _pitch := 1.0) -> void:
		sfx_count += 1

	func add_cash(amount: int) -> void:
		cash += amount

	func set_heat(value: float) -> void:
		heat = value


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	await test_city()
	await test_vehicle()
	await test_missions()
	await test_assets()
	await test_game()
	if failures.is_empty():
		print("ALL TESTS PASSED (%d checks)" % checks)
		quit(0)
	else:
		for f in failures:
			print("FAIL: " + f)
		print("%d checks, %d failures" % [checks, failures.size()])
		quit(1)


func check(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("  ok: " + label)
	else:
		failures.append(label)
		print("  fail: " + label)


func test_city() -> void:
	print("city")
	var city := City.new()
	root.add_child(city)
	city.build(4242)
	check(city.building_count > 60, "city generated buildings")
	check(city.intersections.size() == (City.GRID + 1) * (City.GRID + 1),
			"road grid has 7x7 intersections")
	check(city.mission_spots.size() >= 12, "mission spots exist")
	check(city.parked_spots.size() >= 18, "parked car spots exist")
	check(city.spawn_point.y > 0.5, "spawn point is above the road")
	var d := fmod(absf(city.spawn_point.x), City.CELL)
	check(minf(d, City.CELL - d) < City.ROAD * 0.5, "spawn point lies on a road")
	check(city.next_index(Vector2i(0, 0), Vector2i(0, 0)) != Vector2i(0, 0),
			"traffic graph offers a next intersection")
	city.free()


func test_vehicle() -> void:
	print("vehicle")
	var city := City.new()
	root.add_child(city)
	city.build(7)
	var v := Vehicle.new()
	root.add_child(v)
	v.setup(city, Color(0.9, 0.2, 0.2), false)
	v.start_traffic(Vector2i(3, 3))
	var start := v.global_position
	for i in 40:
		await physics_frame
	check(v.global_position.distance_to(start) > 1.0, "traffic car drives its route")
	check(v.speed > 1.0, "traffic car has forward speed")

	v.autopilot = false
	var dummy := Node3D.new()
	root.add_child(dummy)
	v.driver = dummy
	v.controls = Vector3(1.0, 0.0, 0.0)
	var before := v.global_position
	for i in 35:
		await physics_frame
	check(v.speed > 3.0, "throttle accelerates the car")
	check(v.global_position.distance_to(before) > 2.0, "driven car moves in the world")

	var fast := v.speed
	v.controls = Vector3(0.0, 0.0, 1.0)
	for i in 20:
		await physics_frame
	check(v.speed < fast - 2.0 or absf(v.speed) < 2.0, "handbrake slows the car (%.1f -> %.1f)" % [fast, v.speed])
	check(v.speed_ratio() <= 1.0, "speed ratio stays normalised")

	v.free()
	dummy.free()
	city.free()


func test_missions() -> void:
	print("missions")
	var city := City.new()
	root.add_child(city)
	city.build(99)
	var stub := StubGame.new()
	root.add_child(stub)
	var missions := Missions.new()
	root.add_child(missions)
	missions.setup(city, stub)

	check(missions.markers.size() == 3, "three mission markers")
	check(not missions.active, "no mission active at start")

	stub.global_position = missions.markers[0].global_position
	missions._process(0.016)
	check(missions.active, "walking into a marker starts a mission")
	check(missions.checkpoints.size() == 5, "courier has five checkpoints")
	check(missions.time_left > 0.0, "mission timer running")

	stub.global_position = missions.checkpoints[0]
	missions._process(0.016)
	check(missions.index == 1, "reaching a checkpoint advances it")

	for i in 1:
		while missions.active and missions.index < missions.checkpoints.size():
			stub.global_position = missions.checkpoints[missions.index]
			missions._process(0.016)
	check(not missions.active, "courier completes after the last checkpoint")
	check(stub.cash == Missions.REWARDS[Missions.COURIER], "courier pays its reward")

	missions.cooldown = 0.0
	for m in missions.markers:
		m.visible = true
	missions._begin(Missions.HEAT)
	check(is_equal_approx(stub.heat, 2.6), "heat mission raises the wanted level")
	missions._process(46.0)
	check(not missions.active, "heat mission ends after the timer")
	check(stub.cash == Missions.REWARDS[Missions.COURIER] + Missions.REWARDS[Missions.HEAT],
			"heat mission pays its reward")

	missions.free()
	stub.free()
	city.free()


func test_assets() -> void:
	print("assets")
	for name in ["asphalt", "road", "sidewalk", "grass", "roof",
			"facade_0", "facade_1", "facade_2", "facade_3",
			"icon_192", "icon_432_fg", "icon_432_bg"]:
		check(ResourceLoader.exists("res://assets/textures/%s.png" % name),
				"texture %s present" % name)
	var tex := load("res://assets/textures/facade_0.png") as Texture2D
	check(tex != null and tex.get_width() == 256, "facade texture decodes at 256 px")
	for name in ["intro_theme", "menu_theme", "radio_synth", "radio_beat",
			"radio_electro", "engine_loop", "siren_loop", "crash"]:
		check(ResourceLoader.exists("res://assets/audio/%s.wav" % name),
				"audio %s present" % name)
	var bank := AudioBank.new()
	root.add_child(bank)
	check(bank._stream("radio_synth") != null, "AudioBank loads a music track")
	check(bank._stream("engine_loop") != null, "AudioBank loads the engine loop")
	bank.free()


func test_game() -> void:
	print("game")
	var g := Game.new()
	root.add_child(g)
	for i in 12:
		await physics_frame
	check(g.city != null and g.city.building_count > 60, "game builds the city")
	check(g.player != null, "game spawns the player")
	check(g.cam != null and g.cam.target == g.player, "camera follows the player")
	check(g.vehicles.size() >= 25, "game spawns traffic and parked cars")
	check(g.missions != null, "game wires missions")
	check(g.hud != null, "game creates the HUD")
	check(g.cash == 500, "starting cash is 500")
	g.time_of_day = 0.5
	g._update_sky()
	check(g.sun.light_energy > 0.5, "midday sun is bright")
	g.time_of_day = 0.0
	g._update_sky()
	check(g.sun.light_energy < 0.3, "midnight sun is dim")
	check(g.clock_string() == "00:00", "clock reads midnight")
	g.wanted = 3.0
	g._update_police(0.016)
	check(g.wanted >= 3.0, "wanted level is tracked")
	g.add_cash(250)
	check(g.cash == 750, "cash can be awarded")
	g.free()
