class_name Creature
extends Node3D
## A creature of the island: grazing animals and biome monsters. Models come
## from tools/creatures/ and share bone names, so one procedural animator
## handles four-legged, six-legged, two-legged and floating bodies.
## Behaviour ("temper") is either "flee" (deer, boar, wolf) or "threaten"
## (monsters chase and roar, then lose interest). Tuning: data/creatures.json.

enum State { IDLE, GRAZE, WALK, FLEE, CHASE, ROAR, RETURN, ATTACK, DEAD }
## Metres within which shy animals hear a fight (sword hits) and bolt.
const FIGHT_HEARD := 30.0

## Phase offsets (fraction of a step cycle) per leg group.
const QUAD_WALK := {"H_L": 0.0, "F_L": 0.25, "H_R": 0.5, "F_R": 0.75}
const QUAD_RUN := {"H_L": 0.55, "F_L": 0.0, "H_R": 0.6, "F_R": 0.1}
const HEX_TRIPOD := {"F_L": 0.0, "M_R": 0.0, "H_L": 0.0, "F_R": 0.5, "M_L": 0.5, "H_R": 0.5}

## Emitted when the creature starts a roar or call, so the sound system can play it.
signal vocal(kind: String)

var cfg: Dictionary = {}
## Returns ground height at (x, z). Injected so the creature works without the world.
var height_at: Callable = func(_x: float, _z: float) -> float: return 0.0
## Optional (x, z) -> bool: true where this creature must never step (horses: lava).
var avoid_at: Callable = Callable()
## Seconds left of bolting from a gunshot (shy animals).
var scared := 0.0
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

# Combat
var model: Node3D
var mat: ShaderMaterial
var temper := "flee"
var health := 60.0
var attack_cd := 0.0
var flash := 0.0
var dead_time := 0.0
var size_scale := 1.0
## Model size (metres, before scaling): height and body length, from its mesh bounds.
var model_size := Vector3.ONE
## Current attack: one entry of cfg.attacks (or the body type's defaults).
var atk: Dictionary = {}
var atk_t := 0.0
var atk_done := false        # the impact moment has been resolved
var atk_dir := Vector3.FORWARD
var atk_off := {}            # bone name -> extra euler rotation from the attack pose
var atk_hips := Vector3.ZERO # extra hips offset from the attack pose
var flinch := 0.0
var telegraph: MeshInstance3D
## Emitted at an attack's impact moment: hit is true when it connected.
signal attack_landed(hit: bool, move: String)
## Set by quests: kills of this creature are reported with this tag.
var quest_tag := ""
## Never respawns once killed (quest and boss spawns).
var unique := false
signal killed(c: Creature)


## Builds the creature from its species config. seed_value varies size, tint and timing.
func setup(species_cfg: Dictionary, seed_value: int) -> void:
	cfg = species_cfg
	rng.seed = seed_value
	body = cfg.get("body", "quad")
	temper = cfg.get("temper", "flee")
	health = cfg.get("health", 60.0)
	add_to_group("creatures")
	model = load(cfg.model).instantiate()
	add_child(model)
	var s: Array = cfg.get("scale", [1.0, 1.0])
	size_scale = rng.randf_range(s[0], s[1])
	model.scale = Vector3.ONE * size_scale
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	var bounds := AABB()
	var first := true
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		bounds = mi.get_aabb() if first else bounds.merge(mi.get_aabb())
		first = false
	model_size = Vector3(bounds.size.x, bounds.size.y, bounds.size.z)
	var spirit: bool = cfg.get("shader", "") == "spirit"
	mat = ShaderMaterial.new()
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
	if flash > 0.0:
		flash = maxf(0.0, flash - delta * 4.0)
		mat.set_shader_parameter("hit_flash", flash)
	if state == State.DEAD:
		_dead_update(delta)
		return
	_think(delta)
	_move(delta)
	_pose()


# ---------- Combat ----------

## True until the creature is killed (it comes back later at home).
func alive() -> bool:
	return state != State.DEAD


## Monsters, and animals that fight back once provoked.
func is_hostile_to_player() -> bool:
	return temper == "threaten" or cfg.get("fights_back", false)


## Rough body radius, so big monsters can be hit from further away.
func hit_radius() -> float:
	return float(cfg.get("radius", 0.5)) * size_scale


