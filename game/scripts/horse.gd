class_name Horse
extends Creature
## A riding horse. Uses the creature animator for its legs (same skeleton as
## the other animals) but never flees or fights: when nobody is riding it, it
## stands, grazes and ambles a few metres around where it was left. While
## ridden, the rider (Player) moves it and sets `speed`; the horse just keeps
## its gait in step. Tuning: data/horses.json ("gait" and "ride").

var id := ""
var horse_name := ""
var ride_cfg: Dictionary = {}
## The player riding this horse, or null.
var rider: Node3D
## The "Ride the horse" / "Get off" prompt that follows the horse.
var use_point: Interactable
## Summoned by a whistle: waypoints (x, z) to follow, and who called.
var route := PackedVector2Array()
var route_i := 0
var caller: Node3D
## Called with this horse when it reaches whoever whistled.
var on_arrived: Callable = Callable()
## Seconds without getting closer to the next waypoint (stuck guard).
var _stuck := 0.0
var _best := INF


## Builds the horse. entry: one item of horses.json "horses"; gait/ride: shared tuning.
func setup_horse(entry: Dictionary, gait: Dictionary, ride: Dictionary, seed_value: int) -> void:
	var c := gait.duplicate()
	c.model = entry.model
	c.temper = "tame"
	c.health = 9999.0
	ride_cfg = ride
	id = entry.id
	horse_name = entry.get("name", "horse")
	setup(c, seed_value)
	# Not a creature the sword can hit or monsters can be confused with.
	remove_from_group("creatures")
	add_to_group("horses")
	use_point = Interactable.new("Ride the " + horse_name, float(ride.get("mount_distance", 2.4)))
	add_child(use_point)
	use_point.beacon.position.y = 2.6


## Gallop blend: 0 at a walk, 1 at full gallop (drives the leg phases and bounce).
func gait_mix() -> float:
	var walk: float = ride_cfg.get("walk_speed", 2.4)
	var trot: float = ride_cfg.get("trot_speed", 6.5)
	return clampf((speed - walk) / maxf(trot - walk, 0.1), 0.0, 1.0)


## Vertical bounce of the saddle this frame (the rider moves with it).
func saddle_bob() -> float:
	var moving := clampf(speed / float(cfg.walk_speed), 0.0, 1.0)
	return float(cfg.bob) * moving * (1.0 + run_mix) * absf(sin(phase * TAU * 2.0))


## Called when the rider gets on (true) or off (false).
func set_ridden(by: Node3D) -> void:
	rider = by
	state = State.IDLE
	graze_mix = 0.0
	if by == null:
		speed = 0.0
		home = global_position
		_choose_idle()
		use_point.label = "Ride the " + horse_name
	else:
		use_point.label = "Get off the " + horse_name


func _process(delta: float) -> void:
	if skeleton == null:
		return
	t += delta
	if rider != null:
		# The rider moves us; keep the legs in step with the real speed.
		run_mix = move_toward(run_mix, gait_mix(), delta * 3.0)
		graze_mix = 0.0
		var stride: float = lerpf(cfg.walk_stride, cfg.run_stride, run_mix)
		phase = fposmod(phase + speed * delta / stride, 1.0)
		_pose()
		return
	if not route.is_empty():
		_follow_route(delta)
		_pose()
		return
	_wander(delta)
	_move(delta)
	_pose()


## Answers a whistle: trot, then gallop along `waypoints` towards `who`.
func summon(waypoints: PackedVector2Array, who: Node3D) -> void:
	route = waypoints
	route_i = 1 if waypoints.size() > 1 else 0
	caller = who
	state = State.WALK
	graze_mix = 0.0
	_stuck = 0.0
	_best = INF


## True while answering a whistle.
func is_coming() -> bool:
	return not route.is_empty()


func _follow_route(delta: float) -> void:
	var stop_at := 3.2
	var to_caller := Vector2.INF
	if is_instance_valid(caller):
		to_caller = Vector2(caller.global_position.x - global_position.x, caller.global_position.z - global_position.z)
		if to_caller.length() < stop_at:
			_arrive()
			return
	var wp := route[route_i]
	var here := Vector2(global_position.x, global_position.z)
	var to := wp - here
	var d := to.length()
	if d < 1.5:
		route_i += 1
		_best = INF
		if route_i >= route.size():
			_arrive()
			return
		wp = route[route_i]
		to = wp - here
		d = to.length()
	# Gallop on the open road, ease to a trot for the last stretch and the turns.
	var left := d
	for k in range(route_i, route.size() - 1):
		left += route[k].distance_to(route[k + 1])
	var want := lerpf(float(ride_cfg.get("trot_speed", 6.5)), float(ride_cfg.get("gallop_speed", 13.0)) * 0.8, clampf((left - 12.0) / 30.0, 0.0, 1.0))
	speed = move_toward(speed, want, delta * 6.0)
	var yaw := atan2(-to.x, -to.y)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * 6.0, 0.0, 1.0))
	var step := Vector2(-sin(rotation.y), -cos(rotation.y)) * minf(speed * delta, d)
	var next := here + step
	if avoid_at.is_valid() and avoid_at.call(next.x, next.y):
		next = here + to.normalized() * minf(speed * delta, d)   # turning wide would step in: go straight
	global_position = Vector3(next.x, height_at.call(next.x, next.y), next.y)
	run_mix = move_toward(run_mix, clampf((speed - 2.0) / 7.0, 0.0, 1.0), delta * 2.0)
	var stride: float = lerpf(cfg.walk_stride, cfg.run_stride, run_mix)
	phase = fposmod(phase + speed * delta / stride, 1.0)
	# Stuck guard: if a waypoint can't be reached for a few seconds, skip it.
	if d < _best - 0.2:
		_best = d
		_stuck = 0.0
	else:
		_stuck += delta
		if _stuck > 4.0:
			route_i += 1
			_stuck = 0.0
			_best = INF
			if route_i >= route.size():
				_arrive()


func _arrive() -> void:
	route = PackedVector2Array()
	speed = 0.0
	run_mix = 0.0
	if is_instance_valid(caller):
		var to := caller.global_position - global_position
		if Vector2(to.x, to.z).length() > 0.1:
			rotation.y = atan2(-to.x, -to.z) + PI * 0.5   # stand side-on, ready to mount
	home = global_position
	_choose_idle()
	if on_arrived.is_valid():
		on_arrived.call(self)


## Stand, graze or amble to a nearby spot, then stand again.
func _wander(delta: float) -> void:
	timer -= delta
	match state:
		State.WALK:
			var to := target - global_position
			to.y = 0.0
			if to.length() < 0.6 or timer < -20.0:
				_choose_idle()
		_:
			if timer <= 0.0:
				if rng.randf() < 0.45:
					var r: float = cfg.get("wander_radius", 5.0)
					var a := rng.randf() * TAU
					target = home + Vector3(cos(a), 0, sin(a)) * rng.randf_range(1.5, r)
					if avoid_at.is_valid() and avoid_at.call(target.x, target.z):
						_choose_idle()   # never amble towards lava
						return
					state = State.WALK
					timer = 0.0
				else:
					_choose_idle()
