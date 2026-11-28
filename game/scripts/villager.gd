class_name Villager
extends Node3D
## A person of the island: a dressed ExplorerBody with a daily habit, a role
## and dialogue. Defined in data/npcs.json; the Story node runs conversations.
##
## Habits (cfg.mode):
##   wander  - strolls a few metres around home (the original villagers)
##   stroll  - walks between random places in town along the streets
##   patrol  - walks a fixed loop of waypoints (guards)
##   work    - stays at a workplace facing a direction, busy (idle_anim)
##   chat    - stands with a partner, talking and gesturing
##   sit     - sits on a bench or at a table
## Guards also fight monsters that come into town, and anyone can be told to
## run for shelter (hide) during an attack.
##
## Daily routine (townsfolk who stroll or wander): some visit the church in the
## morning, many spend the evening outside the tavern, and everyone walks home
## and goes indoors at night, coming back out after dawn.

## Hour of the day (0-24), set by the world each frame.
static var hour := 12.0
## Where routines lead: "tavern" and "church" spots, set when the town is built.
static var places := {}
## House doors (where townsfolk go indoors at night), set when the town is built.
static var doors: Array = []

var cfg: Dictionary = {}
var id := ""
var display_name := ""
var role := ""
var body: ExplorerBody
var height_at: Callable = func(_x: float, _z: float) -> float: return 0.0
var player: Node3D
var town: Town
var home := Vector3.ZERO
var target := Vector3.ZERO
var path: Array = []
var timer := 0.0
var walking := false
var talking := false
var mode := "wander"
var rng := RandomNumberGenerator.new()
var marker: Label3D
var marker_kind := ""
## Set by quests and events: walk to this spot and stay out of sight.
var hiding := false
var hide_spot := Vector3.INF
## Guards: the creature being fought.
var foe: Node3D
var attack_cd := 0.0
var patrol_i := 0
## Fewer animation updates when far from the camera (set by Story).
var lod := 0
var _lod_skip := 0
## Where the daily routine has them: "", "home", "tavern" or "church".
var routine := ""
var _base_mode := ""
var _routine_check := 0.0
var _shift := 0.0          ## this person's habits run up to ~40 min early or late
var _likes := {}           ## "tavern" / "church": goes there at all
var _habit_rng := RandomNumberGenerator.new()
var _col: CollisionShape3D


## Builds the villager. Colours in cfg.outfit are [r, g, b] arrays.
func setup(villager_cfg: Dictionary, seed_value: int) -> void:
	cfg = villager_cfg
	id = cfg.id
	display_name = cfg.name
	role = cfg.get("role", "")
	mode = cfg.get("mode", "wander")
	_base_mode = mode
	rng.seed = seed_value
	# Own generator for habits, so everyone's other randomness stays as it was.
	_habit_rng.seed = seed_value * 7919 + 1
	_shift = _habit_rng.randf_range(-0.7, 0.7)
	_likes = {"tavern": _habit_rng.randf() < 0.65, "church": _habit_rng.randf() < 0.4}
	var outfit := {}
	for k in cfg.outfit:
		var v = cfg.outfit[k]
		outfit[k] = Color(v[0], v[1], v[2]) if v is Array and v.size() == 3 and (v[0] is float or v[0] is int) else v
	# Each person gets their own face, skin tone and hair from a seed of their id.
	outfit["seed"] = hash(cfg.get("id", name))
	body = ExplorerBody.new()
	body.outfit = outfit
	body.scale = Vector3.ONE * float(cfg.get("scale", 1.0))
	add_child(body)
	home = Vector3(cfg.home[0], 0, cfg.home[1])
	target = home
	timer = rng.randf_range(1.0, 4.0)
	if cfg.get("anvil", false):
		_add_anvil()
	# A solid body so the player bumps into villagers instead of walking through.
	var blocker := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3 * body.scale.x
	cap.height = 1.7 * body.scale.x
	col.shape = cap
	col.position.y = cap.height * 0.5
	blocker.add_child(col)
	add_child(blocker)
	_col = col
	marker = make_marker()
	marker.position.y = MARKER_Y * body.scale.x
	add_child(marker)
	if mode == "sit":
		body.position.y = -0.05
	add_to_group("villagers")