## The line through the middle of the body (for sword hits): upright for
## two-legged and floating creatures, nose to tail for the others.
func body_axis() -> Array:
	var h := model_size.y * size_scale
	var base := global_position + model.position
	if body in ["biped", "float"]:
		var lo := 0.25 if body == "biped" else float(cfg.get("hover", 0.4)) + 0.3
		return [base + Vector3.UP * lo * size_scale, base + Vector3.UP * h * 0.85]
	var fwd := -global_transform.basis.z
	var half := model_size.z * size_scale * 0.38
	var mid := base + Vector3.UP * h * 0.5
	return [mid + fwd * half, mid - fwd * half]


## Called by the player's sword.
func take_hit(amount: float, from_pos: Vector3) -> void:
	if state == State.DEAD:
		return
	health -= amount
	flash = 1.0
	flinch = 1.0
	var away := global_position - from_pos
	away.y = 0
	# Heavy monsters barely budge; light ones are knocked back.
	global_position += away.normalized() * 0.35 / maxf(float(cfg.get("mass", 1.0)), 0.5)
	# The noise of a fight sends shy animals nearby running.
	for c in get_tree().get_nodes_in_group("creatures") if is_inside_tree() else []:
		if c != self and c.temper == "flee" and c.global_position.distance_to(global_position) < FIGHT_HEARD:
			c.hear_gunshot(global_position, true, false)
	if health <= 0.0:
		_die()
		return
	if cfg.get("fights_back", false):
		temper = "threaten"
	if temper == "threaten":
		if state != State.ATTACK:
			state = State.CHASE
			timer = cfg.get("chase_time", 6.0)
		cooldown = 0.0
		vocal.emit("roar")
	else:
		state = State.FLEE


## A gunshot `from` somewhere near: shy animals bolt (and keep running for a
## while), monsters within earshot roar and come looking.
func hear_gunshot(from: Vector3, startle: bool, alert: bool) -> void:
	if state == State.DEAD or state == State.ATTACK:
		return
	if temper == "flee":
		if startle:
			scared = float(cfg.get("scare_time", 7.0))
			state = State.FLEE
			var away := global_position - from
			away.y = 0.0
			target = global_position + away.normalized() * 25.0
	elif alert and state in [State.IDLE, State.GRAZE, State.WALK, State.RETURN]:
		cooldown = 0.0
		_start_roar()


func _die() -> void:
	state = State.DEAD
	dead_time = 0.0
	speed = 0.0
	atk = {}
	atk_off.clear()
	atk_hips = Vector3.ZERO
	_show_telegraph(false)
	vocal.emit("roar")
	killed.emit(self)


## Topples over, sinks into the ground, then returns home after a while.
func _dead_update(delta: float) -> void:
	dead_time += delta
	var fall := clampf(dead_time / 0.7, 0.0, 1.0)
	model.rotation.z = lerpf(0.0, PI * 0.5 if body != "float" else 0.0, fall * fall)
	if body == "float":
		model.scale = Vector3.ONE * size_scale * maxf(0.01, 1.0 - dead_time * 0.6)
	if dead_time > 3.0:
		model.position.y = -(dead_time - 3.0) * 0.8
	if dead_time > 5.0:
		visible = false
		if unique:
			queue_free()
			return
	if dead_time > float(cfg.get("respawn_time", 90.0)):
		health = cfg.get("health", 60.0)
		temper = cfg.get("temper", "flee")
		model.rotation = Vector3.ZERO
		model.position = Vector3.ZERO
		model.scale = Vector3.ONE * size_scale
		global_position = home
		visible = true
		_choose_idle()


## The attack moves this creature knows. Each move: windup, strike and recover
## (seconds), reach (m), arc (degrees in front that the blow covers), damage
## (times cfg.damage), lunge (m travelled during the strike), aoe (m radius
## around the impact point instead of an arc), min/max range to choose it.
func moves() -> Array:
	if cfg.has("attacks"):
		return cfg.attacks
	return DEFAULT_MOVES.get(body, DEFAULT_MOVES["quad"])


