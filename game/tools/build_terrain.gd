extends SceneTree
## Builds a Terrain3D zone (heights, texture painting) from a FastNoise2
## heightmap and the zone's hand-made sculpt, then saves the Terrain3D data.
##
##   godot --headless --path game -s res://tools/build_terrain.gd -- res://world/test_zone/green_valley.json
##
## Input: the zone JSON (rivers, falls, lakes, sculpt; see green_valley.json)
## and <source>.r16 / <source>.json written by tools/world_generation/heightgen.
## Output: Terrain3D region files in the zone's data_dir. Re-running rebuilds
## from the same seed and the same sculpt, so the result is always the same;
## hand-made places live in the JSON, never only in the generated file.

## Texture slots painted into the control map (green_valley.gd loads the
## matching textures into the same slots).
const GRASS := 0
const DRY_GRASS := 1
const ROCK := 2
const FOREST_FLOOR := 3
const MUD := 4
const WET_ROCK := 5


func _init() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var desc_path := args[0] if args.size() > 0 else "res://world/test_zone/green_valley.json"
	var desc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(desc_path))
	var src: String = desc.source
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(src + ".json"))
	var n: int = meta.size
	var spacing: float = meta.spacing
	var hmin: float = meta.height_min
	var hmax: float = meta.height_max
	var raw := FileAccess.get_file_as_bytes(src + ".r16")
	assert(raw.size() == n * n * 2, "heightmap size mismatch")
	var origin := Vector2(desc.origin[0], desc.origin[1])
	var h := PackedFloat32Array()
	h.resize(n * n)
	for i in n * n:
		h[i] = hmin + (raw.decode_u16(i * 2) / 65535.0) * (hmax - hmin)

	var t0 := Time.get_ticks_msec()
	var water := _sculpt(h, n, spacing, origin, desc)
	print("sculpted in %d ms" % (Time.get_ticks_msec() - t0))

	var img := Image.create_from_data(n, n, false, Image.FORMAT_RF, h.to_byte_array())
	var t := Terrain3D.new()
	t.free_editor_textures = false
	t.region_size = Terrain3D.SIZE_256
	t.vertex_spacing = spacing
	root.add_child(t)
	t.data.import_images([img, null, null], Vector3(origin.x, 0, origin.y), 0.0, 1.0)
	print("imported")
	_paint(t, h, n, spacing, origin, desc, water)
	print("painted in %d ms" % (Time.get_ticks_msec() - t0))
	var dir: String = desc.data_dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	t.data.save_directory(dir)
	print("built %s: %d x %d at %.1f m, %d regions -> %s" % [desc_path, n, n, spacing, t.data.get_region_count(), dir])
	quit(0)


# ---------- Hand-made sculpt ----------

## Carves each river's valley and channel along its bed line, steps the bed
## down at waterfalls, and digs pools and ponds. Returns, per vertex, the
## distance to the nearest stream (for painting).
func _sculpt(h: PackedFloat32Array, n: int, spacing: float, origin: Vector2, desc: Dictionary) -> PackedFloat32Array:
	var sc: Dictionary = desc.get("sculpt", {})
	var reach: float = sc.get("valley_radius", 60.0)
	var slope: float = sc.get("bank_slope", 0.3)
	var near := PackedFloat32Array()
	near.resize(n * n)
	near.fill(1e9)
	for r in desc.get("rivers", []):
		var pts: Array = r.points
		var half: float = r.width * 0.5
		for j in n:
			for i in n:
				var p := origin + Vector2(i, j) * spacing
				var best := 1e9
				var bed := 0.0
				for k in pts.size() - 1:
					var a := Vector2(pts[k][0], pts[k][1])
					var b := Vector2(pts[k + 1][0], pts[k + 1][1])
					var ab := b - a
					var tt := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
					var d := p.distance_to(a + ab * tt)
					if d < best:
						best = d
						bed = lerpf(pts[k][2], pts[k + 1][2], tt)
				var idx := j * n + i
				near[idx] = minf(near[idx], best)
				if best > reach:
					continue
				# Channel: a soft U a little deeper than the water; then banks rising to the valley walls.
				var ground := bed + 0.65 * minf(best / half, 1.0) ** 2 if best < half else bed + 0.65 + (best - half) * slope
				var w := smoothstep(reach, reach * 0.35, best)
				h[idx] = lerpf(h[idx], ground, w)
	for pool in sc.get("pools", []):
		var c := Vector2(pool.center[0], pool.center[1])
		var rad: float = pool.radius
		var reach2: float = rad * float(pool.get("blend", 2.2))   # how far out the bowl eases back into the land
		for j in n:
			for i in n:
				var p := origin + Vector2(i, j) * spacing
				var d := p.distance_to(c)
				if d > reach2:
					continue
				var idx := j * n + i
				# A bowl down to `floor` inside, easing back to the land out to `reach2`.
				if d < rad:
					h[idx] = lerpf(pool.floor, pool.rim, (d / rad) ** 2)
				else:
					h[idx] = lerpf(pool.rim, h[idx], smoothstep(rad, reach2, d))
	return near


# ---------- Texture painting ----------

func _paint(t: Terrain3D, h: PackedFloat32Array, n: int, spacing: float, origin: Vector2, desc: Dictionary, near: PackedFloat32Array) -> void:
	var fl := FastNoiseLite.new()
	fl.seed = 77
	fl.frequency = 0.012
	var falls := []
	for f in desc.get("falls", []):
		falls.append(Vector2(f.top[0], f.top[2]).lerp(Vector2(f.bottom[0], f.bottom[2]), 0.5))
	var shores := []
	for l in desc.get("lakes", []):
		shores.append([Vector2(l.center[0], l.center[1]), float(l.radius), float(l.level)])
	for j in n:
		for i in n:
			var idx := j * n + i
			var p := origin + Vector2(i, j) * spacing
			var hx := h[j * n + mini(i + 1, n - 1)] - h[j * n + maxi(i - 1, 0)]
			var hz := h[mini(j + 1, n - 1) * n + i] - h[maxi(j - 1, 0) * n + i]
			var steep := Vector2(hx, hz).length() / (2.0 * spacing)
			var id := GRASS
			if fl.get_noise_2d(p.x, p.y) > 0.25:
				id = FOREST_FLOOR
			if h[idx] > 33.0 and steep < 0.35:
				id = DRY_GRASS
			if steep > 0.75:
				id = ROCK
			for f in falls:
				if p.distance_to(f) < 12.0 and steep > 0.4:
					id = WET_ROCK
			if near[idx] < 3.2:
				id = MUD
			for s in shores:
				if p.distance_to(s[0]) < s[1] * 1.2 and h[idx] < s[2] + 0.5:
					id = MUD
			var pos := Vector3(p.x, 0, p.y)
			t.data.set_control_base_id(pos, id)
			t.data.set_control_overlay_id(pos, GRASS)
			t.data.set_control_blend(pos, 0.0)
			t.data.set_control_auto(pos, false)
	t.data.update_maps(Terrain3DRegion.TYPE_CONTROL)
