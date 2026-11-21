class_name City
extends Node3D
## Procedural neon city. Everything is built from primitives and the
## repository's own generated textures, so the game contains no third-party
## art. The city is deterministic for a given seed.

const GRID := 6
const CELL := 80.0
const ROAD := 16.0
const BLOCK := 64.0
const HALF := GRID * CELL * 0.5          # 240 m: outermost road centre
const EXTENT := HALF + ROAD * 0.5        # 248 m: city edge

var rng := RandomNumberGenerator.new()
var intersections: Array[Vector3] = []
var mission_spots: Array[Vector3] = []
var traffic_spawns: Array[Vector3] = []
var spawn_point := Vector3(0, 1.2, 0)
var building_count := 0
var parked_spots: Array[Vector3] = []
var parked_yaws: Array[float] = []

var _facades: Array[StandardMaterial3D] = []
var _asphalt: StandardMaterial3D
var _road_h: StandardMaterial3D
var _road_v: StandardMaterial3D
var _sidewalk: StandardMaterial3D
var _grass: StandardMaterial3D
var _roof: StandardMaterial3D
var _neon_palette := [
	Color(1.0, 0.15, 0.55), Color(0.15, 0.9, 1.0), Color(1.0, 0.55, 0.1),
	Color(0.6, 0.2, 1.0), Color(0.2, 1.0, 0.55), Color(1.0, 0.9, 0.2),
]


func build(seed_value: int) -> void:
	rng.seed = seed_value
	_build_materials()
	_build_ground()
	_build_boundary()
	for i in GRID + 1:
		for j in GRID + 1:
			intersections.append(grid_pos(i, j))
	_build_roads()
	for i in GRID:
		for j in GRID:
			_build_block(i, j)
	_build_street_lights()
	_build_palms()
	_collect_spots()
	spawn_point = grid_pos(GRID / 2, GRID / 2) + Vector3(6.0, 1.2, 6.0)
	_build_start_marker()


func grid_pos(i: int, j: int) -> Vector3:
	return Vector3((i - GRID * 0.5) * CELL, 0.0, (j - GRID * 0.5) * CELL)


func random_intersection() -> Vector2i:
	return Vector2i(rng.randi_range(0, GRID), rng.randi_range(0, GRID))


func next_index(cur: Vector2i, prev: Vector2i) -> Vector2i:
	var options: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cur + d
		if n.x < 0 or n.y < 0 or n.x > GRID or n.y > GRID:
			continue
		if n == prev:
			continue
		options.append(n)
	if options.is_empty():
		return prev
	return options[rng.randi_range(0, options.size() - 1)]


# --- materials --------------------------------------------------------------

func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _surface(tex: String, tint: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var t := _tex(tex)
	if t != null:
		m.albedo_texture = t
	m.albedo_color = tint
	m.roughness = rough
	m.metallic = 0.05
	return m


func _build_materials() -> void:
	_asphalt = _surface("res://assets/textures/asphalt.png", Color(0.55, 0.55, 0.6))
	_sidewalk = _surface("res://assets/textures/sidewalk.png", Color(0.9, 0.9, 0.95))
	_grass = _surface("res://assets/textures/grass.png", Color(0.5, 0.9, 0.55))
	_roof = _surface("res://assets/textures/roof.png", Color(0.5, 0.5, 0.55))

	_road_h = _surface("res://assets/textures/road.png", Color(0.9, 0.9, 0.95))
	_road_h.uv1_scale = Vector3(1.0, 62.0, 1.0)
	_road_v = _road_h.duplicate() as StandardMaterial3D
	_road_v.uv1_scale = Vector3(62.0, 1.0, 1.0)

	for i in 4:
		var albedo := _surface("res://assets/textures/facade_%d.png" % i, Color.WHITE, 0.8)
		albedo.uv1_scale = Vector3(2.0, 4.0, 1.0)
		var et := _tex("res://assets/textures/facade_%d_emit.png" % i)
		if et != null:
			albedo.emission_enabled = true
			albedo.emission_texture = et
			albedo.emission = Color.WHITE
			albedo.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
			albedo.emission_energy_multiplier = 0.8
		_facades.append(albedo)


# --- ground and roads -------------------------------------------------------

func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(EXTENT * 2.0 + 40.0, EXTENT * 2.0 + 40.0)
	ground.mesh = plane
	ground.material_override = _asphalt
	ground.position.y = 0.0
	add_child(ground)

	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(EXTENT * 2.0 + 40.0, 2.0, EXTENT * 2.0 + 40.0)
	shape.shape = box
	shape.position.y = -1.0
	body.add_child(shape)
	add_child(body)


func _build_boundary() -> void:
	# Sea wall so a car cannot drive off the edge of the world. A neon strip on
	# top makes the edge read as a deliberate city limit instead of a void.
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.07, 0.08, 0.12)
	wall_mat.roughness = 0.95
	wall_mat.emission_enabled = true
	wall_mat.emission = Color(0.1, 0.2, 0.35)
	wall_mat.emission_energy_multiplier = 0.35
	var strip_mat := StandardMaterial3D.new()
	strip_mat.albedo_color = Color(0.2, 0.9, 1.0)
	strip_mat.emission_enabled = true
	strip_mat.emission = Color(0.2, 0.9, 1.0)
	strip_mat.emission_energy_multiplier = 2.2
	strip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var span := EXTENT * 2.0 + 40.0
	var specs := [
		[Vector3(0.0, 5.0, EXTENT + 10.0), Vector3(span, 10.0, 4.0)],
		[Vector3(0.0, 5.0, -EXTENT - 10.0), Vector3(span, 10.0, 4.0)],
		[Vector3(EXTENT + 10.0, 5.0, 0.0), Vector3(4.0, 10.0, span)],
		[Vector3(-EXTENT - 10.0, 5.0, 0.0), Vector3(4.0, 10.0, span)],
	]
	for spec in specs:
		var body := StaticBody3D.new()
		body.position = spec[0]
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec[1]
		shape.shape = box
		body.add_child(shape)
		add_child(body)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[1]
		mi.mesh = bm
		mi.material_override = wall_mat
		mi.position = spec[0]
		add_child(mi)
		var strip := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(spec[1].x + 0.2, 0.3, spec[1].z + 0.2)
		strip.mesh = sm
		strip.material_override = strip_mat
		strip.position = Vector3(spec[0].x, 10.15, spec[0].z)
		add_child(strip)