const DEFAULT_MOVES := {
	"biped": [
		{"name": "overhead_smash", "windup": 0.7, "strike": 0.22, "recover": 0.6, "reach": 2.8, "arc": 70, "damage": 1.2, "telegraph": true},
		{"name": "hook", "windup": 0.5, "strike": 0.25, "recover": 0.45, "reach": 2.6, "arc": 120, "damage": 0.9},
	],
	"quad": [
		{"name": "bite", "windup": 0.35, "strike": 0.18, "recover": 0.35, "reach": 1.7, "arc": 70, "damage": 1.0},
	],
	"hex": [
		{"name": "horn_lunge", "windup": 0.6, "strike": 0.35, "recover": 0.55, "reach": 1.6, "arc": 60, "damage": 1.1, "lunge": 2.4, "max_range": 5.5},
		{"name": "bite", "windup": 0.3, "strike": 0.18, "recover": 0.4, "reach": 1.9, "arc": 70, "damage": 0.8, "max_range": 2.4},
	],
	"float": [
		{"name": "claw_swipe", "windup": 0.45, "strike": 0.22, "recover": 0.45, "reach": 2.2, "arc": 110, "damage": 1.0},
	],
}


func _move_max_range(m: Dictionary) -> float:
	return float(m.get("max_range", float(m.get("reach", 2.0)) + float(m.get("lunge", 0.0)))) * (0.75 + 0.25 * size_scale)


## Longest distance from which this creature starts any attack.
func engage_range() -> float:
	var r := 0.0
	for m in moves():
		r = maxf(r, _move_max_range(m))
	return r + hit_radius() * 0.5


func _choose_move(d: float) -> Dictionary:
	var options := []
	var total := 0.0
	for m: Dictionary in moves():
		if d > _move_max_range(m) + hit_radius() * 0.5 or d < float(m.get("min_range", 0.0)):
			continue
		options.append(m)
		total += float(m.get("weight", 1.0))
	if options.is_empty():
		return {}
	var pick := rng.randf() * total
	for m: Dictionary in options:
		pick -= float(m.get("weight", 1.0))
		if pick <= 0.0:
			return m
	return options[-1]


func _start_attack(m: Dictionary) -> void:
	state = State.ATTACK
	speed = 0.0
	atk = m
	atk_t = 0.0
	atk_done = false
	atk_dir = -global_transform.basis.z
	attack_cd = cfg.get("attack_rate", 1.6)
	if m.get("telegraph", false):
		_show_telegraph(true)
	if m.get("roar", false):
		vocal.emit("roar")


func _atk_total() -> float:
	return float(atk.windup) + float(atk.strike) + float(atk.recover)


## Wind-up (0..1), strike (0..1) and recovery weight (1..0) of the current attack.
func _atk_phase() -> Vector3:
	var w := float(atk.windup)
	var s := float(atk.strike)
	var r := float(atk.recover)
	var wind := clampf(atk_t / w, 0.0, 1.0)
	var strike := clampf((atk_t - w) / s, 0.0, 1.0)
	var rec := 1.0 - clampf((atk_t - w - s) / r, 0.0, 1.0)
	return Vector3(wind * wind * (3.0 - 2.0 * wind), strike, rec * rec * (3.0 - 2.0 * rec))


func _attack_update(delta: float) -> void:
	atk_t += delta
	var w := float(atk.windup)
	var s := float(atk.strike)
	# Track the target through most of the wind-up, then commit to the direction
	# so a well-timed dodge makes the blow miss.
	if threat and atk_t < w * float(atk.get("track", 0.7)):
		var to := threat.global_position - global_position
		to.y = 0
		if to.length() > 0.1:
			atk_dir = to.normalized()
	# Lunging moves cover ground during the strike.
	var lunge := float(atk.get("lunge", 0.0)) * size_scale
	if lunge > 0.0 and atk_t > w and atk_t < w + s:
		var step := atk_dir * lunge / s * delta
		var ahead := global_position + step * 4.0
		if height_at.call(ahead.x, ahead.z) >= float(cfg.get("min_height", -INF)) and not _blocked_by_threat(step):
			global_position += step
			phase = fposmod(phase + lunge / s * delta / float(cfg.get("run_stride", 1.0)), 1.0)
	if not atk_done and atk_t >= w + s * float(atk.get("impact", 0.5)):
		atk_done = true
		_show_telegraph(false)
		_resolve_impact()
	if telegraph and telegraph.visible:
		var m := telegraph.material_override as ShaderMaterial
		m.set_shader_parameter("fill", clampf(atk_t / (w + s * 0.5), 0.0, 1.0))
		telegraph.global_position = _impact_point() + Vector3.UP * 0.06
		telegraph.global_position.y = height_at.call(telegraph.global_position.x, telegraph.global_position.z) + 0.06
	if atk_t >= _atk_total():
		atk = {}
		atk_off.clear()
		atk_hips = Vector3.ZERO
		# Keep fighting while the player stays close; distance and leash still end it.
		state = State.CHASE
		timer = float(cfg.get("chase_time", 6.0)) * 0.6


