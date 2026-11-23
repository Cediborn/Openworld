extends Node3D
# Test scene: one creature frozen at several moments of an attack, side view.
# Args: <out.png> <species> <move> <t1,t2,...> [side|front]
var frames := 0
var cs: Array = []
func _ready():
	var args := OS.get_cmdline_user_args()
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.55, 0.6, 0.68)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, -60, 0); sun.light_energy = 1.5; sun.shadow_enabled = true; add_child(sun)
	var ground := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(80, 80); ground.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color(0.3, 0.42, 0.2); ground.material_override = gm; add_child(ground)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/creatures.json"))
	var sp: String = args[1]
	var times: PackedStringArray = args[3].split(",")
	var cfg: Dictionary = data.species[sp].duplicate(true)
	cfg.scale = [1.0, 1.0]
	var move := {}
	var c0 := Creature.new()
	for m in (cfg.attacks if cfg.has("attacks") else c0.DEFAULT_MOVES[cfg.get("body", "quad")]):
		if m.name == args[2]: move = m
	c0.free()
	var gap: float = maxf(2.2, float(cfg.get("radius", 0.5)) * 4.0)
	for i in times.size():
		var c := Creature.new()
		add_child(c)
		c.setup(cfg, 3)
		c.position = Vector3(0, 0, (i - (times.size() - 1) * 0.5) * gap * 1.0)
		c.set_meta("start", c.position)
		c.set_meta("t", float(times[i]))
		c.set_meta("move", move)
		cs.append(c)
	var cam := Camera3D.new(); cam.fov = 40; add_child(cam); cam.current = true
	var span := gap * times.size()
	var view: String = args[4] if args.size() > 4 else "side"
	if view == "side":
		cam.position = Vector3(-span * 0.55 - 2.0, 1.5, 0); cam.look_at(Vector3(0, 0.9, 0))
	else:
		cam.position = Vector3(-span * 0.8, span * 0.35 + 1.0, -span * 0.9); cam.look_at(Vector3(0, 0.8, 0))
	sun.look_at_from_position(cam.position + Vector3(1.5, 6.0, -2.0), Vector3(0, 0.6, 0))
func _process(_d):
	frames += 1
	for c in cs:
		c.position = c.get_meta("start")
		c.rotation.y = 0.0
		c.state = Creature.State.ATTACK
		c.atk = c.get_meta("move")
		c.atk_t = c.get_meta("t")
		c.atk_dir = Vector3(0, 0, -1)
		c.speed = 0.0
		c._pose()
	if frames == 25:
		get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0]); get_tree().quit()
