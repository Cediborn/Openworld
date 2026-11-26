class_name Water
extends Node3D
## Reusable water: rivers and streams that follow a bed line, waterfalls,
## ponds and lakes (optionally frozen), with sound, mist and splashes.
## Built from a description (a JSON file per place) plus a ground-height
## function, so the surface always sits on the real terrain: each vertex
## measures its own depth and the shader shades shallows, foam and shore
## from it (no screen-space reads, so it is cheap on phones).
##
## The player wades (Player.water_depth, set from depth_at()) and splashes on
## entering; footsteps in water use the "water" step sounds.

## Ground height at (x, z) in this node's space.
var height_at: Callable
## Every water body in the scene, for depth_at().
static var bodies: Array = []

const MAT_PATH := "res://shaders/spatial_env_water.gdshader"


## Builds everything listed in `desc` ({"rivers": [...], "falls": [...], "lakes": [...]}).
func build(desc: Dictionary, ground: Callable, mobile := false) -> void:
	height_at = ground
	for r in desc.get("rivers", []):
		add_river(r, mobile)
	for f in desc.get("falls", []):
		add_fall(f, mobile)
	for l in desc.get("lakes", []):
		add_lake(l, mobile)


func _exit_tree() -> void:
	bodies = bodies.filter(func(b): return b.node != self)


# ---------- Rivers and streams ----------

