extends Node3D
## The open world: loads the baked island and builds the ground, plants,
## village, sky, effects, creatures, sound, villagers, quest, player, HUD,
## menus and on-screen controls; saves progress.

var data := WorldData.new()
var config: Dictionary = {}
var mobile := OS.has_feature("mobile")
var player: Player
var sky: SkyCycle
var grass: GrassField
## Lakes, streams and falls (data/water.json).
var water: Water
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
## Debug action for screenshots: "attack", "talk" or "hurt".
var shot_act := ""
var hud: Hud
var story: Story
var town: Town
var state: GameState
var quests: Quests
var features: WorldFeatures
var journal: Journal
var services: Services
var audio: GameAudio
var menu: GameMenu
var quality: Quality
var stable: Stable
var expansion: Expansion
var settings: Dictionary = {}
var touch := false
var in_title := false
var autosave := 30.0
## Seconds between automatic saves.
const AUTOSAVE_EVERY := 30.0
## The adventure being played: its save slot id, its name and time played (s).
var current_slot := ""
var slot_name := ""
var playtime := 0.0
var last_saved_msec := 0


## Loading steps, in order. Each is recorded before it runs; if the game
## crashes during one, that step is skipped on the next launch (safe mode)
## and its name is shown on screen so it can be reported.
const BOOT_FILE := "user://boot_step.txt"
const SKIP_FILE := "user://skip_steps.json"
const ESSENTIAL := ["world data", "quality settings", "sky and lighting", "ground", "player", "villagers", "quests", "world features", "first frame", "done"]
var skip: Array = []
var boot_label: Label
var crash_note := ""
var booted := false


func _ready() -> void:
	_parse_args()
	if "--test-zone" in OS.get_cmdline_user_args():
		# The Terrain3D green-valley test zone (also from exported builds).
		get_tree().change_scene_to_file.call_deferred("res://world/test_zone/green_valley.tscn")
		return
	UiTheme.click_sounds(self)
	config = JSON.parse_string(FileAccess.get_file_as_string("res://data/game_config.json"))
	_read_last_boot()
	_show_boot_label()
	_boot()


