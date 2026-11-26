class_name Stable
extends Node3D
## The riding horses (white, black and brown) at their hitching rail beside
## the meadow path near the spawn. Use the prompt next to a horse to climb on;
## use it again to get off. Horses stay where you leave them, and the save
## file remembers where that was. Data: data/horses.json.
##
## Your horse is the white one until you ride another; whistle (T, or the
## horseshoe button) and it finds its way to you round buildings, cliffs and
## lava (HorseNav). Horses never wander into lava, and one left standing in it
## (an old save, or a dismount in the crater) is led out to the nearest safe
## ground it can walk home from.

var data: WorldData
var player: Player
var cfg: Dictionary = {}
var horses: Array[Horse] = []
## Id of the player's own horse (answers the whistle).
var owned_id := "white"
var nav: HorseNav
## How far a whistle carries (metres).
var whistle_range := 600.0
## Short messages for the HUD (wired by the world).
var notify: Callable = Callable()
## Sound effects (wired by the world): name, volume dB.
var play_sfx: Callable = Callable()
## Where horses are led when a rescue finds no open ground nearby: the rail.
var _rail_spot := Vector2(7.0, 35.0)


## Builds the rail and the horses, and wires mounting to the player.
func setup(world_data: WorldData, p: Player) -> void:
	data = world_data
	player = p
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/horses.json"))
	player.ride = cfg.get("ride", {})
	_build_rail()
	var i := 0
	for entry: Dictionary in cfg.horses:
		var h := Horse.new()
		add_child(h)
		h.setup_horse(entry, cfg.gait, cfg.ride, 4242 + i * 31)
		h.height_at = func(x: float, z: float) -> float: return data.height(x, z)
		h.avoid_at = func(x: float, z: float) -> bool: return data.is_lava(x, z)
		h.on_arrived = _arrived
		h.set_meta("start", entry)
		h.use_point.action = func(_n: Interactable) -> void: _use(h)
		horses.append(h)
		i += 1
	reset()


## Puts every horse back at the rail (new game).
func reset() -> void:
	owned_id = "white"
	if player.horse:
		player.dismount()
	for h in horses:
		var e: Dictionary = h.get_meta("start")
		_place(h, Vector2(e.pos[0], e.pos[1]), deg_to_rad(float(e.get("yaw", 0.0))))


func _place(h: Horse, at: Vector2, yaw: float) -> void:
	h.global_position = Vector3(at.x, data.height(at.x, at.y), at.y)
	h.rotation.y = yaw
	h.home = h.global_position
	h.set_ridden(null)


func _use(h: Horse) -> void:
	if player.dead or player.in_conversation:
		return
	if player.horse == h:
		player.dismount()
		if data.is_lava(h.global_position.x, h.global_position.z):
			lead_out(h)
	elif player.horse == null and h.rider == null:
		player.mount(h)
		owned_id = h.id


## The player's own horse.
func owned() -> Horse:
	for h in horses:
		if h.id == owned_id:
			return h
	return horses[0] if not horses.is_empty() else null


func _ensure_nav() -> void:
	if nav == null:
		nav = HorseNav.new(data)
	if not nav.built:
		nav.build(get_parent())


## Answers the player's whistle. Returns what happened: "coming", "here",
## "riding", "too_far", "near" (comes as close as it can), "no_way" or "none".
func whistle() -> String:
	if play_sfx.is_valid():
		play_sfx.call("whistle", -3.0)
	var h := owned()
	if h == null:
		return "none"
	if player.horse != null:
		_say("You're already riding.")
		return "riding"
	var me := Vector2(player.global_position.x, player.global_position.z)
	var at := Vector2(h.global_position.x, h.global_position.z)
	if me.distance_to(at) < 4.0:
		_say("Your %s is right here." % h.horse_name)
		return "here"
	if me.distance_to(at) > whistle_range:
		_say("Your %s is too far away to hear you (%d m). Find it on the map." % [h.horse_name, int(me.distance_to(at))])
		return "too_far"
	_ensure_nav()
	var route := nav.path(at, me)
	var stuck := route.size() < 2
	if stuck:
		# No way all the way here: come as close as it safely can and wait there.
		route = nav.path(at, me, true)
		if route.size() < 2:
			_say("Your %s can't find a way to you here. Try open ground." % h.horse_name)
			return "no_way"
	h.summon(route, player)
	if play_sfx.is_valid():
		play_sfx.call("horse_whinny", -4.0)
	if stuck:
		_say("Your %s can't reach you here. It will wait on safe ground %d m away." % [h.horse_name, int(route[route.size() - 1].distance_to(me))])
		return "near"
	_say("Your %s heard you and is on its way (%d m)." % [h.horse_name, int(_length(route))])
	return "coming"


