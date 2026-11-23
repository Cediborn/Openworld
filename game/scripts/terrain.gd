class_name Terrain
extends Node3D
## Draws the island ground as a grid of flat tiles that the terrain shader lifts
## to the baked heights. Near tiles are finer than far ones. Also adds the
## collision shape, the lava surface and the distant mountain ring.

const TILE := 128.0
const VENDOR := "res://assets/vendor/polyhaven/textures/"
## How deep the player wades into lava before standing on the hidden floor (m).
const LAVA_WADE_DEPTH := 0.45
## Poly Haven texture per layer, and how many times it repeats per metre.
const LAYERS := [
	["sparse_grass", 0.22], ["snow_02", 0.15], ["dark_rock_02", 0.12], ["forest_floor", 0.2],
	["leafy_grass", 0.22], ["dirt_floor", 0.3], ["cobblestone_floor_05", 0.33], ["rock_face_03", 0.08],
]
## Colour grade applied to each photo layer.
const TINTS := [
	Vector3(0.95, 1.05, 0.8), Vector3(1.0, 1.0, 1.05), Vector3(0.45, 0.4, 0.42), Vector3(0.38, 0.3, 0.55),
	Vector3(0.8, 0.95, 0.6), Vector3(0.85, 0.8, 0.75), Vector3(0.9, 0.9, 0.9), Vector3(0.85, 0.85, 0.88),
]
const FALLBACK := [
	Color(0.24, 0.36, 0.11), Color(0.9, 0.93, 0.97), Color(0.16, 0.13, 0.13), Color(0.16, 0.11, 0.2),
	Color(0.36, 0.4, 0.17), Color(0.38, 0.29, 0.19), Color(0.42, 0.41, 0.39), Color(0.4, 0.39, 0.37),
]

var data: WorldData
var mobile := false
var material: ShaderMaterial


var photo := true


func setup(world_data: WorldData, is_mobile: bool, use_photo := true) -> void:
	data = world_data
	mobile = is_mobile
	photo = use_photo
	material = _make_material()
	_build_tiles()
	_build_collision()
	_build_lava()
	_build_far_ring()


func _make_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/spatial_env_terrain.gdshader")
	m.set_shader_parameter("height_map", data.height_texture())
	m.set_shader_parameter("biome_map", data.biome_texture())
	m.set_shader_parameter("path_map", data.mask_texture())
	m.set_shader_parameter("world_size", WorldData.SIZE)
	m.set_shader_parameter("texel", WorldData.STEP)
	m.set_shader_parameter("macro_noise", Props.noise())
	var cols := PackedVector3Array()
	var scales := PackedFloat32Array()
	for i in LAYERS.size():
		cols.append(Vector3(FALLBACK[i].r, FALLBACK[i].g, FALLBACK[i].b))
		scales.append(LAYERS[i][1])
	m.set_shader_parameter("fallback_colors", cols)
	m.set_shader_parameter("layer_scale", scales)
	m.set_shader_parameter("layer_tint", PackedVector3Array(TINTS))
	var albedo := _layer_array("albedo") if photo else null
	var normal := _layer_array("normal") if not mobile else null
	m.set_shader_parameter("use_textures", albedo != null)
	m.set_shader_parameter("use_normal_maps", normal != null)
	if albedo:
		m.set_shader_parameter("albedo_layers", albedo)
	if normal:
		m.set_shader_parameter("normal_layers", normal)
	return m


## Builds a Texture2DArray from the downloaded photo textures, or null if any is missing.
func _layer_array(map: String) -> Texture2DArray:
	var images: Array[Image] = []
	for l in LAYERS:
		var p: String = VENDOR + l[0] + "/" + map + ".jpg"
		if not ResourceLoader.exists(p):
			return null
		var img: Image = (load(p) as Texture2D).get_image()
		images.append(img)
	# Layers must share size and format; normalise if the importer disagreed.
	var fmt := images[0].get_format()
	var size := images[0].get_size()
	var same := true
	for img in images:
		same = same and img.get_format() == fmt and img.get_size() == size and img.has_mipmaps()
	if not same:
		for i in images.size():
			var img := images[i]
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			if img.get_size() != Vector2i(1024, 1024):
				img.resize(1024, 1024, Image.INTERPOLATE_BILINEAR)
			img.generate_mipmaps()
	var arr := Texture2DArray.new()
	if arr.create_from_images(images) != OK:
		return null
	return arr