func _read_last_boot() -> void:
	if FileAccess.file_exists(SKIP_FILE):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(SKIP_FILE))
		if parsed is Array:
			skip = parsed
		# A new build gets a fresh start: steps skipped after an old crash are retried.
		var ver := str(ProjectSettings.get_setting("application/config/version", ""))
		var vf := "user://skip_version.txt"
		var old := FileAccess.get_file_as_string(vf) if FileAccess.file_exists(vf) else ""
		if old != ver:
			skip.clear()
			var w := FileAccess.open(vf, FileAccess.WRITE)
			w.store_string(ver)
			w.close()
		for e in ESSENTIAL:
			skip.erase(e)
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
		quality = q
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
	if await _step("water"):
		water = Water.new()
		add_child(water)
		water.build(data.water, data.terrain_height, mobile)
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
	if await _step("town streets"):
		town = Town.new()
		add_child(town)
		town.setup(data, village)
	if village and await _step("your house and the church"):
		expansion = Expansion.new()
		add_child(expansion)
		expansion.build_landmarks(self)
	_mark("player")
	await get_tree().process_frame
	_spawn_player()
	touch = DisplayServer.is_touchscreen_available() or mobile
	hud = Hud.new()
	add_child(hud)
	player.data = data
	player.health_changed.connect(hud.set_health)
	player.hurt.connect(hud.flash_hurt)
	player.died.connect(_on_player_died)
	hud.set_health(player.health, player.max_health)
	state = GameState.new()
	add_child(state)
	state.player = player
	state.notify.connect(func(t: String, kind: String) -> void: hud.toast(t, kind))
	state.changed.connect(_update_stats)
	player.use_potion = state.use_potion
	state.load_state({})
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
	if await _step("horses"):
		stable = Stable.new()
		add_child(stable)
		stable.setup(data, player)
	if await _step("sound"):
		audio = GameAudio.new()
		add_child(audio)
		audio.setup(data, player, creatures)
	if await _step("villagers"):
		story = Story.new()
		add_child(story)
		story.state = state
		story.on_heart_blade = func(quiet: bool) -> void:
			state.add_item("heart_blade", 1, quiet)
		story.setup(data, player, hud, touch, town, mobile)
		story.progress_changed.connect(save_game)
	if audio:
		player.swung.connect(func(i: int) -> void: get_tree().create_timer(0.12).timeout.connect(func() -> void: audio.sfx("sword_swing_%d" % (i % 3), -6.0, randf_range(0.95, 1.05))))
		player.struck.connect(func(_t: Node3D, _p: Vector3) -> void: audio.sfx("sword_hit", -2.0, randf_range(0.9, 1.1)))
		player.blocked_hit.connect(func() -> void: audio.sfx("block", -4.0))
		player.dodged.connect(func() -> void: audio.sfx("roll", -6.0))
		player.splashed.connect(func() -> void: audio.sfx("splash", -6.0, randf_range(0.9, 1.1)))
		hud.banner_shown.connect(func(t: String) -> void:
			if t.begins_with("Discovered"):
				audio.sfx("discover", -6.0)
			elif t.contains("Quest") or t.contains("defeated") or t.contains("awakened") or t.contains("Treasure"):
				audio.sfx("quest", -6.0))
		state.notify.connect(func(_t: String, kind: String) -> void:
			if kind == "coins":
				audio.sfx("coins", -8.0)
			elif kind == "level":
				audio.sfx("quest", -4.0)
			elif _t.begins_with("Drank"):
				audio.sfx("potion", -6.0))
	if story and await _step("quests"):
		quests = Quests.new()
		add_child(quests)
		quests.setup(data, player, hud, story, state)
		quests.sky = sky
		quests.quest_changed.connect(func() -> void:
			_update_stats()
			_queue_save())
	if quests and await _step("world features"):
		features = WorldFeatures.new()
		add_child(features)
		quests.features = features
		quests.spawn_creature = features.spawn_creature
		features.setup(data, player, hud, story, state, quests, village, sky, audio, mobile)
		services = Services.new()
		add_child(services)
		services.state = state
		services.quests = quests
		services.features = features
		services.story = story
		story.services = services.for_villager
		journal = Journal.new()
		add_child(journal)
		journal.quests = quests
		journal.state = state
		journal.features = features
		journal.data = data
		journal.player = player
	if expansion and features and await _step("interiors, firearm and lights"):
		expansion.wire(self)
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
	settings = SaveGame.load_settings()
	_apply_settings(settings)
	menu = GameMenu.new()
	add_child(menu)
	menu.new_game.connect(_new_game)
	menu.continue_game.connect(_continue_game)
	menu.resumed.connect(_resume)
	menu.save_and_quit.connect(_save_and_quit)
	menu.quit_game.connect(func() -> void:
		save_game()
		get_tree().quit())
	menu.load_slot.connect(_load_slot)
	menu.save_now.connect(func() -> void:
		in_title = false
		save_game())
	menu.slot_renamed.connect(func(id: String, n: String) -> void:
		if id == current_slot:
			slot_name = n)
	menu.open_journal.connect(func(section: String) -> void:
		if journal:
			menu.hide_menu()
			journal.open_journal(section)
			# Closing a journal opened from the pause menu goes back to it.
			journal.closed.connect(_pause, CONNECT_ONE_SHOT))
	menu.settings_changed.connect(func(s: Dictionary) -> void:
		_apply_settings(s)
		SaveGame.save_settings(s))
	if shot_act == "title":
		hud.visible = false
		menu.show_title(true, settings)
	if shot_path == "" and tour.is_empty():
		in_title = true
		hud.visible = false
		get_tree().paused = true
		menu.show_title(SaveGame.has_save(), settings)


# ---------- Menus, saving and respawning ----------

