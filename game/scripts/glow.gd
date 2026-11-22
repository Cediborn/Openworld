class_name Glow
extends RefCounted
## Giant glowing mushrooms and crystal clusters for Glow Hollow.
## Each returns a list of [mesh, material] parts.


static func _mat(albedo: Color, emission: Color, energy: float, rough := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.emission_enabled = energy > 0.0
	m.emission = emission
	m.emission_energy_multiplier = energy
	m.roughness = rough
	return m


static func mushroom(rng: RandomNumberGenerator) -> Array:
	var h := 7.0
	var stem := SurfaceTool.new()
	stem.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cap := SurfaceTool.new()
	cap.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gills := SurfaceTool.new()
	gills.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Gently curved stem.
	var bend := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
	var prev := Vector3(0, -0.3, 0)
	for s in 5:
		var t := float(s + 1) / 5.0
		var p := Vector3(0, h * t, 0) + bend * t * t
		Trees._branch(stem, prev, p, lerpf(0.75, 0.42, t - 0.2), lerpf(0.75, 0.42, t), 10)
		prev = p
	var top := prev
	var r := h * 0.55
	var segs := 20
	# Cap: a wide dome, slightly drooping at the rim.
	var rings := 6
	for ri in rings:
		var a0 := float(ri) / rings
		var a1 := float(ri + 1) / rings
		for s in segs:
			var t0 := TAU * s / segs
			var t1 := TAU * (s + 1) / segs
			var pts := []
			for ab in [[a0, t0], [a0, t1], [a1, t0], [a1, t1]]:
				var rr: float = r * sin(ab[0] * PI * 0.55)
				var yy: float = top.y + 0.4 + r * 0.42 * cos(ab[0] * PI * 0.55) - r * 0.08 * ab[0] * ab[0]
				pts.append(Vector3(top.x + cos(ab[1]) * rr, yy, top.z + sin(ab[1]) * rr))
			for k in [0, 2, 1, 1, 2, 3]:
				cap.add_vertex(pts[k])
	# Glowing underside.
	var rim_y := top.y + 0.4 + r * 0.42 * cos(PI * 0.55) - r * 0.08
	for s in segs:
		var t0 := TAU * s / segs
		var t1 := TAU * (s + 1) / segs
		var rr := r * sin(PI * 0.55)
		for v in [top + Vector3(0, 0.3, 0), Vector3(top.x + cos(t1) * rr, rim_y, top.z + sin(t1) * rr), Vector3(top.x + cos(t0) * rr, rim_y, top.z + sin(t0) * rr)]:
			gills.add_vertex(v)
	stem.generate_normals()
	cap.generate_normals()
	gills.generate_normals()
	var hue := rng.randf()
	var glow_c := Color.from_hsv(0.5 + hue * 0.35, 0.7, 1.0)
	return [
		[stem.commit(), _mat(Color(0.82, 0.78, 0.86), Color(0.5, 0.45, 0.9), 0.15, 0.7)],
		[cap.commit(), _mat(Color.from_hsv(0.72 + hue * 0.1, 0.55, 0.35), glow_c, 0.6, 0.45)],
		[gills.commit(), _mat(glow_c, glow_c, 3.0, 0.5)],
	]


static func crystals(rng: RandomNumberGenerator) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := rng.randi_range(4, 7)
	for c in n:
		var h := rng.randf_range(0.8, 2.6)
		var rad := rng.randf_range(0.12, 0.3)
		var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.5))
		var base := Vector3(rng.randf_range(-0.5, 0.5), -0.2, rng.randf_range(-0.5, 0.5))
		for s in 6:
			var t0 := TAU * s / 6.0
			var t1 := TAU * (s + 1) / 6.0
			var a := tilt * Vector3(cos(t0) * rad, 0, sin(t0) * rad) + base
			var b := tilt * Vector3(cos(t1) * rad, 0, sin(t1) * rad) + base
			var a2 := tilt * Vector3(cos(t0) * rad, h, sin(t0) * rad) + base
			var b2 := tilt * Vector3(cos(t1) * rad, h, sin(t1) * rad) + base
			var tip := tilt * Vector3(0, h + rad * 2.2, 0) + base
			for v in [a, a2, b, b, a2, b2, a2, tip, b2]:
				st.add_vertex(v)
	st.generate_normals()
	var col := Color.from_hsv(rng.randf_range(0.48, 0.85), 0.6, 1.0)
	var m := _mat(col * 0.6, col, 2.2, 0.15)
	m.metallic_specular = 0.9
	return [[st.commit(), m]]
