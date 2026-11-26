class_name WorldData
extends RefCounted
## The baked world: heights, zone weights and trail masks, loaded from data/.
## Everything that needs the ground height or "which zone am I in" asks here.

const SIZE := 1024.0                 ## metres, square, centred on the origin
const STEP := 2.0                    ## metres between samples
const RES := 513                     ## samples per side
const LAVA_LEVEL := 1.0              ## height of the molten lava surface
const VILLAGE_CENTER := Vector2(-300, 0)
const ZONE_NAMES := ["Hub Meadow", "Frost Peaks", "Ember Wastes", "Glow Hollow", "Brickton"]
## Sector direction (x, z) of each outer zone: north, east, south, west.
const ZONE_DIRS := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]

var heights := PackedFloat32Array()
var biome := PackedByteArray()
var mask := PackedByteArray()
var houses: Array = []
var _floors := {}            # Vector2i cell -> [[centre, yaw, half size, y], ...]
const FLOOR_CELL := 16.0


## Zone weights [meadow, snow, lava, glow, village] for a point. Sums to 1.
static func biome_weights(x: float, z: float) -> Array:
	var r := Vector2(x, z).length()
	var outer := smoothstep(140.0, 250.0, r)
	var dir := Vector2(x, z) / maxf(r, 0.001)
	var w := [0.0, 0.0, 0.0, 0.0]
	var total := 0.0
	for i in 4:
		var c: float = maxf(dir.dot(ZONE_DIRS[i]), 0.0)
		w[i] = pow(c, 6.0)
		total += w[i]
	var out := [1.0 - outer]
	for i in 4:
		out.append(outer * w[i] / maxf(total, 0.0001))
	return out


## True where molten lava covers the ground (the crater in Ember Wastes).
## Horses never path into it, and a horse left there is led out.
func is_lava(x: float, z: float) -> bool:
	if absf(x - 360.0) > 150.0 or absf(z) > 260.0:
		return false
	return height(x, z) < LAVA_LEVEL + 0.35 and zone(x, z)[2] > 0.3


func load_data() -> bool:
	if not FileAccess.file_exists("res://data/height.bin"):
		return false
	heights = FileAccess.get_file_as_bytes("res://data/height.bin").to_float32_array()
	biome = FileAccess.get_file_as_bytes("res://data/biome.bin")
	mask = FileAccess.get_file_as_bytes("res://data/mask.bin")
	var js := FileAccess.get_file_as_string("res://data/village.json")
	houses = JSON.parse_string(js) if js != "" else []
	# Landmarks (your house, the church) reserve their ground too, so trees,
	# rocks and lamps keep clear. Village skips "reserved" entries when building.
	var lm = JSON.parse_string(FileAccess.get_file_as_string("res://data/landmarks.json")) if FileAccess.file_exists("res://data/landmarks.json") else null
	if lm is Dictionary:
		for e: Dictionary in lm.landmarks:
			var r := e.duplicate()
			r["reserved"] = true
			r["y"] = height(float(e.x), float(e.z))
			houses.append(r)
	if heights.size() != RES * RES:
		return false
	carve_water()
	return true


# ---------- Water (data/water.json, planned by tools/world_generation/plan_water.py) ----------

## The island's lakes, streams and falls, as planned from its terrain.
var water: Dictionary = {}
## 1 where there is water (lakes below their level, stream channels).
var wet := PackedByteArray()


## Digs the dug ponds and brook channels into the heights (only ever lower),
## then marks every wet cell: as trail ground (so grass, trees and rocks keep
## out and the bed is mud) and in `wet` (for is_water and the map).
func carve_water() -> void:
	wet.resize(RES * RES)
	wet.fill(0)
	if not FileAccess.file_exists("res://data/water.json"):
		return
	water = JSON.parse_string(FileAccess.get_file_as_string("res://data/water.json"))
	for r in water.get("rivers", []):
		var pts: Array = r.points
		var half: float = r.width * 0.5
		var reach := half + 4.0
		for k in pts.size() - 1:
			var a := Vector2(pts[k][0], pts[k][1])
			var b := Vector2(pts[k + 1][0], pts[k + 1][1])
			var lo := _cell(minf(a.x, b.x) - reach, minf(a.y, b.y) - reach)
			var hi := _cell(maxf(a.x, b.x) + reach, maxf(a.y, b.y) + reach)
			for j in range(int(lo.y), int(hi.y) + 2):
				for i in range(int(lo.x), int(hi.x) + 2):
					if i >= RES or j >= RES:
						continue
					var p := Vector2(-SIZE * 0.5 + i * STEP, -SIZE * 0.5 + j * STEP)
					var ab := b - a
					var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
					var d := p.distance_to(a + ab * t)
					if d > reach:
						continue
					var bed := lerpf(pts[k][2], pts[k + 1][2], t)
					var idx := j * RES + i
					if r.get("carve", false):
						var g := bed + 0.5 * (d / half) ** 2 if d < half else bed + 0.5 + (d - half) * 0.6
						heights[idx] = minf(heights[idx], g)
					if d < half + 0.5:
						_mark_wet(idx)
	for l in water.get("lakes", []):
		var c := Vector2(l.center[0], l.center[1])
		var rad: float = l.radius
		var level: float = l.level
		var lo := _cell(c.x - rad * 1.25, c.y - rad * 1.25)
		var hi := _cell(c.x + rad * 1.25, c.y + rad * 1.25)
		for j in range(int(lo.y), int(hi.y) + 2):
			for i in range(int(lo.x), int(hi.x) + 2):
				if i >= RES or j >= RES:
					continue
				var p := Vector2(-SIZE * 0.5 + i * STEP, -SIZE * 0.5 + j * STEP)
				var d := p.distance_to(c)
				var idx := j * RES + i
				if l.has("carve") and d < rad:
					heights[idx] = minf(heights[idx], lerpf(float(l.carve.floor), level + 0.4, (d / rad) ** 2))
				if d < rad * 1.25 and heights[idx] < level:
					_mark_wet(idx)


