extends SceneTree
## Horse whistle and lava rescue (run: godot --headless --path game -s res://tests/integration/horse_test.gd).
## Boots the real world and checks: a save with the white horse standing in
## the lava crater loads with that same horse led out to safe ground it can
## walk home from; horses never amble into lava; the whistle brings your horse
## from the meadow rail into Brickton without passing through a building, wall
## or lava; whistling too far away or while riding gives feedback; and the
## owned horse survives a save round trip.

var world: Node
var fails := 0


func check(ok: bool, msg: String) -> void:
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok:
		fails += 1


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
	var stable: Stable = world.stable
	var white: Horse = null
	for h in stable.horses:
		if h.id == "white":
			white = h
	check(white != null, "the white horse exists")
	var notes: Array[String] = []
	stable.notify = func(tx: String) -> void: notes.append(tx)

	# --- An old save (no "owned" key) with the white horse in the lava crater. ---
	var lava := _find_lava(data)
	check(lava != Vector2.INF, "found a lava spot to test with (%s)" % lava)
	var black_before := [0.0, 0.0]
	for h in stable.horses:
		if h.id == "black":
			black_before = [h.global_position.x, h.global_position.z]
	stable.load_state({"white": [lava.x, lava.y, 0.5], "black": [black_before[0], black_before[1], 0.0]})
	var wp := Vector2(white.global_position.x, white.global_position.z)
	check(not data.is_lava(wp.x, wp.y), "the white horse is no longer in the lava (now at %s)" % wp)
	check(stable.nav.is_open(wp.x, wp.y), "it stands on open ground a horse can use")
	check(stable.nav.path(wp, Vector2(7, 35)).size() >= 2, "it can walk from there back to the meadow rail")
	check(wp.distance_to(lava) < 200.0, "it was led to the nearest safe ground, not teleported home (%.0f m)" % wp.distance_to(lava))
	check(white.id == "white" and stable.owned_id == "white" and stable.horses.has(white), "it is the same white horse and still yours")
	check(stable.horses.size() == 3, "no replacement horse was created (3 horses)")
	check(notes.any(func(n: String) -> bool: return n.contains("lava")), "the player is told the horse was led out of the lava")

	# --- Horses never amble into lava. ---
	var edge := _lava_edge(data, stable.nav)
	white.global_position = Vector3(edge.x, data.height(edge.x, edge.y), edge.y)
	white.home = white.global_position
	var entered := false
	for i in 3000:   # ~5 minutes of grazing and ambling at 0.1 s steps
		white._process(0.1)
		if data.is_lava(white.global_position.x, white.global_position.z):
			entered = true
			print("  entered lava at step %d: %s (start %s, lava at start %s, state %d)" % [i, white.global_position, edge, data.is_lava(edge.x, edge.y), white.state])
			break
	check(not entered, "left beside the crater for 5 minutes, the horse never steps into lava")
	stable.reset()

	# --- Whistle from Brickton: comes round buildings, not through them. ---
	var street := Vector2(-300, -3)
	p.global_position = Vector3(street.x, data.height(street.x, street.y) + 0.3, street.y)
	for i in 30:
		await physics_frame
	var res := stable.whistle()
	check(res == "coming", "whistling in Brickton: the horse answers (%s)" % res)
	check(white.is_coming(), "the white horse is on its way")
	var start := Vector2(white.global_position.x, white.global_position.z)
	var arrived := false
	var through_wall := 0
	var in_lava := false
	var simulated := 0.0
	while simulated < 180.0:
		white._process(1.0 / 30.0)
		simulated += 1.0 / 30.0
		var hp := white.global_position
		if not _open_near(stable.nav, hp.x, hp.z):
			through_wall += 1
		if data.is_lava(hp.x, hp.z):
			in_lava = true
		if not white.is_coming():
			arrived = true
			break
	var gap := Vector2(white.global_position.x - p.global_position.x, white.global_position.z - p.global_position.z).length()
	check(arrived and gap < 4.0, "it arrives beside you (%.1f m away after %.0f s, from %.0f m)" % [gap, simulated, start.distance_to(street)])
	check(through_wall == 0, "it never passes through a building, wall or cliff (%d blocked samples)" % through_wall)
	check(not in_lava, "it never crosses lava")
	check(notes.any(func(n: String) -> bool: return n.contains("on its way")) and notes.any(func(n: String) -> bool: return n.contains("is here")), "on-screen notes for 'on its way' and 'is here'")

	# --- Somewhere it can't reach: it comes as close as it safely can and says so. ---
	var spot := stable.nav.nearest_open(Vector2(-250, -3))
	p.global_position = Vector3(spot.x, data.height(spot.x, spot.y) + 0.3, spot.y)
	var pc := stable.nav.cell_of(spot)
	var walled := {}
	for dj in range(-2, 3):
		for di in range(-2, 3):
			if maxi(absi(di), absi(dj)) == 2:
				var c := pc + Vector2i(di, dj)
				walled[c] = stable.nav.grid.is_point_solid(c)
				stable.nav.grid.set_point_solid(c, true)
	notes.clear()
	var res2 := stable.whistle()
	check(res2 == "near", "whistling where it can't reach you: it comes as near as it can (%s)" % res2)
	simulated = 0.0
	through_wall = 0
	while white.is_coming() and simulated < 120.0:
		white._process(1.0 / 30.0)
		simulated += 1.0 / 30.0
		if not _open_near(stable.nav, white.global_position.x, white.global_position.z):
			through_wall += 1
	var wait_d := Vector2(white.global_position.x, white.global_position.z).distance_to(spot)
	check(not white.is_coming() and wait_d > 6.0 and wait_d < 20.0 and through_wall == 0, "it waits on open ground just outside (%.1f m away, %d blocked samples)" % [wait_d, through_wall])
	check(notes.any(func(n: String) -> bool: return n.contains("can't reach you")), "and the player is told it can't reach them")
	for c in walled:
		stable.nav.grid.set_point_solid(c, walled[c])
	p.global_position = Vector3(street.x, data.height(street.x, street.y) + 0.3, street.y)
	white.global_position = Vector3(street.x + 2.0, data.height(street.x + 2.0, street.y), street.y)

	# --- Feedback: right here, riding, too far. ---
	check(stable.whistle() == "here", "whistling with the horse beside you says it's right here")
	p.mount(white)
	check(stable.whistle() == "riding", "whistling while riding says you're already riding")
	p.dismount()
	white.global_position = Vector3(460, data.height(460, -460), -460)
	p.global_position = Vector3(-440, data.height(-440, 440) + 0.3, 440)
	check(stable.whistle() == "too_far", "whistling from the far side of the island: too far to hear")

	# --- Riding another horse makes it yours; saved and loaded. ---
	stable.reset()
	var brown: Horse = null
	for h in stable.horses:
		if h.id == "brown":
			brown = h
	p.global_position = brown.global_position + Vector3(1.5, 0.3, 0)
	stable._use(brown)
	check(p.horse == brown and stable.owned_id == "brown", "riding the brown horse makes it your horse")
	p.dismount()
	var saved := stable.save_state()
	stable.owned_id = "white"
	stable.load_state(saved)
	check(stable.owned_id == "brown", "your horse is remembered in the save")
	stable.load_state({})
	check(stable.owned_id == "white", "an old save without it defaults to the white horse")

	print("RESULT: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(fails)


func _find_lava(data: WorldData) -> Vector2:
	for z in range(-200, 201, 8):
		for x in range(300, 460, 8):
			if data.is_lava(x, z) and data.is_lava(x + 8, z) and data.is_lava(x - 8, z):
				return Vector2(x, z)
	return Vector2.INF


## An open spot within a few metres of lava.
func _lava_edge(data: WorldData, nav: HorseNav) -> Vector2:
	for z in range(-200, 201, 4):
		for x in range(240, 470, 4):
			if nav.is_open(x, z) and (data.is_lava(x + 6, z) or data.is_lava(x - 6, z) or data.is_lava(x, z + 6)):
				return Vector2(x, z)
	return Vector2(250, 0)


## Open ground here or in a neighbouring cell (the horse's body spans a cell edge).
func _open_near(nav: HorseNav, x: float, z: float) -> bool:
	for o in [Vector2.ZERO, Vector2(1.5, 0), Vector2(-1.5, 0), Vector2(0, 1.5), Vector2(0, -1.5)]:
		if nav.is_open(x + o.x, z + o.y):
			return true
	return false
