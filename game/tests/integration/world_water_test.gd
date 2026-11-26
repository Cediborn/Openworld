extends SceneTree
## The island's water (run: godot --headless --path game -s res://tests/integration/world_water_test.gd).
## Ponds, tarns and brooks from data/water.json: they exist in every region
## that should have them, sit on the terrain, keep every road, house, quest
## spot and discovery dry, run downhill, can be waded, and the frozen tarns
## of Frost Peaks hold you up.

var fails := 0
var world: Node


func check(ok: bool, msg: String) -> void:
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func _init() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	var t0 := Time.get_ticks_msec()
	while not world.booted and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	check(world.booted, "world booted")
	world._new_game()
	var data: WorldData = world.data
	var w: Dictionary = data.water
	var p: Player = world.player
	p.max_health = 1.0e7
	p.health = 1.0e7

	# --- What there is ---
	var zones := {}
	for l in w.lakes:
		zones[data.dominant_zone(l.center[0], l.center[1])] = true
	check(w.lakes.size() >= 5 and w.rivers.size() >= 2 and w.falls.size() >= 2, "lakes %d, streams %d, waterfalls %d" % [w.lakes.size(), w.rivers.size(), w.falls.size()])
	check(zones.has(0) and zones.has(1) and zones.has(3), "water in Hub Meadow, Frost Peaks and Glow Hollow (%s)" % str(zones.keys()))
	check(world.water != null and world.water.get_child_count() > 5, "the water is built in the world")

	# --- Nothing important is flooded ---
	var spots := []
	for key in ["discoveries", "treasures", "shrines", "rare_bosses", "structures"]:
		for f in world.features.cfg.get(key, []):
			if f.has("pos"):
				spots.append(Vector2(f.pos[0], f.pos[1]))
	for qid in world.quests.defs:
		for s in world.quests.defs[qid].get("steps", []):
			if s.get("pos") is Array:
				spots.append(Vector2(s.pos[0], s.pos[-1]))
	for h in data.houses:
		spots.append(Vector2(h.x, h.z))
	var flooded := []
	for s in spots:
		if data.is_water(s.x, s.y) or Water.depth_at(Vector3(s.x, data.height(s.x, s.y), s.y)) > 0.0:
			flooded.append(s)
	check(flooded.is_empty(), "no quest spot, place, house or shrine is under water (%d checked, flooded: %s)" % [spots.size(), str(flooded)])
	var raw := FileAccess.get_file_as_bytes("res://data/mask.bin")
	var on_road := 0
	for k in WorldData.RES * WorldData.RES:
		if data.wet[k] == 1 and maxi(raw[k * 2], raw[k * 2 + 1]) > 64:
			on_road += 1
	check(on_road == 0, "no road or path is under water (%d cells)" % on_road)

	# --- Streams: downhill, carved, wadeable ---
	for r in w.rivers:
		var downhill := true
		var worst := 0.0
		for i in r.points.size():
			var pt: Array = r.points[i]
			if i > 0:
				downhill = downhill and pt[2] <= r.points[i - 1][2]
			worst = maxf(worst, absf(data.terrain_height(pt[0], pt[1]) - pt[2]))
		check(downhill and worst < 0.35, "%s runs downhill in its channel (worst %.2f m off)" % [r.name, worst])
	var brook: Dictionary = w.rivers[0]
	var mid: Array = brook.points[brook.points.size() / 2]
	check(Water.depth_at(Vector3(mid[0], data.height(mid[0], mid[1]), mid[1])) > 0.2, "the brook is wading-deep")

	# --- Lakes: deep in the middle, nothing floating over dry land ---
	for l in w.lakes:
		if l.get("frozen", false):
			continue
		var c := Vector3(l.center[0], 0, l.center[1])
		var deepest := 0.0
		for dx in range(-8, 9, 2):
			for dz in range(-8, 9, 2):
				var q := c + Vector3(dx, 0, dz)
				q.y = data.terrain_height(q.x, q.z)
				deepest = maxf(deepest, Water.depth_at(q))
		check(deepest > 0.6, "%s has deep water (%.2f m)" % [l.name, deepest])
	var floating := 0
	for mi in world.water.get_children():
		if mi is MeshInstance3D:
			var arrays: Array = mi.mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			for k in range(0, verts.size(), 5):
				if cols[k].r == 0.0 and cols[k].g < 0.99 and verts[k].y - data.terrain_height(verts[k].x, verts[k].z) > 0.25:
					floating += 1
	check(floating == 0, "no water floats above dry ground (%d vertices)" % floating)

	# --- Wading and ice ---
	var splashes := [0]
	p.splashed.connect(func() -> void: splashes[0] += 1)
	var pond: Dictionary = w.lakes.filter(func(l): return l.name == "Meadow Pond")[0]
	var edge := Vector3(pond.center[0] + pond.radius + 6.0, 0, pond.center[1])
	p.global_position = Vector3(edge.x, data.height(edge.x, edge.z) + 0.3, edge.z)
	await frames(20)
	p.yaw = PI * 0.5   # face west, into the pond
	p.move_input = Vector2(0, -1)
	var wade := 0.0
	for i in 200:
		await physics_frame
		wade = maxf(wade, p.water_depth)
	p.move_input = Vector2.ZERO
	check(wade > 0.3 and splashes[0] >= 1, "walking into the Meadow Pond: wading %.2f m deep, %d splash" % [wade, splashes[0]])
	var tarn: Dictionary = w.lakes.filter(func(l): return l.get("frozen", false))[0]
	p.global_position = Vector3(tarn.center[0], float(tarn.level) + 1.0, tarn.center[1])
	p.velocity = Vector3.ZERO
	await frames(90)
	check(p.global_position.y > float(tarn.level) - 0.15 and p.water_depth == 0.0, "the frozen tarn holds you up (%.2f m vs ice %.2f)" % [p.global_position.y, tarn.level])

	print("RESULT: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(fails)
