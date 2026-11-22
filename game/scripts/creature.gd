class_name Creature
extends Node3D
## A creature of the island: grazing animals and biome monsters. Models come
## from tools/creatures/ and share bone names, so one procedural animator
## handles four-legged, six-legged, two-legged and floating bodies.
## Behaviour ("temper") is either "flee" (deer, boar, wolf) or "threaten"
## (monsters chase and roar, then lose interest). Tuning: data/creatures.json.

enum State { IDLE, GRAZE, WALK, FLEE, CHASE, ROAR, RETURN }

## Phase offsets (fraction of a step cycle) per leg group.
const QUAD_WALK := {"H_L": 0.0, "F_L": 0.25, "H_R": 0.5, "F_R": 0.75}
const QUAD_RUN := {"H_L": 0.55, "F_L": 0.0, "H_R": 0.6, "F_R": 0.1}
const HEX_TRIPOD := {"F_L": 0.0, "M_R": 0.0, "H_L": 0.0, "F_R": 0.5, "M_L": 0.5, "H_R": 0.5}

## Emitted when the creature starts a roar or call, so the sound system can play it.
signal vocal(kind: String)

var cfg: Dictionary = {}
## Returns ground height at (x, z). Injected so the creature works without the world.
var height_at: Callable = func(_x: float, _z: float) -> float: return 0.0
## The node creatures react to (the player). May be null.
var threat: Node3D
var home := Vector3.ZERO
var rng := RandomNumberGenerator.new()

var skeleton: Skeleton3D
var bone := {}
var body := "quad"
var state := State.IDLE
var timer := 0.0
var target := Vector3.ZERO
var speed := 0.0
var phase := 0.0
var run_mix := 0.0
var graze_mix := 0.0
var roar_mix := 0.0
var hips_rest := Vector3.ZERO
var t := 0.0
var call_timer := 0.0
var cooldown := 0.0


## Builds the creature from its species config. seed_value varies size, tint and timing.
func setup(species_cfg: Dictionary, seed_value: int) -> void:
	cfg = species_cfg
	rng.seed = seed_value
	body = cfg.get("body", "quad")
	var model: Node3D = load(cfg.model).instantiate()
	add_child(model)
	var s: Array = cfg.get("scale", [1.0, 1.0])
	model.scale = Vector3.ONE * rng.randf_range(s[0], s[1])
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	var spirit: bool = cfg.get("shader", "") == "spirit"
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/spatial_creature_spirit.gdshader" if spirit else "res://shaders/spatial_creature_fur.gdshader")
	mat.set_shader_parameter("fur_noise", Props.noise())
	mat.set_shader_parameter("tint", rng.randf_range(0.9, 1.1))
	var gc: Array = cfg.get("glow_color", [1.0, 0.5, 0.1])
	mat.set_shader_parameter("glow_color", Color(gc[0], gc[1], gc[2]))
	mat.set_shader_parameter("glow_energy", float(cfg.get("glow_energy", 0.0)))
	mat.set_shader_parameter("base_roughness", float(cfg.get("roughness", 0.85)))
	mat.set_shader_parameter("pulse_offset", rng.randf() * TAU)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = mat
		if spirit:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in skeleton.get_bone_count():
		bone[skeleton.get_bone_name(i)] = i
	hips_rest = skeleton.get_bone_rest(bone["Hips"]).origin
	phase = rng.randf()
	call_timer = rng.randf_range(4.0, 20.0)
	_choose_idle()


func _process(delta: float) -> void:
	if skeleton == null:
		return
	t += delta
	_think(delta)
	_move(delta)
	_pose()


func _threat_distance() -> float:
	if threat == null:
		return INF
	return Vector2(threat.global_position.x - global_position.x, threat.global_position.z - global_position.z).length()


# ---------- Brain ----------

func _think(delta: float) -> void:
	timer -= delta
	cooldown -= delta
	call_timer -= delta
	if call_timer <= 0.0:
		call_timer = rng.randf_range(10.0, 26.0)
		if state != State.FLEE and state != State.ROAR:
			vocal.emit("call")
	var d := _threat_distance()
	if cfg.get("temper", "flee") == "flee":
		if d < cfg.flee_radius and state != State.FLEE:
			state = State.FLEE
		if state == State.FLEE and threat:
			var away := global_position - threat.global_position
			away.y = 0
			target = global_position + away.normalized() * 15.0
			if d > cfg.calm_radius:
				_choose_idle()
			return
	else:
		var from_home := Vector2(global_position.x - home.x, global_position.z - home.z).length()
		match state:
			State.IDLE, State.GRAZE, State.WALK:
				if d < cfg.aggro_radius and cooldown <= 0.0:
					_start_roar()
					return
			State.ROAR:
				if timer <= 0.0:
					state = State.CHASE
					timer = cfg.chase_time
				return
			State.CHASE:
				if threat:
					target = threat.global_position
				if timer <= 0.0 or d > cfg.aggro_radius * 2.0 or from_home > cfg.leash:
					state = State.RETURN
					target = home
					cooldown = cfg.get("cooldown", 12.0)
				elif d < cfg.stop_distance:
					_start_roar()
				return
			State.RETURN:
				if from_home < 2.0:
					_choose_idle()
				return
	match state:
		State.IDLE, State.GRAZE:
			if timer <= 0.0:
				var a := rng.randf() * TAU
				var r := sqrt(rng.randf()) * float(cfg.wander_radius)
				target = home + Vector3(cos(a) * r, 0, sin(a) * r)
				state = State.WALK
		State.WALK:
			if Vector2(target.x - global_position.x, target.z - global_position.z).length() < 0.8:
				_choose_idle()


