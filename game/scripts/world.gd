extends Node3D
## The open world: loads the baked island and builds the ground, plants,
## village, sky, effects, creatures, sound, player and on-screen controls.

var data := WorldData.new()
var config: Dictionary = {}
var mobile := OS.has_feature("mobile")
var player: Player
var sky: SkyCycle
var grass: GrassField
var village: Village
var effects: ZoneEffects
var hud_fps: Label
var hud_clock: Label
var hud_zone: Label
var zone_timer := 0.0
var last_zone := -1
var shot_path := ""
var shot_frames := 0
var shot_hour := -1.0


## Loading steps, in order. Each is recorded before it runs; if the game
## crashes during one, that step is skipped on the next launch (safe mode)
## and its name is shown on screen so it can be reported.
const BOOT_FILE := "user://boot_step.txt"
const SKIP_FILE := "user://skip_steps.json"
const ESSENTIAL := ["world data", "quality settings", "sky and lighting", "ground", "player", "first frame", "done"]
var skip: Array = []
var boot_label: Label
var crash_note := ""
var booted := false


func _ready() -> void:
	_parse_args()
	config = JSON.parse_string(FileAccess.get_file_as_string("res://data/game_config.json"))
	_read_last_boot()
	_show_boot_label()
	_boot()


func _read_last_boot() -> void:
	if FileAccess.file_exists(SKIP_FILE):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(SKIP_FILE))
		if parsed is Array:
			skip = parsed
	if FileAccess.file_exists(BOOT_FILE):
		var last := FileAccess.get_file_as_string(BOOT_FILE).strip_edges()
		if last != "" and last != "done":
			crash_note = "Last launch crashed while loading: %s. Skipping it this time." % last
			# Essential steps are never skipped; only optional scenery can be.
			if last in ESSENTIAL:
				crash_note = "Last launch crashed while loading: %s." % last
			elif not last in skip:
				skip.append(last)
			var f := FileAccess.open(SKIP_FILE, FileAccess.WRITE)
			f.store_string(JSON.stringify(skip))
			f.close()


func _mark(step: String) -> void:
	var f := FileAccess.open(BOOT_FILE, FileAccess.WRITE)
	f.store_string(step)
	f.close()
	if boot_label:
		boot_label.text = ("%s\n\n" % crash_note if crash_note != "" else "") + "Loading: " + step + "..."


func _show_boot_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.name = "BootBg"
	layer.add_child(bg)
	boot_label = _label(Vector2(40, 40), 26)
	boot_label.size = Vector2(1400, 400)
	boot_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	layer.add_child(boot_label)


func _step(name: String) -> bool:
	_mark(name)
	await get_tree().process_frame
	await get_tree().process_frame
	return name in ESSENTIAL or not name in skip


func _boot() -> void:
	if await _step("world data"):
		if not data.load_data():
			boot_label.text = "World data missing."
			return
	if await _step("quality settings"):
		var q := Quality.new()
		add_child(q)
		q.setup(mobile, config)
	if await _step("sky and lighting"):
		sky = SkyCycle.new()
		add_child(sky)
		sky.setup(mobile, config)
		if shot_hour >= 0.0:
			sky.time_of_day = shot_hour
			sky.day_minutes = 100000.0
	var photo_ground: bool = await _step("ground photo textures")
	if await _step("ground"):
		var terrain := Terrain.new()
		add_child(terrain)
		terrain.setup(data, mobile, photo_ground)
	var veg := Vegetation.new()
	add_child(veg)
	veg.mobile = mobile
	veg.data = data
	veg.begin()
	if await _step("trees"):
		veg.add_kinds(["oak", "pine"])
	if await _step("rocks"):
		veg.add_kinds(["model_rock"])
	if await _step("plants"):
		veg.add_kinds(["model_plant"])
	if await _step("mushrooms and crystals"):
		veg.add_kinds(["mushroom", "crystal"])
	if await _step("village"):
		village = Village.new()
		add_child(village)
		village.setup(data)
	_mark("player")
	await get_tree().process_frame
	_spawn_player()
	if await _step("grass"):
		grass = GrassField.new()
		add_child(grass)
		grass.setup(data, player, mobile)
	var creatures: Array = []
	if await _step("wildlife"):
		var wildlife := Wildlife.new()
		add_child(wildlife)
		wildlife.setup(data, player, mobile)
		creatures = wildlife.animals
	if await _step("sound"):
		var audio := GameAudio.new()
		add_child(audio)
		audio.setup(data, player, creatures)
	if await _step("weather effects"):
		effects = ZoneEffects.new()
		add_child(effects)
		effects.setup(player, mobile)
	if sky:
		sky.night_changed.connect(_on_night)
	_build_ui()
	_mark("first frame")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_mark("done")
	booted = true
	boot_label.get_parent().get_node("BootBg").queue_free()
	if crash_note != "":
		boot_label.text = crash_note
		get_tree().create_timer(8.0).timeout.connect(func(): boot_label.text = "")
	else:
		boot_label.text = ""
	if fly.size() == 5:
		var cam := Camera3D.new()
		cam.far = 5000.0
		add_child(cam)
		cam.position = Vector3(float(fly[0]), float(fly[1]), float(fly[2]))
		cam.rotation_degrees = Vector3(float(fly[4]), float(fly[3]), 0)
		cam.current = true


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot_path = a.substr(7)
		elif a.begins_with("--hour="):
			shot_hour = float(a.substr(7))
		elif a.begins_with("--spawn="):
			var p := a.substr(8).split(",")
			config_spawn_override = Vector3(float(p[0]), 0, float(p[1]))
			spawn_yaw = float(p[2]) if p.size() > 2 else 0.0
		elif a.begins_with("--tour="):
			tour = a.substr(7).split(";")
		elif a.begins_with("--fly="):
			fly = a.substr(6).split(",")
		elif a == "--mobile":
			mobile = true


