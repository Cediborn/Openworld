extends Node3D
# Test scene: explorer from the front and back under a sun, playing an animation.
var frames := 0
var body: ExplorerBody
func _ready():
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.45,0.47,0.5)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.6,0.62,0.66)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-35, 30, 0); sun.light_energy = 1.4; sun.shadow_enabled = true; add_child(sun)
	var anim_name: String = OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else "Idle"
	for i in 3:
		var b := ExplorerBody.new(); add_child(b)
		b.position.x = (i - 1) * 1.1
		b.rotation.y = [0.0, PI, PI * 0.5][i]
		b.call_deferred("play", anim_name, 0.0)
	var cam := Camera3D.new(); cam.position = Vector3(0, 1.0, 3.6); cam.fov = 45; add_child(cam); cam.current = true
func _process(_d):
	frames += 1
	if frames == 30:
		get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0]); get_tree().quit()
