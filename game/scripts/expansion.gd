class_name Expansion
extends Node3D
## Wires the expansion into the world: your house (white stone, by the south
## gardens), the Church of the Mended Isle, walk-in interiors for Brickton
## (Interiors), the flintlock and its HUD, the horse whistle, hunting drops,
## resting in your own bed and the town's night lights (LightPool).
## world.gd calls build_landmarks() during boot (before villagers spawn, so
## people inside the church stand on its floor) and wire() once the rest of
## the world exists.

var world: Node
var data: WorldData
var player: Player
var village: Village
var church: Church
var interiors: Interiors
var house_index := -1
var weapon_hud: CanvasLayer
var crosshair: Control
var ammo_label: Label
var lamps: LightPool
var night := 0.0
## A soft light near the camera at night so you can always see your explorer
## (no outline or glow; just enough fill to read the figure against the dark).
var fill: OmniLight3D


## Your house and the church (they reserve their ground in data/landmarks.json).
func build_landmarks(w: Node) -> void:
	world = w
	data = w.data
	village = w.village
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/landmarks.json"))
	for e: Dictionary in cfg.landmarks:
		var h := e.duplicate()
		h["y"] = data.terrain_height(float(e.x), float(e.z))
		match str(e.kind):
			"player_house":
				h["y"] = float(h.y) + 0.35   # sit the floor clear of the grass on the high side
				village.build_house(h)
				house_index = village.buildings.size() - 1
				_garden(village.buildings[house_index].root, h)
			"church":
				church = Church.new()
				add_child(church)
				church.setup(data, h, village)


## Everything that needs the player, HUD, sound, quests and story.
func wire(w: Node) -> void:
	world = w
	player = w.player
	var hud: Hud = w.hud
	var audio: GameAudio = w.audio
	var sfx := func(n: String, db := -4.0, pitch := 1.0) -> void:
		if audio:
			audio.sfx(n, db, pitch)
	# Interiors (after the house exists, so it is furnished too).
	interiors = Interiors.new()
	add_child(interiors)
	interiors.setup(data, village, player)
	interiors.play_sfx = sfx
	interiors.on_rest = rest
	interiors.state = w.state
	# Townsfolk routines: home doors (not yours), the tavern front, the church steps.
	Villager.doors.clear()
	for i in village.buildings.size():
		if i != house_index:
			var b: Dictionary = village.buildings[i]
			Villager.doors.append(b.root.to_global(b.door_local + Vector3(0, 0, 0.6)) * Vector3(1, 0, 1))
	var tavern_i := interiors.find("inn")
	if tavern_i >= 0:
		var b: Dictionary = village.buildings[tavern_i]
		Villager.places["tavern"] = b.root.to_global(b.door_local + Vector3(0, 0, 3.0)) * Vector3(1, 0, 1)
	if church:
		Villager.places["church"] = church.to_global(Vector3(0, 0, church.d * 0.5 + 7.0)) * Vector3(1, 0, 1)
	if church:
		church.player = player
		church.sky = w.sky
		if w.story:
			church.open_text = func(c: Dictionary) -> void: w.story.open(c)
	# The flintlock.
	var gun := Firearm.new()
	player.add_child(gun)
	gun.setup(player, w.state, w.config.get("firearm", {}))
	gun.play_sfx = sfx
	gun.message.connect(func(t: String) -> void: hud.toast(t, "warn"))
	player.gun = gun
	_build_weapon_hud()
	gun.ammo_changed.connect(_update_weapon_hud)
	w.state.changed.connect(_update_weapon_hud)
	# Whistle for your horse.
	if w.stable:
		w.stable.notify = func(t: String) -> void: hud.toast(t, "item")
		w.stable.play_sfx = sfx
		w.stable._ensure_nav()
		player.whistled.connect(func() -> void: w.stable.whistle())
	# Hunting: animals and monsters drop meat, hides and materials.
	for c in get_tree().get_nodes_in_group("creatures"):
		if c is Creature and not c is Horse:
			c.killed.connect(_on_kill)
	# Street lamps and lanterns share a few real lights (nearest to you, at night).
	lamps = LightPool.new()
	add_child(lamps)
	lamps.setup(player, w.lite)
	_trail_lanterns(w)
	_collect_lamps(w)
	fill = OmniLight3D.new()
	fill.light_color = Color(0.85, 0.88, 1.0)
	fill.omni_range = 7.0
	fill.omni_attenuation = 1.6
	fill.shadow_enabled = false
	fill.light_specular = 0.1
	fill.visible = false
	player.cam_pivot.add_child(fill)
	fill.position = Vector3(0.4, 0.6, 1.6)
	# Occlusion culling: houses, walls and the church hide what's behind them (PC).
	if not w.mobile:
		get_viewport().use_occlusion_culling = true
	# Ambient sound in the tavern and the church.
	if audio:
		var inn := interiors.find("inn")
		if inn >= 0:
			_ambience("tavern", village.buildings[inn].root.global_position + Vector3(0, 1.5, 0), 10.0, -12.0)
		if church:
			_ambience("church", church.global_position + Vector3(0, 3, 0), 22.0, -14.0)
	_update_weapon_hud()