func _add_anvil() -> void:
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.22, 0.22, 0.24)
	iron.metallic = 0.85
	iron.roughness = 0.45
	var anvil := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.7, 0.18, 0.28)
	anvil.mesh = b
	anvil.material_override = iron
	anvil.position = Vector3(0, 0.66, 0.6)
	add_child(anvil)
	var stand := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.22, 0.57, 0.2)
	stand.mesh = sb
	stand.material_override = ExplorerBody._fabric(Color(0.3, 0.2, 0.12))
	stand.position = Vector3(0, 0.285, 0.6)
	add_child(stand)


## Height of the marker above a villager's feet (metres).
const MARKER_Y := 2.55
## World size of the marker's glyph box up close (metres per pixel at font_size).
const MARKER_PIXEL := 0.0042
## Beyond this distance (metres) a marker stops shrinking on screen.
const MARKER_FAR := 12.0
const MARKER_YELLOW := Color(1.0, 0.82, 0.08)
const MARKER_BLUE := Color(0.55, 0.85, 1.0)
static var _marker_font: FontVariation


## A big bold billboard "!" (hidden until set): drawn on top of walls and
## trees so mission givers can be spotted from across town.
static func make_marker(kind := "") -> Label3D:
	if _marker_font == null:
		_marker_font = FontVariation.new()
		_marker_font.base_font = ThemeDB.fallback_font
		_marker_font.variation_embolden = 1.4
	var m := Label3D.new()
	m.font = _marker_font
	m.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	m.font_size = 200
	m.pixel_size = MARKER_PIXEL
	m.outline_size = 34
	m.outline_modulate = Color(0.18, 0.1, 0.0, 0.95)
	m.no_depth_test = true
	m.render_priority = 10
	m.outline_render_priority = 9
	m.double_sided = true
	m.visible = false
	paint_marker(m, kind)
	return m


## Shows kind ("!" yellow, "?" blue) on a marker, or hides it for "".
static func paint_marker(m: Label3D, kind: String) -> void:
	m.visible = kind != ""
	m.text = kind
	m.modulate = MARKER_YELLOW if kind == "!" else (MARKER_BLUE if kind == "?" else Color(0.85, 0.85, 0.85))


## Keeps a marker readable at any distance d (metres from the camera): real
## size up close, then a constant size on screen so far ones don't vanish.
static func fit_marker(m: Label3D, d: float) -> void:
	var far := d > MARKER_FAR
	m.fixed_size = far
	m.pixel_size = MARKER_PIXEL / MARKER_FAR if far else MARKER_PIXEL


## "!" (quest to offer), "?" (quest to hand in / talk to), "$" (shop) or "" (nothing).
func set_marker(kind: String) -> void:
	if kind == marker_kind:
		return
	marker_kind = kind
	paint_marker(marker, kind)


## Dialogue lines for a context key (original quest stage names, "default",
## "night", or quest-specific keys set in npcs.json).
func lines_for(stage: String) -> Array:
	var all: Dictionary = cfg.get("lines", {})
	if all.has(stage):
		return all[stage]
	if all.has("default"):
		var pool: Array = all["default"]
		# Ambient chatter: one or two lines, different each time.
		if pool.size() > 2:
			var i := rng.randi() % pool.size()
			return [pool[i]]
		return pool
	return all.get("intro", [])


## Freezes the villager facing the player while talking.
func set_talking(on: bool) -> void:
	talking = on


## Sends the villager to shelter (an attack on the town) or back to normal life.
func set_hiding(on: bool, spot := Vector3.INF) -> void:
	hiding = on
	hide_spot = spot
	path = []
	walking = false
	visible = true
	if _col:
		_col.set_deferred("disabled", false)


