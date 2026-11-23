extends Node3D
# Test scene: the real Player swinging at an ice troll that is winding up an
# overhead smash, with a beetle mid-lunge and a golem pounding the ground behind.
# Saves the frame when the explorer's blade is live. Args: <out.png>
var player: Player
var troll: Creature
var frames := 0
var pressed := false
var saved := false
func _ready():
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.6, 0.62, 0.66)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 150, 0); sun.light_energy = 1.4; sun.shadow_enabled = true; add_child(sun)
	var floor_body := StaticBody3D.new(); var col := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(80, 1, 80); col.shape = box; col.position.y = -0.5
	floor_body.add_child(col); add_child(floor_body)
	var g := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(80, 80); g.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color(0.3, 0.42, 0.2); g.material_override = gm; add_child(g)
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/game_config.json"))
	player = Player.new(); player.setup(cfg); add_child(player); player.position = Vector3(0, 0.05, 0)
	player.yaw = PI
	var cr: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/creatures.json"))
	troll = _creature(cr.species.ice_troll, Vector3(0.3, 0, 2.3), 0.0)
	var beetle := _creature(cr.species.mushroom_beetle, Vector3(-4.0, 0, 5.0), PI * 0.8)
	beetle.state = Creature.State.ATTACK; beetle.atk = cr.species.mushroom_beetle.attacks[0]; beetle.atk_t = 0.6
	var golem := _creature(cr.species.lava_golem, Vector3(4.5, 0, 6.5), PI * 1.15)
	golem.state = Creature.State.ATTACK; golem.atk = cr.species.lava_golem.attacks[1]; golem.atk_t = 0.95
	for c in [beetle, golem]:
		c.set_meta("t", c.atk_t)
	var cam := Camera3D.new(); add_child(cam); cam.current = true; cam.fov = 50
	cam.position = Vector3(5.2, 2.0, 0.4); cam.look_at(Vector3(0.0, 1.2, 1.6))
func _creature(c: Dictionary, pos: Vector3, yaw: float) -> Creature:
	var cc := c.duplicate(); cc.erase("min_height"); cc.aggro_radius = 0.0; cc.scale = [1.0, 1.0]
	var cr := Creature.new(); add_child(cr); cr.setup(cc, 5); cr.position = pos; cr.rotation.y = yaw; cr.set_meta("p", pos); cr.set_meta("y", yaw)
	cr.process_mode = Node.PROCESS_MODE_DISABLED   # posed by hand each frame (slow software rendering skips time)
	return cr
func _process(_d):
	for c in get_children():
		if c is Creature and c.state == Creature.State.ATTACK and not c.atk.is_empty():
			c._pose()
func _physics_process(_d):
	frames += 1
	for c in get_children():
		if c is Creature:
			c.position = c.get_meta("p"); c.rotation.y = c.get_meta("y")
			if c.has_meta("t"):
				c.state = Creature.State.ATTACK; c.atk_t = c.get_meta("t"); c.atk_done = true; c.speed = 0.0
	if frames == 20 and not pressed:
		pressed = true
		player.attack_pressed = true
	if troll and frames > 20:
		troll.state = Creature.State.ATTACK; troll.atk = troll.cfg.attacks[0]; troll.atk_t = 0.72; troll.atk_done = true; troll.atk_dir = Vector3(0, 0, -1)
	if pressed and not saved and player.swing >= 0 and player.body.anim.current_animation == "Sword_Slash1" and player.body.anim.current_animation_position >= 0.2:
		saved = true
		player.body.anim.seek(0.215, true)
		player.body.anim.pause()
		await get_tree().process_frame
		await get_tree().process_frame
		print("SHOT anim=", player.body.current, " pos=", player.body.anim.current_animation_position, " swing_t=", player.swing_t, " drawn=", player.body.sword_hand.visible)
		get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		get_tree().quit()
