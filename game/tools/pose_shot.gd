extends Node3D
# Test scene: the explorer frozen at several moments of one animation, sword drawn.
# Args: <out.png> <anim> <t1,t2,...> [side|front|back]
var frames := 0
func _ready():
	var args := OS.get_cmdline_user_args()
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.45,0.5,0.56)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.6,0.62,0.66)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 35, 0); sun.light_energy = 1.4; sun.shadow_enabled = true; add_child(sun)
	var ground := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(30, 30); ground.mesh = pm; add_child(ground)
	var times: PackedStringArray = args[2].split(",")
	var view: String = args[3] if args.size() > 3 else "front"
	var n := times.size()
	for i in n:
		var b := ExplorerBody.new(); add_child(b)
		b.position.x = (i - (n - 1) * 0.5) * -1.7
		b.rotation.y = {"front": 0.0, "side": -PI * 0.5, "back": PI, "q": -PI * 0.25}[view]
		b.set_meta("t", float(times[i]))
		b.set_meta("anim", args[1])
	var cam := Camera3D.new(); cam.fov = 40; add_child(cam); cam.current = true
	cam.position = Vector3(0, 1.3, 2.2 + n * 1.25); cam.look_at(Vector3(0, 1.0, 0))
func _process(_d):
	frames += 1
	for b in get_children():
		if b is ExplorerBody and b.anim:
			b.set_sword_drawn(true)
			if b.anim.current_animation != b.get_meta("anim"):
				b.anim.play(b.get_meta("anim"), 0.0)
			b.anim.seek(b.get_meta("t"), true)
			b.anim.pause()
	if frames == 20:
		get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0]); get_tree().quit()
