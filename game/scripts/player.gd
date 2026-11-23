class_name Player
extends CharacterBody3D
## Third-person explorer. Keyboard and mouse on PC, joystick and buttons on phone.
## Speeds come from data/game_config.json. Animations follow the real speed.

const LOOK_SENS := 0.0025
## Slopes whose normal points up more than this (cos 72°) can be scrambled up.
const SCRAMBLE_MIN_NORMAL_Y := 0.31
const SCRAMBLE_SPEED := 2.6
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

## Emitted whenever health changes (for the HUD).
signal health_changed(health: float, max_health: float)
## Emitted when health reaches zero; the world respawns the player.
signal died
## Emitted on each hit taken, with true when it is lava burning.
signal hurt(burn: bool)

var data: WorldData          # injected by the world, for lava checks
var combat: Dictionary = {}
var max_health := 100.0
var health := 100.0
var dead := false
var attack_pressed := false   # set by the touch attack button
var since_damage := 99.0
var since_attack := 99.0
var attack_hit_at := -1.0     # seconds into the current swing when the blade connects
var attack_clock := 0.0
var burn_tick := 0.0
var damage_mult := 1.0
## Camera look speed multiplier from the settings menu.
var look_mult := 1.0
## Set by the Story node while a conversation is open: no attacking or moving.
var in_conversation := false


func setup(config: Dictionary) -> void:
	walk_speed = config.get("walk_speed", walk_speed)
	jog_speed = config.get("jog_speed", jog_speed)
	sprint_speed = config.get("sprint_speed", sprint_speed)
	jump_velocity = config.get("jump_velocity", jump_velocity)
	gravity = config.get("gravity", gravity)
	camera_distance = config.get("camera_distance", camera_distance)
	combat = config.get("combat", {})
	max_health = combat.get("max_health", 100.0)
	health = max_health


func _ready() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(58)

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
		yaw -= event.relative.x * LOOK_SENS * look_mult
		pitch = clampf(pitch - event.relative.y * LOOK_SENS * look_mult, -1.2, 0.6)
	elif event is InputEventMouseButton and event.pressed and not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		attack_pressed = true
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F:
		attack_pressed = true


func _physics_process(delta: float) -> void:
	yaw -= look_input.x * LOOK_SENS * 1.6 * look_mult
	pitch = clampf(pitch - look_input.y * LOOK_SENS * 1.6 * look_mult, -1.2, 0.6)
	look_input = Vector2.ZERO

	var kb := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var stick: Vector2 = (move_input + kb).limit_length(1.0)
	var running: bool = sprint_held or Input.is_physical_key_pressed(KEY_SHIFT)
	var walking: bool = Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_ALT)
	var want_jump: bool = jump_pressed or Input.is_physical_key_pressed(KEY_SPACE)
	jump_pressed = false
	var want_attack := attack_pressed
	attack_pressed = false
	since_damage += delta
	since_attack += delta
	if dead or in_conversation:
		stick = Vector2.ZERO
		want_jump = false
		want_attack = false
	_update_combat(delta, want_attack)

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
	if attack_hit_at >= 0.0:
		speed *= combat.get("attack_move_factor", 0.3)
	var in_lava := _in_lava()
	if in_lava:
		speed *= combat.get("lava_speed_factor", 0.55)
	var wish: Vector3 = Basis(Vector3.UP, yaw) * Vector3(stick.x, 0, stick.y)
	var target := wish.normalized() * speed if amount > 0.05 else Vector3.ZERO
	var accel: float = 14.0 if is_on_floor() else 3.0
	velocity.x = move_toward(velocity.x, target.x, accel * delta * 4.0)
	velocity.z = move_toward(velocity.z, target.z, accel * delta * 4.0)
	if is_on_floor():
		if air_time > 0.35:
			land_timer = 0.25
		air_time = 0.0
		if want_jump and not body.busy():
			velocity.y = jump_velocity
			body.play("Jump_Start", 0.08)
	else:
		air_time += delta
		velocity.y -= gravity * delta
	move_and_slide()
	# Scramble up slopes that are steep but not cliffs, so you can always climb
	# out of hollows and craters by pushing towards the slope.
	if is_on_wall() and amount > 0.3 and not is_on_floor():
		var n := get_wall_normal()
		if n.y > SCRAMBLE_MIN_NORMAL_Y and wish.dot(-Vector3(n.x, 0, n.z).normalized()) > 0.3:
			velocity.y = maxf(velocity.y, SCRAMBLE_SPEED)

	var flat := Vector2(velocity.x, velocity.z)
	if flat.length() > 0.3:
		var face: float = atan2(flat.x, flat.y)
		body.rotation.y = lerp_angle(body.rotation.y, face, 1.0 - exp(-10.0 * delta))
	_animate(flat.length(), delta)

	var follow := global_position + Vector3(0, 1.6, 0)
	cam_pivot.global_position = cam_pivot.global_position.lerp(follow, 1.0 - exp(-18.0 * delta))
	cam_pivot.rotation = Vector3(pitch, yaw, 0)


