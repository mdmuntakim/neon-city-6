class_name Player
extends CharacterBody3D
## On-foot character: third-person movement, sprint, jump, and a simple
## articulated model so the player reads clearly from the chase camera.

const WALK_SPEED := 6.2
const RUN_SPEED := 10.5
const ACCEL := 38.0
const JUMP_VELOCITY := 6.2
const GRAVITY := 22.0

var cam_yaw := 0.0
var move_input := Vector2.ZERO
var sprinting := false
var jump_queued := false
var health := 100.0
var _visual: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _walk_phase := 0.0
var _last_pos := Vector3.ZERO


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)
	_build_model()
	_last_pos = global_position


func _build_model() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	var jacket := StandardMaterial3D.new()
	jacket.albedo_color = Color(0.95, 0.2, 0.5)
	jacket.roughness = 0.7
	var jeans := StandardMaterial3D.new()
	jeans.albedo_color = Color(0.12, 0.16, 0.32)
	jeans.roughness = 0.9
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.62, 0.45)
	skin.roughness = 0.8

	var torso := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.62, 0.72, 0.34)
	torso.mesh = tm
	torso.material_override = jacket
	torso.position.y = 1.25
	_visual.add_child(torso)

	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.21
	hm.height = 0.42
	head.mesh = hm
	head.material_override = skin
	head.position.y = 1.78
	_visual.add_child(head)

	var hair := MeshInstance3D.new()
	var hair_m := BoxMesh.new()
	hair_m.size = Vector3(0.44, 0.14, 0.44)
	hair.mesh = hair_m
	var hair_mat := StandardMaterial3D.new()
	hair_mat.albedo_color = Color(0.05, 0.04, 0.04)
	hair.material_override = hair_mat
	hair.position.y = 1.93
	_visual.add_child(hair)

	_leg_l = _limb(Vector3(-0.17, 0.92, 0.0), Vector3(0.22, 0.85, 0.24), jeans)
	_leg_r = _limb(Vector3(0.17, 0.92, 0.0), Vector3(0.22, 0.85, 0.24), jeans)
	_arm_l = _limb(Vector3(-0.42, 1.52, 0.0), Vector3(0.16, 0.62, 0.18), jacket)
	_arm_r = _limb(Vector3(0.42, 1.52, 0.0), Vector3(0.16, 0.62, 0.18), jacket)


func _limb(pivot_pos: Vector3, size: Vector3, mat: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_pos
	_visual.add_child(pivot)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position.y = -size.y * 0.5
	pivot.add_child(mi)
	return pivot


func _physics_process(delta: float) -> void:
	var dir := Vector3(move_input.x, 0.0, move_input.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	dir = dir.rotated(Vector3.UP, cam_yaw)
	var target_speed := RUN_SPEED if sprinting else WALK_SPEED
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(dir * target_speed, ACCEL * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if is_on_floor():
		if jump_queued:
			velocity.y = JUMP_VELOCITY
			jump_queued = false
		elif velocity.y < 0.0:
			velocity.y = -0.1
	else:
		velocity.y -= GRAVITY * delta

	move_and_slide()
	_animate(delta, horizontal.length())


func _animate(delta: float, speed_now: float) -> void:
	var moving := speed_now > 0.4
	if moving:
		_walk_phase += delta * (7.0 if not sprinting else 12.0)
	else:
		_walk_phase = lerpf(_walk_phase, 0.0, delta * 8.0)
	var swing := sin(_walk_phase) * (0.55 if moving else 0.0)
	if _leg_l != null:
		_leg_l.rotation.x = swing
		_leg_r.rotation.x = -swing
		_arm_l.rotation.x = -swing * 0.8
		_arm_r.rotation.x = swing * 0.8
	if _visual != null and speed_now > 0.4:
		var yaw := atan2(-velocity.x, -velocity.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, yaw, delta * 10.0)


func teleport(p: Vector3) -> void:
	global_position = p
	velocity = Vector3.ZERO
	_last_pos = p


func face_towards(p: Vector3) -> void:
	var d := p - global_position
	if d.length() > 0.01 and _visual != null:
		_visual.rotation.y = atan2(-d.x, -d.z)
