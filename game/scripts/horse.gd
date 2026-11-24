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
	_wander(delta)
	_move(delta)
	_pose()


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
					state = State.WALK
					timer = 0.0
				else:
					_choose_idle()