## r: {"points": [[x, z, bed_y], ...], "width": m, "depth": m, "murk": 0..1, "speed": m/s, "rapids": [index, ...]}
## The surface is a ribbon `depth` above the bed line, as wide as `width`.
func add_river(r: Dictionary, mobile := false) -> void:
	var pts := _points(r.points)
	var width: float = r.get("width", 4.0)
	var depth: float = r.get("depth", 0.5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	var across := 7 if not mobile else 5
	var rows := []
	var dense := _resample(pts, 1.5)
	for i in dense.size():
		var p: Vector3 = dense[i]
		var fwd: Vector3 = (dense[mini(i + 1, dense.size() - 1)] - dense[maxi(i - 1, 0)]) * Vector3(1, 0, 1)
		fwd = fwd.normalized() if fwd.length() > 0.001 else Vector3.FORWARD
		var side := Vector3(fwd.z, 0, -fwd.x)
		if i > 0:
			along += (dense[i] - dense[i - 1]).length()
		var row := []
		for k in across:
			var u := float(k) / (across - 1) - 0.5
			var v := p + side * u * width
			var surface := p.y + depth
			var g: float = height_at.call(v.x, v.z)
			# Edges ride up the bank a little so there is never a gap at the shore.
			var y := maxf(surface, minf(g + 0.03, surface + 0.12)) if absf(u) > 0.45 else surface
			row.append([Vector3(v.x, y, v.z), Vector2(u * width, along), clampf((surface - g) / 4.0, 0.0, 1.0)])
		rows.append(row)
	var turb := _turbulence(r, dense, pts)
	for i in rows.size() - 1:
		for k in across - 1:
			var quad := [rows[i][k], rows[i][k + 1], rows[i + 1][k + 1], rows[i + 1][k]]
			var tb := [turb[i], turb[i], turb[i + 1], turb[i + 1]]
			for idx in [0, 1, 2, 0, 2, 3]:
				var q: Array = quad[idx]
				st.set_color(Color(q[2], tb[idx], 0.0))
				st.set_uv(q[1])
				st.set_normal(Vector3.UP)
				st.add_vertex(q[0])
	var mi := _mesh(st, {"flow_speed": 0.0 if r.get("frozen", false) else r.get("speed", 0.8), "murk": r.get("murk", 0.0), "clarity": 1.2,
		"frozen": r.get("frozen", false), "glow": r.get("glow", 0.0)})
	bodies.append({"node": self, "kind": "river", "points": dense, "width": width, "depth": depth})
	if r.get("sound", true):
		_sound_along(dense, "stream", -12.0 if width < 6.0 else -8.0)
	add_child(mi)


func _turbulence(r: Dictionary, dense: Array, pts: Array) -> Array:
	var out := []
	for p in dense:
		var t := 0.0
		for idx in r.get("rapids", []):
			var c: Vector3 = pts[int(idx)]
			t = maxf(t, 1.0 - clampf(Vector2(p.x - c.x, p.z - c.z).length() / 9.0, 0.0, 1.0))
		out.append(t)
	return out


# ---------- Waterfalls ----------

## f: {"top": [x, y, z], "bottom": [x, y, z], "width": m, "frozen": bool}
## A sheet from the lip to the pool, bowed outward, with mist and a roar.
func add_fall(f: Dictionary, mobile := false) -> void:
	var top := Vector3(f.top[0], f.top[1], f.top[2])
	var bottom := Vector3(f.bottom[0], f.bottom[1], f.bottom[2])
	var width: float = f.get("width", 3.0)
	var frozen: bool = f.get("frozen", false)
	var fwd := (bottom - top) * Vector3(1, 0, 1)
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var side := Vector3(fwd.z, 0, -fwd.x)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 10
	var cols := 5
	var drop := top.y - bottom.y
	var grid := []
	for j in rows + 1:
		var t := float(j) / rows
		# Water leaves the lip forward, then falls (a gentle parabola), spreading a little.
		var p := top.lerp(bottom, t)
		p += fwd * sin(t * PI * 0.6) * minf(drop * 0.12, 1.5)
		var row := []
		for k in cols + 1:
			var u := float(k) / cols - 0.5
			row.append([p + side * u * width * (1.0 + t * 0.25), Vector2(u * width, t * drop)])
		grid.append(row)
	for j in rows:
		for k in cols:
			var quad := [grid[j][k], grid[j][k + 1], grid[j + 1][k + 1], grid[j + 1][k]]
			for idx in [0, 1, 2, 0, 2, 3]:
				var q: Array = quad[idx]
				st.set_color(Color(0.5, 1.0, 0.0))
				st.set_uv(q[1])
				st.set_normal(fwd)
				st.add_vertex(q[0])
	add_child(_mesh(st, {"falling": not frozen, "frozen": frozen, "flow_speed": 0.0 if frozen else 2.6}))
	if frozen:
		return
	# Mist and spray where it lands; fewer particles on phones.
	var mist := GPUParticles3D.new()
	mist.amount = 24 if mobile else 60
	mist.lifetime = 2.6
	mist.position = bottom + Vector3(0, 0.4, 0)
	mist.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 10, 16))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(width * 0.6, 0.3, 1.2)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0, 0.15, 0)
	pm.scale_min = 1.5
	pm.scale_max = 3.5
	pm.color = Color(1, 1, 1, 0.22)
	mist.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2)
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.vertex_color_use_as_albedo = true
	mm.albedo_texture = _puff()
	quad.material = mm
	mist.draw_pass_1 = quad
	add_child(mist)
	var snd := AudioStreamPlayer3D.new()
	snd.stream = _loop("waterfall")
	snd.position = bottom + Vector3(0, 1, 0)
	snd.unit_size = 6.0 + drop
	snd.max_distance = 60.0 + drop * 4.0
	snd.volume_db = -6.0
	snd.bus = "Ambience" if AudioServer.get_bus_index("Ambience") != -1 else "Master"
	snd.autoplay = true
	add_child(snd)
	bodies.append({"node": self, "kind": "lake", "center": bottom, "radius": width * 0.8, "level": bottom.y + 0.6})


# ---------- Lakes and ponds ----------

