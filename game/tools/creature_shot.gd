extends Node3D
# Test scene: the three green-valley animals side by side under a sun.
# Args: <out.png> <mode: idle|walk|run|graze|roar> [view: side|front|close] [species,list] [spacing]
var frames := 0
var mode := "idle"
func _ready():
	var args := OS.get_cmdline_user_args()
	mode = args[1] if args.size() > 1 else "idle"
	var view: String = args[2] if args.size() > 2 else "side"
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.55, 0.6, 0.68)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-35, -65, 0); sun.light_energy = 1.5; sun.shadow_enabled = true; add_child(sun)
	var ground := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(40, 40); ground.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color(0.3, 0.42, 0.2); ground.material_override = gm; add_child(ground)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/creatures.json"))
	var list: PackedStringArray = (args[3] if args.size() > 3 else "deer,boar,wolf").split(",")
	var gap: float = float(args[4]) if args.size() > 4 else 1.8
	var zs := {}
	for i in list.size():
		zs[list[i]] = (float(list.size() - 1) * 0.5 - i) * gap
	for sp in list:
		var c := Creature.new()
		var cfg: Dictionary = data.species[sp].duplicate()
		cfg.scale = [1.0, 1.0]
		cfg.idle_time = [999.0, 999.0]
		cfg.graze_chance = 1.0 if mode == "graze" else 0.0
		cfg.aggro_radius = 0.0
		cfg.temper = "flee"
		cfg.flee_radius = -1.0
		add_child(c)
		c.setup(cfg, 3)
		c.position = Vector3(0, 0, zs[sp])
		c.set_meta("start", c.position)
		if mode in ["walk", "run"]:
			c.state = Creature.State.WALK if mode == "walk" else Creature.State.FLEE
			c.speed = cfg.walk_speed if mode == "walk" else cfg.run_speed
			c.run_mix = 1.0 if mode == "run" else 0.0
			c.target = c.position + Vector3(0, 0, -1000)
	var cam := Camera3D.new(); cam.fov = 40; add_child(cam); cam.current = true
	var span: float = gap * list.size()
	if view == "side":
		cam.position = Vector3(-span * 1.05 - 0.5, span * 0.18 + 0.6, -0.3); cam.look_at(Vector3(0, span * 0.14 + 0.35, 0.0))
	elif view == "close":
		cam.position = Vector3(-2.2, 1.0, -1.7); cam.look_at(Vector3(0, 0.75, -1.7))
	else:
		cam.position = Vector3(-3.0, 1.6, -5.0); cam.look_at(Vector3(0, 0.75, 0))
	sun.look_at_from_position(cam.position + Vector3(1.5, 5.0, -2.0), Vector3(0, 0.6, 0))
func _process(_d):
	frames += 1
	for c in get_children():
		if c is Creature:
			c.position = c.get_meta("start")
			c.rotation.y = 0.0
			if mode == "run":
				c.state = Creature.State.FLEE
			if mode == "roar":
				c.state = Creature.State.ROAR
				c.timer = 99.0
	if frames == 37:
		get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0]); get_tree().quit()