# ---------- Combat ----------

func _in_lava() -> bool:
	if data == null:
		return false
	var p := global_position
	return p.y < WorldData.LAVA_LEVEL + 0.05 and data.zone(p.x, p.z)[2] > 0.3


func _update_combat(delta: float, want_attack: bool) -> void:
	# Health comes back slowly once you've been out of harm for a while.
	if not dead and since_damage > combat.get("regen_delay", 6.0) and health < max_health:
		health = minf(max_health, health + combat.get("regen_per_second", 5.0) * delta)
		health_changed.emit(health, max_health)
	if not dead and _in_lava():
		burn_tick -= delta
		take_damage(combat.get("lava_damage_per_second", 30.0) * delta, Vector3.INF, true)
	if want_attack and attack_hit_at < 0.0 and is_on_floor() and not body.busy():
		body.set_sword_drawn(true)
		# Swing towards where the camera looks if standing still.
		if Vector2(velocity.x, velocity.z).length() < 0.5:
			body.rotation.y = yaw + PI
		var length := body.play_once("Sword_Attack", 0.08, combat.get("sword_anim_speed", 1.5))
		attack_hit_at = length * combat.get("sword_hit_fraction", 0.38)
		attack_clock = 0.0
		since_attack = 0.0
	if attack_hit_at >= 0.0:
		attack_clock += delta
		if attack_clock >= attack_hit_at:
			attack_hit_at = -1.0
			_strike()
	if since_attack > combat.get("sheathe_after", 6.0):
		body.set_sword_drawn(false)


## Hits every creature in front of the explorer within sword reach.
func _strike() -> void:
	var fwd := Vector3(sin(body.rotation.y), 0, cos(body.rotation.y))
	var reach: float = combat.get("sword_range", 2.6)
	var arc := cos(deg_to_rad(combat.get("sword_arc_degrees", 80.0)))
	for c in get_tree().get_nodes_in_group("creatures"):
		if not c.visible or not c.alive():
			continue
		var to: Vector3 = c.global_position - global_position
		to.y = 0
		var d: float = to.length() - c.hit_radius()
		if d < reach and (to.length() < 0.6 or fwd.dot(to.normalized()) > arc):
			c.take_hit(combat.get("sword_damage", 34.0) * damage_mult, global_position)


## Damage from monsters (from_pos set) or lava (burn).
func take_damage(amount: float, from_pos: Vector3, burn := false) -> void:
	if dead:
		return
	health -= amount
	since_damage = 0.0
	if not burn:
		if attack_hit_at < 0.0:
			body.play_once("Hit_Chest", 0.05)
		if from_pos != Vector3.INF:
			var away := global_position - from_pos
			away.y = 0
			velocity += away.normalized() * combat.get("knockback", 5.0) + Vector3.UP * 2.5
		hurt.emit(false)
	elif burn_tick <= 0.0:
		burn_tick = 0.5
		hurt.emit(true)
	health_changed.emit(maxf(health, 0.0), max_health)
	if health <= 0.0:
		health = 0.0
		dead = true
		attack_hit_at = -1.0
		body.play_once("Death01", 0.1)
		died.emit()


## Quest reward: a stronger sword whose blade glows.
func set_sword_upgrade(mult: float, glow: Color) -> void:
	damage_mult = mult
	body.set_blade_glow(glow)


## Brings the explorer back to life at a safe spot.
func respawn(at: Vector3) -> void:
	dead = false
	health = max_health
	since_damage = 99.0
	velocity = Vector3.ZERO
	global_position = at
	cam_pivot.global_position = at + Vector3(0, 1.6, 0)
	body.cancel_action()
	body.set_sword_drawn(false)
	health_changed.emit(health, max_health)


func _animate(speed: float, delta: float) -> void:
	if dead or body.busy():
		return
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
