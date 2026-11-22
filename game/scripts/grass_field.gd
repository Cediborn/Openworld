class_name GrassField
extends Node3D
## A patch of grass (and a sparse layer of wildflowers) that travels with the
## player. It snaps to whole grid cells, so blades stay put in the world.

var spacing := 0.45
var radius := 45.0
var target: Node3D
var materials: Array[ShaderMaterial] = []


func setup(data: WorldData, follow: Node3D, mobile: bool) -> void:
	target = follow
	spacing = 0.75 if mobile else 0.45
	radius = 26.0 if mobile else 45.0
	var n := int(radius * 2.0 / spacing)
	var tuft := Props.make_grass_tuft()
	var grass := _make_layer(data, tuft, n, false)
	var flower := _make_layer(data, _flower_mesh(), n, true)
	add_child(grass)
	add_child(flower)


func _make_layer(data: WorldData, mesh: Mesh, n: int, flowers: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = n * n
	var half := n * spacing * 0.5
	for j in n:
		for i in n:
			mm.set_instance_transform(j * n + i, Transform3D(Basis(), Vector3(i * spacing - half, 0, j * spacing - half)))
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/spatial_veg_grass.gdshader")
	m.set_shader_parameter("height_map", data.height_texture())
	m.set_shader_parameter("biome_map", data.biome_texture())
	m.set_shader_parameter("path_map", data.mask_texture())
	m.set_shader_parameter("variation", Props.noise())
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("flowers", flowers)
	materials.append(m)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-radius - 2, -50, -radius - 2), Vector3(radius * 2 + 4, 500, radius * 2 + 4))
	return mmi


## A thin stem with a small flat flower head on top.
static func _flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.42
	for q in [[Vector3(-0.006, 0, 0), 0.0], [Vector3(0.006, 0, 0), 0.0], [Vector3(0, h, 0), 0.7]]:
		st.set_uv(Vector2(0.5, q[1]))
		st.add_vertex(q[0])
	var petals := 6
	for p in petals:
		var a0 := TAU * p / petals
		var a1 := TAU * (p + 1) / petals
		for v in [Vector3(0, h, 0), Vector3(cos(a0), 0.15, sin(a0)) * 0.045 + Vector3(0, h, 0), Vector3(cos(a1), 0.15, sin(a1)) * 0.045 + Vector3(0, h, 0)]:
			st.set_uv(Vector2(0.5, 1.0))
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func set_night(amount: float) -> void:
	for m in materials:
		m.set_shader_parameter("night", amount)


func _process(_delta: float) -> void:
	if target == null:
		return
	var p := target.global_position
	global_position = Vector3(snappedf(p.x, spacing), 0, snappedf(p.z, spacing))
