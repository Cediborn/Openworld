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
var dodge_pressed := false    # set by the touch dodge button
var block_held := false       # set by the touch block button
var potion_pressed := false   # set by the touch potion button
var gun_toggle_pressed := false  # G / touch gun button: draw or holster the shotgun
var reload_pressed := false      # R / touch reload button
var aim_held := false            # touch: hold to aim (PC: right mouse while the pistol is drawn)
var whistle_pressed := false     # T / touch horse button: whistle for your horse
## Keyboard combat: A swings the sword, S shoots, D defends (holds a block).
## Each one puts away the other weapon first if it is out.
var sword_key_pressed := false
var shoot_key_pressed := false
var _shot_queued := 0.0          # S with the pistol holstered: draw it, then fire
## The pump-action shotgun (see Firearm); null until the world sets it up.
var gun: Firearm
## Emitted when the explorer whistles for a horse.
signal whistled
var since_damage := 99.0
var since_attack := 99.0
var burn_tick := 0.0
var damage_mult := 1.0
## Damage taken is multiplied by this (armour); per-element extra factors below.
var armor_mult := 1.0
var resist := {"frost": 1.0, "fire": 1.0}
## Camera look speed multiplier from the settings menu.
var look_mult := 1.0
## Set by the Story node while a conversation is open: no attacking or moving.
var in_conversation := false

# Sword combo state. Each swing comes from combat.combo in game_config.json:
# the animation, when the blade is "live" (fractions of the clip) and how far
# the explorer steps in. Damage is dealt only where the blade's real path
# crosses a creature's body, so hits land when the sword visibly connects.
var swing := -1               # index into the combo, -1 when not attacking
var swing_t := 0.0            # seconds into the current swing
var swing_len := 0.0
var swing_queued := false
var swing_hit := {}           # creatures already struck by this swing
var swing_yaw := 0.0          # facing locked for the swing
var swing_step := Vector3.ZERO
var prev_blade: Array = []
var combo_reset := 0.0
var dodge_t := -1.0
var dodge_dir := Vector3.ZERO
var blocking := false
var heal_left := 0.0
## Called to use a healing potion; returns true if one was used (set by the world).
var use_potion: Callable
## Emitted when a swing connects (for sounds and effects).
signal struck(target: Node3D, pos: Vector3)
## Emitted when a blocked hit is absorbed.
signal blocked_hit
## Stepped or fell into water (for the splash).
signal splashed
## How deep the water is where you stand (0 on land); you wade slower in it.
var water_depth := 0.0
## Emitted when a swing starts (combo index) and when a dodge roll starts.
signal swung(index: int)
signal dodged
var trail: SwordTrail

# Riding (see Horse and Stable; tuning in data/horses.json "ride").
## The horse being ridden, or null.
var horse: Horse
## Riding tuning, set by the Stable.
var ride: Dictionary = {}
var ride_speed := 0.0
var ride_yaw := 0.0
var _foot_shape: CollisionShape3D
var _horse_shape: CollisionShape3D
## 0..1: how far the camera has moved in to the aiming position.
var _aim_blend := 0.0
const AIM_CAMERA_DISTANCE := 2.1
## Emitted when getting on (true) or off (false) a horse.
signal ridden(on: bool)


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
	_foot_shape = col
	# The horse's body while riding: a capsule lying along its back.
	_horse_shape = CollisionShape3D.new()
	var hc := CapsuleShape3D.new()
	hc.radius = 0.3
	hc.height = 1.9
	_horse_shape.shape = hc
	_horse_shape.position.y = 1.15
	_horse_shape.disabled = true
	add_child(_horse_shape)
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
	trail = SwordTrail.new()
	trail.body = body
	add_child(trail)


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
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_A:
			attack_pressed = true
			sword_key_pressed = true
		elif event.physical_keycode == KEY_S:
			shoot_key_pressed = true
		elif event.keycode == KEY_Q:
			dodge_pressed = true
		elif event.keycode == KEY_H:
			potion_pressed = true
		elif event.keycode == KEY_G:
			gun_toggle_pressed = true
		elif event.keycode == KEY_R:
			reload_pressed = true
		elif event.keycode == KEY_T:
			whistle_pressed = true


