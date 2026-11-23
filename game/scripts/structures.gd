class_name Structures
extends RefCounted
## Builders for the island's man-made and strange places: camps, ruins, the
## ember temple, the sanctuary, shrines, caves, crystal formations, burrows,
## wagons, market stalls, the town gate and street furniture. Everything is
## assembled from primitives with the project's photo textures, and solid
## parts get box colliders so the explorer and villagers can't walk through.

const TEX := "res://assets/vendor/polyhaven/textures/"
const PH_MODELS := "res://assets/vendor/polyhaven/models/"
static var _mats := {}


static func tex_mat(name: String, tint := Color.WHITE, scale := 0.5, rough := 0.9) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [name, tint, scale]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.roughness = rough
	if ResourceLoader.exists(TEX + name + "/albedo.jpg"):
		m.albedo_texture = load(TEX + name + "/albedo.jpg")
		if ResourceLoader.exists(TEX + name + "/normal.jpg"):
			m.normal_enabled = true
			m.normal_texture = load(TEX + name + "/normal.jpg")
	_mats[key] = m
	return m


static func plain(c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var key := "plain|%s|%s|%s" % [c, rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_mats[key] = m
	return m


static func glow_mat(c: Color, energy := 2.5) -> StandardMaterial3D:
	var key := "glow|%s|%s" % [c, energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.2
	_mats[key] = m
	return m


static func stone() -> StandardMaterial3D:
	return tex_mat("castle_brick_07", Color(0.8, 0.8, 0.78), 0.6)


static func old_stone(tint := Color(0.72, 0.72, 0.68)) -> StandardMaterial3D:
	return tex_mat("mossy_rock", tint, 0.35)


static func wood(tint := Color(0.55, 0.42, 0.3)) -> StandardMaterial3D:
	return tex_mat("weathered_brown_planks", tint, 0.9)


static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO, solid := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	if solid:
		collider(parent, size, pos, rot)
	return mi


static func cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, rot := Vector3.ZERO, solid := false, sides := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = sides
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = maxf(r_top, r_bot)
		shape.height = h
		col.shape = shape
		body.add_child(col)
		body.position = pos
		body.rotation = rot
		parent.add_child(body)
	return mi


static func sphere(parent: Node3D, r: float, pos: Vector3, mat: Material, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	mi.mesh = s
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func prism(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var p := PrismMesh.new()
	p.size = size
	mi.mesh = p
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func collider(parent: Node3D, size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = pos
	body.rotation = rot
	parent.add_child(body)
	return body


static func label(parent: Node3D, text: String, pos: Vector3, size := 48, color := Color(1, 0.95, 0.85)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = 10
	l.position = pos
	parent.add_child(l)
	return l


## A polyhaven rock model (rock_face_01, boulder...) scaled and rotated, with a box collider.
static func rock(parent: Node3D, model: String, pos: Vector3, scl: float, yaw: float, tint := Color(0.85, 0.85, 0.85), solid_size := Vector3.ZERO) -> Node3D:
	var path := PH_MODELS + model + "/" + model + ".gltf"
	var n: Node3D
	if ResourceLoader.exists(path):
		n = load(path).instantiate()
	else:
		n = Node3D.new()
		sphere(n, 1.0, Vector3(0, 0.6, 0), old_stone(), Vector3(1.2, 0.8, 1.0))
	n.position = pos
	n.rotation.y = yaw
	n.scale = Vector3.ONE * scl
	parent.add_child(n)
	if solid_size != Vector3.ZERO:
		collider(parent, solid_size, pos + Vector3(0, solid_size.y * 0.5, 0), Vector3(0, yaw, 0))
	return n


static func flame_light(parent: Node3D, pos: Vector3, c := Color(1.0, 0.6, 0.25), energy := 1.6, rng := 9.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	l.position = pos
	parent.add_child(l)
	return l


# ---------- Camps ----------

## Tent: an A-frame of canvas. abandoned = slumped and torn.
static func tent(parent: Node3D, pos: Vector3, yaw: float, color: Color, abandoned := false) -> Node3D:
	var t := Node3D.new()
	t.position = pos
	t.rotation.y = yaw
	parent.add_child(t)
	var canvas := plain(color, 0.95)
	var lean := 0.0 if not abandoned else 0.35
	prism(t, Vector3(2.4, 1.6 - lean, 2.6), Vector3(0, 0.8 - lean * 0.5, 0), canvas, Vector3(0, 0, lean * 0.4))
	cyl(t, 0.03, 0.03, 1.7, Vector3(0, 0.85, 1.3), wood())
	if not abandoned:
		cyl(t, 0.03, 0.03, 1.7, Vector3(0, 0.85, -1.3), wood())
	collider(t, Vector3(2.2, 1.2, 2.5), Vector3(0, 0.6, 0))
	return t


static func campfire(parent: Node3D, pos: Vector3, lit := true) -> Node3D:
	var f := Node3D.new()
	f.position = pos
	parent.add_child(f)
	for i in 8:
		var a := TAU * i / 8.0
		sphere(f, 0.16, Vector3(cos(a) * 0.55, 0.08, sin(a) * 0.55), old_stone(Color(0.5, 0.5, 0.5)), Vector3(1, 0.7, 1))
	for i in 3:
		cyl(f, 0.06, 0.06, 0.9, Vector3(0, 0.12, 0), wood(Color(0.3, 0.22, 0.15)), Vector3(PI * 0.5, TAU * i / 3.0, 0.2))
	if lit:
		var flame := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.25
		cm.height = 0.6
		flame.mesh = cm
		flame.material_override = glow_mat(Color(1.0, 0.55, 0.15), 4.0)
		flame.position = Vector3(0, 0.4, 0)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.add_child(flame)
		flame_light(f, Vector3(0, 0.8, 0), Color(1.0, 0.6, 0.25), 1.8, 10.0)
	else:
		sphere(f, 0.35, Vector3(0, 0.02, 0), plain(Color(0.08, 0.07, 0.06), 1.0), Vector3(1, 0.15, 1))
	return f


static func crate(parent: Node3D, pos: Vector3, yaw := 0.0, s := 0.8, broken := false) -> MeshInstance3D:
	var c := box(parent, Vector3(s, s * (0.55 if broken else 1.0), s), pos + Vector3(0, s * (0.27 if broken else 0.5), 0), wood(Color(0.6, 0.46, 0.3)), Vector3(0.15 if broken else 0.0, yaw, 0), true)
	return c


static func barrel(parent: Node3D, pos: Vector3, tipped := false) -> MeshInstance3D:
	if tipped:
		return cyl(parent, 0.35, 0.35, 0.9, pos + Vector3(0, 0.35, 0), wood(Color(0.5, 0.36, 0.22)), Vector3(PI * 0.5, 0, 0.3), true, 12)
	return cyl(parent, 0.33, 0.37, 0.95, pos + Vector3(0, 0.47, 0), wood(Color(0.5, 0.36, 0.22)), Vector3.ZERO, true, 12)


static func bedroll(parent: Node3D, pos: Vector3, yaw: float, c: Color) -> void:
	box(parent, Vector3(0.7, 0.08, 1.8), pos + Vector3(0, 0.04, 0), plain(c, 1.0), Vector3(0, yaw, 0))


## Wagon with wheels; overturned lies on its side with cargo spilled.
static func wagon(parent: Node3D, pos: Vector3, yaw: float, overturned := false) -> Node3D:
	var w := Node3D.new()
	w.position = pos
	w.rotation.y = yaw
	parent.add_child(w)
	var body := Node3D.new()
	w.add_child(body)
	if overturned:
		body.rotation.z = PI * 0.5
		body.position = Vector3(0.6, 0.0, 0)
	box(body, Vector3(1.6, 0.12, 3.2), Vector3(0, 0.7, 0), wood())
	for sx in [-1.0, 1.0]:
		box(body, Vector3(0.08, 0.5, 3.2), Vector3(sx * 0.8, 0.98, 0), wood())
	box(body, Vector3(1.6, 0.5, 0.08), Vector3(0, 0.98, 1.6), wood())
	box(body, Vector3(1.6, 0.5, 0.08), Vector3(0, 0.98, -1.6), wood())
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			if overturned and sx > 0 and sz > 0:
				continue   # one wheel came off
			cyl(body, 0.45, 0.45, 0.1, Vector3(sx * 0.9, 0.45, sz * 1.1), wood(Color(0.35, 0.25, 0.15)), Vector3(0, 0, PI * 0.5), false, 14)
	collider(w, Vector3(1.8, 1.4, 3.3), Vector3(0.3 if overturned else 0.0, 0.7, 0))
	if overturned:
		cyl(w, 0.45, 0.45, 0.1, Vector3(-1.6, 0.05, 2.2), wood(Color(0.35, 0.25, 0.15)), Vector3(0, 0, 0.0), false, 14)
		crate(w, Vector3(-1.4, 0, -1.0), 0.6, 0.6, true)
		barrel(w, Vector3(-1.9, 0, 0.6), true)
	return w


# ---------- Stone and ruins ----------

static func pillar(parent: Node3D, pos: Vector3, h: float, r := 0.45, broken := false, mat: Material = null) -> void:
	var m := mat if mat else old_stone()
	box(parent, Vector3(r * 2.4, 0.35, r * 2.4), pos + Vector3(0, 0.17, 0), m)
	cyl(parent, r, r * 1.05, h, pos + Vector3(0, 0.35 + h * 0.5, 0), m, Vector3(0, 0, 0.04 if broken else 0.0), true, 12)
	if not broken:
		box(parent, Vector3(r * 2.5, 0.35, r * 2.5), pos + Vector3(0, 0.35 + h + 0.17, 0), m)


## Broken wall run from a to b (local), random heights.
static func ruin_wall(parent: Node3D, a: Vector3, b: Vector3, h: float, rng: RandomNumberGenerator, mat: Material = null) -> void:
	var m := mat if mat else old_stone()
	var d := b - a
	var n := maxi(1, int(d.length() / 1.6))
	var yaw := atan2(d.x, d.z)
	for i in n:
		var p := a + d * ((i + 0.5) / n)
		var hh := h * rng.randf_range(0.35, 1.0)
		box(parent, Vector3(0.7, hh, d.length() / n + 0.05), p + Vector3(0, hh * 0.5, 0), m, Vector3(0, yaw, 0), true)


## Square ruin with broken walls, fallen columns and a doorway facing +z.
static func ruin(parent: Node3D, pos: Vector3, yaw: float, size: float, seed_value: int, tint := Color(0.72, 0.72, 0.68)) -> Node3D:
	var r := Node3D.new()
	r.position = pos
	r.rotation.y = yaw
	parent.add_child(r)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var m := old_stone(tint)
	var s := size * 0.5
	box(r, Vector3(size + 1.0, 0.4, size + 1.0), Vector3(0, 0.2, 0), m)
	ruin_wall(r, Vector3(-s, 0.4, -s), Vector3(s, 0.4, -s), 3.5, rng, m)
	ruin_wall(r, Vector3(-s, 0.4, -s), Vector3(-s, 0.4, s), 3.0, rng, m)
	ruin_wall(r, Vector3(s, 0.4, -s), Vector3(s, 0.4, s), 2.5, rng, m)
	ruin_wall(r, Vector3(-s, 0.4, s), Vector3(-1.5, 0.4, s), 2.8, rng, m)
	ruin_wall(r, Vector3(1.5, 0.4, s), Vector3(s, 0.4, s), 2.2, rng, m)
	for i in 3:
		var a := rng.randf() * TAU
		cyl(r, 0.4, 0.42, rng.randf_range(2.0, 3.5), Vector3(rng.randf_range(-s, s) * 0.6, 0.75, rng.randf_range(-s, s) * 0.6), m, Vector3(PI * 0.5, a, 0), true, 10)
	return r


## Stone tablet with carved writing (an inspect target stands in front of it).
static func tablet(parent: Node3D, pos: Vector3, yaw: float, glow := Color(0, 0, 0)) -> Node3D:
	var t := Node3D.new()
	t.position = pos
	t.rotation.y = yaw
	parent.add_child(t)
	box(t, Vector3(1.4, 1.9, 0.35), Vector3(0, 0.95, 0), old_stone(Color(0.6, 0.6, 0.58)), Vector3.ZERO, true)
	if glow != Color(0, 0, 0):
		for i in 4:
			box(t, Vector3(0.9 - i * 0.12, 0.05, 0.02), Vector3(0, 1.5 - i * 0.25, 0.18), glow_mat(glow, 2.0))
	return t


static func standing_stone(parent: Node3D, pos: Vector3, h: float, yaw: float) -> void:
	box(parent, Vector3(0.9, h, 0.55), pos + Vector3(0, h * 0.5 - 0.2, 0), old_stone(Color(0.65, 0.66, 0.62)), Vector3(0.05, yaw, 0.04), true)


# ---------- Crystals, burrows, glowing things ----------

static func crystal_cluster(parent: Node3D, pos: Vector3, color: Color, n: int, height: float, seed_value: int, energy := 2.5) -> Node3D:
	var c := Node3D.new()
	c.position = pos
	parent.add_child(c)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var m := glow_mat(color, energy)
	for i in n:
		var h := height * rng.randf_range(0.4, 1.0)
		var a := rng.randf() * TAU
		var off := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, height * 0.35)
		var mi := cyl(c, 0.0, h * 0.13, h, off + Vector3(0, h * 0.45, 0), m, Vector3(rng.randf_range(-0.35, 0.35), rng.randf() * TAU, rng.randf_range(-0.35, 0.35)), false, 6)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	collider(c, Vector3(height * 0.5, height * 0.8, height * 0.5), Vector3(0, height * 0.4, 0))
	var l := flame_light(c, Vector3(0, height * 0.7, 0), color, 1.2, height * 3.0)
	l.name = "Light"
	return c


static func burrow(parent: Node3D, pos: Vector3, r := 1.3) -> void:
	sphere(parent, r, pos + Vector3(0, 0.05, 0), plain(Color(0.02, 0.02, 0.025), 1.0), Vector3(1, 0.05, 1))
	for i in 10:
		var a := TAU * i / 10.0
		sphere(parent, r * 0.35, pos + Vector3(cos(a) * r * 1.05, 0.05, sin(a) * r * 1.05), tex_mat("dirt_floor", Color(0.4, 0.35, 0.3), 1.0), Vector3(1.0, 0.45, 1.0))


static func footprints(parent: Node3D, from: Vector3, to: Vector3, height_at: Callable) -> void:
	var d := to - from
	var n := int(d.length() / 0.9)
	var yaw := atan2(d.x, d.z)
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	var m := plain(Color(0.12, 0.1, 0.08, 1.0), 1.0)
	for i in n:
		var p := from + d * (float(i) / n) + side * (0.15 if i % 2 == 0 else -0.15)
		p.y = height_at.call(p.x, p.z) + 0.03
		box(parent, Vector3(0.14, 0.02, 0.3), p, m, Vector3(0, yaw, 0))


# ---------- Town furniture ----------

static func lamp_post(parent: Node3D, pos: Vector3, lit_mat: Material) -> void:
	cyl(parent, 0.06, 0.08, 3.2, pos + Vector3(0, 1.6, 0), plain(Color(0.12, 0.12, 0.13), 0.6, 0.6), Vector3.ZERO, true, 8)
	box(parent, Vector3(0.5, 0.06, 0.06), pos + Vector3(0.2, 3.15, 0), plain(Color(0.12, 0.12, 0.13), 0.6, 0.6))
	var lan := box(parent, Vector3(0.26, 0.34, 0.26), pos + Vector3(0.42, 2.95, 0), lit_mat)
	lan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func market_stall(parent: Node3D, pos: Vector3, yaw: float, awning: Color, goods: Array) -> Node3D:
	var s := Node3D.new()
	s.position = pos
	s.rotation.y = yaw
	parent.add_child(s)
	box(s, Vector3(2.6, 0.9, 1.0), Vector3(0, 0.45, 0), wood(Color(0.62, 0.48, 0.32)), Vector3.ZERO, true)
	for sx in [-1.25, 1.25]:
		for sz in [-0.9, 0.45]:
			cyl(s, 0.05, 0.05, 2.4, Vector3(sx, 1.2, sz), wood())
	box(s, Vector3(2.9, 0.05, 1.8), Vector3(0, 2.45, -0.2), plain(awning, 0.9), Vector3(-0.18, 0, 0))
	# Goods on the counter.
	for i in goods.size():
		var x := -0.9 + i * 0.6
		var g: Color = goods[i]
		sphere(s, 0.13, Vector3(x, 0.98, 0.05), plain(g, 0.7), Vector3(1.3, 0.6, 1.0))
		sphere(s, 0.1, Vector3(x + 0.15, 1.0, -0.15), plain(g.darkened(0.15), 0.7))
	return s


static func well(parent: Node3D, pos: Vector3) -> void:
	cyl(parent, 1.1, 1.2, 0.9, pos + Vector3(0, 0.45, 0), stone(), Vector3.ZERO, true, 20)
	cyl(parent, 0.95, 0.95, 0.05, pos + Vector3(0, 0.75, 0), plain(Color(0.1, 0.2, 0.25), 0.05, 0.2), Vector3.ZERO, false, 20)
	for sx in [-1.0, 1.0]:
		cyl(parent, 0.07, 0.07, 2.2, pos + Vector3(sx * 0.95, 1.5, 0), wood())
	box(parent, Vector3(2.4, 0.1, 1.2), pos + Vector3(0, 2.65, 0), tex_mat("clay_roof_tiles_02", Color(0.8, 0.7, 0.65), 0.6), Vector3(0, 0, 0))
	cyl(parent, 0.08, 0.08, 1.9, pos + Vector3(0, 2.1, 0), wood(), Vector3(0, 0, PI * 0.5))


static func bench(parent: Node3D, pos: Vector3, yaw: float) -> void:
	box(parent, Vector3(1.8, 0.08, 0.45), pos + Vector3(0, 0.45, 0), wood(Color(0.58, 0.45, 0.32)), Vector3(0, yaw, 0))
	for sx in [-0.75, 0.75]:
		box(parent, Vector3(0.1, 0.45, 0.4), pos + Basis(Vector3.UP, yaw) * Vector3(sx, 0.22, 0), wood(), Vector3(0, yaw, 0))
	collider(parent, Vector3(1.8, 0.5, 0.45), pos + Vector3(0, 0.25, 0), Vector3(0, yaw, 0))


static func table_set(parent: Node3D, pos: Vector3, yaw: float) -> void:
	box(parent, Vector3(1.6, 0.08, 0.9), pos + Vector3(0, 0.78, 0), wood(Color(0.55, 0.42, 0.3)), Vector3(0, yaw, 0))
	cyl(parent, 0.1, 0.12, 0.75, pos + Vector3(0, 0.38, 0), wood(), Vector3.ZERO, true)
	for sz in [-0.75, 0.75]:
		bench(parent, pos + Basis(Vector3.UP, yaw) * Vector3(0, 0, sz), yaw)
	cyl(parent, 0.07, 0.06, 0.16, pos + Vector3(0.3, 0.9, 0.1), plain(Color(0.75, 0.6, 0.35), 0.4))


static func notice_board(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = yaw
	parent.add_child(n)
	for sx in [-0.8, 0.8]:
		cyl(n, 0.07, 0.07, 2.4, Vector3(sx, 1.2, 0), wood())
	box(n, Vector3(1.9, 1.2, 0.08), Vector3(0, 1.6, 0), wood(Color(0.62, 0.5, 0.36)), Vector3.ZERO, true)
	var papers := [Color(0.95, 0.92, 0.82), Color(0.9, 0.86, 0.7), Color(0.98, 0.95, 0.88)]
	for i in 5:
		box(n, Vector3(0.36, 0.45, 0.01), Vector3(-0.65 + i * 0.33, 1.6 + (0.18 if i % 2 == 0 else -0.15), 0.05), plain(papers[i % 3], 1.0), Vector3(0, 0, 0.06 * (i - 2)))
	box(n, Vector3(2.1, 0.12, 0.4), Vector3(0, 2.3, 0), tex_mat("clay_roof_tiles_02", Color(0.8, 0.7, 0.65), 0.6))
	label(n, "CONTRACTS", Vector3(0, 2.55, 0.05), 40)
	return n


static func fence(parent: Node3D, a: Vector3, b: Vector3, height_at: Callable) -> void:
	var d := b - a
	var n := maxi(1, int(d.length() / 2.0))
	var yaw := atan2(d.x, d.z)
	for i in n + 1:
		var p := a + d * (float(i) / n)
		p.y = height_at.call(p.x, p.z)
		cyl(parent, 0.06, 0.07, 1.1, p + Vector3(0, 0.55, 0), wood(), Vector3.ZERO, false, 6)
		if i < n:
			var q := a + d * ((i + 0.5) / n)
			q.y = height_at.call(q.x, q.z)
			for hy in [0.45, 0.85]:
				box(parent, Vector3(0.05, 0.08, d.length() / n), q + Vector3(0, hy, 0), wood(), Vector3(0, yaw, 0))


static func hay(parent: Node3D, pos: Vector3, yaw: float) -> void:
	cyl(parent, 0.55, 0.55, 1.1, pos + Vector3(0, 0.55, 0), plain(Color(0.78, 0.66, 0.35), 1.0), Vector3(PI * 0.5, yaw, 0), true, 14)


## The town's east gate: two stone towers joined by a timber arch, with a palisade.
static func gate(parent: Node3D, pos: Vector3, yaw: float, height_at: Callable, lit_mat: Material) -> Node3D:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = yaw
	parent.add_child(g)
	for sz in [-1.0, 1.0]:
		var tp := Vector3(0, 0, sz * 4.2)
		box(g, Vector3(3.0, 7.5, 3.0), tp + Vector3(0, 3.5, 0), stone(), Vector3.ZERO, true)
		box(g, Vector3(3.4, 0.4, 3.4), tp + Vector3(0, 7.4, 0), stone())
		for k in 4:
			var a := TAU * k / 4.0 + PI * 0.25
			box(g, Vector3(0.6, 0.7, 0.6), tp + Vector3(cos(a) * 1.4, 7.9, sin(a) * 1.4), stone())
		var lan := box(g, Vector3(0.3, 0.4, 0.3), tp + Vector3(1.65, 3.2, -sz * 0.9), lit_mat)
		lan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	box(g, Vector3(1.0, 1.0, 5.6), Vector3(0, 6.2, 0), wood(Color(0.45, 0.33, 0.22)))
	var sign_l := label(g, "BRICKTON", Vector3(0.55, 6.2, 0), 90)
	sign_l.rotation.y = PI * 0.5
	var sign_r := label(g, "BRICKTON", Vector3(-0.55, 6.2, 0), 90)
	sign_r.rotation.y = -PI * 0.5
	# Palisade runs out from each tower.
	for sz in [-1.0, 1.0]:
		for i in 9:
			var lp := Vector3(0, 0, sz * (6.2 + i * 0.9))
			var wp := g.global_transform * lp if g.is_inside_tree() else pos + Basis(Vector3.UP, yaw) * lp
			var hgt: float = height_at.call(wp.x, wp.z) - pos.y
			cyl(g, 0.22, 0.24, 3.6, lp + Vector3(0, hgt + 1.6, 0), wood(Color(0.42, 0.32, 0.22)), Vector3.ZERO, false, 8)
		collider(g, Vector3(0.6, 3.4, 8.5), Vector3(0, 1.6, sz * 9.9))
	return g


## Rock arch / cave mouth from rock models (falls back to boulders).
static func cave(parent: Node3D, pos: Vector3, yaw: float, tint := Color(0.75, 0.78, 0.85)) -> Node3D:
	var c := Node3D.new()
	c.position = pos
	c.rotation.y = yaw
	parent.add_child(c)
	rock(c, "rock_face_01", Vector3(-3.4, -0.4, -1.0), 2.2, PI * 0.5, tint, Vector3(2.5, 5.0, 7.0))
	rock(c, "rock_face_02", Vector3(3.4, -0.4, -1.0), 2.2, -PI * 0.5, tint, Vector3(2.5, 5.0, 7.0))
	rock(c, "rock_face_01", Vector3(0, -0.4, -5.5), 2.4, 0.0, tint, Vector3(8.0, 5.5, 2.0))
	# Roof slab: makes it a cave.
	box(c, Vector3(9.5, 1.4, 8.5), Vector3(0, 4.6, -1.8), tex_mat("rock_face_03", tint, 0.35), Vector3(0.05, 0, 0.03), true)
	sphere(c, 3.0, Vector3(0, 5.2, -2.0), tex_mat("rock_face_03", tint, 0.35), Vector3(1.8, 0.7, 1.6))
	return c


## A wooden hut or lodge (single room with a pitched roof and a door facing +z).
static func hut(parent: Node3D, pos: Vector3, yaw: float, w: float, d: float, roof: Color) -> Node3D:
	var h := Node3D.new()
	h.position = pos
	h.rotation.y = yaw
	parent.add_child(h)
	box(h, Vector3(w + 0.3, 0.5, d + 0.3), Vector3(0, 0.0, 0), stone())
	box(h, Vector3(w, 2.6, d), Vector3(0, 1.55, 0), wood(Color(0.55, 0.42, 0.3)), Vector3.ZERO, true)
	for sx in [-1.0, 1.0]:
		box(h, Vector3(w * 0.62, 0.15, d + 0.8), Vector3(sx * w * 0.27, 3.25, 0), plain(roof, 0.9), Vector3(0, 0, -sx * 0.6))
	box(h, Vector3(1.0, 1.9, 0.08), Vector3(0, 1.2, d * 0.5 + 0.02), wood(Color(0.35, 0.25, 0.18)))
	box(h, Vector3(0.7, 0.6, 0.06), Vector3(w * 0.3, 1.7, d * 0.5 + 0.02), glow_mat(Color(1.0, 0.75, 0.4), 0.8))
	return h
