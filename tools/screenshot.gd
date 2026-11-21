extends SceneTree
## Capture the intro, menu, city and a driving shot for the README.
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##       --rendering-driver opengl3 -s tools/screenshot.gd
## Screenshots land in docs/screenshots/.

const OUT := "res://docs/screenshots"


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT + "/" + name_ + ".png")
	img.save_png(path)
	print("shot: ", path)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	var intro := Intro.new()
	root.add_child(intro)
	intro.set_process(false)
	intro.t = 9.0
	intro.queue_redraw()
	for i in 4:
		await process_frame
	await _shot("01_intro")
	intro.free()

	var menu := Menu.new()
	root.add_child(menu)
	for i in 20:
		await process_frame
	await _shot("02_menu")
	menu.free()

	var game := Game.new()
	root.add_child(game)
	for i in 60:
		await process_frame
	await _shot("03_city")

	var car: Vehicle = game.vehicles[0]
	car.global_position = game.city.grid_pos(3, 3) + Vector3(4.0, 0.2, -10.0)
	car.rotation.y = 0.0
	game._enter_vehicle(car)
	game._touch_move = Vector2(0.0, -0.45)
	for i in 18:
		await process_frame
	await _shot("04_driving")

	# Put the car back on a central street, slow it down, then let the wanted
	# level spawn cruisers so the shot shows the city, the HUD and the police.
	car.global_position = game.city.grid_pos(3, 3) + Vector3(4.0, 0.2, -6.0)
	car.rotation.y = 0.0
	game._touch_move = Vector2.ZERO
	game._touch_brake = true
	for i in 8:
		await process_frame
	game.set_heat(3.0)
	game._update_police(0.016)
	var side := 0.0
	for p in game.police_cars:
		p.global_position = car.global_position + Vector3(-7.0 + side, 0.2, -18.0)
		side += 7.0
	for i in 5:
		await process_frame
	await _shot("05_heat")

	game.free()
	quit(0)
