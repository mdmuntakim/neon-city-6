class_name CameraRig
extends Node3D
## Third-person chase camera. Drag to look, auto-aligns behind a car after a
## moment without input, and pulls in when a building is in the way.

var target: Node3D
var yaw := 0.0
var pitch := -0.28
var spring: SpringArm3D
var camera: Camera3D
var look_sensitivity := 0.0045
var idle_time := 0.0
var _base_length := 5.0


func _ready() -> void:
	spring = SpringArm3D.new()
	spring.spring_length = _base_length
	spring.margin = 0.25
	spring.collision_mask = 1
	spring.rotation.x = pitch
	add_child(spring)
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.near = 0.15
	camera.far = 700.0
	camera.current = true
	spring.add_child(camera)


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	global_position = target.global_position + Vector3(0.0, 1.15, 0.0)
	idle_time += delta
	if idle_time > 1.2 and target is Vehicle:
		var v := target as Vehicle
		if v.driver != null and absf(v.speed) > 3.0:
			yaw = lerp_angle(yaw, v.rotation.y, clampf(delta * 2.2, 0.0, 1.0))
	spring.rotation.x = lerpf(spring.rotation.x, pitch, clampf(delta * 10.0, 0.0, 1.0))
	rotation.y = yaw
	var wanted := 5.0 if not (target is Vehicle) else 7.2
	spring.spring_length = lerpf(spring.spring_length, wanted, clampf(delta * 3.0, 0.0, 1.0))


func look(delta_x: float, delta_y: float) -> void:
	yaw -= delta_x * look_sensitivity
	pitch = clampf(pitch - delta_y * look_sensitivity, -0.95, 0.25)
	idle_time = 0.0


func set_target(node: Node3D, keep_yaw := false) -> void:
	target = node
	if not keep_yaw:
		yaw = node.rotation.y
		idle_time = 2.0
