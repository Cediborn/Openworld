class_name Props
extends RefCounted
## Builds tree, rock and grass meshes in code, so the first build needs no
## downloaded models. Each kind is merged into one mesh for MultiMesh drawing.


static func _noise_tex(freq: float, seamless := true) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	var n := FastNoiseLite.new()
	n.frequency = freq
	n.fractal_octaves = 4
	t.noise = n
	t.seamless = seamless
	t.width = 256
	t.height = 256
	t.generate_mipmaps = true
	return t


static var noise_a: NoiseTexture2D = null


static func noise() -> NoiseTexture2D:
	if noise_a == null:
		noise_a = _noise_tex(0.02)
	return noise_a


# ---------- Trees ----------

static func bark_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.27, 0.21, 0.16)
	m.roughness = 0.95
	m.albedo_texture = _noise_tex(0.08)
	m.uv1_scale = Vector3(2, 6, 1)
	m.normal_enabled = true
	var nt := _noise_tex(0.12)
	nt.as_normal_map = true
	nt.bump_strength = 6.0
	m.normal_texture = nt
	return m


static func leaf_material(dark: Color, light: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/spatial_veg_foliage.gdshader")
	m.set_shader_parameter("noise_tex", noise())
	m.set_shader_parameter("leaf_dark", dark)
	m.set_shader_parameter("leaf_light", light)
	return m


static func _append(st: SurfaceTool, mesh: Mesh, xf: Transform3D, occl := 1.0) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var ind: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var basis := xf.basis
	for i in ind.size():
		var k: int = ind[i]
		var n: Vector3 = (basis * nrm[k]).normalized()
		st.set_normal(n)
		if uv.size() > k:
			st.set_uv(uv[k])
		# Outward, upper-facing leaves get more light.
		st.set_color(Color(clampf(occl * (0.55 + n.y * 0.25 + 0.2), 0.0, 1.0), 0, 0))
		st.add_vertex(xf * v[k])


## A broad-leaved tree (oak-like). Returns [bark_mesh, leaf_mesh].
static func make_tree(rng: RandomNumberGenerator, height := 11.0) -> Array:
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)

	var trunk_h: float = height * 0.32
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.28
	trunk.bottom_radius = 0.5
	trunk.height = trunk_h
	trunk.radial_segments = 10
	trunk.rings = 3
	var lean := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.08))
	_append(bark, trunk, Transform3D(lean, lean * Vector3(0, trunk_h * 0.5, 0)))
	var top: Vector3 = lean * Vector3(0, trunk_h, 0)

	var crown_c: Vector3 = top + Vector3(0, height * 0.22, 0)
	var crown_r: float = height * 0.42
	var branch := CylinderMesh.new()
	branch.top_radius = 0.07
	branch.bottom_radius = 0.2
	branch.height = crown_r * 1.1
	branch.radial_segments = 6
	branch.rings = 1
	var blob := SphereMesh.new()
	blob.radial_segments = 14
	blob.rings = 8

	var n_branch := rng.randi_range(4, 6)
	for b in n_branch:
		var ang: float = TAU * b / n_branch + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(ang), rng.randf_range(0.5, 1.0), sin(ang)).normalized()
		var bb := Basis(Vector3.UP.cross(dir).normalized(), Vector3.UP.angle_to(dir))
		_append(bark, branch, Transform3D(bb, top + dir * branch.height * 0.5))
	# Leaf clumps: big ones around the crown, small ones filling gaps.
	var clumps := rng.randi_range(16, 22)
	for c in clumps:
		var p := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.9, 0.9), rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.5, 1.0)
		var r: float = rng.randf_range(0.28, 0.45) * crown_r
		var pos: Vector3 = crown_c + Vector3(p.x * crown_r * 0.8, p.y * crown_r * 0.6, p.z * crown_r * 0.8)
		var s := Basis().scaled(Vector3(r, r * rng.randf_range(0.7, 0.9), r) * 2.0)
		var occl: float = clampf(0.5 + (pos - crown_c).length() / crown_r * 0.5, 0.0, 1.0)
		_append(leaves, blob, Transform3D(s, pos), occl)

	bark.generate_tangents()
	return [bark.commit(), leaves.commit()]


## A conifer for the slopes. Returns [bark_mesh, leaf_mesh].
static func make_pine(rng: RandomNumberGenerator, height := 14.0) -> Array:
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.08
	trunk.bottom_radius = 0.35
	trunk.height = height
	trunk.radial_segments = 8
	_append(bark, trunk, Transform3D(Basis(), Vector3(0, height * 0.5, 0)))
	var tiers := 7
	for t in tiers:
		var f: float = float(t) / tiers
		var cone := CylinderMesh.new()
		cone.top_radius = 0.05
		cone.bottom_radius = lerpf(3.2, 0.7, f) * rng.randf_range(0.9, 1.1)
		cone.height = height * 0.24
		cone.radial_segments = 12
		cone.rings = 2
		var y: float = height * (0.22 + f * 0.7)
		_append(leaves, cone, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(0, y, 0)), 0.45 + f * 0.55)
	bark.generate_tangents()
	return [bark.commit(), leaves.commit()]


# ---------- Rocks ----------

static func make_rock(rng: RandomNumberGenerator) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 12
	sphere.rings = 7
	var arrays := sphere.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.frequency = 1.6
	var stretch := Vector3(rng.randf_range(1.0, 1.8), rng.randf_range(0.5, 0.9), rng.randf_range(0.9, 1.4))
	for i in v.size():
		var p: Vector3 = v[i]
		p *= 1.0 + n.get_noise_3dv(p) * 0.35
		p = p * stretch
		p.y = maxf(p.y, -0.15)
		v[i] = p
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ind: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in ind.size():
		st.add_vertex(v[ind[i]])
	st.generate_normals()
	return st.commit()


static func rock_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.46, 0.45, 0.42)
	m.albedo_texture = _noise_tex(0.06)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.6, 0.6, 0.6)
	m.roughness = 0.9
	m.normal_enabled = true
	var nt := _noise_tex(0.1)
	nt.as_normal_map = true
	nt.bump_strength = 8.0
	m.normal_texture = nt
	return m


# ---------- Grass ----------

## Three crossed blades, each 2 segments tall. UV.y = 0 at root, 1 at tip.
static func make_grass_tuft() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in 7:
		var ang: float = b * TAU / 7.0 + 0.3
		var side := Vector3(cos(ang), 0, sin(ang)) * 0.035
		var lean := Vector3(-sin(ang), 0, cos(ang)) * 0.12
		var off := Vector3(cos(ang * 2.3), 0, sin(ang * 1.7)) * 0.08
		var h: float = 0.45 + 0.2 * float(b % 3)
		var p0 := off - side
		var p1 := off + side
		var p2 := off - side * 0.6 + Vector3(0, h * 0.55, 0) + lean * 0.35
		var p3 := off + side * 0.6 + Vector3(0, h * 0.55, 0) + lean * 0.35
		var p4 := off + Vector3(0, h, 0) + lean
		var pts := [[p0, 0.0], [p1, 0.0], [p2, 0.55], [p1, 0.0], [p3, 0.55], [p2, 0.55], [p2, 0.55], [p3, 0.55], [p4, 1.0]]
		for q in pts:
			st.set_uv(Vector2(0.5, q[1]))
			st.add_vertex(q[0])
	st.generate_normals()
	return st.commit()
