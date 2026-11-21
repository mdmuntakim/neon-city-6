class_name Vehicle
extends CharacterBody3D
## Arcade car used for parked cars, traffic, police and the player's ride.
## Forward is -Z. Traffic and police are the same class with `autopilot` on.

signal crashed(impact: float)

const GRAVITY := 22.0

var city: City
var driver: Node3D = null
var autopilot := false
var police := false
var chase_target: Node3D = null
var is_parked := false

var speed := 0.0
var max_speed := 30.0
var accel := 17.0
var reverse_speed := 9.0
var steer_rate := 1.8
var drag := 4.5

var cur := Vector2i.ZERO
var nxt := Vector2i.ZERO
var prev := Vector2i.ZERO
var cruise_speed := 13.0
var lane := 3.4

var controls := Vector3.ZERO   # x throttle, y steer, z brake/handbrake
var body_color := Color(0.9, 0.2, 0.3)

var _visual: Node3D
var _wheels: Array[Node3D] = []
var _crash_cd := 0.0
var _blink := 0.0
var _light_left: StandardMaterial3D
var _light_right: StandardMaterial3D
var _steer_visual := 0.0


func setup(city_ref: City, colour: Color, police_car := false) -> void:
	city = city_ref
	body_color = colour
	police = police_car
	collision_layer = 2
	collision_mask = 1
	max_speed = 34.0 if police_car else 30.0
	accel = 22.0 if police_car else 17.0
	_build_model()
	if police_car:
		add_to_group("police")


func start_traffic(at: Vector2i) -> void:
	autopilot = true
	cur = at
	prev = at
	nxt = city.next_index(cur, prev)
	position = city.grid_pos(cur.x, cur.y) + Vector3(4.0, 0.6, 4.0)
	rotation.y = _yaw_towards(_route_target())


func _build_model() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.85, 1.25, 4.2)
	shape.shape = box
	shape.position.y = 0.72
	add_child(shape)

	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	var paint := StandardMaterial3D.new()
	paint.albedo_color = body_color
	paint.metallic = 0.55
	paint.roughness = 0.28

	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.85, 0.62, 4.2)
	body.mesh = bm
	body.material_override = paint
	body.position.y = 0.78
	_visual.add_child(body)

	var cabin := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.62, 0.55, 2.0)
	cabin.mesh = cm
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.09, 0.14)
	glass.metallic = 0.8
	glass.roughness = 0.15
	cabin.material_override = glass
	cabin.position = Vector3(0.0, 1.32, 0.15)
	_visual.add_child(cabin)

	var roof := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(1.5, 0.1, 1.9)
	roof.mesh = rm
	roof.material_override = paint
	roof.position = Vector3(0.0, 1.62, 0.15)
	_visual.add_child(roof)

	var wheel_mesh := CylinderMesh.new()
	wheel_mesh.top_radius = 0.42
	wheel_mesh.bottom_radius = 0.42
	wheel_mesh.height = 0.32
	var tyre := StandardMaterial3D.new()
	tyre.albedo_color = Color(0.04, 0.04, 0.05)
	tyre.roughness = 0.95
	for p in [Vector3(-0.88, 0.45, -1.35), Vector3(0.88, 0.45, -1.35),
			Vector3(-0.88, 0.45, 1.35), Vector3(0.88, 0.45, 1.35)]:
		var pivot := Node3D.new()
		pivot.position = p
		_visual.add_child(pivot)
		var wheel := MeshInstance3D.new()
		wheel.mesh = wheel_mesh
		wheel.material_override = tyre
		wheel.rotation.z = PI * 0.5
		pivot.add_child(wheel)
		_wheels.append(pivot)

	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(1.0, 0.97, 0.85)
	head_mat.emission_enabled = true
	head_mat.emission = Color(1.0, 0.95, 0.8)
	head_mat.emission_energy_multiplier = 3.0
	head_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var tail_mat := StandardMaterial3D.new()
	tail_mat.albedo_color = Color(1.0, 0.1, 0.1)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.1, 0.1)
	tail_mat.emission_energy_multiplier = 2.0
	tail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for x in [-0.62, 0.62]:
		var hl := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(0.42, 0.16, 0.08)
		hl.mesh = hm
		hl.material_override = head_mat
		hl.position = Vector3(x, 0.8, -2.11)
		_visual.add_child(hl)
		var tl := MeshInstance3D.new()
		tl.mesh = hm
		tl.material_override = tail_mat
		tl.position = Vector3(x, 0.8, 2.11)
		_visual.add_child(tl)

	if police:
		var bar := MeshInstance3D.new()
		var barm := BoxMesh.new()
		barm.size = Vector3(1.2, 0.16, 0.35)
		bar.mesh = barm
		bar.position = Vector3(0.0, 1.75, 0.1)
		_light_left = StandardMaterial3D.new()
		_light_left.albedo_color = Color(1, 0.1, 0.1)
		_light_left.emission_enabled = true
		_light_left.emission = Color(1, 0.1, 0.1)
		_light_left.emission_energy_multiplier = 5.0
		_light_left.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bar.material_override = _light_left
		_visual.add_child(bar)

		var left := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.5, 0.18, 0.36)
		left.mesh = lm
		left.material_override = _light_left
		left.position = Vector3(-0.36, 1.76, 0.1)
		_visual.add_child(left)

		_light_right = StandardMaterial3D.new()
		_light_right.albedo_color = Color(0.1, 0.3, 1)
		_light_right.emission_enabled = true
		_light_right.emission = Color(0.1, 0.35, 1)
		_light_right.emission_energy_multiplier = 5.0
		_light_right.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var right := MeshInstance3D.new()
		right.mesh = lm
		right.material_override = _light_right
		right.position = Vector3(0.36, 1.76, 0.1)
		_visual.add_child(right)