## Stops a lunge from running through the player.
func _blocked_by_threat(step: Vector3) -> bool:
	if threat == null:
		return false
	var to := threat.global_position - (global_position + step)
	to.y = 0
	return to.length() < hit_radius() + 0.45


## Where the blow lands: in front of the creature at the move's reach.
func _impact_point() -> Vector3:
	var reach := float(atk.get("reach", 2.0)) * (0.75 + 0.25 * size_scale)
	var centre := reach * (0.6 if atk.has("aoe") else 0.5)
	return global_position + atk_dir * centre


## Deals damage only if the target is where the blow actually lands.
func _resolve_impact() -> void:
	var hit := false
	if threat and threat.get("dead") != true and threat.has_method("take_damage"):
		var to := threat.global_position - global_position
		to.y = 0
		var d := to.length()
		var reach := float(atk.get("reach", 2.0)) * (0.75 + 0.25 * size_scale) + 0.35
		var vertical := absf(threat.global_position.y - global_position.y) < 2.5 * size_scale
		if atk.has("aoe"):
			var p := _impact_point()
			var dd := Vector2(threat.global_position.x - p.x, threat.global_position.z - p.z).length()
			hit = vertical and dd < float(atk.aoe) * (0.75 + 0.25 * size_scale)
		else:
			var arc := cos(deg_to_rad(float(atk.get("arc", 80.0)) * 0.5))
			hit = vertical and d < reach and (d < hit_radius() + 0.3 or atk_dir.dot(to.normalized()) >= arc)
		if hit:
			threat.take_damage(float(cfg.get("damage", 10.0)) * float(atk.get("damage", 1.0)), global_position, false, cfg.get("element", ""))
	attack_landed.emit(hit, atk.get("name", ""))


func _show_telegraph(on: bool) -> void:
	if on and telegraph == null:
		telegraph = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2.ONE * 2.0
		telegraph.mesh = pm
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/spatial_fx_telegraph.gdshader")
		telegraph.material_override = m
		telegraph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		telegraph.top_level = true
		add_child(telegraph)
	if telegraph:
		telegraph.visible = on
		if on:
			var r: float = float(atk.get("aoe", float(atk.get("reach", 2.0)) * 0.5)) * (0.75 + 0.25 * size_scale)
			telegraph.scale = Vector3(r, 1, r)


func _threat_distance() -> float:
	if threat == null:
		return INF
	return Vector2(threat.global_position.x - global_position.x, threat.global_position.z - global_position.z).length()


# ---------- Brain ----------

func _think(delta: float) -> void:
	timer -= delta
	cooldown -= delta
	call_timer -= delta
	attack_cd -= delta
	flinch = maxf(0.0, flinch - delta * 4.0)
	if call_timer <= 0.0:
		call_timer = rng.randf_range(10.0, 26.0)
		if state != State.FLEE and state != State.ROAR:
			vocal.emit("call")
	var d := _threat_distance()
	if threat and threat.get("dead") == true and state in [State.CHASE, State.ATTACK, State.ROAR]:
		if state == State.ATTACK and atk_t < float(atk.get("windup", 0.0)):
			atk = {}
			atk_off.clear()
			atk_hips = Vector3.ZERO
			_show_telegraph(false)
		if state != State.ATTACK or atk.is_empty():
			state = State.RETURN
			target = home
	if state == State.ATTACK:
		_attack_update(delta)
		return
	if temper == "flee":
		scared = maxf(0.0, scared - delta)
		if (d < cfg.flee_radius or scared > 0.0) and state != State.FLEE:
			state = State.FLEE
		if state == State.FLEE and threat:
			var away := global_position - threat.global_position
			away.y = 0
			target = global_position + away.normalized() * 15.0
			if d > cfg.calm_radius and scared <= 0.0:
				_choose_idle()
			return
	else:
		var from_home := Vector2(global_position.x - home.x, global_position.z - home.z).length()
		match state:
			State.IDLE, State.GRAZE, State.WALK:
				if d < cfg.get("aggro_radius", 0.0) and cooldown <= 0.0 and not (threat and threat.get("dead") == true):
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
				if timer <= 0.0 or d > maxf(cfg.get("aggro_radius", 10.0), 8.0) * 2.0 or from_home > cfg.get("leash", 40.0):
					state = State.RETURN
					target = home
					cooldown = cfg.get("cooldown", 12.0)
				elif attack_cd <= 0.0 and d < engage_range():
					var m := _choose_move(d)
					if not m.is_empty():
						_start_attack(m)
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
	state = State.GRAZE if rng.randf() < float(cfg.get("graze_chance", 0.0)) else State.IDLE
	var it: Array = cfg.get("idle_time", [2.0, 6.0])
	timer = rng.randf_range(it[0], it[1])


