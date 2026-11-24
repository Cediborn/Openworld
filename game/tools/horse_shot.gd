extends Node3D
# Test scene: the three horses side by side, a rider on the middle one, and a
# villager with a mission marker. Args: <out.png> [mode: idle|walk|gallop] [view: side|front|close]
var frames := 0
var mode := "idle"
var horses: Array = []
var rider: ExplorerBody
var ride: Dictionary
func _ready():
	var args := OS.get_cmdline_user_args()
	mode = args[1] if args.size() > 1 else "idle"
	var view: String = args[2] if args.size() > 2 else "side"
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.55, 0.6, 0.68)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	add_child(env)
	var sun := DirectionalLight3D.new(); sun.light_energy = 1.5; sun.shadow_enabled = true; add_child(sun)
	var ground := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(40, 40); ground.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color(0.3, 0.42, 0.2); ground.material_override = gm; add_child(ground)
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/horses.json"))
	ride = cfg.ride
	var i := 0
	for e in cfg.horses:
		var h := Horse.new()
		add_child(h)
		h.setup_horse(e, cfg.gait, cfg.ride, 7)
		h.position = Vector3((i - 1) * 3.3, 0, 0)
		h.rotation.y = PI * 0.5   # facing -X... (towards the left of the camera)
		h.set_meta("start", h.position)
		horses.append(h)
		i += 1
	rider = ExplorerBody.new()
	add_child(rider)
	var v := Villager.new()
	add_child(v)
	v.setup({"id": "t", "name": "T", "outfit": {}, "home": [3.0, -4.5]}, 1)
	v.position = Vector3(3.0, 0, -4.5)
	v.set_marker("!")
	v.set_process(false)
	var cam := Camera3D.new(); cam.fov = 40; add_child(cam); cam.current = true
	if view == "side":
		cam.position = Vector3(0.0, 2.0, -12.0); cam.look_at(Vector3(0.0, 1.2, 0.0))
	elif view == "close":
		cam.position = Vector3(0.3, 2.0, -4.6); cam.look_at(Vector3(0, 1.35, 0))
	else:
		cam.position = Vector3(-6.0, 2.4, -1.5); cam.look_at(Vector3(0, 1.3, 0))
	sun.look_at_from_position(cam.position + Vector3(2.5, 6.0, 1.0), Vector3(0, 0.8, 0))
func _process(_d):
	frames += 1
	var spd: float = {"idle": 0.0, "walk": 2.4, "gallop": 13.0}[mode]
	for h: Horse in horses:
		h.position = h.get_meta("start")
		h.rotation.y = PI * 0.5
		if h == horses[1]:
			h.rider = rider
			h.speed = spd
	var mid: Horse = horses[1]
	rider.position = mid.position + Vector3(0, float(ride.saddle_height) - float(ride.rider_hips) + mid.saddle_bob() * 1.6, 0)
	rider.rotation.y = mid.rotation.y + PI
	rider.play("Ride", 0.0)
	if frames == 41:
		get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0]); get_tree().quit()
