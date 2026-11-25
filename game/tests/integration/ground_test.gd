extends SceneTree
## Ground contact test (run: godot --headless --path game -s res://tests/integration/ground_test.gd).
## Boots the real world, then in every region stands, walks and jumps the
## explorer over slopes, grass, roads and rocks, checking that the collision
## capsule rests on the visible ground (no sinking, no floating), that it does
## not drift downwards over time, and that the boots touch the surface.

var world: Node
var fails := 0


func check(ok: bool, msg: String) -> void:
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok:
		fails += 1


func physics(n: int) -> void:
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
	var p: Player = world.player
	p.max_health = 1.0e7
	p.health = 1.0e7
	var data: WorldData = world.data
	# One spot per region plus a road, a steep hillside and a rocky field.
	var spots := {
		"Hub Meadow": Vector2(0, 40), "meadow hillside": Vector2(60, 90), "Frost Peaks": Vector2(10, -300),
		"Ember Wastes rim": Vector2(260, 60), "Glow Hollow": Vector2(20, 300), "Brickton road": Vector2(-300, -3),
		"Brickton outskirts": Vector2(-250, -100),
	}
	for name in spots:
		var s: Vector2 = spots[name]
		if data.zone(s.x, s.y)[2] > 0.3 and data.height(s.x, s.y) < WorldData.LAVA_LEVEL + 0.5:
			continue
		# Streets have carts, stalls and wells: step aside until standing on bare ground.
		for attempt in 6:
			p.global_position = Vector3(s.x + attempt * 3.0, data.height(s.x + attempt * 3.0, s.y) + 0.3, s.y)
			p.velocity = Vector3.ZERO
			await physics(60)
			if _on_terrain(p):
				break
		var gap := p.global_position.y - data.height(p.global_position.x, p.global_position.z)
		check(absf(gap) < 0.12, "%s: standing on the ground (feet %.3f m from it)" % [name, gap])
		# Stand still for a while: no gradual sinking.
		var y0 := p.global_position.y
		await physics(240)
		check(absf(p.global_position.y - y0) < 0.02, "%s: no drift after 4 s (%.3f m)" % [name, p.global_position.y - y0])
		# Walk in a circle and measure the worst gap while moving.
		var worst := 0.0
		var worst_float := 0.0
		for i in 180:
			var a := i / 180.0 * TAU
			p.move_input = Vector2(cos(a), sin(a))
			await physics_frame
			if p.is_on_floor() and _on_terrain(p):
				var g := p.global_position.y - data.height(p.global_position.x, p.global_position.z)
				worst = minf(worst, g)
				worst_float = maxf(worst_float, g)
		p.move_input = Vector2.ZERO
		check(worst > -0.12, "%s: never sinks while walking (worst %.3f m)" % [name, worst])
		check(worst_float < 0.15, "%s: never floats while walking (worst %.3f m)" % [name, worst_float])
		# The lowest boot is on the ground when standing.
		await physics(30)
		var foot := _lowest_foot(p)
		var fg := foot - data.height(p.global_position.x, p.global_position.z)
		check(fg > -0.1 and fg < 0.14, "%s: boots touch the ground (%.3f m)" % [name, fg])

	# Jump and land on the meadow.
	p.global_position = Vector3(0, data.height(0, 40) + 0.3, 40)
	await physics(30)
	p.jump_pressed = true
	var top := 0.0
	var start_y := p.global_position.y
	var landed := false
	for i in 120:
		await physics_frame
		top = maxf(top, p.global_position.y - start_y)
		if i > 10 and p.is_on_floor():
			landed = true
			break
	check(top > 0.4, "jump leaves the ground (%.2f m)" % top)
	check(landed, "jump lands again")
	var gap2 := p.global_position.y - data.height(p.global_position.x, p.global_position.z)
	check(absf(gap2) < 0.12, "after landing the feet are on the ground (%.3f m)" % gap2)
	print("RESULT: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(fails)


func _lowest_foot(p: Player) -> float:
	var sk: Skeleton3D = p.body.skeleton
	var low := INF
	for b in ["LeftToes", "RightToes"]:
		var i := sk.find_bone(b)
		if i >= 0:
			low = minf(low, (sk.global_transform * sk.get_bone_global_pose(i)).origin.y)
	return low


## True when the floor under the explorer is the terrain heightmap (not a rock, bridge or the lava floor).
func _on_terrain(p: Player) -> bool:
	for i in p.get_slide_collision_count():
		var c := p.get_slide_collision(i)
		var body := c.get_collider() as Node
		if body and body.get_parent() is Terrain and c.get_normal().y > 0.5:
			var shape := (body as CollisionObject3D).shape_owner_get_owner((body as CollisionObject3D).shape_find_owner(c.get_collider_shape_index())) as CollisionShape3D
			return shape != null and shape.shape is HeightMapShape3D
	return false
