extends Node3D
## Green valley test zone. Everything is generated here so the scene file stays tiny.

const TEX_DIR := "res://assets/polyhaven/"

var gen := TerrainGen.new()
var rng := RandomNumberGenerator.new()
var mobile := OS.has_feature("mobile")
var player: Player
var fps_label: Label
var shot_path := ""
var shot_frames := 0


func _ready() -> void:
	rng.seed = 7
	_parse_args()
	_build_environment()
	_build_terrain()
	_build_far_mountains()
	_scatter_trees()
	_scatter_rocks()
	_build_grass()
	_spawn_player()
	_build_ui()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot_path = a.substr(7)
		elif a == "--mobile":
			mobile = true


# ---------- Sky, sun, fog ----------

func _build_environment() -> void:
	var sky_mat := PhysicalSkyMaterial.new()
	sky_mat.rayleigh_coefficient = 2.2
	sky_mat.mie_coefficient = 0.008
	sky_mat.mie_eccentricity = 0.85
	sky_mat.turbidity = 9.0
	sky_mat.sun_disk_scale = 2.0
	sky_mat.ground_color = Color(0.25, 0.27, 0.2)
	sky_mat.energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME if not mobile else Sky.PROCESS_MODE_QUALITY

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.2
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.70, 0.78, 0.88)
	env.fog_sun_scatter = 0.35
	env.fog_density = 0.0006
	env.fog_aerial_perspective = 0.8
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.05
	if not mobile:
		env.ssao_enabled = true
		env.ssao_radius = 1.2
		env.ssao_intensity = 1.6
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.006
		env.volumetric_fog_albedo = Color(0.95, 0.92, 0.85)
		env.volumetric_fog_anisotropy = 0.6
		env.volumetric_fog_length = 120.0
		env.volumetric_fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-24, -40, 0)   # low golden-hour sun, over the right shoulder
	sun.light_color = Color(1.0, 0.86, 0.66)
	sun.light_energy = 1.6
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if mobile else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 60.0 if mobile else 220.0
	sun.light_volumetric_fog_energy = 1.4
	add_child(sun)


# ---------- Ground ----------

func _terrain_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/terrain.gdshader")
	m.set_shader_parameter("macro_noise", Props.noise())
	var have := true
	for kind in ["grass", "path", "rock"]:
		for map in ["albedo", "normal"]:
			var p: String = TEX_DIR + kind + "_" + map + ".jpg"
			if ResourceLoader.exists(p):
				m.set_shader_parameter(kind + "_" + map, load(p))
			else:
				have = false
	m.set_shader_parameter("use_textures", have)
	return m


func _build_terrain() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = gen.build_mesh()
	mi.material_override = _terrain_material()
	body.add_child(mi)
	var col := CollisionShape3D.new()
	col.shape = gen.build_collision()
	col.scale = Vector3(TerrainGen.STEP, 1, TerrainGen.STEP)
	body.add_child(col)