func _build_roads() -> void:
	for i in GRID + 1:
		var c := (i - GRID * 0.5) * CELL
		_add_road(Vector3(c, 0.02, 0.0), false)   # road running along z
		_add_road(Vector3(0.0, 0.02, c), true)    # road running along x
	for p in intersections:
		var patch := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(ROAD, ROAD)
		patch.mesh = pm
		patch.material_override = _asphalt
		patch.position = Vector3(p.x, 0.04, p.z)
		add_child(patch)


func _add_road(center: Vector3, horizontal: bool) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(ROAD, EXTENT * 2.0)
	mi.mesh = pm
	mi.material_override = _road_h if horizontal else _road_v
	mi.position = center
	if not horizontal:
		mi.rotation.y = PI * 0.5
	add_child(mi)


# --- blocks -----------------------------------------------------------------

func _build_block(bi: int, bj: int) -> void:
	var cx := (bi - GRID * 0.5 + 0.5) * CELL
	var cz := (bj - GRID * 0.5 + 0.5) * CELL
	var base := Vector3(cx, 0.0, cz)

	var park := rng.randf() < 0.16
	var slab_mat := _grass if park else _sidewalk
	var slab := MeshInstance3D.new()
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(BLOCK, 0.3, BLOCK)
	slab.mesh = slab_mesh
	slab.material_override = slab_mat
	slab.position = base + Vector3(0.0, 0.15, 0.0)
	add_child(slab)

	if park:
		_build_park(base)
		return

	for li in 2:
		for lj in 2:
			if rng.randf() < 0.12:
				continue
			var lx := cx + (li - 0.5) * 30.0
			var lz := cz + (lj - 0.5) * 30.0
			var w := rng.randf_range(19.0, 27.0)
			var d := rng.randf_range(19.0, 27.0)
			var h := rng.randf_range(9.0, 58.0)
			if rng.randf() < 0.10:
				h = rng.randf_range(60.0, 92.0)
			_add_building(Vector3(lx, 0.3, lz), w, d, h)


func _add_building(pos: Vector3, w: float, d: float, h: float) -> void:
	building_count += 1
	var body := StaticBody3D.new()
	body.position = pos + Vector3(0.0, h * 0.5, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, h, d)
	shape.shape = box
	body.add_child(shape)
	add_child(body)

	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(w, h, d)
	mi.mesh = mesh
	var idx := rng.randi_range(0, 3)
	mi.material_override = _facades[idx]
	mi.position = body.position
	add_child(mi)

	var roof := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(w + 0.6, 0.5, d + 0.6)
	roof.mesh = rm
	roof.material_override = _roof
	roof.position = pos + Vector3(0.0, h + 0.25, 0.0)
	add_child(roof)

	if rng.randf() < 0.55:
		_add_neon(pos, w, d, h)


func _add_neon(pos: Vector3, w: float, d: float, h: float) -> void:
	var col: Color = _neon_palette[rng.randi_range(0, _neon_palette.size() - 1)]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var vertical := rng.randf() < 0.5
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	if vertical:
		mesh.size = Vector3(0.35, min(14.0, h * 0.55), 0.35)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		mi.position = pos + Vector3(side * (w * 0.5 + 0.1), h * 0.62, d * 0.5 + 0.1)
	else:
		mesh.size = Vector3(w * 0.7, 1.2, 0.25)
		mi.position = pos + Vector3(0.0, min(h - 2.0, rng.randf_range(5.0, 18.0)), d * 0.5 + 0.15)
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)

	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 1.2
	light.omni_range = 9.0
	light.position = mi.position
	add_child(light)


