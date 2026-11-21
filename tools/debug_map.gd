extends SceneTree
## Temporary diagnostic: top-down view of the city and vehicle state prints.

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("/tmp/opencode/" + name_ + ".png")
	print("shot: ", name_)


func _run() -> void:
	var game := Game.new()
	root.add_child(game)
	for i in 30:
		await process_frame
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 560.0
	cam.position = Vector3(0, 400, 0)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	root.add_child(cam)
	cam.make_current()
	for i in 5:
		await process_frame
	await _shot("map_top")
	cam.queue_free()

	var car: Vehicle = game.vehicles[0]
	car.global_position = game.city.grid_pos(3, 3) + Vector3(4.0, 0.2, -10.0)
	car.rotation.y = 0.0
	game._enter_vehicle(car)
	game._touch_move = Vector2(0.0, -0.45)
	for i in 45:
		await process_frame
	print("car after 45: ", car.global_position, " rot=", car.rotation, " speed=", car.speed_ratio())
	print("cam: ", game.cam.global_position, " focus=", game.focus_node().global_position)
	game.set_heat(3.0)
	game._update_police(0.016)
	for p in game.police_cars:
		p.global_position = car.global_position + Vector3(0.0, 0.0, -20.0)
	for i in 20:
		await process_frame
	print("car after heat: ", car.global_position, " rot=", car.rotation, " speed=", car.speed_ratio())
	print("cam after: ", game.cam.global_position)
	await _shot("debug_heat")
	game.free()
	quit(0)
