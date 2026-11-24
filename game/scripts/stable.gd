class_name Stable
extends Node3D
## The riding horses (white, black and brown) at their hitching rail beside
## the meadow path near the spawn. Use the prompt next to a horse to climb on;
## use it again to get off. Horses stay where you leave them, and the save
## file remembers where that was. Data: data/horses.json.

var data: WorldData
var player: Player
var cfg: Dictionary = {}
var horses: Array[Horse] = []


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
		h.set_meta("start", entry)
		h.use_point.action = func(_n: Interactable) -> void: _use(h)
		horses.append(h)
		i += 1
	reset()


## Puts every horse back at the rail (new game).
func reset() -> void:
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
	elif player.horse == null and h.rider == null:
		player.mount(h)


## Where each horse is: {id: [x, z, yaw]}.
func save_state() -> Dictionary:
	var s := {}
	for h in horses:
		s[h.id] = [h.global_position.x, h.global_position.z, h.rotation.y]
	return s


## Restores horse positions from a save. A horse standing on the player
## (saved while riding) steps aside so you load in next to it.
func load_state(s: Dictionary) -> void:
	if player.horse:
		player.dismount()
	for h in horses:
		if s.has(h.id):
			var v: Array = s[h.id]
			_place(h, Vector2(v[0], v[1]), v[2])
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