func _process(delta: float) -> void:
	if body == null:
		return
	if marker.visible:
		marker.position.y = MARKER_Y * body.scale.x + 0.12 * sin(Time.get_ticks_msec() * 0.004 + home.x)
	if lod > 0:
		# Far away: update a third as often, with three frames' worth of time.
		_lod_skip = (_lod_skip + 1) % 3
		if _lod_skip != 0:
			return
		delta *= 3.0
	if talking and player:
		var to := player.global_position - global_position
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), clampf(delta * 6.0, 0, 1))
		body.play("Idle_Talking", 0.3)
		return
	_routine_check -= delta
	if _routine_check <= 0.0:
		_routine_check = 1.0
		_follow_routine()
	if hiding:
		_hide_update(delta)
		return
	if role == "guard" and _guard_fight(delta):
		_stick_to_ground()
		return
	timer -= delta
	if walking:
		_walk(delta)
	else:
		_idle(delta)
	_stick_to_ground()


func _stick_to_ground() -> void:
	global_position.y = height_at.call(global_position.x, global_position.z)


func _idle(_delta: float) -> void:
	match mode:
		"work", "chat", "sit":
			var face: float = deg_to_rad(float(cfg.get("face", 0.0)))
			rotation.y = lerp_angle(rotation.y, face, 0.1)
			var anim: String = cfg.get("idle_anim", {"work": "Interact", "chat": "Idle_Talking", "sit": "Sitting_Idle"}[mode])
			body.play(anim, 0.4)
			# Workers step away from the bench now and then and come back.
			if mode == "work" and timer <= 0.0 and float(cfg.get("wander", 0.0)) > 0.2:
				_pick_wander()
		"visit":
			# Outside the tavern: chatting; at the church: a quiet prayer.
			body.play("Pray" if routine == "church" else "Idle_Talking", 0.4)
		"stroll":
			body.play(cfg.get("idle_anim", "Idle"), 0.3)
			if timer <= 0.0 and town:
				var dest: Vector3 = town.nodes[rng.randi() % town.nodes.size()]
				path = town.route(global_position, dest)
				walking = not path.is_empty()
				timer = rng.randf_range(4.0, 12.0)
		"patrol":
			body.play(cfg.get("idle_anim", "Idle"), 0.3)
			if timer <= 0.0:
				var pts: Array = cfg.get("route", [])
				if pts.size() > 0:
					patrol_i = (patrol_i + 1) % pts.size()
					var dest := Vector3(pts[patrol_i][0], 0, pts[patrol_i][1])
					path = town.route(global_position, dest) if town and cfg.get("streets", true) else [dest]
					path.append(dest)
					walking = true
		_:
			body.play(cfg.get("idle_anim", "Idle"), 0.3)
			if timer <= 0.0 and float(cfg.get("wander", 0.0)) > 0.2:
				_pick_wander()


func _pick_wander() -> void:
	var a := rng.randf() * TAU
	target = home + Vector3(cos(a), 0, sin(a)) * sqrt(rng.randf()) * float(cfg.get("wander", 0.0))
	path = [target, home] if mode == "work" else [target]
	walking = true


func _walk(delta: float) -> void:
	if path.is_empty():
		walking = false
		if routine == "home":
			set_hiding(true)   # at the door: indoors for the night
			return
		timer = rng.randf_range(3.0, 9.0) if mode != "patrol" else rng.randf_range(2.0, 5.0)
		return
	var goal: Vector3 = path[0]
	var to := goal - global_position
	to.y = 0
	if to.length() < 0.5:
		path.pop_front()
		return
	var speed: float = cfg.get("walk_speed", 1.0)
	global_position += to.normalized() * minf(speed * delta, to.length())
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), clampf(delta * 5.0, 0, 1))
	var anim: String = cfg.get("walk_anim", "Walk")
	if anim == "Walk_Formal":
		anim = "Walk"
	body.play(anim, 0.3, speed / _anim_speed(anim))