## l: {"center": [x, z], "radius": m, "level": y, "frozen": bool, "murk": 0..1}
## A disc at `level`, wide enough to meet the shore all round; the shore is
## wherever the ground rises above the water.
func add_lake(l: Dictionary, mobile := false) -> void:
	var c := Vector3(l.center[0], 0, l.center[1])
	var radius: float = l.radius
	var level: float = l.level
	var rings := 10 if not mobile else 7
	var segs := 40 if not mobile else 28
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := []
	for i in rings + 1:
		var row := []
		for s in segs:
			var a := TAU * s / segs
			var r := radius * 1.25 * float(i) / rings
			var p := c + Vector3(cos(a), 0, sin(a)) * r
			var g: float = height_at.call(p.x, p.z)
			row.append([Vector3(p.x, level, p.z), Vector2(p.x, p.z), clampf((level - g) / 4.0, 0.0, 1.0), g < level + 0.2])
		pts.append(row)
	for i in rings:
		for s in segs:
			var s2 := (s + 1) % segs
			var quad := [pts[i][s], pts[i][s2], pts[i + 1][s2], pts[i + 1][s]]
			if not (quad[0][3] or quad[1][3] or quad[2][3] or quad[3][3]):
				continue   # dry land all round: no water here
			for idx in [0, 2, 1, 0, 3, 2]:
				var q: Array = quad[idx]
				st.set_color(Color(q[2], 0.0, 0.0))
				st.set_uv(q[1])
				st.set_normal(Vector3.UP)
				st.add_vertex(q[0])
	var frozen: bool = l.get("frozen", false)
	var mi := _mesh(st, {"flow_speed": 0.0, "frozen": frozen, "murk": l.get("murk", 0.0), "clarity": l.get("clarity", 2.5), "glow": l.get("glow", 0.0)})
	add_child(mi)
	if frozen:
		# Ice holds you up: the frozen surface is solid ground.
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = mi.mesh.create_trimesh_shape()
		body.add_child(cs)
		body.set_meta("walkable", true)
		add_child(body)
	else:
		bodies.append({"node": self, "kind": "lake", "center": c, "radius": radius * 1.25, "level": level})


# ---------- Queries ----------

## How deep the water is at a world position (0 on dry land). Frozen water is ground.
static func depth_at(pos: Vector3) -> float:
	var best := 0.0
	for b in bodies:
		if not is_instance_valid(b.node):
			continue
		var local: Vector3 = b.node.to_local(pos)
		match b.kind:
			"lake":
				if Vector2(local.x - b.center.x, local.z - b.center.z).length() < b.radius:
					best = maxf(best, b.level - local.y)
			"river":
				var pts: Array = b.points
				for i in pts.size() - 1:
					var a: Vector3 = pts[i]
					var c: Vector3 = pts[i + 1]
					var ab := Vector2(c.x - a.x, c.z - a.z)
					var t := clampf(Vector2(local.x - a.x, local.z - a.z).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
					var q := Vector2(a.x, a.z) + ab * t
					if q.distance_to(Vector2(local.x, local.z)) < b.width * 0.5:
						best = maxf(best, lerpf(a.y, c.y, t) + b.depth - local.y)
	return maxf(best, 0.0)


# ---------- Helpers ----------

func _points(src: Array) -> Array:
	var out := []
	for p in src:
		out.append(Vector3(p[0], p[2], p[1]))
	return out


## Even spacing along the line (and its bed heights), for a smooth ribbon.
func _resample(pts: Array, step: float) -> Array:
	var out := [pts[0]]
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var n := maxi(1, int(Vector2(b.x - a.x, b.z - a.z).length() / step))
		for k in range(1, n + 1):
			out.append(a.lerp(b, float(k) / n))
	return out


func _mesh(st: SurfaceTool, params: Dictionary) -> MeshInstance3D:
	var m := ShaderMaterial.new()
	m.shader = load(MAT_PATH)
	m.set_shader_parameter("ripple_noise", Props.noise())
	for k in params:
		m.set_shader_parameter(k, params[k])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _sound_along(pts: Array, name: String, db: float) -> void:
	# A few emitters spaced along the bank: the murmur follows the stream.
	var stream := _loop(name)
	if stream == null:
		return
	for i in range(0, pts.size(), 30):
		var s := AudioStreamPlayer3D.new()
		s.stream = stream
		s.position = pts[i] + Vector3(0, 0.5, 0)
		s.unit_size = 5.0
		s.max_distance = 35.0
		s.volume_db = db
		s.bus = "Ambience" if AudioServer.get_bus_index("Ambience") != -1 else "Master"
		s.autoplay = true
		add_child(s)


func _loop(name: String) -> AudioStream:
	var path := "res://assets/audio/ambience/%s.ogg" % name
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStreamOggVorbis = load(path)
	s.loop = true
	return s


static func _puff() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t