func set_night(amount: float) -> void:
	night = amount
	if interiors:
		interiors.set_night(amount)
	if church:
		church.set_night(amount)
	if lamps:
		lamps.set_night(amount)
	if fill:
		fill.light_energy = 0.55 * smoothstep(0.2, 0.8, amount)
		fill.visible = fill.light_energy > 0.02


## New game: the flintlock and a pouch of shot.
func on_new_game() -> void:
	_give_kit(true)


## Loaded save: older saves get the flintlock once, with a note.
func on_loaded() -> void:
	_give_kit(false)


func _give_kit(quiet: bool) -> void:
	var state: GameState = world.state
	if state.has_flag("got_flintlock"):
		return
	state.set_flag("got_flintlock")
	state.add_item(Firearm.GUN_ITEM, 1, true)
	state.add_item(Firearm.AMMO_ITEM, int(world.config.get("firearm", {}).get("start_shot", 12)), true)
	if not quiet:
		world.hud.show_notice("Brann the hunter sent you a flintlock pistol and 12 shots.\nS to shoot (it draws itself), right mouse to aim, R to reload, A to go back to the sword.")


## Sleeping in your own bed: until morning, fully rested, game saved.
func rest() -> void:
	var sky: SkyCycle = world.sky
	if sky:
		sky.time_of_day = 7.0
	player.health = player.max_health
	player.health_changed.emit(player.health, player.max_health)
	if world.audio:
		world.audio.sfx("bed", -6.0)
	world.hud.show_banner("You sleep in your own bed", "Morning. You feel fully rested.")
	world.save_game()


func _on_kill(c: Creature) -> void:
	var drops: Dictionary = c.cfg.get("drops", {})
	if drops.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for id in drops:
		var r: Array = drops[id]
		var n := rng.randi_range(int(r[0]), int(r[1]))
		if n > 0:
			world.state.add_item(id, n)


# ---------- Your house's garden ----------

func _garden(root: Node3D, h: Dictionary) -> void:
	var w: float = h.w
	var d: float = h.d
	var g: float = h.get("garden", 6.0)
	var white := village._tex_mat("plastered_stone_wall", Color(1.25, 1.24, 1.2), 0.3)
	# A low white wall round a front courtyard, with a gap at the path.
	var front := d * 0.5 + g
	var gap := 2.0
	var door_x := -w * 0.15
	for seg in [[Vector3(-w * 0.5 - 1.0, 0, d * 0.5), Vector3(-w * 0.5 - 1.0, 0, front)],
			[Vector3(w * 0.5 + 1.0, 0, d * 0.5), Vector3(w * 0.5 + 1.0, 0, front)],
			[Vector3(-w * 0.5 - 1.0, 0, front), Vector3(door_x - gap * 0.5, 0, front)],
			[Vector3(door_x + gap * 0.5, 0, front), Vector3(w * 0.5 + 1.0, 0, front)]]:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var mid := (a + b) * 0.5
		var gp := root.to_global(mid)
		var y := data.terrain_height(gp.x, gp.z) - root.global_position.y
		var len := a.distance_to(b)
		var dir := (b - a).normalized()
		Structures.box(root, Vector3(len, 0.8, 0.35), mid + Vector3(0, y + 0.2, 0), white, Vector3(0, atan2(dir.x, dir.z) + PI * 0.5, 0), true)
	# Flower beds, a bench, a small tree in a tub, lanterns and the name board.
	var cols := [Color(0.9, 0.3, 0.35), Color(0.95, 0.85, 0.3), Color(0.6, 0.4, 0.9), Color(0.95, 0.95, 0.95)]
	for k in 8:
		var x := -w * 0.5 + 0.2 + (k % 4) * 0.9
		var z := d * 0.5 + 1.6 + (k / 4) * 2.4
		Structures.box(root, Vector3(0.8, 0.15, 0.6), Vector3(x, 0.05, z), Structures.plain(Color(0.25, 0.18, 0.1), 1.0))
		for f in 3:
			Structures.sphere(root, 0.09, Vector3(x - 0.25 + f * 0.25, 0.22, z), Structures.plain(cols[(k + f) % 4], 0.8))
	Structures.bench(root, Vector3(w * 0.3, 0, d * 0.5 + 2.2), PI)
	Structures.cyl(root, 0.3, 0.25, 0.5, Vector3(w * 0.42, 0.25, d * 0.5 + 4.5), Structures.wood(Color(0.45, 0.32, 0.2)))
	Structures.sphere(root, 0.7, Vector3(w * 0.42, 1.3, d * 0.5 + 4.5), Structures.plain(Color(0.25, 0.45, 0.2), 0.9))
	var lit := village.window_mat
	for sx in [-1.0, 1.0]:
		Structures.lamp_post(root, Vector3(door_x + sx * (gap * 0.5 + 0.4), 0, front), lit)
	# Name board on two posts by the gate.
	var sx := door_x + gap * 0.5 + 1.4
	for px in [-0.6, 0.6]:
		Structures.box(root, Vector3(0.1, 1.7, 0.1), Vector3(sx + px, 0.85, front + 0.4), Structures.wood(Color(0.4, 0.28, 0.18)))
	Structures.box(root, Vector3(1.5, 0.55, 0.06), Vector3(sx, 1.45, front + 0.4), Structures.wood(Color(0.55, 0.4, 0.26)))
	Structures.label(root, "Your House", Vector3(sx, 1.45, front + 0.45), 40, Color(0.98, 0.92, 0.7))
	# A carved crest over the door marks the owner.
	Structures.box(root, Vector3(0.9, 0.9, 0.08), Vector3(door_x, Village.FLOOR_Y + 2.75, d * 0.5 + 0.05), Structures.plain(Color(0.2, 0.32, 0.6), 0.7))
	Structures.sphere(root, 0.22, Vector3(door_x, Village.FLOOR_Y + 2.75, d * 0.5 + 0.1), Structures.plain(Color(0.9, 0.75, 0.3), 0.3, 0.9), Vector3(1, 1, 0.3))