func _physics_process(delta: float) -> void:
	_crash_cd = maxf(0.0, _crash_cd - delta)
	if driver != null:
		step(delta, controls.x, controls.y, controls.z > 0.5)
	elif autopilot:
		_ai_controls()
		step(delta, controls.x, controls.y, controls.z > 0.5)
	else:
		speed = move_toward(speed, 0.0, 12.0 * delta)
		_apply_motion(delta, 0.0)


func _ai_controls() -> void:
	var target := _route_target()
	var to := target - global_position
	to.y = 0.0
	if police and chase_target != null:
		target = chase_target.global_position
		to = target - global_position
		to.y = 0.0
	if to.length() < 1.0:
		controls = Vector3(0.0, 0.0, 0.0)
		return
	var desired := atan2(-to.x, -to.z)
	var diff := wrapf(desired - rotation.y, -PI, PI)
	var steer := clampf(diff * 2.2, -1.0, 1.0)
	var throttle := 1.0
	var target_speed := cruise_speed
	if police:
		target_speed = max_speed * 0.92
		if absf(diff) > 1.1 and speed > 12.0:
			throttle = 0.25
	elif absf(diff) > 0.7:
		throttle = 0.35
		target_speed *= 0.55
	if speed > target_speed:
		throttle = -0.4
	controls = Vector3(throttle, steer, 0.0)


func _route_target() -> Vector3:
	var a := city.grid_pos(cur.x, cur.y)
	var b := city.grid_pos(nxt.x, nxt.y)
	var dir := (b - a)
	dir.y = 0.0
	if dir.length() < 0.01:
		return b
	dir = dir.normalized()
	var right := dir.cross(Vector3.UP)
	return b + right * lane


func step(delta: float, throttle: float, steer_in: float, brake: bool) -> void:
	throttle = clampf(throttle, -1.0, 1.0)
	steer_in = clampf(steer_in, -1.0, 1.0)
	var prev_speed := speed

	if throttle > 0.01:
		speed += throttle * accel * delta
	elif throttle < -0.01:
		speed += throttle * accel * 0.55 * delta
	else:
		speed = move_toward(speed, 0.0, drag * delta)

	if brake:
		speed = move_toward(speed, 0.0, 26.0 * delta)

	speed = clampf(speed, -reverse_speed, max_speed)
	var grip := clampf(absf(speed) / 6.0, 0.0, 1.0)
	var rate := steer_rate * (1.7 if brake else 1.0)
	rotation.y += steer_in * rate * grip * delta * signf(speed)
	_steer_visual = lerpf(_steer_visual, steer_in, clampf(delta * 8.0, 0.0, 1.0))

	_apply_motion(delta, prev_speed)


func _apply_motion(delta: float, prev_speed: float) -> void:
	var forward := -global_transform.basis.z
	velocity.x = forward.x * speed
	velocity.z = forward.z * speed
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.1
	move_and_slide()

	var wall_hit := false
	for i in get_slide_collision_count():
		var normal := get_slide_collision(i).get_normal()
		if normal.y < 0.6:
			wall_hit = true
			break

	if wall_hit and _crash_cd <= 0.0:
		var impact := absf(prev_speed)
		if impact > 6.0:
			_crash_cd = 0.45
			speed = -impact * 0.12
			crashed.emit(impact)
		else:
			speed *= 0.6

	if autopilot and speed > 0.0:
		var target := _route_target()
		var flat := global_position - target
		flat.y = 0.0
		if flat.length() < 5.0:
			prev = cur
			cur = nxt
			nxt = city.next_index(cur, prev)


func _process(delta: float) -> void:
	if _wheels.size() == 4:
		for w in _wheels:
			w.rotation.x -= speed * delta * 2.2
		_wheels[0].rotation.y = _steer_visual * 0.45
		_wheels[1].rotation.y = _steer_visual * 0.45
	if _visual != null:
		_visual.rotation.z = lerpf(_visual.rotation.z, -_steer_visual * clampf(speed / 40.0, 0.0, 1.0) * 0.09, delta * 5.0)
	if police and _light_left != null:
		_blink += delta * 6.0
		var on := sin(_blink) > 0.0
		_light_left.emission_energy_multiplier = 6.0 if on else 0.3
		if _light_right != null:
			_light_right.emission_energy_multiplier = 0.3 if on else 6.0


func _yaw_towards(p: Vector3) -> float:
	var d := p - global_position
	return atan2(-d.x, -d.z)


func speed_ratio() -> float:
	return clampf(absf(speed) / max_speed, 0.0, 1.0)


func is_driven() -> bool:
	return driver != null
