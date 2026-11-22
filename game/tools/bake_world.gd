extends SceneTree
## Bakes the world map into small data files the game loads instantly:
##   data/height.bin   513x513 float32 heights (metres)
##   data/biome.bin    513x513 RGBA8: R snow, G lava, B glow forest, A village (meadow = rest)
##   data/mask.bin     513x513 RG8: R dirt trail, G cobblestone road
##   data/village.json house placements
## Run: godot --headless --path game -s res://tools/bake_world.gd

const RES := WorldData.RES
const SIZE := WorldData.SIZE
const STEP := WorldData.STEP

var hills := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var ridge := FastNoiseLite.new()
var basalt := FastNoiseLite.new()
var channel := FastNoiseLite.new()
var trail_d := PackedFloat32Array()
var road_d := PackedFloat32Array()


func _init() -> void:
	hills.seed = 11; hills.frequency = 0.004; hills.fractal_octaves = 4
	detail.seed = 12; detail.frequency = 0.03; detail.fractal_octaves = 3
	ridge.seed = 13; ridge.frequency = 0.0055; ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED; ridge.fractal_octaves = 5
	basalt.seed = 14; basalt.frequency = 0.012; basalt.fractal_octaves = 3
	channel.seed = 15; channel.frequency = 0.006; channel.fractal_octaves = 2

	var t0 := Time.get_ticks_msec()
	trail_d = _distance_field(_trails(), 60.0)
	var houses := _village_layout()
	road_d = _distance_field(_village_roads(houses), 30.0)

	var heights := PackedFloat32Array(); heights.resize(RES * RES)
	var biome := PackedByteArray(); biome.resize(RES * RES * 4)
	var mask := PackedByteArray(); mask.resize(RES * RES * 2)
	for j in RES:
		for i in RES:
			var x := -SIZE * 0.5 + i * STEP
			var z := -SIZE * 0.5 + j * STEP
			var k := j * RES + i
			var w := WorldData.biome_weights(x, z)
			heights[k] = _height(x, z, w, trail_d[k])
			biome[k * 4] = int(w[1] * 255.0)
			biome[k * 4 + 1] = int(w[2] * 255.0)
			biome[k * 4 + 2] = int(w[3] * 255.0)
			biome[k * 4 + 3] = int(w[4] * 255.0)
			mask[k * 2] = int((1.0 - smoothstep(1.3, 2.6, trail_d[k])) * 255.0)
			mask[k * 2 + 1] = int((1.0 - smoothstep(2.0, 3.4, road_d[k])) * 255.0)
	_flatten_houses(heights, houses)
	_write("res://data/height.bin", heights.to_byte_array())
	_write("res://data/biome.bin", biome)
	_write("res://data/mask.bin", mask)
	var f := FileAccess.open("res://data/village.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(houses, " "))
	print("baked in %d ms, %d houses" % [Time.get_ticks_msec() - t0, houses.size()])
	quit()


func _height(x: float, z: float, w: Array, td: float) -> float:
	var r := Vector2(x, z).length()
	var base := hills.get_noise_2d(x, z)
	var det := detail.get_noise_2d(x, z)
	var near_trail := 1.0 - smoothstep(10.0, 70.0, td)

	var meadow := base * 8.0 + det * 0.5
	var rid := ridge.get_noise_2d(x, z) * 0.5 + 0.5
	var snow := 14.0 + base * 6.0 + rid * 110.0 * smoothstep(170.0, 380.0, r) * (1.0 - near_trail * 0.85)
	var b := basalt.get_noise_2d(x, z) * 14.0
	var terraced := lerpf(b, floor(b / 2.5) * 2.5, 0.7)
	var lava := 9.0 + terraced * 0.6 + det * 0.6
	var ch := absf(channel.get_noise_2d(x, z))
	var carve := (1.0 - smoothstep(0.025, 0.06, ch)) * smoothstep(0.35, 0.7, w[2]) * (1.0 - near_trail) * smoothstep(200.0, 260.0, r)
	lava = lerpf(lava, WorldData.LAVA_LEVEL - 2.0, carve)
	var glow := -1.5 + base * 5.0 + det * 1.2
	var village := 2.0 + base * 1.5 + det * 0.3

	var h: float = w[0] * meadow + w[1] * snow + w[2] * lava + w[3] * glow + w[4] * village
	# Mountain wall around the edge of the island.
	var edge := smoothstep(430.0, 505.0, r)
	h += edge * edge * (90.0 + rid * 140.0)
	return h


# ---------- Trails and roads ----------

func _trails() -> Array:
	var ends := [Vector2(0, -360), Vector2(360, 0), Vector2(0, 360), Vector2(-330, 0)]
	var lines := []
	for e in ends:
		var pts := []
		var steps := 60
		var side := Vector2(-e.y, e.x).normalized()
		for s in steps + 1:
			var t := float(s) / steps
			var p: Vector2 = e * t + side * (sin(t * 7.0 + e.x * 0.01) * 18.0 * sin(t * PI))
			pts.append(p)
		lines.append(pts)
	# A loop around the hub meadow.
	var loop := []
	for s in 49:
		var a := TAU * s / 48.0
		loop.append(Vector2(cos(a), sin(a)) * (95.0 + sin(a * 3.0) * 12.0))
	lines.append(loop)
	return lines


func _village_layout() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var houses := []
	var center := WorldData.VILLAGE_CENTER
	# Two curving rows of houses facing a main street running east-west.
	for row in [-1, 1]:
		for n in 7:
			var x: float = center.x - 66.0 + n * 22.0 + rng.randf_range(-3, 3)
			var street_z: float = center.y + sin(x * 0.03) * 6.0
			var z: float = street_z + row * rng.randf_range(13.0, 16.0)
			houses.append({
				"x": x, "z": z,
				"rot": (0.0 if row < 0 else PI) + rng.randf_range(-0.12, 0.12),
				"w": rng.randf_range(7.0, 10.0), "d": rng.randf_range(6.5, 8.5),
				"floors": rng.randi_range(1, 2), "style": rng.randi_range(0, 3),
			})
	return houses


func _village_roads(houses: Array) -> Array:
	var center := WorldData.VILLAGE_CENTER
	var street := []
	for s in 41:
		var x: float = center.x - 90.0 + s * 4.5
		street.append(Vector2(x, center.y + sin(x * 0.03) * 6.0))
	var lines := [street]
	for h in houses:
		var street_z: float = center.y + sin(h.x * 0.03) * 6.0
		lines.append([Vector2(h.x, h.z), Vector2(h.x, street_z)])
	return lines


## Distance (m) from every grid point to the nearest polyline, capped at max_d.
func _distance_field(lines: Array, max_d: float) -> PackedFloat32Array:
	var d := PackedFloat32Array(); d.resize(RES * RES); d.fill(max_d)
	var reach := int(ceil(max_d / STEP))
	for pts in lines:
		for s in pts.size() - 1:
			var a: Vector2 = pts[s]
			var b: Vector2 = pts[s + 1]
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
			var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
			var i0: int = clampi(int((lo.x + SIZE * 0.5) / STEP) - reach, 0, RES - 1)
			var i1: int = clampi(int((hi.x + SIZE * 0.5) / STEP) + reach, 0, RES - 1)
			var j0: int = clampi(int((lo.y + SIZE * 0.5) / STEP) - reach, 0, RES - 1)
			var j1: int = clampi(int((hi.y + SIZE * 0.5) / STEP) + reach, 0, RES - 1)
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					var p := Vector2(-SIZE * 0.5 + i * STEP, -SIZE * 0.5 + j * STEP)
					var q := Geometry2D.get_closest_point_to_segment(p, a, b)
					var dd := p.distance_to(q)
					var k := j * RES + i
					if dd < d[k]:
						d[k] = dd
	return d


func _flatten_houses(heights: PackedFloat32Array, houses: Array) -> void:
	for h in houses:
		var ci := int((h.x + SIZE * 0.5) / STEP)
		var cj := int((h.z + SIZE * 0.5) / STEP)
		var base: float = heights[cj * RES + ci]
		h["y"] = base
		var rad := int(ceil(maxf(h.w, h.d) * 0.8 / STEP)) + 3
		for j in range(cj - rad, cj + rad + 1):
			for i in range(ci - rad, ci + rad + 1):
				if i < 0 or j < 0 or i >= RES or j >= RES:
					continue
				var dist := Vector2(i - ci, j - cj).length() * STEP
				var t := 1.0 - smoothstep(maxf(h.w, h.d) * 0.6, maxf(h.w, h.d) * 0.6 + 6.0, dist)
				var k := j * RES + i
				heights[k] = lerpf(heights[k], base, t)


func _write(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data"))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