func _apply_settings(s: Dictionary) -> void:
	settings = s
	GameAudio.apply_volumes(s.music, s.effects, s.master, s.ambience)
	UiTheme.reduced_motion = s.reduced_motion
	get_tree().root.content_scale_factor = clampf(float(s.text_size), 0.85, 1.3)
	if quality:
		quality.set_preset(s.quality)
	if player:
		player.look_mult = s.sensitivity
		player.camera.far = {"near": 1200.0, "normal": 2500.0}.get(s.view_distance, 5000.0)
	if hud_fps:
		hud_fps.visible = s.show_fps
	if hud:
		hud.set_full(s.hud_full)
	if sky:
		sky.env.adjustment_brightness = clampf(float(s.brightness), 0.7, 1.3)
		sky.set_shadow_quality(s.shadows)
	if grass:
		grass.set_density(s.foliage)
	if not mobile and not OS.has_feature("mobile") and DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if s.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode and not (mode == DisplayServer.WINDOW_MODE_WINDOWED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED):
			DisplayServer.window_set_mode(mode)
		if not s.fullscreen:
			var wh: PackedStringArray = str(s.window_size).split("x")
			var want := Vector2i(int(wh[0]), int(wh[1])) if wh.size() == 2 else Vector2i(1600, 900)
			if DisplayServer.window_get_size() != want and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_size(want)
				DisplayServer.window_set_position(DisplayServer.screen_get_position() + (DisplayServer.screen_get_size() - want) / 2)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if s.vsync else DisplayServer.VSYNC_DISABLED)
		var vp := get_viewport()
		vp.msaa_3d = Viewport.MSAA_2X if s.aa == "msaa" else Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if s.aa == "off" else Viewport.SCREEN_SPACE_AA_FXAA


## Starts a new adventure in a new save slot (other slots are never touched).
func _new_game(slot_name := "") -> void:
	if current_slot != "" and not in_title:
		save_game()   # keep the adventure we are leaving
	if slot_name.strip_edges() == "":
		slot_name = SaveGame.next_name()
	current_slot = SaveGame.new_slot(slot_name)
	self.slot_name = slot_name
	playtime = 0.0
	if state:
		state.load_state({})
	if story:
		story.load_state({})
	if quests:
		quests.load_state({})
	if features:
		features.end_event()
		features.refresh()
	var sp: Array = config.get("spawn", [0, 0, 40])
	player.respawn(Vector3(sp[0], data.height(sp[0], sp[2]) + 0.3, sp[2]))
	player.yaw = 0.0
	if stable:
		stable.reset()
	if sky:
		sky.time_of_day = config.get("start_hour", 7.6)
	if expansion and expansion.player:
		expansion.on_new_game()
	_resume()
	hud.show_notice("Find the village to the west.\nSomeone there needs your help.")
	save_game()


## Continues the most recently saved adventure.
func _continue_game() -> void:
	_load_slot(SaveGame.latest_slot())


## Loads an adventure exactly where it was saved, replacing whatever is in play
## (which was saved first when the pause menu opened).
func _load_slot(id: String) -> void:
	if id == "":
		return
	var s := SaveGame.load_save(id)
	if current_slot != "" and current_slot != id and not in_title:
		save_game()
	current_slot = id
	slot_name = str(s.get("meta", {}).get("name", "Adventure"))
	playtime = float(s.get("playtime", s.get("meta", {}).get("playtime", 0.0)))
	if features:
		features.end_event()
	if s.has("player"):
		var p: Array = s.player
		player.respawn(Vector3(p[0], maxf(p[1], data.height(p[0], p[2]) + 0.1), p[2]))
		player.yaw = s.get("yaw", 0.0)
		player.health = s.get("health", player.max_health)
		player.health_changed.emit(player.health, player.max_health)
	if state:
		state.load_state(s.get("progress", {"items": {"potion": 3}}))
	if story:
		story.load_state(s.get("story", {}))
	if quests:
		quests.load_state(s.get("quests", {}))
	if features:
		features.refresh()
	if stable:
		stable.load_state(s.get("horses", {}))
	if sky and s.has("hour"):
		sky.time_of_day = s.hour
	if expansion and expansion.player:
		expansion.on_loaded()
	_resume()
	save_game()   # marks it as the adventure last played (Continue)