func _move(delta: float) -> void:
	var want := 0.0
	if state == State.WALK or state == State.RETURN:
		want = cfg.walk_speed
	elif state == State.FLEE or state == State.CHASE:
		want = cfg.run_speed
		# Close the gap, but stop just outside arm's reach instead of sliding into the player.
		var stop := float(cfg.get("attack_range", 2.0)) * 0.8
		if state == State.CHASE and _threat_distance() < stop:
			want = 0.0
			speed = 0.0
	if state == State.ATTACK:
		want = 0.0
		speed = 0.0
	speed = move_toward(speed, want, delta * (6.0 if want > speed else 5.0))
	var fast := state == State.FLEE or state == State.CHASE
	run_mix = move_toward(run_mix, 1.0 if fast else 0.0, delta * 2.5)
	graze_mix = move_toward(graze_mix, 1.0 if state == State.GRAZE else 0.0, delta * 1.2)
	roar_mix = move_toward(roar_mix, 1.0 if state == State.ROAR else 0.0, delta * 4.0)
	var to := target - global_position
	to.y = 0
	var face_target := (state == State.ROAR or state == State.CHASE) and threat != null
	if face_target:
		to = threat.global_position - global_position
		to.y = 0
	if state == State.ATTACK:
		to = atk_dir
		face_target = true
	if (speed > 0.01 or face_target) and to.length() > 0.01:
		var yaw := atan2(-to.x, -to.z)
		var turn := 9.0 if state == State.ATTACK else (5.0 if fast or face_target else 2.0)
		rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * turn, 0, 1))
	if speed > 0.01:
		var step := -global_transform.basis.z * speed * delta
		var ahead := global_position + step * (1.5 / maxf(speed * delta, 0.001))
		# Never walk into lava (or anywhere too low for this species): head home instead.
		if _unsafe(global_position, step, ahead):
			step = Vector3.ZERO
			# A fleeing animal swerves along the edge instead of freezing there.
			if state == State.FLEE:
				for ang in [0.8, -0.8, 1.6, -1.6, 2.4, -2.4]:
					var s: Vector3 = (-global_transform.basis.z * speed * delta).rotated(Vector3.UP, ang)
					if not _unsafe(global_position, s, global_position + s * (1.5 / maxf(speed * delta, 0.001))):
						step = s
						rotation.y += ang * 0.25
						target = global_position + s.normalized() * 15.0
						break
			if step == Vector3.ZERO:
				target = home
		global_position += step
		var stride: float = lerpf(cfg.walk_stride, cfg.run_stride, run_mix)
		phase = fposmod(phase + speed * delta / stride, 1.0)
	var y: float = height_at.call(global_position.x, global_position.z)
	if body == "float":
		y += float(cfg.get("hover", 0.4)) + 0.15 * sin(t * 1.3)
	global_position.y = y


## Lava, or too low for this species, at the next step or 1.5 m ahead.
func _unsafe(from: Vector3, step: Vector3, ahead: Vector3) -> bool:
	var dest := from + step
	return height_at.call(ahead.x, ahead.z) < float(cfg.get("min_height", -INF)) \
			or (avoid_at.is_valid() and (avoid_at.call(ahead.x, ahead.z) or avoid_at.call(dest.x, dest.z)))


# ---------- Procedural animation ----------

func _rot(name: String, euler: Vector3) -> void:
	if bone.has(name):
		skeleton.set_bone_pose_rotation(bone[name], Quaternion.from_euler(euler + atk_off.get(name, Vector3.ZERO)))