func _start_roar() -> void:
	state = State.ROAR
	timer = cfg.get("roar_time", 1.6)
	vocal.emit("roar")


func _choose_idle() -> void:
	state = State.GRAZE if rng.randf() < float(cfg.graze_chance) else State.IDLE
	var it: Array = cfg.idle_time
	timer = rng.randf_range(it[0], it[1])


func _move(delta: float) -> void:
	var want := 0.0
	if state == State.WALK or state == State.RETURN:
		want = cfg.walk_speed
	elif state == State.FLEE or state == State.CHASE:
		want = cfg.run_speed
	speed = move_toward(speed, want, delta * (6.0 if want > speed else 5.0))
	var fast := state == State.FLEE or state == State.CHASE
	run_mix = move_toward(run_mix, 1.0 if fast else 0.0, delta * 2.5)
	graze_mix = move_toward(graze_mix, 1.0 if state == State.GRAZE else 0.0, delta * 1.2)
	roar_mix = move_toward(roar_mix, 1.0 if state == State.ROAR else 0.0, delta * 4.0)
	var to := target - global_position
	to.y = 0
	var face_target := state == State.ROAR and threat != null
	if face_target:
		to = threat.global_position - global_position
		to.y = 0
	if (speed > 0.01 or face_target) and to.length() > 0.1:
		var yaw := atan2(-to.x, -to.z)
		rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * (5.0 if fast or face_target else 2.0), 0, 1))
	if speed > 0.01:
		var step := -global_transform.basis.z * speed * delta
		var ahead := global_position + step * (1.5 / maxf(speed * delta, 0.001))
		# Never walk into lava (or anywhere too low for this species): head home instead.
		if height_at.call(ahead.x, ahead.z) < float(cfg.get("min_height", -INF)):
			target = home
			step = Vector3.ZERO
		global_position += step
		var stride: float = lerpf(cfg.walk_stride, cfg.run_stride, run_mix)
		phase = fposmod(phase + speed * delta / stride, 1.0)
	var y: float = height_at.call(global_position.x, global_position.z)
	if body == "float":
		y += float(cfg.get("hover", 0.4)) + 0.15 * sin(t * 1.3)
	global_position.y = y


# ---------- Procedural animation ----------

func _rot(name: String, euler: Vector3) -> void:
	if bone.has(name):
		skeleton.set_bone_pose_rotation(bone[name], Quaternion.from_euler(euler))


func _pose() -> void:
	var moving := clampf(speed / float(cfg.walk_speed), 0.0, 1.0)
	match body:
		"biped":
			_pose_biped(moving)
		"float":
			_pose_float(moving)
		_:
			_pose_legs(moving)
	var bob: float = cfg.bob * moving * (1.0 + run_mix) * absf(sin(phase * TAU * 2.0))
	skeleton.set_bone_pose_position(bone["Hips"], hips_rest + Vector3(0, bob, 0))


