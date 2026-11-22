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


func load_data() -> bool:
	if not FileAccess.file_exists("res://data/height.bin"):
		return false
	heights = FileAccess.get_file_as_bytes("res://data/height.bin").to_float32_array()
	biome = FileAccess.get_file_as_bytes("res://data/biome.bin")
	mask = FileAccess.get_file_as_bytes("res://data/mask.bin")
	var js := FileAccess.get_file_as_string("res://data/village.json")
	houses = JSON.parse_string(js) if js != "" else []
	return heights.size() == RES * RES


func _cell(x: float, z: float) -> Vector2:
	return Vector2(clampf((x + SIZE * 0.5) / STEP, 0.0, RES - 1.001), clampf((z + SIZE * 0.5) / STEP, 0.0, RES - 1.001))


## Ground height at a point, bilinear between samples.
func height(x: float, z: float) -> float:
	var c := _cell(x, z)
	var i := int(c.x)
	var j := int(c.y)
	var fx := c.x - i
	var fz := c.y - j
	var k := j * RES + i
	var a := lerpf(heights[k], heights[k + 1], fx)
	var b := lerpf(heights[k + RES], heights[k + RES + 1], fx)
	return lerpf(a, b, fz)


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