func _pose() -> void:
	atk_off.clear()
	atk_hips = Vector3.ZERO
	if state == State.ATTACK and not atk.is_empty():
		_attack_pose(atk.get("name", ""), _atk_phase())
	if flinch > 0.0:
		var f := flinch * flinch
		atk_off["Spine"] = atk_off.get("Spine", Vector3.ZERO) + Vector3(0.25 * f, 0, 0)
		atk_off["Head"] = atk_off.get("Head", Vector3.ZERO) + Vector3(0.3 * f, 0, 0)
	var moving := clampf(speed / float(cfg.walk_speed), 0.0, 1.0)
	match body:
		"biped":
			_pose_biped(moving)
		"float":
			_pose_float(moving)
		_:
			_pose_legs(moving)
	var bob: float = cfg.bob * moving * (1.0 + run_mix) * absf(sin(phase * TAU * 2.0))
	skeleton.set_bone_pose_position(bone["Hips"], hips_rest + Vector3(0, bob, 0) + atk_hips)


func _add(name: String, e: Vector3) -> void:
	atk_off[name] = atk_off.get(name, Vector3.ZERO) + e


## Extra rotations for an attack. ph.x = wind-up (0..1), ph.y = strike (0..1),
## ph.z = recovery weight (1 while attacking, easing to 0 at the end).
## Axes (all models face -Z): +X tilts a hanging limb forward, a level body or
## head upward; Z with the side's sign lifts an arm outwards.
func _attack_pose(move: String, ph: Vector3) -> void:
	var w := ph.x
	var s := ph.y
	var k := ph.z
	var snap := 1.0 - pow(1.0 - s, 3.0)   # fast strike
	match move:
		"overhead_smash":
			# Both fists rise high over the head with the chest arched back,
			# then crash down in front while the body folds forward.
			var arm := lerpf(3.0 * w, 0.75, snap) * k
			for sd in ["_L", "_R"]:
				var sg := 1.0 if sd == "_L" else -1.0
				_add("A1" + sd, Vector3(arm, 0, sg * (0.25 * w - 0.35 * snap) * k))
				_add("A2" + sd, Vector3(1.0 * w * (1.0 - snap) * k, 0, 0))
			_add("Spine", Vector3((0.4 * w - 0.75 * snap) * k, 0, 0))
			_add("Chest", Vector3((0.2 * w - 0.3 * snap) * k, 0, 0))
			_add("Head", Vector3((0.25 * w - 0.2 * snap) * k, 0, 0))
			_add("L1_L", Vector3(0.45 * snap * k, 0, 0))
			_add("L2_L", Vector3(-0.6 * snap * k, 0, 0))
			_add("L1_R", Vector3(-0.15 * snap * k, 0, 0))
			atk_hips = Vector3(0, (-0.06 * w - 0.22 * snap) * k, -0.15 * snap * k) * size_scale
		"ground_pound":
			# Golem: both arms raised to the side, then hammered into the ground.
			var lift := (1.0 - snap)
			for sd in ["_L", "_R"]:
				var sg := 1.0 if sd == "_L" else -1.0
				_add("A1" + sd, Vector3((1.9 * w * lift + 1.2 * snap) * k, 0, sg * 0.9 * w * lift * k))
				_add("A2" + sd, Vector3(0.9 * w * lift * k, 0, 0))
			_add("Spine", Vector3((0.25 * w * lift - 0.95 * snap) * k, 0, 0))
			_add("Chest", Vector3(-0.35 * snap * k, 0, 0))
			for sd in ["_L", "_R"]:
				_add("L1" + sd, Vector3(0.7 * snap * k, 0, 0))
				_add("L2" + sd, Vector3(-1.1 * snap * k, 0, 0))
				_add("L3" + sd, Vector3(0.4 * snap * k, 0, 0))
			atk_hips = Vector3(0, (0.08 * w * lift - 0.42 * snap) * k, -0.1 * snap * k) * size_scale
		"hook":
			# One arm (the -X side) drawn back and out, then swung across in front
			# while the hips and shoulders twist through the blow.
			var swing := lerpf(-1.0 * w, 1.0, snap) * k
			_add("A1_R", Vector3((-0.7 * w + 1.5 * snap) * k, 0, (-1.2 * w * (1.0 - snap) + 0.35 * snap) * k))
			_add("A2_R", Vector3(0.5 * k * (1.0 - snap * 0.6), 0, 0))
			_add("A1_L", Vector3(0.4 * w * k, 0, 0.3 * k))
			_add("Hips", Vector3(0, -0.35 * swing, 0))
			_add("Spine", Vector3(-0.15 * snap * k, -0.45 * swing, 0))
			_add("Chest", Vector3(0, -0.3 * swing, 0))
			_add("L1_R", Vector3(0.35 * snap * k, 0, 0))
			_add("L2_R", Vector3(-0.4 * snap * k, 0, 0))
			atk_hips = Vector3(0, -0.08 * snap * k, -0.08 * snap * k) * size_scale
		"punch":
			# Straight jab: pull the fist back, then drive it forward with the shoulder.
			_add("A1_L", Vector3((-0.6 * w + 2.0 * snap) * k, 0, 0.1 * k))
			_add("A2_L", Vector3((1.4 * w * (1.0 - snap)) * k, 0, 0))
			_add("A1_R", Vector3(0.5 * w * k, 0, -0.2 * k))
			_add("A2_R", Vector3(1.0 * k, 0, 0))
			_add("Spine", Vector3(-0.35 * snap * k, (0.3 * w - 0.45 * snap) * k, 0))
			_add("L1_L", Vector3(0.4 * snap * k, 0, 0))
			atk_hips = Vector3(0, -0.06 * snap * k, -0.15 * snap * k) * size_scale
		"bite", "lunge_bite":
			# Crouch with the head drawn back, then snap forward and up.
			_add("Neck", Vector3((0.35 * w - 0.75 * snap) * k, 0, 0))
			_add("Head", Vector3((0.3 * w - 0.4 * snap + 0.5 * snap * snap) * k, 0, 0))
			_add("Spine", Vector3((0.1 * w - 0.15 * snap) * k, 0, 0))
			_add("Hips", Vector3(-0.12 * w * (1.0 - snap) * k, 0, 0))
			for leg in ["F1_L", "F1_R"]:
				_add(leg, Vector3((-0.25 * w + 0.45 * snap) * k, 0, 0))
			for leg in ["H1_L", "H1_R"]:
				_add(leg, Vector3((0.3 * w - 0.35 * snap) * k, 0, 0))
			atk_hips = Vector3(0, -0.06 * w * (1.0 - snap) * k, (0.06 * w - 0.12 * snap) * k) * size_scale
		"pounce":
			# Wolf: sinks low on the hind legs, then springs with the forelegs reaching.
			var air := sin(s * PI)
			_add("Hips", Vector3((-0.25 * w + 0.35 * air) * k, 0, 0))
			_add("Neck", Vector3((-0.3 * w + 0.2 * air - 0.5 * snap * snap) * k, 0, 0))
			_add("Head", Vector3((0.2 * w + 0.3 * snap) * k, 0, 0))
			for leg in ["F1_L", "F1_R"]:
				_add(leg, Vector3((-0.2 * w + 1.1 * air) * k, 0, 0))
				_add(leg.replace("1", "3"), Vector3(-0.6 * air * k, 0, 0))
			for leg in ["H1_L", "H1_R"]:
				_add(leg, Vector3((0.55 * w - 0.9 * air) * k, 0, 0))
				_add(leg.replace("1", "3"), Vector3(0.8 * w * (1.0 - air) * k, 0, 0))
			atk_hips = Vector3(0, (-0.14 * w * (1.0 - s) + 0.35 * air) * k, 0) * size_scale
		"tusk_charge", "gore":
			# Boar: head down, a burst forward, then a hard upward toss of the tusks.
			var toss := smoothstep(0.6, 1.0, s)
			_add("Neck", Vector3((-0.55 * w + 0.95 * toss) * k, 0, 0))
			_add("Head", Vector3((-0.35 * w + 0.6 * toss) * k, 0, 0))
			_add("Hips", Vector3(0.12 * w * k, 0, 0))
			for leg in ["F1_L", "F1_R"]:
				_add(leg, Vector3(-0.3 * w * k, 0, 0))
			for leg in ["H1_L", "H1_R"]:
				_add(leg, Vector3(0.35 * w * k, 0, 0))
			atk_hips = Vector3(0, -0.07 * w * k, 0) * size_scale
		"horn_lunge":
			# Beetle: front rears up with the horn raised, legs gather under the
			# body; then it drives forward low and hooks the horn up through the target.
			var gore := smoothstep(0.55, 1.0, s)
			_add("Hips", Vector3((0.32 * w * (1.0 - snap) - 0.18 * snap * (1.0 - gore)) * k, 0, 0))
			_add("Chest", Vector3((0.2 * w - 0.25 * snap + 0.3 * gore) * k, 0, 0))
			_add("Neck", Vector3((0.4 * w - 0.55 * snap + 0.9 * gore) * k, 0, 0))
			_add("Head", Vector3((0.3 * w - 0.3 * snap + 0.6 * gore) * k, 0, 0))
			for leg in ["F", "M", "H"]:
				for sd in ["_L", "_R"]:
					var sg := 1.0 if sd == "_L" else -1.0
					var lift := 0.35 if leg == "F" else (0.15 if leg == "M" else -0.1)
					_add(leg + "2" + sd, Vector3(0, 0, sg * (lift * w * (1.0 - snap) - 0.2 * snap) * k))
			atk_hips = Vector3(0, (0.1 * w * (1.0 - snap) - 0.08 * snap) * k, 0) * size_scale
		"tail_whip":
			# Salamander: the body coils, then the tail lashes round in an arc.
			var lash := lerpf(-0.9 * w, 1.4, snap) * k
			_add("Hips", Vector3(0, lash, 0))
			_add("Chest", Vector3(0, -lash * 0.6, 0))
			_add("Tail", Vector3(0, lash * 1.6, 0))
			_add("Head", Vector3(0.25 * w * k, 0, 0))
		"claw_swipe", "wail_lunge":
			# Frost spirit: both arms flung up and back, then raked down across the front.
			var rake := lerpf(-1.0, 1.0, snap)
			for sd in ["_L", "_R"]:
				var sg := 1.0 if sd == "_L" else -1.0
				_add("A1" + sd, Vector3((2.4 * w * (1.0 - snap) + 0.9 * snap) * k, 0, sg * (0.9 * w * (1.0 - snap) - 0.6 * snap) * k))
				_add("A2" + sd, Vector3(0.5 * k, 0, 0))
				_add("A3" + sd, Vector3((-0.6 * w + 0.4 * snap) * k, 0, 0))
			_add("Spine", Vector3((0.35 * w - 0.6 * snap) * k, 0.25 * rake * k, 0))
			_add("Head", Vector3((0.4 * w - 0.3 * snap) * k, 0, 0))
			_add("Tail", Vector3(-0.5 * snap * k, 0, 0))
			atk_hips = Vector3(0, 0.25 * w * (1.0 - snap) * k, -0.2 * snap * k) * size_scale
		"slam_quake":
			_attack_pose("ground_pound", ph)
		"spit":
			_add("Neck", Vector3((0.5 * w - 0.3 * snap) * k, 0, 0))
			_add("Head", Vector3((0.4 * w - 0.5 * snap) * k, 0, 0))
			_add("Hips", Vector3(0.15 * w * k, 0, 0))
		"burrow", "emerge":
			pass