# ---------- HUD ----------

func _build_weapon_hud() -> void:
	weapon_hud = CanvasLayer.new()
	weapon_hud.layer = 6
	add_child(weapon_hud)
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(func() -> void:
		var c := Color(1, 1, 1, 0.85)
		var gun: Firearm = player.gun
		var r := 6.0 if gun and gun.aiming else 12.0
		for v in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			crosshair.draw_line(v * r, v * (r + 9.0), Color(0, 0, 0, 0.5), 4.0)
			crosshair.draw_line(v * r, v * (r + 9.0), c, 2.0)
		crosshair.draw_circle(Vector2.ZERO, 1.6, c))
	weapon_hud.add_child(crosshair)
	ammo_label = Label.new()
	ammo_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	ammo_label.position = Vector2(-160, -70)
	ammo_label.size = Vector2(320, 40)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ammo_label.add_theme_font_size_override("font_size", 24)
	ammo_label.add_theme_color_override("font_outline_color", Color.BLACK)
	ammo_label.add_theme_constant_override("outline_size", 6)
	weapon_hud.add_child(ammo_label)


func _process(_delta: float) -> void:
	if crosshair and player and player.gun:
		crosshair.visible = player.gun.drawn and world.hud.visible
		ammo_label.visible = crosshair.visible
		crosshair.queue_redraw()


func _update_weapon_hud() -> void:
	if ammo_label == null or player == null or player.gun == null:
		return
	var gun: Firearm = player.gun
	var state_txt := "Reloading..." if gun.reloading() else ("● Loaded" if gun.loaded else "○ Empty (R)")
	ammo_label.text = "Flintlock   %s   Shot × %d" % [state_txt, gun.ammo()]


# ---------- Lights and ambience ----------

func _collect_lamps(w: Node) -> void:
	# Every lamp post's lantern (Structures.lamp_post) in the town and here.
	for root in [w.town, self, village]:
		if root == null:
			continue
		for n in root.find_children("*", "MeshInstance3D", true, false):
			if n.has_meta("lamp"):
				lamps.add_spot(n.global_position)


func _ambience(name: String, at: Vector3, size: float, db: float) -> void:
	var path := "res://assets/audio/ambience/%s.ogg" % name
	if not ResourceLoader.exists(path):
		return
	var p := AudioStreamPlayer3D.new()
	var s: AudioStreamOggVorbis = load(path)
	s.loop = true
	p.stream = s
	p.volume_db = db
	p.unit_size = size
	p.max_distance = size * 3.0
	p.bus = "Ambience"
	p.autoplay = true
	add_child(p)
	p.global_position = at


## A few lanterns beside the meadow trails (every ~60 m), lit at night.
func _trail_lanterns(w: Node) -> void:
	var placed: Array[Vector2] = []
	var lit := village.window_mat
	for z in range(-240, 241, 12):
		for x in range(-170, 241, 12):
			var p := Vector2(x, z)
			if p.length() > 235.0 or data.on_path(p.x, p.y) < 0.6 or data.is_lava(p.x, p.y):
				continue
			if placed.any(func(q: Vector2) -> bool: return q.distance_to(p) < 60.0):
				continue
			# Step off the trail to its edge.
			var side := Vector2.INF
			for a in 8:
				var off := Vector2(cos(a * TAU / 8.0), sin(a * TAU / 8.0)) * 3.2
				if data.on_path(p.x + off.x, p.y + off.y) < 0.15:
					side = p + off
					break
			if side == Vector2.INF:
				continue
			placed.append(p)
			Structures.lamp_post(self, Vector3(side.x, data.height(side.x, side.y), side.y), lit)
