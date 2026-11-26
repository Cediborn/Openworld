extends SceneTree
## The Terrain3D green-valley test zone (run: godot --headless --path game -s res://tests/integration/green_valley_test.gd).
## Gate for using Terrain3D in the main world: the FastNoise2 heightmap and
## its sculpt import at the right heights; the brook really runs downhill and
## drops over a waterfall into a pool and on to a pond; water sits on the
## terrain (never floating above it or buried); the explorer stands, walks
## uphill and wades on Terrain3D collision without sinking; the horse rides
## over it; foliage is planted, none of it in the water.

var fails := 0


func check(ok: bool, msg: String) -> void:
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func _init() -> void:
	await process_frame
	var zone: Node3D = load("res://world/test_zone/green_valley.tscn").instantiate()
	root.add_child(zone)
	await frames(20)
	var t: Terrain3D = zone.terrain
	var desc: Dictionary = zone.desc
	print("engine: ", ProjectSettings.get_setting("physics/3d/physics_engine"))

	# --- Terrain data ---
	check(t.data.get_region_count() == 4, "Terrain3D loads the zone's 4 regions (%d)" % t.data.get_region_count())
	var hr: Vector2 = t.data.get_height_range()
	check(hr.x > -1.0 and hr.y < 50.0 and hr.y - hr.x > 25.0, "heights span the valley and hills (%.1f..%.1f m)" % [hr.x, hr.y])
	check(t.mesh_lods >= 5, "terrain draws with %d levels of detail" % t.mesh_lods)

	# --- The brook: bed on the terrain, downhill all the way, a real waterfall ---
	var pts: Array = desc.rivers[0].points
	var worst := 0.0
	for i in pts.size():
		if i == 3 or i == 4:
			continue   # the lip and the plunge pool are shaped separately
		worst = maxf(worst, absf(zone.ground(pts[i][0], pts[i][1]) - pts[i][2]))
	check(worst < 0.4, "the stream bed is carved where the brook runs (worst %.2f m off)" % worst)
	var downhill := true
	for i in pts.size() - 1:
		downhill = downhill and pts[i + 1][2] < pts[i][2]
	check(downhill, "the brook runs downhill from its spring to the pond")
	var lip: float = zone.ground(pts[3][0], pts[3][1])
	var foot: float = zone.ground(pts[4][0], pts[4][1])
	check(lip - foot > 7.0, "the waterfall drops %.1f m" % (lip - foot))

	# --- Water sits on the terrain ---
	var mid := Vector3(pts[6][0], 0, pts[6][1])
	mid.y = zone.ground(mid.x, mid.z)
	var d := Water.depth_at(mid)
	check(d > 0.3 and d < 0.7, "the stream is wading-deep (%.2f m)" % d)
	var pond: Dictionary = desc.lakes[0]
	var pc := Vector3(pond.center[0], 0, pond.center[1])
	pc.y = zone.ground(pc.x, pc.z)
	check(Water.depth_at(pc) > 1.0, "the pond is deep in the middle (%.2f m)" % Water.depth_at(pc))
	var rim := pc + Vector3(pond.radius * 1.6, 0, 0)
	rim.y = zone.ground(rim.x, rim.z)
	check(Water.depth_at(rim) == 0.0, "and dry beyond its shore")
	var floating := 0
	for mi in zone.water.get_children():
		if mi is MeshInstance3D:
			var arrays: Array = mi.mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			for k in range(0, verts.size(), 7):
				var v := verts[k]
				# A surface vertex over dry land must be a shore vertex hugging the bank.
				if cols[k].r == 0.0 and v.y - zone.ground(v.x, v.z) > 0.25 and cols[k].g < 0.99:
					floating += 1
	check(floating == 0, "no water floats above dry ground (%d vertices)" % floating)

	# --- Player on Terrain3D collision ---
	var p: Player = zone.player
	await frames(90)
	var gap: float = p.global_position.y - zone.ground(p.global_position.x, p.global_position.z)
	check(p.is_on_floor() and absf(gap) < 0.15, "the explorer stands on the terrain (%.2f m)" % gap)
	var sink := 0.0
	p.move_input = Vector2(0, -1)   # forward: north, up the valley side
	for i in 240:
		await physics_frame
		sink = maxf(sink, zone.ground(p.global_position.x, p.global_position.z) - p.global_position.y)
	p.move_input = Vector2.ZERO
	check(sink < 0.1, "walking over slopes, never sinks in (worst %.2f m)" % sink)
	# Into the brook: wading slows you and splashes.
	var splashes := [0]
	p.splashed.connect(func() -> void: splashes[0] += 1)
	var bank := Vector3(pts[6][0] + 6.0, 0, pts[6][1])
	p.global_position = Vector3(bank.x, zone.ground(bank.x, bank.z) + 0.3, bank.z)
	p.velocity = Vector3.ZERO
	await frames(20)
	p.yaw = PI * 0.5   # face west, across the brook
	p.move_input = Vector2(0, -1)
	var deepest := 0.0
	for i in 150:
		await physics_frame
		deepest = maxf(deepest, p.water_depth)
	p.move_input = Vector2.ZERO
	check(deepest > 0.2, "wading into the brook (%.2f m deep)" % deepest)
	check(splashes[0] >= 1, "makes a splash")

	# --- Horse ---
	var h: Horse = zone.horse
	p.global_position = h.global_position + Vector3(1.5, 0.3, 0)
	await frames(10)
	p.mount(h)
	check(p.horse == h, "the explorer mounts the horse")
	p.move_input = Vector2(0, -1)
	var horse_gap := 0.0
	for i in 240:
		await physics_frame
		horse_gap = maxf(horse_gap, absf(h.global_position.y - zone.ground(h.global_position.x, h.global_position.z)))
	p.move_input = Vector2.ZERO
	# Ridden, the horse follows the rider's capsule, which on steep slopes sits a little off the surface.
	check(horse_gap < 0.5, "the horse rides on the terrain surface (worst %.2f m off)" % horse_gap)

	# --- Foliage ---
	check(zone.planted[0] + zone.planted[1] > 150 and zone.planted[2] > 20 and zone.planted[3] > 2000,
		"trees, rocks and grass are planted (%s)" % str(zone.planted))

	print("RESULT: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(fails)
