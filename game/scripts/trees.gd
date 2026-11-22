class_name Trees
extends RefCounted
## Builds game-ready trees from photo textures: tapered bark branches plus
## leaf cards (photographed leaves with cut-outs), the usual technique for
## real-time foliage. Each tree comes in a near and a far version.

const PH := "res://assets/vendor/polyhaven/"
const LEAF_TEX := PH + "models/jacaranda_tree/textures/jacaranda_tree_leaves_diff_1k.png"
## Fir needles are modelled as geometry in Poly Haven, so pines reuse the feathery
## jacaranda leaflets, tinted dark blue-green, which read as fir sprigs.
const NEEDLE_TEX := LEAF_TEX
const BARK_TEX := PH + "textures/bark_brown_02/albedo.jpg"
const BARK_NRM := PH + "textures/bark_brown_02/normal.jpg"


static func has_photo_leaves() -> bool:
	return ResourceLoader.exists(LEAF_TEX)


static func bark_material() -> Material:
	if not ResourceLoader.exists(BARK_TEX):
		return Props.bark_material()
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(BARK_TEX)
	m.normal_enabled = true
	m.normal_texture = load(BARK_NRM)
	m.uv1_scale = Vector3(1.5, 3.0, 1)
	m.roughness = 0.95
	return m


static func leaf_material(tex_path: String, tint: Color, snow := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/spatial_veg_leaves.gdshader")
	m.set_shader_parameter("leaf_tex", load(tex_path))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("snow", 1.0 if snow else 0.0)
	return m


## Tapered branch from a to b, as a 6-sided tube with UVs for bark.
static func _branch(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, sides := 6) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT).normalized()
	var up := side.cross(axis).normalized()
	var length := a.distance_to(b)
	for s in sides:
		var t0 := TAU * s / sides
		var t1 := TAU * (s + 1) / sides
		var d0 := side * cos(t0) + up * sin(t0)
		var d1 := side * cos(t1) + up * sin(t1)
		var quad := [[a + d0 * r0, d0, Vector2(float(s) / sides, 0)], [b + d0 * r1, d0, Vector2(float(s) / sides, length)],
			[a + d1 * r0, d1, Vector2(float(s + 1) / sides, 0)], [b + d1 * r1, d1, Vector2(float(s + 1) / sides, length)]]
		for k in [0, 1, 2, 2, 1, 3]:
			st.set_normal(quad[k][1])
			st.set_uv(quad[k][2])
			st.add_vertex(quad[k][0])


## One leaf card: a quad facing a random direction around point p.
static func _card(st: SurfaceTool, p: Vector3, size: float, rng: RandomNumberGenerator, centre: Vector3, droop := 0.0) -> void:
	var out := (p - centre).normalized()
	var right := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.3), rng.randf_range(-1, 1)).normalized()
	var fwd := right.cross(Vector3.UP).normalized().rotated(right, rng.randf_range(-0.6, 0.6) - droop)
	var half_r := right * size * 0.5
	var half_f := fwd * size * 0.5
	# Normals point away from the crown centre so the canopy shades like one volume.
	var n := (out + Vector3.UP * 0.4).normalized()
	var u0 := 0.5 * float(rng.randi_range(0, 1))
	var v0 := 0.5 * float(rng.randi_range(0, 1))
	var corners := [[p - half_r - half_f, Vector2(u0, v0 + 0.5)], [p + half_r - half_f, Vector2(u0 + 0.5, v0 + 0.5)],
		[p - half_r + half_f, Vector2(u0, v0)], [p + half_r + half_f, Vector2(u0 + 0.5, v0)]]
	var depth := clampf(p.distance_to(centre) / 4.0, 0.0, 1.0)
	for k in [0, 1, 2, 2, 1, 3]:
		st.set_normal(n)
		st.set_uv(corners[k][1])
		st.set_color(Color(depth, 0, 0))
		st.add_vertex(corners[k][0])


## Broad-leaved tree. Returns [bark_mesh, leaf_mesh]. `cards` sets the detail level.
static func broadleaf(rng: RandomNumberGenerator, height: float, cards: int) -> Array:
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_top := Vector3(rng.randf_range(-0.4, 0.4), height * 0.42, rng.randf_range(-0.4, 0.4))
	_branch(bark, Vector3(0, -0.3, 0), trunk_top, height * 0.045, height * 0.03, 8)
	var crown := trunk_top + Vector3(0, height * 0.28, 0)
	var tips := []
	var limbs := rng.randi_range(5, 7)
	for b in limbs:
		var ang := TAU * b / limbs + rng.randf_range(-0.3, 0.3)
		var start := trunk_top.lerp(Vector3(0, height * 0.3, 0), rng.randf_range(0.0, 0.4))
		var dir := Vector3(cos(ang), rng.randf_range(0.6, 1.3), sin(ang)).normalized()
		var mid := start + dir * height * rng.randf_range(0.22, 0.3)
		_branch(bark, start, mid, height * 0.022, height * 0.012)
		for s in 3:
			var d2 := (dir + Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.2, 0.5), rng.randf_range(-0.7, 0.7))).normalized()
			var tip := mid + d2 * height * rng.randf_range(0.12, 0.2)
			_branch(bark, mid, tip, height * 0.011, height * 0.004, 4)
			tips.append(tip)
	var radius := height * 0.3
	for c in cards:
		var tip: Vector3 = tips[c % tips.size()]
		var p := tip + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.8), rng.randf_range(-1, 1)) * radius * 0.55
		_card(leaves, p, height * rng.randf_range(0.16, 0.24), rng, crown, 0.3)
	bark.generate_tangents()
	return [bark.commit(), leaves.commit()]


## Conifer for the snowy slopes. Returns [bark_mesh, needle_mesh].
static func conifer(rng: RandomNumberGenerator, height: float, cards: int) -> Array:
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var needles := SurfaceTool.new()
	needles.begin(Mesh.PRIMITIVE_TRIANGLES)
	_branch(bark, Vector3(0, -0.3, 0), Vector3(0, height, 0), height * 0.03, 0.03, 8)
	var whorls := int(cards / 6)
	for w in whorls:
		var f := float(w) / whorls
		var y := lerpf(height * 0.15, height * 0.97, f)
		var reach := lerpf(height * 0.28, height * 0.04, f)
		for k in 6:
			var ang := TAU * k / 6.0 + w * 0.9 + rng.randf_range(-0.2, 0.2)
			var out := Vector3(cos(ang), -0.25, sin(ang))
			var a := Vector3(0, y, 0)
			var b := a + out * reach
			if reach > 0.6:
				_branch(bark, a, b, 0.04, 0.01, 4)
			# A drooping needle card along the branch.
			var p := a.lerp(b, 0.55)
			_card(needles, p, reach * 1.25 + 0.4, rng, Vector3(0, y + 0.5, 0), 0.9)
	bark.generate_tangents()
	return [bark.commit(), needles.commit()]
