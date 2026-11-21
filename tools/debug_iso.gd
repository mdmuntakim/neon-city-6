extends SceneTree

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
	game.hud.visible = false
	game.touch.visible = false
	game.player.visible = false
	for c in game.city.get_children():
		if c.name != "StartRing":
			c.visible = false
	for i in 4:
		await process_frame
	await _shot("iso_ringisolated")
	game.free()
	quit(0)