func _build_park(base: Vector3) -> void:
	for k in 7:
		var p := base + Vector3(rng.randf_range(-25.0, 25.0), 0.3, rng.randf_range(-25.0, 25.0))
		_add_palm(p, rng.randf_range(0.8, 1.4))
	var bench := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(4.0, 0.5, 1.2)
	bench.mesh = bm
	bench.material_override = _roof
	bench.position = base + Vector3(0.0, 0.55, 0.0)
	add_child(bench)


# --- street furniture -------------------------------------------------------

func _build_street_lights() -> void:
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.12
	pole_mesh.bottom_radius = 0.16
	pole_mesh.height = 7.0
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.25, 0.26, 0.3)
	pole_mat.metallic = 0.7
	pole_mat.roughness = 0.4

	var lamp_mesh := BoxMesh.new()
	lamp_mesh.size = Vector3(1.2, 0.25, 0.5)
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.85, 0.6)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.8, 0.45)
	lamp_mat.emission_energy_multiplier = 4.0
	lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for i in GRID + 1:
		for j in GRID:
			var c := (i - GRID * 0.5) * CELL
			var mid := (j - GRID * 0.5 + 0.5) * CELL
			for s in [-1.0, 1.0]:
				var p := Vector3(c + s * (ROAD * 0.5 + 1.2), 0.0, mid)
				_add_light_post(p, pole_mesh, pole_mat, lamp_mesh, lamp_mat, s)
			var p2 := Vector3(mid, 0.0, c + (ROAD * 0.5 + 1.2))
			_add_light_post(p2, pole_mesh, pole_mat, lamp_mesh, lamp_mat, 0.0)


func _add_light_post(p: Vector3, pole_mesh: Mesh, pole_mat: Material,
		lamp_mesh: Mesh, lamp_mat: Material, side: float) -> void:
	var pole := MeshInstance3D.new()
	pole.mesh = pole_mesh
	pole.material_override = pole_mat
	pole.position = p + Vector3(0.0, 3.5, 0.0)
	add_child(pole)
	var lamp := MeshInstance3D.new()
	lamp.mesh = lamp_mesh
	lamp.material_override = lamp_mat
	lamp.position = p + Vector3(-side * 0.7, 6.9, 0.0)
	add_child(lamp)


func _build_palms() -> void:
	for i in GRID:
		for j in GRID:
			if rng.randf() > 0.45:
				continue
			var cx := (i - GRID * 0.5 + 0.5) * CELL
			var cz := (j - GRID * 0.5 + 0.5) * CELL
			var p := Vector3(cx + rng.randf_range(-30.0, 30.0), 0.3,
					cz + rng.randf_range(-30.0, 30.0))
			_add_palm(p, rng.randf_range(0.8, 1.3))


func _add_palm(pos: Vector3, scale_f: float) -> void:
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.18
	tm.bottom_radius = 0.32
	tm.height = 7.0
	trunk.mesh = tm
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.35, 0.22, 0.13)
	trunk.material_override = trunk_mat
	trunk.position = pos + Vector3(0.0, 3.5 * scale_f, 0.0)
	trunk.scale = Vector3.ONE * scale_f
	trunk.rotation.z = rng.randf_range(-0.08, 0.08)
	add_child(trunk)

	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.1, 0.55, 0.25)
	leaf_mat.roughness = 1.0
	for k in 6:
		var leaf := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(3.6, 0.08, 0.8)
		leaf.mesh = lm
		leaf.material_override = leaf_mat
		leaf.position = pos + Vector3(0.0, 7.0 * scale_f, 0.0)
		leaf.rotation.y = TAU * k / 6.0 + rng.randf_range(-0.2, 0.2)
		leaf.rotation.z = -0.35
		leaf.scale = Vector3.ONE * scale_f
		add_child(leaf)


# --- points of interest -----------------------------------------------------

func _collect_spots() -> void:
	for i in GRID + 1:
		for j in GRID + 1:
			if i < GRID and j < GRID:
				traffic_spawns.append(grid_pos(i, j) + Vector3(4.0, 0.6, 4.0))
			if (i + j) % 2 == 0:
				mission_spots.append(grid_pos(i, j) + Vector3(5.0, 0.0, 5.0))
	# Parked cars on the side of a few roads.
	for k in 26:
		var i := rng.randi_range(0, GRID)
		var j := rng.randi_range(0, GRID)
		var along_x := rng.randf() < 0.5
		var p := grid_pos(i, j)
		if along_x:
			p += Vector3(rng.randf_range(-24.0, 24.0), 0.0, ROAD * 0.5 + 1.6)
			parked_spots.append(p)
			parked_yaws.append(0.0 if rng.randf() < 0.5 else PI)
		else:
			p += Vector3(ROAD * 0.5 + 1.6, 0.0, rng.randf_range(-24.0, 24.0))
			parked_spots.append(p)
			parked_yaws.append(PI * 0.5 if rng.randf() < 0.5 else -PI * 0.5)


func _build_start_marker() -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.2
	torus.outer_radius = 2.6
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.9, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.9, 1.0)
	mat.emission_energy_multiplier = 2.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	ring.position = spawn_point + Vector3(-6.0, 0.25, -6.0)
	ring.name = "StartRing"
	add_child(ring)
