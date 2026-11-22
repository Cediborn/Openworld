class_name SkyCycle
extends Node3D
## Day and night: moves the sun and moon, colours the sky, light and fog for
## the time of day, tints the air per zone (cold blue in Frost Peaks, smoky
## orange in Ember Wastes, violet in Glow Hollow) and shows the aurora at night.

signal night_changed(amount: float)

var cfg := {}
var time_of_day := 8.0          ## hours, 0..24
var day_minutes := 16.0         ## real minutes for a full day
var env: Environment
var sky_mat: PhysicalSkyMaterial
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var aurora: MeshInstance3D
var aurora_mat: ShaderMaterial
var mobile := false
var night := 0.0
var zone_w := [1.0, 0.0, 0.0, 0.0, 0.0]


func setup(is_mobile: bool, config: Dictionary) -> void:
	mobile = is_mobile
	cfg = config
	day_minutes = cfg.get("day_minutes", 16.0)
	time_of_day = cfg.get("start_hour", 8.0)

	sky_mat = PhysicalSkyMaterial.new()
	sky_mat.rayleigh_coefficient = 2.2
	sky_mat.mie_coefficient = 0.008
	sky_mat.mie_eccentricity = 0.85
	sky_mat.turbidity = 9.0
	sky_mat.sun_disk_scale = 2.0
	sky_mat.ground_color = Color(0.25, 0.27, 0.2)
	sky_mat.night_sky = _stars()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_64 if mobile else Sky.RADIANCE_SIZE_256

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_aerial_perspective = 0.8
	env.fog_sky_affect = 0.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.05
	if not mobile:
		env.ssao_enabled = true
		env.ssao_radius = 1.2
		env.ssao_intensity = 1.6
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.005
		env.volumetric_fog_anisotropy = 0.6
		env.volumetric_fog_length = 120.0
		env.volumetric_fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if mobile else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 55.0 if mobile else 200.0
	sun.light_volumetric_fog_energy = 1.4
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 0.95)
	moon.shadow_enabled = not mobile
	moon.directional_shadow_max_distance = 80.0
	add_child(moon)
	_build_aurora()
	_apply()


## Procedural star field for the night sky (equirectangular).
func _stars() -> ImageTexture:
	var w := 2048 if not mobile else 1024
	var img := Image.create(w, w / 2, false, Image.FORMAT_RGB8)
	img.fill(Color(0.004, 0.006, 0.014))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in (6000 if not mobile else 2500):
		var x := rng.randi_range(0, w - 1)
		var y := int(acos(rng.randf_range(-1.0, 1.0)) / PI * (w / 2 - 1))
		var b := pow(rng.randf(), 6.0) * 0.9 + 0.08
		var tint := Color(0.8 + rng.randf() * 0.2, 0.85, 1.0 - rng.randf() * 0.2)
		img.set_pixel(x, y, tint * b)
	return ImageTexture.create_from_image(img)


func _build_aurora() -> void:
	aurora = MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Three wavy curtains high above Frost Peaks.
	for c in 3:
		var segs := 48
		for s in segs:
			var u0 := float(s) / segs
			var u1 := float(s + 1) / segs
			var p0 := _curtain(u0, c)
			var p1 := _curtain(u1, c)
			var hgt := 380.0 + c * 60.0
			var quad := [[p0, Vector2(u0, 0)], [p1, Vector2(u1, 0)], [p0 + Vector3(0, hgt, 0), Vector2(u0, 1)], [p1 + Vector3(0, hgt, 0), Vector2(u1, 1)]]
			for k in [0, 1, 2, 2, 1, 3]:
				st.set_uv(quad[k][1])
				st.set_color(Color(float(c) / 3.0, 0, 0))
				st.add_vertex(quad[k][0])
	aurora.mesh = st.commit()
	aurora_mat = ShaderMaterial.new()
	aurora_mat.shader = load("res://shaders/spatial_sky_aurora.gdshader")
	aurora_mat.set_shader_parameter("noise_tex", Props.noise())
	aurora.material_override = aurora_mat
	aurora.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	aurora.custom_aabb = AABB(Vector3(-2000, 0, -2500), Vector3(4000, 2200, 2600))
	add_child(aurora)