## Four or six legs, each leg four bones. Sideways-splayed legs (salamander,
## beetle) swing around the vertical axis instead and the body wiggles.
func _pose_legs(moving: float) -> void:
	var swing: float = cfg.swing * (1.0 + 0.5 * run_mix) * moving
	var lift: float = cfg.lift * moving
	var splay: float = cfg.get("splay", 0.0)
	var legs: Array = ["F_L", "F_R", "M_L", "M_R", "H_L", "H_R"] if body == "hex" else ["F_L", "F_R", "H_L", "H_R"]
	for leg: String in legs:
		var off: float = HEX_TRIPOD[leg] if body == "hex" else lerpf(QUAD_WALK[leg], QUAD_RUN[leg], run_mix)
		var p: float = (phase + off) * TAU
		var s := sin(p)
		var up := maxf(cos(p), 0.0)   # > 0 while the foot swings forward through the air
		var g := leg.substr(0, 1)
		var side := leg.substr(1)
		var sgn := 1.0 if side == "_L" else -1.0
		var upright := 1.0 - splay
		# Upright legs pitch around X; splayed legs yaw around Y and lift around Z.
		_rot(g + "1" + side, Vector3(swing * s * upright, swing * s * splay * sgn, 0))
		if g == "H":
			_rot(g + "2" + side, Vector3(-lift * up * 0.5 * upright, 0, lift * up * 0.5 * splay * sgn))
			_rot(g + "3" + side, Vector3(lift * up * 0.9 * upright, 0, 0))
			_rot(g + "4" + side, Vector3(-lift * up * 0.4 * upright, 0, 0))
		else:
			_rot(g + "2" + side, Vector3(-0.1 * swing * s * upright, 0, lift * up * 0.5 * splay * sgn))
			_rot(g + "3" + side, Vector3(-lift * up * 1.2 * upright, 0, 0))
			_rot(g + "4" + side, Vector3(lift * up * 0.6 * upright, 0, 0))
	var wiggle: float = cfg.get("wiggle", 0.0) * moving * sin(phase * TAU)
	_rot("Hips", Vector3(0.06 * run_mix * sin(phase * TAU), wiggle, 0))
	_rot("Chest", Vector3(0, -wiggle, 0))
	var nod := 0.05 * moving * sin(phase * TAU * 2.0)
	var look := 0.25 * sin(t * 0.4 + rng.seed % 7) * (1.0 - moving)
	# Roar: head thrown up and back (four legs) or horn raised (beetle).
	_rot("Neck", Vector3(-1.0 * graze_mix + nod - 0.15 * run_mix + 0.5 * roar_mix, look * 0.5, 0))
	_rot("Head", Vector3(-0.45 * graze_mix + 0.1 * run_mix + 0.35 * roar_mix, look * 0.5, 0))
	_rot("Tail", Vector3(0.3 * run_mix, 0.25 * sin(t * 2.3) + wiggle * 2.0, 0))


## Two legs, two arms. Roar: chest back, arms raised wide.
func _pose_biped(moving: float) -> void:
	var swing: float = cfg.swing * (1.0 + 0.4 * run_mix) * moving
	var lift: float = cfg.lift * moving
	for side in ["_L", "_R"]:
		var off := 0.0 if side == "_L" else 0.5
		var p: float = (phase + off) * TAU
		var s := sin(p)
		var up := maxf(cos(p), 0.0)
		var sgn := 1.0 if side == "_L" else -1.0
		_rot("L1" + side, Vector3(swing * s, 0, 0))
		_rot("L2" + side, Vector3(-lift * up, 0, 0))
		_rot("L3" + side, Vector3(lift * up * 0.4, 0, 0))
		# Arms swing opposite to the legs; raised and spread when roaring.
		var arm_x := -swing * s * 0.8 * (1.0 - roar_mix) - 1.3 * roar_mix
		_rot("A1" + side, Vector3(arm_x, 0, sgn * (0.12 + 0.9 * roar_mix)))
		_rot("A2" + side, Vector3(-0.3 - 0.25 * moving - 0.4 * roar_mix, 0, 0))
	var sway := 0.06 * moving * sin(phase * TAU)
	_rot("Hips", Vector3(0, sway, 0.03 * moving * sin(phase * TAU)))
	_rot("Spine", Vector3(-0.12 * run_mix + 0.2 * roar_mix, -sway * 0.5, 0))
	_rot("Chest", Vector3(0.15 * roar_mix + 0.05 * sin(t * 1.1), -sway * 0.5, 0))
	var look := 0.3 * sin(t * 0.35 + rng.seed % 5) * (1.0 - moving)
	_rot("Neck", Vector3(-0.2 * graze_mix + 0.25 * roar_mix, look * 0.5, 0))
	_rot("Head", Vector3(0.3 * roar_mix, look * 0.5, 0))


## Floating wraith: drifts, arms trail, mist tail swirls.
func _pose_float(moving: float) -> void:
	for side in ["_L", "_R"]:
		var sgn := 1.0 if side == "_L" else -1.0
		var wave := sin(t * 1.7 + (0.0 if side == "_L" else 1.3))
		_rot("A1" + side, Vector3(0.3 * moving + 0.15 * wave - 1.4 * roar_mix, 0, sgn * (0.2 + 0.1 * wave + 0.7 * roar_mix)))
		_rot("A2" + side, Vector3(-0.3 - 0.2 * wave * (1.0 - roar_mix), 0, 0))
		_rot("A3" + side, Vector3(-0.2 * wave, 0, 0))
	_rot("Spine", Vector3(0.25 * moving + 0.2 * roar_mix, 0.08 * sin(t * 0.9), 0))
	_rot("Head", Vector3(0.1 * sin(t * 0.7) + 0.3 * roar_mix, 0.3 * sin(t * 0.43), 0))
	_rot("Tail", Vector3(0.35 * moving + 0.1 * sin(t * 1.9), 0.4 * sin(t * 1.2), 0.15 * sin(t * 2.3)))