## Walks (briskly) to the shelter spot, then disappears indoors.
func _hide_update(delta: float) -> void:
	if hide_spot == Vector3.INF:
		_go_indoors()
		return
	var to := hide_spot - global_position
	to.y = 0
	if to.length() < 0.6:
		_go_indoors()
		return
	global_position += to.normalized() * minf(2.6 * delta, to.length())
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), clampf(delta * 6.0, 0, 1))
	body.play("Jog_Fwd", 0.2, 2.6 / 3.6)
	_stick_to_ground()


## Guards close in on monsters inside the town and strike at them. Returns
## true while busy fighting.
func _guard_fight(delta: float) -> bool:
	attack_cd -= delta
	if foe == null or not is_instance_valid(foe) or not foe.alive() or not foe.visible:
		foe = null
		var best := 18.0
		for c in get_tree().get_nodes_in_group("creatures"):
			if c.alive() and c.visible and c.is_hostile_to_player() and c.quest_tag.begins_with("raid"):
				var d: float = c.global_position.distance_to(global_position)
				if d < best:
					best = d
					foe = c
		if foe == null:
			return false
	var to := foe.global_position - global_position
	to.y = 0
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), clampf(delta * 8.0, 0, 1))
	var reach: float = 1.6 + foe.hit_radius()
	if to.length() > reach:
		global_position += to.normalized() * minf(3.2 * delta, to.length() - reach * 0.8)
		body.play("Jog_Fwd", 0.2, 3.2 / 3.6)
	elif attack_cd <= 0.0 and not body.busy():
		attack_cd = rng.randf_range(1.3, 2.0)
		body.play_once("Sword_Slash" + str(1 + rng.randi() % 2), 0.08, 1.0)
		get_tree().create_timer(0.3).timeout.connect(func() -> void:
			if is_instance_valid(foe) and foe.alive() and foe.global_position.distance_to(global_position) < reach + 0.6:
				foe.take_hit(float(cfg.get("guard_damage", 18.0)), global_position))
	elif not body.busy():
		body.play("Sword_Idle", 0.2)
	return true


static func _anim_speed(anim_name: String) -> float:
	match anim_name:
		"Jog_Fwd":
			return 3.6
		_:
			return 1.45


func _go_indoors() -> void:
	visible = false
	if _col:
		_col.set_deferred("disabled", true)   # no invisible body blocking the doorway


# ---------- Daily routine ----------

## What the clock asks of this person now ("" = their usual habit).
func wanted_routine() -> String:
	if role != "villager" or cfg.get("keep", false) or not _base_mode in ["stroll", "wander"] \
			or (marker and marker.visible) or doors.is_empty():
		return ""
	var h := fposmod(hour + _shift, 24.0)
	if h >= 21.5 or h < 6.0:
		return "home"
	if h >= 17.5 and _likes.tavern and places.has("tavern"):
		return "tavern"
	if h >= 7.5 and h < 9.5 and _likes.church and places.has("church"):
		return "church"
	return ""


func _follow_routine() -> void:
	if talking or (hiding and routine != "home"):
		return    # a quest or an attack has them; leave it be
	var want := wanted_routine()
	if want == routine:
		if want == "home" and not hiding and not walking:
			_walk_to(_home_door())   # someone brought them back out at night
		return
	var was := routine
	routine = want
	if was == "home" and hiding:
		# Morning: step out of the front door.
		var door := _home_door()
		set_hiding(false)
		global_position = Vector3(door.x, height_at.call(door.x, door.z), door.z)
	match want:
		"home":
			_walk_to(_home_door())
		"tavern", "church":
			var spot: Vector3 = places[want] + Vector3(_habit_rng.randf_range(-3.0, 3.0), 0, _habit_rng.randf_range(-1.5, 1.5))
			_walk_to(spot)
		_:
			mode = _base_mode
			_walk_to(home)


func _walk_to(spot: Vector3) -> void:
	if routine != "":
		mode = "visit"
	path = town.route(global_position, spot) if town else []
	path.append(spot)
	walking = true


func _home_door() -> Vector3:
	var best := Vector3.INF
	for d: Vector3 in doors:
		if best == Vector3.INF or d.distance_to(home) < best.distance_to(home):
			best = d
	return best