func _resume() -> void:
	in_title = false
	menu.hide_menu()
	hud.visible = true
	get_tree().paused = false


func _pause() -> void:
	if not booted or in_title or get_tree().paused:
		return
	save_game()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.visible = false
	var where: String = WorldData.ZONE_NAMES[data.dominant_zone(player.global_position.x, player.global_position.z)] if data else ""
	menu.current_slot = current_slot
	var info := "%s   ·   %s   ·   %s" % [slot_name, where, sky.clock_text()] if sky else where
	menu.show_pause(settings, info, "Progress saved" if current_slot != "" else "Not saved")


func _save_and_quit() -> void:
	save_game()
	in_title = true
	hud.visible = false
	menu.show_title(true, settings)


## Writes progress to the current adventure's slot (position, health, quests,
## items, discoveries, time of day, horses, playtime).
func save_game() -> void:
	# Never at the title screen: the world there is not anyone's adventure yet.
	if player == null or player.dead or shot_path != "" or current_slot == "" or in_title:
		return
	var p := player.global_position
	var region: String = WorldData.ZONE_NAMES[data.dominant_zone(p.x, p.z)] if data else ""
	last_saved_msec = Time.get_ticks_msec()
	if hud:
		hud.show_saving()
	SaveGame.save(current_slot, {
		"playtime": playtime,
		"player": [p.x, p.y, p.z], "yaw": player.yaw, "health": player.health,
		"story": story.save_state() if story else {},
		"progress": state.save_state() if state else {},
		"quests": quests.save_state() if quests else {},
		"hour": sky.time_of_day if sky else 8.0,
		"horses": stable.save_state() if stable else {},
	}, {"name": slot_name, "region": region, "level": state.level if state else 1, "playtime": playtime})


var _save_soon := false


## Saves at the end of the frame (several quest changes can arrive together).
func _queue_save() -> void:
	if _save_soon:
		return
	_save_soon = true
	await get_tree().process_frame
	_save_soon = false
	save_game()


func _update_stats() -> void:
	if hud and state:
		hud.set_stats(state.coins, state.level, state.xp, state.xp_for_next(), state.count("potion") + state.count("elixir"))


func _on_player_died() -> void:
	hud.show_defeated(true)
	await get_tree().create_timer(player.combat.get("respawn_delay", 3.5)).timeout
	var sp: Array = config.get("spawn", [0, 0, 40])
	player.respawn(Vector3(sp[0], data.height(sp[0], sp[2]) + 0.3, sp[2]))
	hud.show_defeated(false)
	hud.show_notice("You wake up in the meadow.")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_P]:
		if get_tree().paused and not in_title:
			_resume()
		else:
			_pause()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save_game()


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
		elif a.begins_with("--ui_tour="):
			ui_tour = a.substr(10).split(",")
		elif a.begins_with("--tour="):
			tour = a.substr(7).split(";")
		elif a.begins_with("--fly="):
			fly = a.substr(6).split(",")
		elif a.begins_with("--act="):
			shot_act = a.substr(6)
		elif a == "--mobile":
			mobile = true


## Debug camera for screenshots: x,y,z,yaw_deg,pitch_deg.
var fly: PackedStringArray = []
## Screenshot tour: "x,y,z,yaw,pitch,hour;..." saved as <shot>_<n>.png
var tour: PackedStringArray = []
## Interface screenshot tour: "title,pause,settings,quests,people,inventory,map,dialogue,hud"
## saved as <shot>_ui_<name>.png (dev tool for checking the menus).
var ui_tour: PackedStringArray = []
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
	if town:
		town.set_night(amount)
	if expansion:
		expansion.set_night(amount)


