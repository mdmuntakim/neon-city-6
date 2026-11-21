extends SceneTree

func _initialize() -> void:
	var game := Game.new()
	root.add_child(game)
	await process_frame
	await process_frame
	var ring := game.city.get_node_or_null("StartRing")
	print("ring: ", ring, " pos=", ring.global_position, " aabb=", ring.get_aabb(), " children=", ring.get_child_count())
	print("spawn=", game.city.spawn_point)
	for c in game.city.get_children():
		if c is MeshInstance3D and c.mesh is TorusMesh:
			print("torus: ", c.name, " pos=", c.global_position, " aabb=", c.get_aabb(), " visible=", c.visible)
	quit(0)