## Four or six legs, each leg four bones. Sideways-splayed legs (salamander,
## beetle) swing around the vertical axis instead and the body wiggles.
func _pose_legs(moving: float) -> void:
	var lunging: bool = state == State.ATTACK and atk.get("lunge", 0.0) > 0.0 and _atk_phase().y > 0.0 and _atk_phase().y < 1.0
	if lunging:
		moving = 1.0
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
	_rot("Spine", Vector3.ZERO)
	_rot("Tail", Vector3(0.3 * run_mix, 0.25 * sin(t * 2.3) + wiggle * 2.0, 0))


## Two legs, two arms. Roar: chest back, both arms thrown up and out.
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
		# Arms swing opposite to the legs, hang slightly forward and bent at
		# rest, and are flung up and outwards when roaring.
		var arm_x := -swing * s * 0.8 * (1.0 - roar_mix) + 0.15 + 0.9 * roar_mix
		_rot("A1" + side, Vector3(arm_x, 0, sgn * (0.12 + 1.0 * roar_mix)))
		_rot("A2" + side, Vector3(0.3 + 0.25 * moving + 0.6 * roar_mix, 0, 0))
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
		_rot("A1" + side, Vector3(-0.3 * moving + 0.15 * wave + 1.2 * roar_mix, 0, sgn * (0.2 + 0.1 * wave + 0.8 * roar_mix)))
		_rot("A2" + side, Vector3(0.3 + 0.2 * wave * (1.0 - roar_mix), 0, 0))
		_rot("A3" + side, Vector3(-0.2 * wave, 0, 0))
	_rot("Spine", Vector3(0.25 * moving + 0.2 * roar_mix, 0.08 * sin(t * 0.9), 0))
	_rot("Head", Vector3(0.1 * sin(t * 0.7) + 0.3 * roar_mix, 0.3 * sin(t * 0.43), 0))
	_rot("Tail", Vector3(0.35 * moving + 0.1 * sin(t * 1.9), 0.4 * sin(t * 1.2), 0.15 * sin(t * 2.3)))
