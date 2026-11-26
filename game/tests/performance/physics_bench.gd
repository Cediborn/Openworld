extends SceneTree
## Physics engine benchmark (run: godot --headless --path game -s res://tests/performance/physics_bench.gd).
## Runs on the real island collision (the 1024 m heightmap): 150 rigid rocks
## tumbling down Frost Peaks slopes, 40 character bodies walking up and down
## slopes, 400 raycasts a frame (the sword, the pistol and the horse all use
## them), and reports physics time per step and the behaviour that matters to
## the game: does a walking body stay on the ground (no sinking), do rocks come
## to rest, do raycasts hit the ground where the heightmap says it is.
## Compare engines by running once with the default settings and once with an
## override.cfg setting physics/3d/physics_engine="Jolt Physics".

const STEPS := 600


func _init() -> void:
	await process_frame
	var engine: String = ProjectSettings.get_setting("physics/3d/physics_engine", "DEFAULT")
	var data := WorldData.new()
	data.load_data()
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = data.build_collision()
	col.scale = Vector3(WorldData.STEP, 1, WorldData.STEP)
	ground.add_child(col)
	root.add_child(ground)

	var rocks: Array[RigidBody3D] = []
	for i in 150:
		var r := RigidBody3D.new()
		var cs := CollisionShape3D.new()
		var s: Shape3D = SphereShape3D.new() if i % 2 == 0 else BoxShape3D.new()
		cs.shape = s
		r.add_child(cs)
		var x := -60.0 + (i % 15) * 8.0
		var z := -330.0 + (i / 15) * 8.0
		r.position = Vector3(x, data.height(x, z) + 3.0 + (i % 3), z)
		root.add_child(r)
		rocks.append(r)

	var walkers: Array[CharacterBody3D] = []
	for i in 40:
		var c := CharacterBody3D.new()
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.35
		cap.height = 1.8
		cs.shape = cap
		cs.position.y = 0.9
		c.add_child(cs)
		c.floor_max_angle = deg_to_rad(58)
		c.floor_snap_length = 0.6
		var x := -100.0 + i * 5.0
		var z := -200.0
		c.position = Vector3(x, data.height(x, z) + 0.05, z)
		root.add_child(c)
		walkers.append(c)

	var space := ground.get_world_3d().direct_space_state
	var worst_sink := 0.0
	var ray_errs := PackedFloat32Array()
	var ray_miss := 0
	var t_phys := 0.0
	var t_rays := 0.0
	for step in STEPS:
		for c in walkers:
			# Walk north then south (uphill and down into Frost Peaks), with gravity.
			var dir := -1.0 if (step / 200) % 2 == 0 else 1.0
			c.velocity.x = 0.0
			c.velocity.z = dir * 4.0
			c.velocity.y = 0.0 if c.is_on_floor() else c.velocity.y - 9.8 / 60.0
			c.move_and_slide()
		await physics_frame
		t_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1.0e6
		var t1 := Time.get_ticks_usec()
		for k in 400:
			var x := -400.0 + float((k * 37 + step * 11) % 800)
			var z := -400.0 + float((k * 53 + step * 7) % 800)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 400, z), Vector3(x, -50, z)))
			if hit.is_empty():
				ray_miss += 1
			else:
				ray_errs.append(absf(hit.position.y - data.height(x, z)))
		t_rays += Time.get_ticks_usec() - t1
		if step > 30:
			for c in walkers:
				worst_sink = maxf(worst_sink, data.height(c.position.x, c.position.z) - c.position.y)
	ray_errs.sort()
	var ray_err := ray_errs[int(ray_errs.size() * 0.95)]   # 95th percentile: cliffs differ by triangulation
	var resting := 0
	for r in rocks:
		if r.sleeping or r.linear_velocity.length() < 0.2:
			resting += 1
	print("PHYS engine=%s  physics %.3f ms/step  400 rays %.3f ms  worst sink %.3f m  ray error (95%%) %.3f m  ray misses %d  rocks at rest %d/150" % [
		engine, t_phys / STEPS / 1000.0, t_rays / STEPS / 1000.0, worst_sink, ray_err, ray_miss, resting])
	var ok := worst_sink < 0.15 and ray_miss == 0 and ray_err < 0.3
	print("RESULT: %s" % ("ALL PASSED" if ok else "FAILED"))
	quit(0 if ok else 1)
