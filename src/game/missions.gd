class_name Missions
extends Node
## Three replayable mission types. Markers are placed on the road grid; walk
## or drive into one to start it.

signal started(title: String)
signal finished(title: String, reward: int)
signal failed(title: String)

enum { COURIER, CIRCUIT, HEAT }

const TITLES := ["COURIER RUN", "NEON CIRCUIT", "HEAT WAVE"]
const REWARDS := [1500, 2500, 3000]
const LIMITS := [95.0, 80.0, 45.0]

var city: City
var game
var markers: Array[Node3D] = []
var checkpoint_ring: MeshInstance3D
var checkpoint_beam: MeshInstance3D
var active := false
var kind := COURIER
var time_left := 0.0
var time_limit := 0.0
var checkpoints: Array[Vector3] = []
var index := 0
var reward := 0
var cooldown := 0.0
var _t := 0.0


func setup(city_ref: City, game_ref) -> void:
	city = city_ref
	game = game_ref
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var spots := city.mission_spots.duplicate()
	spots.shuffle()
	for i in mini(3, spots.size()):
		markers.append(_make_marker(spots[i], i))

	checkpoint_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 5.0
	torus.outer_radius = 5.6
	checkpoint_ring.mesh = torus
	checkpoint_ring.material_override = _glow_mat(Color(1.0, 0.85, 0.15))
	checkpoint_ring.visible = false
	add_child(checkpoint_ring)

	checkpoint_beam = MeshInstance3D.new()
	var beam := CylinderMesh.new()
	beam.top_radius = 0.4
	beam.bottom_radius = 5.0
	beam.height = 40.0
	checkpoint_beam.mesh = beam
	var bm := _glow_mat(Color(1.0, 0.75, 0.15))
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(1.0, 0.75, 0.15, 0.12)
	checkpoint_beam.material_override = bm
	checkpoint_beam.visible = false
	add_child(checkpoint_beam)


func _glow_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 3.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _make_marker(pos: Vector3, kind_idx: int) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	var cols := [Color(0.2, 0.9, 1.0), Color(1.0, 0.3, 0.7), Color(1.0, 0.55, 0.1)]
	var mat := _glow_mat(cols[kind_idx % cols.size()])
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.4
	torus.outer_radius = 2.9
	ring.mesh = torus
	ring.material_override = mat
	ring.position.y = 0.35
	root.add_child(ring)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 2.6
	cyl.height = 16.0
	beam.mesh = cyl
	var bm := mat.duplicate() as StandardMaterial3D
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(cols[kind_idx % cols.size()], 0.10)
	beam.material_override = bm
	beam.position.y = 8.0
	root.add_child(beam)
	add_child(root)
	return root


func _process(delta: float) -> void:
	_t += delta
	for m in markers:
		if is_instance_valid(m):
			m.rotation.y += delta * 0.8
	if checkpoint_ring != null and checkpoint_ring.visible:
		checkpoint_ring.rotation.z += delta * 1.2
		var s := 1.0 + sin(_t * 3.0) * 0.04
		checkpoint_ring.scale = Vector3(s, s, s)

	if cooldown > 0.0:
		cooldown = maxf(0.0, cooldown - delta)
		if cooldown == 0.0:
			for m in markers:
				if is_instance_valid(m):
					m.visible = true
		return

	if not active:
		var focus: Node3D = game.focus_node()
		if focus == null:
			return
		for i in markers.size():
			var m := markers[i]
			if is_instance_valid(m) and m.visible:
				if focus.global_position.distance_to(m.global_position) < 4.5:
					_begin(i)
					return
		return

	time_left -= delta
	if kind == HEAT:
		if time_left <= 0.0:
			_complete()
		return

	var focus: Node3D = game.focus_node()
	if focus == null:
		return
	if focus.global_position.distance_to(checkpoints[index]) < 8.0:
		index += 1
		if index >= checkpoints.size():
			_complete()
			return
		_move_checkpoint()
		game.sfx("pickup", -2.0)
		game.message("CHECKPOINT %d / %d" % [index, checkpoints.size()], 1.4)
	if time_left <= 0.0:
		_fail()


func _begin(kind_idx: int) -> void:
	kind = kind_idx
	active = true
	index = 0
	time_limit = LIMITS[kind]
	time_left = time_limit
	reward = REWARDS[kind]
	for m in markers:
		if is_instance_valid(m):
			m.visible = false
	checkpoints.clear()
	if kind != HEAT:
		var spots := city.mission_spots.duplicate()
		spots.shuffle()
		for i in mini(5, spots.size()):
			checkpoints.append(spots[i])
		_move_checkpoint()
	else:
		checkpoint_ring.visible = false
		checkpoint_beam.visible = false
		game.set_heat(2.6)
	started.emit(TITLES[kind])
	game.message(TITLES[kind] + " — GO", 2.0)


func _move_checkpoint() -> void:
	if index >= checkpoints.size():
		return
	var p := checkpoints[index]
	checkpoint_ring.visible = true
	checkpoint_beam.visible = true
	checkpoint_ring.global_position = p + Vector3(0.0, 0.4, 0.0)
	checkpoint_beam.global_position = p + Vector3(0.0, 20.0, 0.0)


func _complete() -> void:
	var title: String = TITLES[kind]
	active = false
	checkpoint_ring.visible = false
	checkpoint_beam.visible = false
	cooldown = 4.0
	game.add_cash(reward)
	game.message("%s COMPLETE  +$%d" % [title, reward], 3.0)
	game.sfx("mission_complete")
	finished.emit(title, reward)


func _fail() -> void:
	var title: String = TITLES[kind]
	active = false
	checkpoint_ring.visible = false
	checkpoint_beam.visible = false
	cooldown = 3.0
	game.message(title + " FAILED", 2.5)
	game.sfx("mission_fail")
	failed.emit(title)


func title() -> String:
	return TITLES[kind] if active else ""


func target_position() -> Vector3:
	if active and kind != HEAT and index < checkpoints.size():
		return checkpoints[index]
	return Vector3.ZERO


func target_distance() -> float:
	var focus: Node3D = game.focus_node() if game != null else null
	if focus == null:
		return 0.0
	return focus.global_position.distance_to(target_position())


func cancel() -> void:
	active = false
	checkpoint_ring.visible = false
	checkpoint_beam.visible = false
	cooldown = 2.0
