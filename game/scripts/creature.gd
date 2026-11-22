class_name Creature
extends Node3D
## A four-legged animal (deer, boar, wolf) with procedural walking and a small
## wander / graze / flee brain. The model comes from tools/creatures/
## build_creatures.py; every species shares the same bone names, so one gait
## routine animates them all. Tuning lives in data/creatures.json.

enum State { IDLE, GRAZE, WALK, FLEE }

## Leg order and phase offsets (fraction of a step cycle) for walk and run.
const LEGS := ["H_L", "F_L", "H_R", "F_R"]
const WALK_PHASE := [0.0, 0.25, 0.5, 0.75]
const RUN_PHASE := [0.55, 0.0, 0.6, 0.1]

var cfg: Dictionary = {}
## Returns ground height at (x, z). Injected so the creature works without the world.
var height_at: Callable = func(_x: float, _z: float) -> float: return 0.0
## The node animals react to (the player). May be null.
var threat: Node3D
var home := Vector3.ZERO
var rng := RandomNumberGenerator.new()

var skeleton: Skeleton3D
var bone := {}
var state := State.IDLE
var timer := 0.0
var target := Vector3.ZERO
var speed := 0.0
var phase := 0.0
var run_mix := 0.0
var graze_mix := 0.0
var hips_rest := Vector3.ZERO
var t := 0.0


## Builds the animal. Call before adding to the tree is not required.
func setup(species_cfg: Dictionary, seed_value: int) -> void:
	cfg = species_cfg
	rng.seed = seed_value
	var model: Node3D = load(cfg.model).instantiate()
	add_child(model)
	var s: Array = cfg.get("scale", [1.0, 1.0])
	model.scale = Vector3.ONE * rng.randf_range(s[0], s[1])
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/spatial_creature_fur.gdshader")
	mat.set_shader_parameter("fur_noise", Props.noise())
	mat.set_shader_parameter("tint", rng.randf_range(0.88, 1.1))
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = mat
	for i in skeleton.get_bone_count():
		bone[skeleton.get_bone_name(i)] = i
	hips_rest = skeleton.get_bone_rest(bone["Hips"]).origin
	phase = rng.randf()
	_choose_idle()


func _process(delta: float) -> void:
	if skeleton == null:
		return
	t += delta
	_think(delta)
	_move(delta)
	_pose()


# ---------- Brain ----------

func _think(delta: float) -> void:
	timer -= delta
	var d_threat := INF
	if threat:
		d_threat = Vector2(threat.global_position.x - global_position.x, threat.global_position.z - global_position.z).length()
	if d_threat < cfg.flee_radius and state != State.FLEE:
		state = State.FLEE
	if state == State.FLEE and threat:
		var away := global_position - threat.global_position
		away.y = 0
		target = global_position + away.normalized() * 15.0
		if d_threat > cfg.calm_radius:
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


func _choose_idle() -> void:
	state = State.GRAZE if rng.randf() < float(cfg.graze_chance) else State.IDLE
	var it: Array = cfg.idle_time
	timer = rng.randf_range(it[0], it[1])


func _move(delta: float) -> void:
	var want := 0.0
	if state == State.WALK:
		want = cfg.walk_speed
	elif state == State.FLEE:
		want = cfg.run_speed
	speed = move_toward(speed, want, delta * (6.0 if want > speed else 4.0))
	run_mix = move_toward(run_mix, 1.0 if state == State.FLEE else 0.0, delta * 2.5)
	graze_mix = move_toward(graze_mix, 1.0 if state == State.GRAZE else 0.0, delta * 1.2)
	if speed > 0.01:
		var to := target - global_position
		to.y = 0
		if to.length() > 0.1:
			var yaw := atan2(-to.x, -to.z)
			rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * (5.0 if state == State.FLEE else 2.0), 0, 1))
		global_position += -global_transform.basis.z * speed * delta
		var stride: float = lerpf(cfg.walk_stride, cfg.run_stride, run_mix)
		phase = fposmod(phase + speed * delta / stride, 1.0)
	global_position.y = height_at.call(global_position.x, global_position.z)


# ---------- Procedural animation ----------

func _rot(name: String, euler: Vector3) -> void:
	skeleton.set_bone_pose_rotation(bone[name], Quaternion.from_euler(euler))


func _pose() -> void:
	var moving := clampf(speed / float(cfg.walk_speed), 0.0, 1.0)
	var swing: float = cfg.swing * (1.0 + 0.5 * run_mix) * moving
	var lift: float = cfg.lift * moving
	for i in 4:
		var leg: String = LEGS[i]
		var p: float = (phase + lerpf(WALK_PHASE[i], RUN_PHASE[i], run_mix)) * TAU
		var s := sin(p)
		var up := maxf(cos(p), 0.0)   # > 0 while the foot swings forward through the air
		var side := leg.substr(1)       # "_L" / "_R"
		if leg.begins_with("F"):
			_rot("F1" + side, Vector3(swing * s, 0, 0))
			_rot("F2" + side, Vector3(-0.1 * swing * s, 0, 0))
			_rot("F3" + side, Vector3(-lift * up * 1.2, 0, 0))
			_rot("F4" + side, Vector3(lift * up * 0.6, 0, 0))
		else:
			_rot("H1" + side, Vector3(swing * s * 0.9, 0, 0))
			_rot("H2" + side, Vector3(-lift * up * 0.5, 0, 0))
			_rot("H3" + side, Vector3(lift * up * 0.9, 0, 0))
			_rot("H4" + side, Vector3(-lift * up * 0.4, 0, 0))
	# Body bob twice per cycle, a little rock when running.
	var bob: float = cfg.bob * moving * (1.0 + run_mix) * absf(sin(phase * TAU * 2.0))
	skeleton.set_bone_pose_position(bone["Hips"], hips_rest + Vector3(0, bob, 0))
	_rot("Hips", Vector3(0.06 * run_mix * sin(phase * TAU), 0, 0))
	# Head: lowered to the grass when grazing, nods while walking, alert when fleeing.
	var nod := 0.05 * moving * sin(phase * TAU * 2.0)
	var look := 0.25 * sin(t * 0.4 + rng.seed % 7) * (1.0 - moving)
	_rot("Neck", Vector3(-1.0 * graze_mix + nod - 0.15 * run_mix, look * 0.5, 0))
	_rot("Head", Vector3(-0.45 * graze_mix + 0.1 * run_mix, look * 0.5, 0))
	_rot("Tail", Vector3(0.3 * run_mix, 0.25 * sin(t * 2.3), 0))