## Debug camera for screenshots: x,y,z,yaw_deg,pitch_deg.
var fly: PackedStringArray = []
## Screenshot tour: "x,y,z,yaw,pitch,hour;..." saved as <shot>_<n>.png
var tour: PackedStringArray = []
var tour_cam: Camera3D
var config_spawn_override := Vector3.INF
var spawn_yaw := 0.0


func _spawn_player() -> void:
	player = Player.new()
	player.setup(config)
	var s: Array = config.get("spawn", [0, 0, 40])
	var p := Vector3(s[0], 0, s[2])
	if config_spawn_override != Vector3.INF:
		p = config_spawn_override
	p.y = data.height(p.x, p.z) + 0.3
	player.position = p
	add_child(player)
	player.yaw = spawn_yaw


func _on_night(amount: float) -> void:
	if grass:
		grass.set_night(amount)
	if village:
		village.set_night(amount)


func _label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 6)
	return l


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_fps = _label(Vector2(18, 12), 18)
	layer.add_child(hud_fps)
	hud_clock = _label(Vector2(18, 38), 22)
	layer.add_child(hud_clock)
	hud_zone = _label(Vector2.ZERO, 46)
	hud_zone.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hud_zone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_zone.position = Vector2(-300, 70)
	hud_zone.size = Vector2(600, 60)
	hud_zone.modulate.a = 0.0
	layer.add_child(hud_zone)
	if DisplayServer.is_touchscreen_available() or mobile:
		var tc := TouchControls.new()
		tc.player = player
		layer.add_child(tc)


func _process(delta: float) -> void:
	if player == null or sky == null or hud_fps == null:
		return
	var p := player.global_position
	var w := data.zone(p.x, p.z)
	sky.set_zone(w)
	if effects:
		effects.update(w, sky.night)
	hud_fps.text = "%d FPS" % Engine.get_frames_per_second()
	hud_clock.text = sky.clock_text()
	# Show the zone name when you walk into a new one.
	var z := data.dominant_zone(p.x, p.z)
	if z != last_zone:
		if last_zone != -1 or true:
			hud_zone.text = WorldData.ZONE_NAMES[z]
			zone_timer = 3.5
		last_zone = z
	zone_timer -= delta
	hud_zone.modulate.a = clampf(minf(zone_timer, 3.5 - zone_timer) * 2.0, 0.0, 1.0)

	if tour.size() > 0:
		if booted:
			_run_tour()
		return
	if shot_path != "":
		shot_frames += 1
		if shot_frames == 50:
			for l in [hud_fps, hud_clock, hud_zone]:
				l.visible = false
		if shot_frames == 60:
			get_viewport().get_texture().get_image().save_png(shot_path)
			get_tree().quit()


func _run_tour() -> void:
	if tour_cam == null:
		tour_cam = Camera3D.new()
		tour_cam.far = 5000.0
		add_child(tour_cam)
		tour_cam.current = true
		for l in [hud_fps, hud_clock, hud_zone]:
			l.visible = false
	var idx := shot_frames / 70
	var f := shot_frames % 70
	shot_frames += 1
	if idx >= tour.size():
		get_tree().quit()
		return
	var v := tour[idx].split(",")
	if f == 0:
		var pos := Vector3(float(v[0]), float(v[1]), float(v[2]))
		pos.y += data.height(pos.x, pos.z)
		tour_cam.position = pos
		tour_cam.rotation_degrees = Vector3(float(v[4]), float(v[3]), 0)
		sky.time_of_day = float(v[5])
		player.position = Vector3(pos.x, data.height(pos.x, pos.z) + 0.2, pos.z) + Basis(Vector3.UP, deg_to_rad(float(v[3]))) * Vector3(0.6, 0, -4.0)
		player.position.y = data.height(player.position.x, player.position.z) + 0.2
		player.body.rotation.y = deg_to_rad(float(v[3])) + PI
		sky.zone_w = data.zone(pos.x, pos.z)
	if f == 69:
		get_viewport().get_texture().get_image().save_png(shot_path.get_basename() + "_%d.png" % idx)