func _build_tiles() -> void:
	# Close to the player the mesh uses the same 2 m grid as the collision
	# heightmap, so feet never sink into (or float above) the visible ground.
	var res: Array = [2.0, 4.0, 8.0] if mobile else [2.0, 2.0, 4.0]
	var ends: Array = [70.0, 150.0, INF] if mobile else [120.0, 230.0, INF]
	var meshes: Array = []
	for r in res:
		meshes.append(_plane(r))
	var n := int(WorldData.SIZE / TILE)
	for j in n:
		for i in n:
			var c := Vector3(-WorldData.SIZE * 0.5 + (i + 0.5) * TILE, 0, -WorldData.SIZE * 0.5 + (j + 0.5) * TILE)
			for lod in 3:
				var mi := MeshInstance3D.new()
				mi.mesh = meshes[lod]
				mi.material_override = material
				mi.position = c
				mi.custom_aabb = AABB(Vector3(-TILE * 0.5, -20, -TILE * 0.5), Vector3(TILE, 420, TILE))
				if lod > 0:
					mi.visibility_range_begin = ends[lod - 1]
					mi.visibility_range_begin_margin = 10.0
				if ends[lod] < INF:
					mi.visibility_range_end = ends[lod]
					mi.visibility_range_end_margin = 10.0
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
				add_child(mi)


func _plane(res: float) -> PlaneMesh:
	var p := PlaneMesh.new()
	p.size = Vector2(TILE, TILE)
	p.subdivide_width = int(TILE / res) - 1
	p.subdivide_depth = int(TILE / res) - 1
	return p


func _build_collision() -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = data.build_collision()
	col.scale = Vector3(WorldData.STEP, 1, WorldData.STEP)
	body.add_child(col)
	add_child(body)


func _build_lava() -> void:
	var mi := MeshInstance3D.new()
	var p := PlaneMesh.new()
	p.size = Vector2(300, 520)
	p.subdivide_width = 30
	p.subdivide_depth = 52
	mi.mesh = p
	mi.position = Vector3(360, WorldData.LAVA_LEVEL, 0)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/spatial_env_lava.gdshader")
	m.set_shader_parameter("flow_noise", Props.noise())
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# A hidden floor just under the lava surface: you wade (and burn) instead
	# of sinking into the crater and getting stuck below its steep walls.
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, 0.4, 520)
	col.shape = box
	floor_body.add_child(col)
	floor_body.position = Vector3(360, WorldData.LAVA_LEVEL - LAVA_WADE_DEPTH - 0.2, 0)
	add_child(floor_body)


## Huge mountains far beyond the island so the horizon is never empty.
func _build_far_ring() -> void:
	var ridge := FastNoiseLite.new()
	ridge.seed = 99
	ridge.frequency = 0.002
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 30
	var segs := 160 if not mobile else 96
	var pts := []
	for r in rings + 1:
		var row := []
		var rad: float = lerpf(500.0, 3200.0, pow(float(r) / rings, 1.3))
		for s in segs + 1:
			var a: float = TAU * s / segs
			var x: float = cos(a) * rad
			var z: float = sin(a) * rad
			var env: float = smoothstep(500.0, 900.0, rad) * (1.0 - smoothstep(2600.0, 3200.0, rad))
			var h: float = 60.0 + env * (200.0 + (ridge.get_noise_2d(x, z) * 0.5 + 0.5) * 650.0)
			row.append(Vector3(x, h, z))
		pts.append(row)
	for r in rings:
		for s in segs:
			for v in [pts[r][s], pts[r + 1][s], pts[r][s + 1], pts[r][s + 1], pts[r + 1][s], pts[r + 1][s + 1]]:
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/spatial_env_far_mountains.gdshader")
	m.set_shader_parameter("macro_noise", Props.noise())
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