func _arrived(h: Horse) -> void:
	if h.caller == player:
		var gap := Vector2(h.global_position.x - player.global_position.x, h.global_position.z - player.global_position.z).length()
		_say("Your %s is here." % h.horse_name if gap < 8.0 else "Your %s is waiting for you %d m away." % [h.horse_name, int(gap)])
	h.caller = null


## Leads a horse standing in lava (or anywhere it can't stand) out to the
## nearest open ground. Keeps the same horse: name, owner and everything else.
func lead_out(h: Horse) -> Vector2:
	_ensure_nav()
	var at := Vector2(h.global_position.x, h.global_position.z)
	var safe := nav.nearest_open(at)
	# Only accept ground that connects back to the meadow (not an island in the crater).
	if safe == Vector2.INF or nav.path(safe, _rail_spot).size() < 2:
		safe = nav.nearest_open(_rail_spot)
	_place(h, safe, h.rotation.y)
	return safe


func _say(t: String) -> void:
	if notify.is_valid():
		notify.call(t)


static func _length(route: PackedVector2Array) -> float:
	var d := 0.0
	for i in route.size() - 1:
		d += route[i].distance_to(route[i + 1])
	return d


## Where each horse is: {id: [x, z, yaw]}, and "owned": the player's horse id.
func save_state() -> Dictionary:
	var s := {}
	for h in horses:
		s[h.id] = [h.global_position.x, h.global_position.z, h.rotation.y]
	s["owned"] = owned_id
	return s


## Restores horse positions from a save. A horse standing on the player
## (saved while riding) steps aside so you load in next to it.
func load_state(s: Dictionary) -> void:
	if player.horse:
		player.dismount()
	owned_id = str(s.get("owned", "white"))
	for h in horses:
		if s.has(h.id):
			var v: Array = s[h.id]
			_place(h, Vector2(v[0], v[1]), v[2])
			# Saved standing in lava (it used to be able to wander in): lead it out.
			if data.is_lava(v[0], v[1]):
				var safe := lead_out(h)
				_say("Your %s was stuck in the lava. It has been led out to safe ground (%d, %d)." % [h.horse_name, int(safe.x), int(safe.y)])
				continue
			var to := h.global_position - player.global_position
			to.y = 0.0
			if to.length() < 1.6:
				var side := Vector3(cos(h.rotation.y), 0, -sin(h.rotation.y))
				var spot := player.global_position + side * 2.4
				_place(h, Vector2(spot.x, spot.z), v[2])


## A wooden hitching rail: two posts and a crossbar.
func _build_rail() -> void:
	var r: Array = cfg.get("rail", [])
	if r.size() != 2:
		return
	var a := Vector3(r[0][0], 0, r[0][1])
	var b := Vector3(r[1][0], 0, r[1][1])
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.25, 0.15)
	wood.roughness = 0.9
	var top := -INF
	for p in [a, b]:
		top = maxf(top, data.height(p.x, p.z))
	for p in [a, b, (a + b) * 0.5]:
		var ground := data.height(p.x, p.z)
		var post := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.07
		cm.bottom_radius = 0.08
		cm.height = top + 1.15 - ground + 0.2
		post.mesh = cm
		post.material_override = wood
		add_child(post)
		post.global_position = Vector3(p.x, ground - 0.2 + cm.height * 0.5, p.z)
	var bar := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.055
	bm.bottom_radius = 0.055
	bm.height = a.distance_to(b) + 0.2
	bar.mesh = bm
	bar.material_override = wood
	add_child(bar)
	bar.global_position = (a + b) * 0.5 + Vector3(0, top + 1.05, 0)
	bar.basis = Basis.looking_at((b - a).normalized(), Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
	# A solid rail so you walk around it, not through it.
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 1.2, a.distance_to(b))
	col.shape = box
	body.add_child(col)
	add_child(body)
	body.global_position = (a + b) * 0.5 + Vector3(0, top + 0.5, 0)
	body.basis = Basis.looking_at((b - a).normalized(), Vector3.UP)
