class_name Player
extends CharacterBody3D
## Third-person explorer. Keyboard and mouse on PC, joystick and buttons on phone.
## Speeds come from data/game_config.json. Animations follow the real speed.

const LOOK_SENS := 0.0025
## Speed (m/s) at which each animation looks right at normal playback rate.
const ANIM_SPEED := {"Walk": 1.45, "Jog_Fwd": 3.6, "Sprint": 6.2}

var walk_speed := 2.2
var jog_speed := 4.6
var sprint_speed := 7.5
var jump_velocity := 5.0
var gravity := 18.0
var camera_distance := 4.0

var move_input := Vector2.ZERO     # set by touch joystick
var look_input := Vector2.ZERO     # set by touch drag, consumed each frame
var sprint_held := false
var jump_pressed := false

var yaw := 0.0
var pitch := -0.2
var cam_pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var body: ExplorerBody
var air_time := 0.0
var land_timer := 0.0


func setup(config: Dictionary) -> void:
	walk_speed = config.get("walk_speed", walk_speed)
	jog_speed = config.get("jog_speed", jog_speed)
	sprint_speed = config.get("sprint_speed", sprint_speed)
	jump_velocity = config.get("jump_velocity", jump_velocity)
	gravity = config.get("gravity", gravity)
	camera_distance = config.get("camera_distance", camera_distance)


func _ready() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(52)

	body = ExplorerBody.new()
	add_child(body)
	body.rotation.y = PI   # face away from the camera at spawn

	cam_pivot = Node3D.new()
	add_child(cam_pivot)
	cam_pivot.top_level = true
	cam_pivot.global_position = global_position + Vector3(0, 1.6, 0)
	spring = SpringArm3D.new()
	spring.spring_length = camera_distance
	spring.margin = 0.3
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	spring.shape = probe
	spring.add_excluded_object(get_rid())
	cam_pivot.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.far = 5000.0
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
	var stick: Vector2 = (move_input + kb).limit_length(1.0)
	var running: bool = sprint_held or Input.is_physical_key_pressed(KEY_SHIFT)
	var walking: bool = Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_ALT)
	var want_jump: bool = jump_pressed or Input.is_physical_key_pressed(KEY_SPACE)
	jump_pressed = false

	# Push the stick a little to walk, all the way to jog; sprint button to run.
	var speed := 0.0
	var amount := stick.length()
	if amount > 0.05:
		if running:
			speed = sprint_speed
		elif walking:
			speed = walk_speed
		elif amount < 0.6:
			speed = walk_speed * clampf(amount / 0.6, 0.4, 1.0)
		else:
			speed = jog_speed
	var wish: Vector3 = Basis(Vector3.UP, yaw) * Vector3(stick.x, 0, stick.y)
	var target := wish.normalized() * speed if amount > 0.05 else Vector3.ZERO
	var accel: float = 14.0 if is_on_floor() else 3.0
	velocity.x = move_toward(velocity.x, target.x, accel * delta * 4.0)
	velocity.z = move_toward(velocity.z, target.z, accel * delta * 4.0)
	if is_on_floor():
		if air_time > 0.35:
			land_timer = 0.25
		air_time = 0.0
		if want_jump:
			velocity.y = jump_velocity
			body.play("Jump_Start", 0.08)
	else:
		air_time += delta
		velocity.y -= gravity * delta
	move_and_slide()

	var flat := Vector2(velocity.x, velocity.z)
	if flat.length() > 0.3:
		var face: float = atan2(flat.x, flat.y)
		body.rotation.y = lerp_angle(body.rotation.y, face, 1.0 - exp(-10.0 * delta))
	_animate(flat.length(), delta)

	var follow := global_position + Vector3(0, 1.6, 0)
	cam_pivot.global_position = cam_pivot.global_position.lerp(follow, 1.0 - exp(-18.0 * delta))
	cam_pivot.rotation = Vector3(pitch, yaw, 0)


func _animate(speed: float, delta: float) -> void:
	land_timer -= delta
	if air_time > 0.2:
		body.play("Jump", 0.2)
	elif land_timer > 0.0:
		body.play("Jump_Land", 0.08)
	elif speed < 0.25:
		body.play("Idle", 0.25)
	elif speed < walk_speed + 0.4:
		body.play("Walk", 0.25, speed / ANIM_SPEED.Walk)
	elif speed < jog_speed + 0.8:
		body.play("Jog_Fwd", 0.2, speed / ANIM_SPEED.Jog_Fwd)
	else:
		body.play("Sprint", 0.2, speed / ANIM_SPEED.Sprint)