func _build_far_mountains() -> void:
	var ridge := FastNoiseLite.new()
	ridge.seed = 99
	ridge.frequency = 0.0025
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 40
	var segs := 180
	var pts := []
	for r in rings + 1:
		var row := []
		var rad: float = lerpf(300.0, 1900.0, pow(float(r) / rings, 1.4))
		for s in segs + 1:
			var a: float = TAU * s / segs
			var x: float = cos(a) * rad
			var z: float = sin(a) * rad
			var env: float = smoothstep(300.0, 650.0, rad) * (1.0 - smoothstep(1500.0, 1900.0, rad))
			var h: float = 30.0 + env * (120.0 + (ridge.get_noise_2d(x, z) * 0.5 + 0.5) * 420.0)
			row.append(Vector3(x, h - 6.0, z))
		pts.append(row)
	for r in rings:
		for s in segs:
			var a: Vector3 = pts[r][s]
			var b: Vector3 = pts[r][s + 1]
			var c: Vector3 = pts[r + 1][s]
			var d: Vector3 = pts[r + 1][s + 1]
			for v in [a, c, b, b, c, d]:
				st.set_color(Color(0, 0, 0))
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := _terrain_material()
	m.set_shader_parameter("snow_height", 230.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---------- Placement ----------

func _good_spot(min_path: float, max_slope: float, max_r: float) -> Vector3:
	for i in 30:
		var x: float = rng.randf_range(-max_r, max_r)
		var z: float = rng.randf_range(-max_r, max_r)
		if Vector2(x, z).length() > max_r:
			continue
		if absf(x - TerrainGen.path_x(z)) < min_path:
			continue
		if 1.0 - gen.normal(x, z).y > max_slope:
			continue
		return Vector3(x, gen.height(x, z), z)
	return Vector3.INF


func _multimesh(mesh: Mesh, xforms: Array, mat: Material, shadows := true, vis_end := 0.0) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_end > 0.0:
		mmi.visibility_range_end = vis_end
	add_child(mmi)
	return mmi


func _add_tree_kind(meshes: Array, xforms: Array, leaf_mat: Material, bark_mat: Material) -> void:
	if xforms.is_empty():
		return
	_multimesh(meshes[0], xforms, bark_mat)
	_multimesh(meshes[1], xforms, leaf_mat)
	# Trunk collision.
	for xf in xforms:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.45 * xf.basis.get_scale().x
		cyl.height = 4.0
		col.shape = cyl
		col.position = xf.origin + Vector3(0, 2, 0)
		body.add_child(col)
		add_child(body)


func _scatter_trees() -> void:
	var bark := Props.bark_material()
	var oak_leaf := Props.leaf_material(Color(0.07, 0.15, 0.04), Color(0.30, 0.43, 0.12))
	var pine_leaf := Props.leaf_material(Color(0.04, 0.10, 0.06), Color(0.13, 0.24, 0.12))
	var oaks := []
	for i in 4:
		oaks.append(Props.make_tree(rng, rng.randf_range(10.0, 14.0)))
	var pine := Props.make_pine(rng, 15.0)
	var oak_x := [[], [], [], []]
	var pine_x := []
	var n_trees := 160 if mobile else 320
	for i in n_trees:
		var p := _good_spot(6.0, 0.4, 290.0)
		if p == Vector3.INF or Vector2(p.x, p.z).length() < 12.0:
			continue
		var s: float = rng.randf_range(0.8, 1.25)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p + Vector3(0, -0.2, 0))
		if p.y > 22.0:
			pine_x.append(xf)
		else:
			oak_x[i % 4].append(xf)
	for k in 4:
		_add_tree_kind(oaks[k], oak_x[k], oak_leaf, bark)
	_add_tree_kind(pine, pine_x, pine_leaf, bark)


func _scatter_rocks() -> void:
	var mat := Props.rock_material()
	for kind in 3:
		var mesh := Props.make_rock(rng)
		var xs := []
		for i in (40 if mobile else 80):
			var p := _good_spot(3.0, 0.6, 280.0)
			if p == Vector3.INF:
				continue
			var s: float = rng.randf_range(0.4, 2.2)
			xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p + Vector3(0, -0.15 * s, 0)))
		_multimesh(mesh, xs, mat)


func _build_grass() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass.gdshader")
	mat.set_shader_parameter("variation", Props.noise())
	var fade_end: float = 30.0 if mobile else 55.0
	mat.set_shader_parameter("fade_start", fade_end * 0.6)
	mat.set_shader_parameter("fade_end", fade_end)
	var tuft := Props.make_grass_tuft()
	var density: float = 1.2 if mobile else 3.5   # tufts per square metre
	var cell := 24.0
	var radius := 200.0
	var cells: int = int(radius * 2.0 / cell)
	for cj in cells:
		for ci in cells:
			var ox: float = -radius + ci * cell
			var oz: float = -radius + cj * cell
			if Vector2(ox + cell * 0.5, oz + cell * 0.5).length() > radius:
				continue
			var xs := []
			var count: int = int(cell * cell * density)
			for k in count:
				var x: float = ox + rng.randf() * cell
				var z: float = oz + rng.randf() * cell
				if TerrainGen.path_mask(x, z) > 0.2:
					continue
				var n: Vector3 = gen.normal(x, z)
				if 1.0 - n.y > 0.35:
					continue
				var s: float = rng.randf_range(0.6, 1.1)
				var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 1.3, s * rng.randf_range(0.5, 0.9), s * 1.3))
				xs.append(Transform3D(b, Vector3(x, gen.height(x, z) - 0.03, z)))
			if xs.size() > 0:
				_multimesh(tuft, xs, mat, false, fade_end + cell)


# ---------- Player and UI ----------

func _spawn_player() -> void:
	player = Player.new()
	var z := 110.0
	var x := TerrainGen.path_x(z)
	player.position = Vector3(x, gen.height(x, z) + 0.5, z)
	add_child(player)
	player.yaw = 0.0   # looking down the trail towards the mountains


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	fps_label = Label.new()
	fps_label.position = Vector2(16, 12)
	fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	fps_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(fps_label)
	if DisplayServer.is_touchscreen_available() or mobile:
		var tc := TouchControls.new()
		tc.player = player
		layer.add_child(tc)


func _process(_delta: float) -> void:
	fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	if shot_path != "":
		shot_frames += 1
		if shot_frames == 40:
			fps_label.visible = false
		if shot_frames == 45:
			get_viewport().get_texture().get_image().save_png(shot_path)
			get_tree().quit()