func _physics_process(delta: float) -> void:
	yaw -= look_input.x * LOOK_SENS * 1.6 * look_mult
	pitch = clampf(pitch - look_input.y * LOOK_SENS * 1.6 * look_mult, -1.2, 0.6)
	look_input = Vector2.ZERO

	# Arrow keys move; W sprints (Shift still works too).
	var kb := Vector2(
		float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP)))
	var stick: Vector2 = (move_input + kb).limit_length(1.0)
	var running: bool = sprint_held or Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_SHIFT)
	var walking: bool = Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_ALT)
	var want_jump: bool = jump_pressed or Input.is_physical_key_pressed(KEY_SPACE)
	jump_pressed = false
	var want_attack := attack_pressed
	attack_pressed = false
	var want_dodge := dodge_pressed
	dodge_pressed = false
	var want_potion := potion_pressed
	potion_pressed = false
	var key_block := Input.is_physical_key_pressed(KEY_D)
	var want_block: bool = block_held or key_block or (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	var want_sword_key := sword_key_pressed
	sword_key_pressed = false
	var want_shoot_key := shoot_key_pressed
	shoot_key_pressed = false
	var want_gun := gun_toggle_pressed
	gun_toggle_pressed = false
	var want_reload := reload_pressed
	reload_pressed = false
	var want_whistle := whistle_pressed
	whistle_pressed = false
	since_damage += delta
	since_attack += delta
	if dead or in_conversation:
		stick = Vector2.ZERO
		want_jump = false
		want_attack = false
		want_dodge = false
		want_block = false
		want_potion = false
		want_gun = false
		want_reload = false
		want_whistle = false
		want_sword_key = false
		want_shoot_key = false
		key_block = false
		_shot_queued = 0.0
	if want_whistle:
		whistle()
	var wish: Vector3 = Basis(Vector3.UP, yaw) * Vector3(stick.x, 0, stick.y)
	if gun:
		if want_gun and horse == null and swing < 0:
			gun.toggle()
		# A (sword) and D (defend) put the pistol away so the sword is used.
		if horse == null and gun.drawn and (want_sword_key or key_block):
			gun.set_drawn(false)
		# S shoots: if the pistol is holstered, draw it and fire a moment later.
		var want_shot := false
		if want_shoot_key and horse == null and swing < 0:
			if gun.drawn:
				want_shot = true
			elif gun.owned():
				gun.set_drawn(true)
				_shot_queued = 0.25
			else:
				gun.toggle()   # says you don't have a firearm yet
		if _shot_queued > 0.0:
			_shot_queued -= delta
			if _shot_queued <= 0.0 and gun.drawn and horse == null:
				want_shot = true
		var drawn := gun.drawn and horse == null
		# With the pistol out, attack fires and block (right mouse) aims instead.
		var aim_input: bool = aim_held or (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
		gun.update(delta, (want_attack or want_shot) and drawn, (aim_input or (want_block and not key_block)) and drawn, want_reload and drawn)
		if drawn:
			want_attack = false
			want_block = false
	if horse:
		_update_combat(delta, false, false, false, want_potion, wish)
		if horse:   # (a fall into lava can end the ride)
			_ride(delta, stick, wish, running, walking, want_jump)
		return
	_update_combat(delta, want_attack, want_dodge, want_block, want_potion, wish)

	# Push the stick a little to walk, all the way to jog; sprint button to run.
	var speed := 0.0
	var amount := stick.length()
	if amount > 0.05:
		if running and not blocking:
			speed = sprint_speed
		elif walking:
			speed = walk_speed
		elif amount < 0.6:
			speed = walk_speed * clampf(amount / 0.6, 0.4, 1.0)
		else:
			speed = jog_speed
	if swing >= 0:
		speed *= combat.get("attack_move_factor", 0.3)
	if blocking or (gun and gun.drawn and (gun.aiming or gun.reloading())):
		speed = minf(speed, walk_speed)
	var in_lava := _in_lava()
	if in_lava:
		speed *= combat.get("lava_speed_factor", 0.55)
	var wet := Water.depth_at(global_position) if not Water.bodies.is_empty() else 0.0
	if wet > 0.12 and water_depth <= 0.12:
		splashed.emit()
	water_depth = wet
	speed *= lerpf(1.0, 0.5, clampf(wet / 0.9, 0.0, 1.0))   # wading
	var target := wish.normalized() * speed if amount > 0.05 else Vector3.ZERO
	if swing >= 0:
		target += swing_step
	if dodge_t >= 0.0:
		target = dodge_dir * combat.get("dodge_speed", 7.5) * (1.0 - smoothstep(0.35, 0.6, dodge_t))
	var accel: float = 14.0 if is_on_floor() else 3.0
	if dodge_t >= 0.0:
		accel = 40.0
	velocity.x = move_toward(velocity.x, target.x, accel * delta * 4.0)
	velocity.z = move_toward(velocity.z, target.z, accel * delta * 4.0)
	if is_on_floor():
		if air_time > 0.35:
			land_timer = 0.25
		air_time = 0.0
		if want_jump and not body.busy() and swing < 0:
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
	if swing >= 0:
		body.rotation.y = lerp_angle(body.rotation.y, swing_yaw, 1.0 - exp(-22.0 * delta))
	elif blocking or (gun and gun.drawn and (gun.aiming or gun.cooldown > 0.0)):
		body.rotation.y = lerp_angle(body.rotation.y, yaw + PI, 1.0 - exp(-14.0 * delta))
	elif dodge_t >= 0.0:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(dodge_dir.x, dodge_dir.z), 1.0 - exp(-25.0 * delta))
	elif flat.length() > 0.3:
		var face: float = atan2(flat.x, flat.y)
		body.rotation.y = lerp_angle(body.rotation.y, face, 1.0 - exp(-10.0 * delta))
	_animate(flat.length(), delta)

	var follow := global_position + Vector3(0, 1.6, 0)
	var aim_k := 1.0 if gun and gun.drawn and gun.aiming else 0.0
	_aim_blend = move_toward(_aim_blend, aim_k, delta * 5.0)
	# Over the right shoulder while aiming, so the crosshair isn't behind your head.
	follow += Basis(Vector3.UP, yaw) * Vector3(0.55, 0.05, 0) * _aim_blend
	cam_pivot.global_position = cam_pivot.global_position.lerp(follow, 1.0 - exp(-18.0 * delta))
	cam_pivot.rotation = Vector3(pitch, yaw, 0)
	spring.spring_length = lerpf(camera_distance, AIM_CAMERA_DISTANCE, _aim_blend)
	body.aim_pitch = lerpf(body.aim_pitch, clampf(pitch + 0.12, -0.9, 0.9) * aim_k, 1.0 - exp(-14.0 * delta))


# ---------- Combat ----------

func _in_lava() -> bool:
	if data == null:
		return false
	var p := global_position
	return p.y < WorldData.LAVA_LEVEL + 0.05 and data.zone(p.x, p.z)[2] > 0.3


func _combo() -> Array:
	return combat.get("combo", [
		{"anim": "Sword_Slash1", "live": [0.27, 0.56], "step": 0.6, "damage": 1.0},
		{"anim": "Sword_Slash2", "live": [0.26, 0.55], "step": 0.6, "damage": 1.0},
		{"anim": "Sword_Slash3", "live": [0.36, 0.6], "step": 1.0, "damage": 1.6},
	])


## True while the explorer cannot be hurt (mid-roll).
func invulnerable() -> bool:
	var iv: Array = combat.get("dodge_iframes", [0.05, 0.4])
	return dodge_t >= iv[0] and dodge_t <= iv[1]


func _update_combat(delta: float, want_attack: bool, want_dodge: bool, want_block: bool, want_potion: bool, wish: Vector3) -> void:
	# Health comes back slowly once you've been out of harm for a while.
	if not dead and since_damage > combat.get("regen_delay", 6.0) and health < max_health:
		health = minf(max_health, health + combat.get("regen_per_second", 5.0) * delta)
		health_changed.emit(health, max_health)
	if heal_left > 0.0 and not dead:
		var h := minf(heal_left, delta * 45.0)
		heal_left -= h
		health = minf(max_health, health + h)
		health_changed.emit(health, max_health)
	if not dead and _in_lava():
		burn_tick -= delta
		take_damage(combat.get("lava_damage_per_second", 30.0) * delta, Vector3.INF, true)
	if want_potion and use_potion.is_valid() and health < max_health:
		if use_potion.call():
			heal_left += float(combat.get("potion_heal", 45.0))
	combo_reset -= delta
	# Dodge roll: a quick roll in the stick direction (or backwards) with a moment of invulnerability.
	if dodge_t >= 0.0:
		dodge_t += delta
		if dodge_t > combat.get("dodge_time", 0.62):
			dodge_t = -1.0
	elif want_dodge and is_on_floor() and not dead:
		_end_swing()
		blocking = false
		dodge_dir = wish.normalized() if wish.length() > 0.1 else -Vector3(sin(body.rotation.y), 0, cos(body.rotation.y))
		dodge_t = 0.0
		body.play_once("Roll", 0.06, combat.get("dodge_anim_speed", 1.5))
		dodged.emit()
		return
	blocking = want_block and dodge_t < 0.0 and swing < 0 and is_on_floor() and not dead
	if blocking:
		body.set_sword_drawn(true)
		since_attack = 0.0
	# Sword combo.
	if want_attack and dodge_t < 0.0 and not dead:
		if swing < 0 and is_on_floor() and (not body.busy() or body.current in ["Hit_Chest", "Jump_Land"]):
			_start_swing(0 if combo_reset <= 0.0 else _next_index(), wish)
		elif swing >= 0 and swing_t > swing_len * 0.15:
			swing_queued = true
	if swing >= 0:
		swing_t += delta
		var c: Dictionary = _combo()[swing]
		var live: Array = c.get("live", [0.3, 0.55])
		var f := swing_t / swing_len
		# Step in during the wind-up, then plant the feet.
		swing_step = swing_step.move_toward(Vector3.ZERO, delta * 6.0) if f > live[0] else swing_step
		if f >= live[0] and f <= live[1]:
			_blade_sweep(c)
			if trail:
				trail.emitting = true
		elif trail:
			trail.emitting = false
		prev_blade = body.blade_segment()
		# Chain into the next swing once this one has cut through.
		if swing_queued and f >= combat.get("combo_chain_at", 0.62):
			_start_swing(_next_index(), wish)
		elif swing_t >= swing_len:
			_end_swing()
	if since_attack > combat.get("sheathe_after", 6.0):
		body.set_sword_drawn(false)


func _next_index() -> int:
	return (swing + 1) % _combo().size() if swing >= 0 else _last_swing_index()


var _last_swing := -1
func _last_swing_index() -> int:
	return (_last_swing + 1) % _combo().size()


func _start_swing(index: int, wish: Vector3) -> void:
	var c: Dictionary = _combo()[index]
	body.set_sword_drawn(true)
	swing = index
	_last_swing = index
	swing_t = 0.0
	swing_queued = false
	swing_hit.clear()
	var speed: float = combat.get("sword_anim_speed", 1.0)
	body.cancel_action()
	swing_len = body.play_once(c.anim, 0.06, speed)
	swung.emit(index)
	since_attack = 0.0
	combo_reset = swing_len + combat.get("combo_window", 0.45)
	# Turn towards the most likely target: the closest creature roughly where
	# the stick (or camera) points, so the sword cuts towards it.
	var aim := wish.normalized() if wish.length() > 0.1 else -Vector3(sin(yaw), 0, cos(yaw))
	var tgt := _pick_target(aim)
	var face := aim
	swing_step = Vector3.ZERO
	if tgt:
		var to: Vector3 = tgt.global_position - global_position
		to.y = 0
		face = to.normalized()
		var gap: float = to.length() - tgt.hit_radius() - combat.get("ideal_gap", 1.15)
		if gap > 0.0:
			swing_step = face * clampf(gap, 0.0, float(c.get("step", 0.6)) * 1.6) / maxf(swing_len * 0.3, 0.05)
	elif c.get("step", 0.0) > 0.0:
		swing_step = face * float(c.step) * 0.5 / maxf(swing_len * 0.3, 0.05)
	swing_yaw = atan2(face.x, face.z)
	prev_blade = []


func _end_swing() -> void:
	swing = -1
	swing_queued = false
	swing_step = Vector3.ZERO
	if trail:
		trail.emitting = false


func _pick_target(aim: Vector3) -> Node3D:
	var best: Node3D = null
	var best_score := INF
	var reach: float = combat.get("lock_range", 4.5)
	for c in get_tree().get_nodes_in_group("creatures"):
		if not c.visible or not c.alive() or not c.is_hostile_to_player():
			continue
		var to: Vector3 = c.global_position - global_position
		to.y = 0
		var d: float = to.length() - c.hit_radius()
		if d > reach:
			continue
		var facing: float = aim.dot(to.normalized()) if to.length() > 0.01 else 1.0
		if facing < 0.2:
			continue
		var score: float = d - facing * 1.5
		if score < best_score:
			best_score = score
			best = c
	return best


## Damages creatures the blade passes through this frame (once per swing).
func _blade_sweep(c: Dictionary) -> void:
	var seg := body.blade_segment()
	var segs := [seg]
	if prev_blade.size() == 2:
		# Fast swings travel far between frames; also test the swept area.
		segs.append([prev_blade[1], seg[1]])
		segs.append([(prev_blade[0] + prev_blade[1]) * 0.5, (seg[0] + seg[1]) * 0.5])
	for cr in get_tree().get_nodes_in_group("creatures"):
		if swing_hit.has(cr) or not cr.visible or not cr.alive():
			continue
		var a: Vector3 = cr.body_axis()[0]
		var b: Vector3 = cr.body_axis()[1]
		var r: float = cr.hit_radius() + 0.08
		for sgm in segs:
			var pts := Geometry3D.get_closest_points_between_segments(sgm[0], sgm[1], a, b)
			if pts[0].distance_to(pts[1]) < r:
				swing_hit[cr] = true
				var dmg: float = combat.get("sword_damage", 34.0) * damage_mult * float(c.get("damage", 1.0))
				cr.take_hit(dmg, global_position)
				struck.emit(cr, pts[0])
				break


## The old single-strike entry point, kept for tests and scripted sequences.
func _strike() -> void:
	for cr in get_tree().get_nodes_in_group("creatures"):
		if not cr.visible or not cr.alive():
			continue
		var to: Vector3 = cr.global_position - global_position
		to.y = 0
		if to.length() - cr.hit_radius() < combat.get("sword_range", 2.6):
			cr.take_hit(combat.get("sword_damage", 34.0) * damage_mult, global_position)


## Damage from monsters (from_pos set) or lava (burn). element: "", "frost" or "fire".
func take_damage(amount: float, from_pos: Vector3, burn := false, element := "") -> void:
	if dead:
		return
	if not burn and invulnerable():
		return
	if burn:
		amount *= resist.get("fire", 1.0)
	else:
		amount *= armor_mult * float(resist.get(element, 1.0))
		if blocking and from_pos != Vector3.INF:
			var to := from_pos - global_position
			to.y = 0
			var fwd := Vector3(sin(body.rotation.y), 0, cos(body.rotation.y))
			if fwd.dot(to.normalized()) > 0.25:
				amount *= combat.get("block_factor", 0.25)
				blocked_hit.emit()
	health -= amount
	since_damage = 0.0
	if not burn:
		if swing < 0 and dodge_t < 0.0 and not blocking and horse == null:
			body.play_once("Hit_Chest", 0.05)
		if from_pos != Vector3.INF and horse == null:
			var away := global_position - from_pos
			away.y = 0
			var kb: float = combat.get("knockback", 5.0) * (0.35 if blocking else 1.0)
			velocity += away.normalized() * kb + Vector3.UP * (0.8 if blocking else 2.5)
		hurt.emit(false)
	elif burn_tick <= 0.0:
		burn_tick = 0.5
		hurt.emit(true)
	health_changed.emit(maxf(health, 0.0), max_health)
	if health <= 0.0:
		health = 0.0
		dead = true
		if horse:
			dismount()
		_end_swing()
		blocking = false
		dodge_t = -1.0
		body.cancel_action()
		body.play_once("Death01", 0.1)
		died.emit()


## Quest reward: a stronger sword whose blade glows.
func set_sword_upgrade(mult: float, glow: Color) -> void:
	damage_mult = mult
	body.set_blade_glow(glow)


## Brings the explorer back to life at a safe spot.
func respawn(at: Vector3) -> void:
	if horse:
		dismount()
	dead = false
	health = max_health
	since_damage = 99.0
	velocity = Vector3.ZERO
	global_position = at
	cam_pivot.global_position = at + Vector3(0, 1.6, 0)
	_end_swing()
	dodge_t = -1.0
	heal_left = 0.0
	body.cancel_action()
	body.set_sword_drawn(false)
	health_changed.emit(health, max_health)


func _animate(speed: float, delta: float) -> void:
	if dead or body.busy():
		return
	land_timer -= delta
	var drawn := body.sword_hand != null and body.sword_hand.visible
	var pistol := gun != null and gun.drawn
	if pistol and air_time <= 0.2 and land_timer <= 0.0 and (speed < 0.25 or gun.aiming):
		body.play("Pistol_Aim" if gun.aiming else "Pistol_Idle", 0.15)
		return
	if blocking:
		body.play("Sword_Block", 0.12)
	elif air_time > 0.2:
		body.play("Jump", 0.2)
	elif land_timer > 0.0:
		body.play("Jump_Land", 0.08)
	elif speed < 0.25:
		body.play("Sword_Idle" if drawn else "Idle", 0.25)
	elif speed < walk_speed + 0.4:
		body.play("Walk", 0.25, speed / ANIM_SPEED.Walk)
	elif speed < jog_speed + 0.8:
		body.play("Jog_Fwd", 0.2, speed / ANIM_SPEED.Jog_Fwd)
	else:
		body.play("Sprint", 0.2, speed / ANIM_SPEED.Sprint)


# ---------- Riding ----------

## Two fingers to the lips: a sharp whistle that calls your horse (see Stable.whistle).
func whistle() -> void:
	if dead or in_conversation:
		return
	if horse == null and is_on_floor() and swing < 0 and dodge_t < 0.0:
		if gun and gun.reloading():
			return
		body.play_once("Whistle", 0.1)
	whistled.emit()


## Climbs onto a horse: the explorer sits in the saddle and the stick now
## steers the horse (walk, trot; sprint to gallop).
func mount(h: Horse) -> void:
	if horse != null or dead:
		return
	horse = h
	if gun and gun.drawn:
		gun.set_drawn(false)
	_end_swing()
	blocking = false
	dodge_t = -1.0
	body.cancel_action()
	body.set_sword_drawn(false)
	ride_speed = 0.0
	ride_yaw = h.rotation.y
	global_position = h.global_position
	velocity = Vector3.ZERO
	body.rotation.y = ride_yaw + PI
	body.position.y = float(ride.get("saddle_height", 1.56)) - float(ride.get("rider_hips", 0.62))
	body.play("Ride", 0.25)
	spring.spring_length = float(ride.get("camera_distance", 6.0))
	_horse_shape.disabled = false
	h.set_ridden(self)
	ridden.emit(true)


## Gets off beside the horse, which stays where it is.
func dismount() -> void:
	if horse == null:
		return
	var h := horse
	horse = null
	h.speed = 0.0
	h.set_ridden(null)
	_horse_shape.disabled = true
	body.position.y = 0.0
	spring.spring_length = camera_distance
	# Step down on the horse's left side (or right, if the left is a wall).
	var left := Vector3(-cos(ride_yaw), 0, sin(ride_yaw))
	var spot := h.global_position + left * 1.0
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(h.global_position + Vector3.UP, spot + Vector3.UP)
	ray.exclude = [get_rid()]
	if not space.intersect_ray(ray).is_empty():
		spot = h.global_position - left * 1.0
	var ground: float = data.height(spot.x, spot.z) if data else spot.y
	global_position = Vector3(spot.x, maxf(ground, h.global_position.y) + 0.1, spot.z)
	velocity = Vector3.ZERO
	body.rotation.y = ride_yaw + PI
	body.play("Idle", 0.2)
	ridden.emit(false)


func _ride(delta: float, stick: Vector2, wish: Vector3, running: bool, walking: bool, want_jump: bool) -> void:
	var amount := stick.length()
	var want := 0.0
	if amount > 0.05:
		if running:
			want = float(ride.get("gallop_speed", 13.0))
		elif walking:
			want = float(ride.get("walk_speed", 2.4))
		elif amount < 0.6:
			want = float(ride.get("walk_speed", 2.4)) * clampf(amount / 0.6, 0.5, 1.0)
		else:
			want = float(ride.get("trot_speed", 6.5))
		# The horse turns towards where the stick points (no spinning on the spot at a gallop).
		var goal := atan2(-wish.x, -wish.z)
		var diff := wrapf(goal - ride_yaw, -PI, PI)
		var rate: float = float(ride.get("turn_rate", 3.2)) * lerpf(1.4, 0.8, clampf(ride_speed / 13.0, 0.0, 1.0))
		ride_yaw += clampf(diff, -rate * delta, rate * delta)
		# Pulling hard round slows the horse down instead of skidding.
		want *= clampf(1.0 - absf(diff) / PI * 0.8, 0.25, 1.0)
	if in_conversation or dead:
		want = 0.0
	if _in_lava():
		want *= combat.get("lava_speed_factor", 0.75)
	var rate2: float = float(ride.get("accel", 5.0)) if want > ride_speed else float(ride.get("brake", 9.0))
	ride_speed = move_toward(ride_speed, want, rate2 * delta)
	var fwd := Vector3(-sin(ride_yaw), 0, -cos(ride_yaw))
	velocity.x = fwd.x * ride_speed
	velocity.z = fwd.z * ride_speed
	if is_on_floor():
		air_time = 0.0
		if want_jump and ride_speed > 0.5:
			velocity.y = float(ride.get("jump_velocity", 6.2))
	else:
		air_time += delta
		velocity.y -= gravity * delta
	_horse_shape.basis = Basis(Vector3.UP, ride_yaw) * Basis(Vector3.RIGHT, PI * 0.5)
	move_and_slide()
	# Bumping into a wall stops the horse rather than letting it run on the spot.
	var real := Vector2(get_real_velocity().x, get_real_velocity().z).length()
	if is_on_wall() and real < ride_speed * 0.5:
		ride_speed = move_toward(ride_speed, real, 20.0 * delta)
	horse.global_position = global_position
	horse.rotation.y = ride_yaw
	horse.speed = ride_speed
	body.rotation.y = ride_yaw + PI
	body.position.y = float(ride.get("saddle_height", 1.56)) - float(ride.get("rider_hips", 0.62)) + horse.saddle_bob() * 1.6
	body.play("Ride", 0.25)
	var follow := global_position + Vector3(0, float(ride.get("camera_height", 2.5)), 0)
	cam_pivot.global_position = cam_pivot.global_position.lerp(follow, 1.0 - exp(-14.0 * delta))
	cam_pivot.rotation = Vector3(pitch, yaw, 0)
