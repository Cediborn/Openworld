class_name TerrainGen
extends RefCounted
## Height function for the green valley, shared by the mesh, the collision,
## and everything that gets placed on the ground.

const SIZE := 640.0          # metres, square, centred on the origin
const STEP := 2.0            # metres between vertices
const RES := int(SIZE / STEP) + 1

var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()


func _init(seed_value: int = 1337) -> void:
	_hills.seed = seed_value
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 0.004
	_hills.fractal_octaves = 4
	_detail.seed = seed_value + 1
	_detail.frequency = 0.03
	_detail.fractal_octaves = 3
	_ridge.seed = seed_value + 2
	_ridge.frequency = 0.006
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 5


## X position of the path's centre line at depth z.
static func path_x(z: float) -> float:
	return sin(z * 0.012) * 26.0 + sin(z * 0.031 + 1.7) * 7.0


## 1.0 on the path, fading to 0.0 a few metres away.
static func path_mask(x: float, z: float) -> float:
	var d: float = absf(x - path_x(z))
	return 1.0 - smoothstep(1.4, 2.6, d)


func height(x: float, z: float) -> float:
	var h: float = _hills.get_noise_2d(x, z) * 9.0 + _detail.get_noise_2d(x, z) * 0.6
	# Flatten a strip along the path so it reads as a trail.
	var d: float = absf(x - path_x(z))
	h = lerpf(h * 0.35, h, smoothstep(3.0, 18.0, d))
	# Mountains rise towards the edge of the map.
	var r: float = Vector2(x, z).length()
	var edge: float = smoothstep(200.0, 310.0, r)
	var peaks: float = (_ridge.get_noise_2d(x, z) * 0.5 + 0.5)
	h += edge * edge * (40.0 + peaks * 110.0)
	return h


func normal(x: float, z: float) -> Vector3:
	var e := 0.75
	var hx: float = height(x + e, z) - height(x - e, z)
	var hz: float = height(x, z + e) - height(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


func build_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(RES * RES)
	norms.resize(RES * RES)
	cols.resize(RES * RES)
	var half := SIZE * 0.5
	for j in RES:
		for i in RES:
			var x: float = -half + i * STEP
			var z: float = -half + j * STEP
			var k: int = j * RES + i
			verts[k] = Vector3(x, height(x, z), z)
			norms[k] = normal(x, z)
			cols[k] = Color(path_mask(x, z), 0, 0, 1)
	idx.resize((RES - 1) * (RES - 1) * 6)
	var n := 0
	for j in RES - 1:
		for i in RES - 1:
			var a: int = j * RES + i
			var b: int = a + 1
			var c: int = a + RES
			var d: int = c + 1
			idx[n] = a; idx[n + 1] = b; idx[n + 2] = c
			idx[n + 3] = b; idx[n + 4] = d; idx[n + 5] = c
			n += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func build_collision() -> HeightMapShape3D:
	var shape := HeightMapShape3D.new()
	shape.map_width = RES
	shape.map_depth = RES
	var data := PackedFloat32Array()
	data.resize(RES * RES)
	var half := SIZE * 0.5
	for j in RES:
		for i in RES:
			data[j * RES + i] = height(-half + i * STEP, -half + j * STEP)
	shape.map_data = data
	return shape
