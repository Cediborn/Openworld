class_name Village
extends Node3D
## Brickton: timber-framed houses with plaster walls, stone bases and tiled
## roofs, placed from data/village.json. Windows light up at night.

const TEX := "res://assets/vendor/polyhaven/textures/"
const PLASTER_TINTS := [Color(0.95, 0.92, 0.85), Color(0.95, 0.82, 0.45), Color(0.85, 0.5, 0.4), Color(0.7, 0.8, 0.6)]

var window_mat: StandardMaterial3D
var mats := {}


func setup(data: WorldData) -> void:
	window_mat = StandardMaterial3D.new()
	window_mat.albedo_color = Color(0.12, 0.13, 0.15)
	window_mat.roughness = 0.1
	window_mat.emission_enabled = true
	window_mat.emission = Color(1.0, 0.7, 0.35)
	window_mat.emission_energy_multiplier = 0.0
	for h in data.houses:
		_house(h)


func set_night(amount: float) -> void:
	window_mat.emission_energy_multiplier = amount * 3.0


func _tex_mat(name: String, tint := Color.WHITE, scale := 0.5) -> StandardMaterial3D:
	var key := name + str(tint)
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.roughness = 0.9
	if ResourceLoader.exists(TEX + name + "/albedo.jpg"):
		m.albedo_texture = load(TEX + name + "/albedo.jpg")
		m.normal_enabled = true
		m.normal_texture = load(TEX + name + "/normal.jpg")
	mats[key] = m
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _house(h: Dictionary) -> void:
	var root := Node3D.new()
	root.position = Vector3(h.x, h.get("y", 0.0), h.z)
	root.rotation.y = h.rot
	add_child(root)
	var w: float = h.w
	var d: float = h.d
	var floors: int = h.floors
	var wall_h := 3.0 * floors
	var stone := _tex_mat("castle_brick_07", Color(0.85, 0.85, 0.85), 0.6)
	var plaster := _tex_mat("plastered_stone_wall", PLASTER_TINTS[int(h.style) % 4], 0.35)
	var timber := _tex_mat("weathered_brown_planks", Color(0.55, 0.45, 0.38), 0.8)
	var roof := _tex_mat("clay_roof_tiles_02", Color(0.85, 0.75, 0.7) if int(h.style) % 2 == 0 else Color(0.55, 0.58, 0.62), 0.5)

	_box(root, Vector3(w + 0.4, 1.0, d + 0.4), Vector3(0, 0.0, 0), stone)
	_box(root, Vector3(w, wall_h, d), Vector3(0, 0.5 + wall_h * 0.5, 0), plaster)
	# Timber frame: corner posts, floor beams and a few braces.
	var t := 0.22
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_box(root, Vector3(t, wall_h, t), Vector3(sx * w * 0.5, 0.5 + wall_h * 0.5, sz * d * 0.5), timber)
	for f in floors + 1:
		var y := 0.5 + f * 3.0
		_box(root, Vector3(w + 0.05, t, t), Vector3(0, y, d * 0.5), timber)
		_box(root, Vector3(w + 0.05, t, t), Vector3(0, y, -d * 0.5), timber)
		_box(root, Vector3(t, t, d + 0.05), Vector3(w * 0.5, y, 0), timber)
		_box(root, Vector3(t, t, d + 0.05), Vector3(-w * 0.5, y, 0), timber)
	for f in floors:
		for sx in [-1, 1]:
			_box(root, Vector3(t, 3.4, t), Vector3(sx * w * 0.3, 0.5 + f * 3.0 + 1.5, d * 0.5 + 0.02), timber, Vector3(0, 0, sx * 0.55))
	# Gable roof.
	var pitch := 0.65
	var half_span := w * 0.5 + 0.6
	var rise := tan(pitch) * half_span
	var slope_len := half_span / cos(pitch)
	var top := 0.5 + wall_h
	for sx in [-1, 1]:
		_box(root, Vector3(slope_len, 0.25, d + 1.2), Vector3(sx * half_span * 0.5, top + rise * 0.5, 0), roof, Vector3(0, 0, -sx * pitch))
	# Gable ends.
	var gable := SurfaceTool.new()
	gable.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sz in [-1, 1]:
		var z: float = sz * d * 0.5
		var tri := [Vector3(-w * 0.5, top, z), Vector3(w * 0.5, top, z), Vector3(0, top + tan(pitch) * w * 0.5, z)]
		if sz < 0:
			tri = [tri[1], tri[0], tri[2]]
		for v in tri:
			gable.add_vertex(v)
	gable.generate_normals()
	var gm := MeshInstance3D.new()
	gm.mesh = gable.commit()
	gm.material_override = plaster
	root.add_child(gm)
	# Chimney.
	_box(root, Vector3(0.7, 2.2, 0.7), Vector3(w * 0.25, top + rise * 0.6 + 0.6, -d * 0.2), stone)
	# Door and windows on the street side (+z).
	var door := _tex_mat("weathered_brown_planks", Color(0.4, 0.28, 0.2), 1.2)
	_box(root, Vector3(1.1, 2.1, 0.12), Vector3(-w * 0.15, 0.5 + 1.05, d * 0.5 + 0.05), door)
	for f in floors:
		for wx in [-0.35, 0.2, 0.38]:
			if f == 0 and wx < -0.2:
				continue
			_box(root, Vector3(0.9, 1.1, 0.1), Vector3(w * wx, 0.5 + f * 3.0 + 1.7, d * 0.5 + 0.04), window_mat)
			_box(root, Vector3(1.1, 0.12, 0.2), Vector3(w * wx, 0.5 + f * 3.0 + 1.1, d * 0.5 + 0.08), timber)
	# Collision.
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(w + 0.4, wall_h + 1.0 + rise, d + 0.4)
	col.shape = shape
	col.position = Vector3(0, (wall_h + 1.0 + rise) * 0.5 - 0.5, 0)
	body.add_child(col)
	root.add_child(body)
