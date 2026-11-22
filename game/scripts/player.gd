class_name Player
extends CharacterBody3D
## Third-person explorer. Keyboard and mouse on PC, joystick and buttons on phone.
## The body is a stand-in built from simple shapes until the realistic model lands.

const WALK := 3.2
const RUN := 6.5
const JUMP := 5.0
const GRAVITY := 18.0
const LOOK_SENS := 0.0025

var move_input := Vector2.ZERO     # set by touch joystick
var look_input := Vector2.ZERO     # set by touch drag, consumed each frame
var sprint_held := false
var jump_pressed := false

var yaw := 0.0
var pitch := -0.18
var cam_pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var model: Node3D
var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var stride := 0.0


func _ready() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(50)

	model = _build_body()
	model.rotation.y = PI   # face away from the camera at spawn
	add_child(model)

	cam_pivot = Node3D.new()
	cam_pivot.position.y = 1.6
	add_child(cam_pivot)
	cam_pivot.top_level = true
	spring = SpringArm3D.new()
	spring.spring_length = 4.2
	spring.margin = 0.3
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	spring.shape = probe
	spring.add_excluded_object(get_rid())
	cam_pivot.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.far = 4000.0
	camera.position.x = 0.55   # over-the-shoulder
	spring.add_child(camera)
	camera.current = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * LOOK_SENS
		pitch = clampf(pitch - event.relative.y * LOOK_SENS, -1.2, 0.6)
	elif event is InputEventMouseButton and event.pressed and not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	yaw -= look_input.x * LOOK_SENS * 1.6
	pitch = clampf(pitch - look_input.y * LOOK_SENS * 1.6, -1.2, 0.6)
	look_input = Vector2.ZERO

	var kb := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var dir2: Vector2 = (move_input + kb).limit_length(1.0)
	var running: bool = sprint_held or Input.is_physical_key_pressed(KEY_SHIFT)
	var want_jump: bool = jump_pressed or Input.is_physical_key_pressed(KEY_SPACE)
	jump_pressed = false

	var basis_y := Basis(Vector3.UP, yaw)
	var wish: Vector3 = basis_y * Vector3(dir2.x, 0, dir2.y)
	var speed: float = (RUN if running else WALK) * dir2.length()
	var target := wish.normalized() * speed if wish.length() > 0.05 else Vector3.ZERO
	var accel: float = 10.0 if is_on_floor() else 3.0
	velocity.x = move_toward(velocity.x, target.x, accel * delta * 6.0)
	velocity.z = move_toward(velocity.z, target.z, accel * delta * 6.0)
	if is_on_floor():
		if want_jump:
			velocity.y = JUMP
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

	var flat := Vector2(velocity.x, velocity.z)
	if flat.length() > 0.3:
		var face: float = atan2(flat.x, flat.y)
		model.rotation.y = lerp_angle(model.rotation.y, face, 1.0 - exp(-12.0 * delta))
	_animate(flat.length(), delta)

	cam_pivot.global_position = cam_pivot.global_position.lerp(global_position + Vector3(0, 1.6, 0), 1.0 - exp(-20.0 * delta))
	cam_pivot.rotation = Vector3(pitch, yaw, 0)


func _animate(speed: float, delta: float) -> void:
	stride += speed * delta * 2.1
	var amt: float = clampf(speed / RUN, 0.0, 1.0)
	var swing: float = sin(stride) * lerpf(0.0, 0.75, amt)
	legs[0].rotation.x = swing
	legs[1].rotation.x = -swing
	arms[0].rotation.x = -swing * 0.8
	arms[1].rotation.x = swing * 0.8
	model.get_node("Body").position.y = 0.0 + absf(cos(stride)) * 0.05 * amt


# ---------- Stand-in body ----------

static func _mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _build_body() -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var jacket := _mat(Color(0.30, 0.31, 0.20))
	var pants := _mat(Color(0.16, 0.16, 0.13))
	var boots := _mat(Color(0.28, 0.18, 0.11), 0.7)
	var skin := _mat(Color(0.72, 0.52, 0.40), 0.6)
	var hair := _mat(Color(0.10, 0.08, 0.06))
	var scarf := _mat(Color(0.48, 0.12, 0.10))
	var canvas := _mat(Color(0.47, 0.38, 0.24))
	var mat_roll := _mat(Color(0.32, 0.35, 0.27))

	var cap := CapsuleMesh.new()
	cap.radius = 0.11
	cap.height = 0.9
	for side in [-1, 1]:
		var hip := Node3D.new()
		hip.position = Vector3(0.11 * side, 0.92, 0)
		body.add_child(hip)
		_part(hip, cap, pants, Vector3(0, -0.45, 0))
		var boot := BoxMesh.new()
		boot.size = Vector3(0.15, 0.12, 0.28)
		_part(hip, boot, boots, Vector3(0, -0.86, 0.04))
		legs.append(hip)

	var torso := CapsuleMesh.new()
	torso.radius = 0.22
	torso.height = 0.75
	_part(body, torso, jacket, Vector3(0, 1.25, 0), Vector3(1.0, 1.0, 0.75))
	var arm := CapsuleMesh.new()
	arm.radius = 0.075
	arm.height = 0.66
	for side in [-1, 1]:
		var sh := Node3D.new()
		sh.position = Vector3(0.27 * side, 1.47, 0)
		body.add_child(sh)
		_part(sh, arm, jacket, Vector3(0.02 * side, -0.3, 0))
		var hand := SphereMesh.new()
		hand.radius = 0.055
		hand.height = 0.11
		_part(sh, hand, skin, Vector3(0.02 * side, -0.65, 0))
		arms.append(sh)

	var neck := TorusMesh.new()
	neck.inner_radius = 0.06
	neck.outer_radius = 0.15
	_part(body, neck, scarf, Vector3(0, 1.58, 0), Vector3(1, 0.9, 1))
	var head := SphereMesh.new()
	head.radius = 0.115
	head.height = 0.26
	_part(body, head, skin, Vector3(0, 1.72, 0))
	var hair_m := SphereMesh.new()
	hair_m.radius = 0.12
	hair_m.height = 0.16
	hair_m.is_hemisphere = true
	_part(body, hair_m, hair, Vector3(0, 1.76, -0.01))

	var pack := BoxMesh.new()
	pack.size = Vector3(0.36, 0.46, 0.2)
	_part(body, pack, canvas, Vector3(0, 1.28, -0.25))
	var roll := CylinderMesh.new()
	roll.top_radius = 0.08
	roll.bottom_radius = 0.08
	roll.height = 0.46
	var r := _part(body, roll, mat_roll, Vector3(0, 1.58, -0.25))
	r.rotation.z = PI * 0.5
	return root