func _label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 6)
	return l


func _build_ui() -> void:
	var layer: CanvasLayer = hud   # clock, FPS and place names hide with the HUD (menus)
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
	hud_zone.add_theme_font_override("font", UiTheme.title_font())
	hud_zone.add_theme_color_override("font_color", UiTheme.GOLD_BRIGHT)
	hud_clock.add_theme_font_override("font", UiTheme.title_font())
	layer.add_child(hud_zone)
	if DisplayServer.is_touchscreen_available() or mobile:
		var tc := TouchControls.new()
		tc.player = player
		tc.on_pause = _pause
		if journal:
			tc.on_journal = journal.open_journal
		layer.add_child(tc)


func _process(delta: float) -> void:
	if player == null or sky == null or hud_fps == null:
		return
	Villager.hour = sky.time_of_day
	if not in_title and not get_tree().paused:
		playtime += delta
	autosave -= delta
	if autosave <= 0.0:
		autosave = AUTOSAVE_EVERY
		save_game()
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
	if ui_tour.size() > 0:
		if booted:
			_run_ui_tour()
		return
	if shot_path != "":
		shot_frames += 1
		if shot_act.begins_with("ride") and stable:
			# Debug: climb on the nearest horse and ride ("ride_run" gallops).
			if shot_frames == 20:
				var near: Horse = null
				for h in stable.horses:
					if near == null or h.global_position.distance_to(player.global_position) < near.global_position.distance_to(player.global_position):
						near = h
				player.mount(near)
			if shot_frames > 20 and shot_act != "ride":
				player.move_input = Vector2(0, -1)
				player.sprint_held = shot_act == "ride_run"
		if shot_frames == 40:
			match shot_act:
				"attack":
					player.attack_pressed = true
				"talk":
					story.interact()
				"hurt":
					player.take_damage(35.0, player.global_position + Vector3(1, 0, 0))
				"journal", "map", "people", "inventory", "discoveries":
					journal.open_journal("quests" if shot_act == "journal" else shot_act)
					get_tree().paused = false   # keep the screenshot counter running
				"pause":
					_pause()
					get_tree().paused = false
				"settings":
					_pause()
					menu._open_settings("pause")
					get_tree().paused = false
		if shot_frames == 50:
			for l in [hud_fps, hud_clock, hud_zone]:
				l.visible = false
		if shot_frames == 60:
			get_viewport().get_texture().get_image().save_png(shot_path)
			get_tree().quit()


func _run_ui_tour() -> void:
	var idx := shot_frames / 12
	var f := shot_frames % 12
	shot_frames += 1
	get_viewport().scaling_3d_scale = 0.35   # the 3D behind is only a backdrop; keeps software rendering quick
	if idx >= ui_tour.size():
		get_tree().quit()
		return
	var what := ui_tour[idx]
	if f == 0:
		journal.visible = false
		menu.hide_menu()
		story.hud.hide_dialogue()
		get_tree().paused = false
		hud.visible = true
		match what:
			"title":
				hud.visible = false
				menu.show_title(true, settings)
			"pause":
				_pause()
			"settings", "settings_audio", "settings_graphics":
				_pause()
				menu._open_settings("pause")
				menu.settings_tabs.current_tab = {"settings": 0, "settings_audio": 2, "settings_graphics": 1}[what]
			"confirm":
				hud.visible = false
				menu.show_title(true, settings)
				menu._ask_new_game()
			"slots":
				hud.visible = false
				menu.show_title(true, settings)
				menu._open_slots("title")
			"dialogue":
				story._start_dialogue(story.by_id["elder"])
			"hud":
				hud.toast("+50 coins", "coins")
				hud.toast("Quest updated", "quest")
				hud.show_banner("The Old Mill", "Discovered")
			_:
				journal.open_journal(what)
		get_tree().paused = false   # keep the counter running
	if f == 10:
		get_viewport().get_texture().get_image().save_png(shot_path.get_basename() + "_ui_%s.png" % what)


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