func _curtain(u: float, c: int) -> Vector3:
	var x := lerpf(-1400.0, 1400.0, u)
	var z := -650.0 - c * 150.0 + sin(u * 9.0 + c) * 140.0 + sin(u * 23.0) * 40.0
	# High enough to clear the far mountain ring (peaks reach ~850 m).
	return Vector3(x, 900.0 + c * 80.0, z)


func set_zone(weights: Array) -> void:
	for i in 5:
		zone_w[i] = lerpf(zone_w[i], weights[i], 0.02)


func _process(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta * 24.0 / (day_minutes * 60.0), 24.0)
	_apply()


func _apply() -> void:
	# Sun path: rises in the east (+x) at 6:00, crosses the south (+z) at noon,
	# sets in the west at 18:00. The moon sits opposite.
	var t := (time_of_day - 6.0) / 12.0 * PI
	var elev := sin(t) * 60.0
	var e := deg_to_rad(elev)
	var to_sun := Vector3(cos(t) * cos(e), sin(e), absf(sin(t)) * 0.7 * cos(e) + 0.25).normalized()
	if to_sun.y > -0.99:
		sun.basis = Basis.looking_at(-to_sun, Vector3.UP)
	var to_moon := Vector3(-to_sun.x, absf(to_sun.y) * 0.8 + 0.5, 0.3).normalized()
	moon.basis = Basis.looking_at(-to_moon, Vector3.UP)
	var day := clampf(smoothstep(-6.0, 10.0, elev), 0.0, 1.0)
	var golden := clampf(1.0 - absf(elev - 8.0) / 22.0, 0.0, 1.0) * day
	night = 1.0 - smoothstep(-10.0, 2.0, elev)

	sun.light_energy = 1.7 * day
	sun.visible = day > 0.01
	sun.light_color = Color(1.0, 0.97, 0.92).lerp(Color(1.0, 0.68, 0.38), golden)
	moon.light_energy = 0.55 * night
	moon.visible = night > 0.05
	env.ambient_light_energy = lerpf(0.55, 1.15, day)
	env.background_energy_multiplier = lerpf(1.0, 1.0, day)
	sky_mat.energy_multiplier = lerpf(0.5, 1.0, day)

	# Base fog for the time of day, then tinted by the zone the player is in.
	var fog := Color(0.70, 0.78, 0.88).lerp(Color(0.95, 0.7, 0.5), golden).lerp(Color(0.05, 0.07, 0.12), night)
	var density := 0.0006
	var zone_fog := [Color(0, 0, 0, 0), Color(0.75, 0.85, 1.0), Color(0.55, 0.38, 0.3), Color(0.35, 0.2, 0.55), Color(0.8, 0.78, 0.72)]
	var zone_density := [0.0, 0.0012, 0.0016, 0.0024, 0.0004]
	for i in range(1, 5):
		var zc: Color = zone_fog[i]
		if i != 1 and i != 4:
			zc = zc.lerp(zc * 0.35, night)
		else:
			zc = zc.lerp(Color(0.06, 0.08, 0.14), night)
		fog = fog.lerp(zc, zone_w[i] * 0.85)
		density += zone_density[i] * zone_w[i]
	env.fog_light_color = fog
	env.fog_density = density
	if not mobile:
		env.volumetric_fog_density = 0.004 + zone_w[3] * 0.01 + zone_w[2] * 0.008
		env.volumetric_fog_albedo = Color(0.95, 0.92, 0.85).lerp(Color(0.6, 0.4, 1.0), zone_w[3]).lerp(Color(1.0, 0.5, 0.25), zone_w[2])
		env.volumetric_fog_emission = Color(0.05, 0.02, 0.08) * zone_w[3] + Color(0.12, 0.03, 0.0) * zone_w[2]
	env.adjustment_saturation = 1.08 - night * 0.3

	aurora_mat.set_shader_parameter("strength", night * (0.6 + zone_w[1] * 0.8))
	aurora.visible = night > 0.02
	night_changed.emit(night)


## "HH:MM" for the clock in the corner.
func clock_text() -> String:
	var h := int(time_of_day)
	var m := int((time_of_day - h) * 60.0)
	return "%02d:%02d" % [h, m]
