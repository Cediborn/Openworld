extends SceneTree
## Script-cost probe (run: godot --headless --path game -s res://tests/performance/perf_probe.gd).
## Boots the world and reports game-logic time per frame (process + physics),
## node and object counts and memory in a few places: the meadow spawn, the
## crowded market square, a boss fight, and back in the meadow (to see that
## nothing leaks). Rendering is not measured headless.

var world: Node


func sample(label: String, sec: float) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var n := 0
	var proc := 0.0
	var phys := 0.0
	var worst := 0.0
	while Time.get_ticks_msec() - t0 < sec * 1000.0:
		await process_frame
		var p := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var ph := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		proc += p
		phys += ph
		worst = maxf(worst, p + ph)
		n += 1
	var r := {"place": label, "logic_ms": (proc + phys) / maxf(n, 1), "worst_ms": worst,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0}
	print("PERF %-18s logic %.2f ms/frame (worst %.1f)  nodes %d  objects %d  memory %.0f MB" % [label, r.logic_ms, r.worst_ms, r.nodes, r.objects, r.mem_mb])
	return r


func goto(x: float, z: float) -> void:
	var p: Player = world.player
	p.global_position = Vector3(x, world.data.height(x, z) + 0.3, z)
	p.cam_pivot.global_position = p.global_position + Vector3(0, 1.6, 0)


func _init() -> void:
	var t_boot := Time.get_ticks_msec()
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	while not world.booted:
		await process_frame
	print("PERF boot %.1f s (headless)" % ((Time.get_ticks_msec() - t_boot) / 1000.0))
	world._new_game()
	world.player.max_health = 1.0e7
	world.player.health = 1.0e7
	goto(0, 40)
	var a: Dictionary = await sample("meadow spawn", 4.0)
	goto(-311, -50)
	await sample("market square", 6.0)
	goto(-58, -365)
	await sample("rare boss fight", 6.0)
	goto(0, 40)
	await sample("meadow again", 4.0)
	var b: Dictionary = await sample("meadow again", 4.0)
	print("PERF objects grew by %d after the tour" % (b.objects - a.objects))
	quit(0)
