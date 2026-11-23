extends Node3D
# Test scene: all villagers in a row, plus the explorer with his sword drawn.
# Args: <out.png>
var frames := 0
var hero: ExplorerBody
func _ready():
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.45, 0.47, 0.52)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 25, 0); sun.light_energy = 1.3; add_child(sun)
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/npcs.json"))
	var x := -3.2
	for v: Dictionary in cfg.villagers:
		var vil := Villager.new()
		add_child(vil)
		v = v.duplicate(true); v.wander = 0.0
		vil.setup(v, 1)
		vil.position = Vector3(x, 0, 0)
		x += 1.3
	hero = ExplorerBody.new()
	add_child(hero)
	hero.position = Vector3(x + 0.3, 0, 0)
	var cam := Camera3D.new(); add_child(cam); cam.current = true
	cam.position = Vector3(0.2, 1.3, 5.8); cam.look_at(Vector3(0.2, 0.9, 0)); cam.fov = 55
func _process(_d):
	frames += 1
	if frames == 5:
		hero.set_sword_drawn(true)
		hero.play_once("Sword_Attack", 0.0, 1.0)
	if frames == 30:
		get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0]); get_tree().quit()