func _mark_wet(idx: int) -> void:
	wet[idx] = 1
	mask[idx * 2 + 1] = 255


## Whether a point is in a lake or stream.
func is_water(x: float, z: float) -> bool:
	if wet.is_empty():
		return false
	var c := _cell(x, z)
	return wet[int(c.y + 0.5) * RES + int(c.x + 0.5)] == 1


func _cell(x: float, z: float) -> Vector2:
	return Vector2(clampf((x + SIZE * 0.5) / STEP, 0.0, RES - 1.001), clampf((z + SIZE * 0.5) / STEP, 0.0, RES - 1.001))


## Ground height at a point, on the same two triangles per cell that the
## collision heightmap and the terrain mesh use (split along the diagonal from
## the cell's +x/-z corner to its -x/+z corner), so anything placed with it
## stands exactly on the ground the player sees and walks on. (Bilinear
## blending differed from that surface by up to a metre on rough ground.)
func height(x: float, z: float) -> float:
	var g := terrain_height(x, z)
	if _floors.is_empty():
		return g
	var key := Vector2i(floori(x / FLOOR_CELL), floori(z / FLOOR_CELL))
	for f: Array in _floors.get(key, []):
		var l := Vector3(x - f[0].x, 0, z - f[0].y).rotated(Vector3.UP, -f[1])
		if absf(l.x) <= f[2].x and absf(l.z) <= f[2].y:
			g = maxf(g, f[3])
	return g


## Building floors (walk-in houses, the church): height() returns the floor
## inside their footprint, so people and things placed there stand on it.
## centre (x, z), yaw (radians), size (m), floor height.
func add_floor(centre: Vector2, yaw: float, size: Vector2, y: float) -> void:
	var r := size.length() * 0.5
	var f := [centre, yaw, size * 0.5, y]
	for j in range(floori((centre.y - r) / FLOOR_CELL), floori((centre.y + r) / FLOOR_CELL) + 1):
		for i in range(floori((centre.x - r) / FLOOR_CELL), floori((centre.x + r) / FLOOR_CELL) + 1):
			var key := Vector2i(i, j)
			if not _floors.has(key):
				_floors[key] = []
			_floors[key].append(f)


## Ground height of the terrain alone (ignores building floors).
func terrain_height(x: float, z: float) -> float:
	var c := _cell(x, z)
	var i := int(c.x)
	var j := int(c.y)
	var fx := c.x - i
	var fz := c.y - j
	var k := j * RES + i
	if fx + fz <= 1.0:
		return heights[k] + (heights[k + 1] - heights[k]) * fx + (heights[k + RES] - heights[k]) * fz
	var h11: float = heights[k + RES + 1]
	return h11 + (heights[k + RES] - h11) * (1.0 - fx) + (heights[k + 1] - h11) * (1.0 - fz)


func normal(x: float, z: float) -> Vector3:
	var e := STEP
	return Vector3(height(x - e, z) - height(x + e, z), 2.0 * e, height(x, z - e) - height(x, z + e)).normalized()


## [meadow, snow, lava, glow, village] from the baked map (nearest sample).
func zone(x: float, z: float) -> Array:
	var c := _cell(x, z)
	var k := (int(c.y + 0.5) * RES + int(c.x + 0.5)) * 4
	var s := biome[k] / 255.0
	var l := biome[k + 1] / 255.0
	var g := biome[k + 2] / 255.0
	var v := biome[k + 3] / 255.0
	return [maxf(0.0, 1.0 - s - l - g - v), s, l, g, v]


func dominant_zone(x: float, z: float) -> int:
	var w := zone(x, z)
	var best := 0
	for i in 5:
		if w[i] > w[best]:
			best = i
	return best


## 1.0 on a dirt trail or cobblestone road.
func on_path(x: float, z: float) -> float:
	var c := _cell(x, z)
	var k := (int(c.y + 0.5) * RES + int(c.x + 0.5)) * 2
	return maxf(mask[k], mask[k + 1]) / 255.0


func height_texture() -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_from_data(RES, RES, false, Image.FORMAT_RF, heights.to_byte_array()))


func biome_texture() -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_from_data(RES, RES, false, Image.FORMAT_RGBA8, biome))


func mask_texture() -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_from_data(RES, RES, false, Image.FORMAT_RG8, mask))


func build_collision() -> HeightMapShape3D:
	var shape := HeightMapShape3D.new()
	shape.map_width = RES
	shape.map_depth = RES
	shape.map_data = heights
	return shape
