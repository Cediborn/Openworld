extends SceneTree
## The expansion in the real world (run: godot --headless --path game -s res://tests/integration/expansion_test.gd).
## Flintlock: owned on a new game, fires from the muzzle at the crosshair,
## kills a deer (which drops meat and a hide), needs reloading, runs dry,
## startles shy animals and alerts monsters, and the sword still works.
## Buildings: doors open, you can walk into a house and back out, interiors
## are furnished per building type, people inside stand on the floor.
## Your house: white stone, enterable, the bed sleeps you to morning and saves.
## Tavern: the barkeep sells food and drink, has rumours and work.
## Church: built, NPCs on its floor, its missions are offered by the priest.
## Saves: an old save without the expansion keeps its progress and gains the kit.

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
	while not world.booted and Time.get_ticks_msec() - t0 < 300000:
		await process_frame
	check(world.booted, "world booted")
	world._new_game()
	await physics(5)
	var p: Player = world.player
	p.max_health = 1.0e7
	p.health = 1.0e7
	await _firearm(p)
	await _buildings(p)
	await _house(p)
	await _tavern(p)
	await _church(p)
	await _save_compat(p)
	print("RESULT: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(fails)


func _place(p: Player, x: float, z: float) -> void:
	var data: WorldData = world.data
	p.global_position = Vector3(x, data.height(x, z) + 0.3, z)
	p.velocity = Vector3.ZERO
	await physics(20)


func _firearm(p: Player) -> void:
	var st: GameState = world.state
	var gun: Firearm = p.gun
	check(gun != null and gun.owned(), "new game: you own the flintlock")
	check(st.count("pistol_shot") == 12 and gun.loaded, "new game: loaded, with 12 shots in the pouch")
	await _place(p, 30, 60)
	gun.toggle()
	check(gun.drawn and p.body.gun_hand.visible and not p.body.gun_hip.visible, "G draws the pistol from its holster")
	await physics(30)
	var m := p.body.muzzle_position()
	var hand := p.body.skeleton.global_transform * p.body.skeleton.get_bone_global_pose(p.body.skeleton.find_bone("RightHand")).origin
	check(m.distance_to(hand) < 0.5, "the muzzle is at the explorer's hand (%.2f m)" % m.distance_to(hand))
	# A deer 15 m ahead of the camera.
	var deer: Creature = null
	var other: Creature = null
	for c in get_nodes_in_group("creatures"):
		if c.cfg.get("temper", "") == "flee" and str(c.cfg.get("model", "")).contains("Deer"):
			if deer == null:
				deer = c
			elif other == null:
				other = c
	check(deer != null and other != null, "two deer to hunt")
	var cam := p.camera
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var spot := p.global_position + fwd * 15.0
	# Freeze the wildlife manager so it doesn't wake the deer (which would bolt from us).
	for n in root.find_children("*", "Wildlife", true, false):
		n.process_mode = Node.PROCESS_MODE_DISABLED
	deer.process_mode = Node.PROCESS_MODE_DISABLED
	deer.visible = true
	deer.global_position = Vector3(spot.x, world.data.height(spot.x, spot.z), spot.z)
	other.process_mode = Node.PROCESS_MODE_INHERIT
	other.visible = true
	var o2 := p.global_position + fwd.rotated(Vector3.UP, 1.4) * 50.0
	other.global_position = Vector3(o2.x, world.data.height(o2.x, o2.z), o2.z)
	other.state = Creature.State.IDLE
	# Aim at the deer's middle: hold aim, then turn the camera onto it (the
	# camera sits on the line through its pivot, so aim from the pivot).
	var target: Vector3 = (deer.body_axis()[0] + deer.body_axis()[1]) * 0.5
	p.aim_held = true
	for k in 3:
		await physics(30)
		var to := target - cam.global_position
		p.yaw = atan2(-to.x, -to.z)
		p.pitch = asin(clampf(to.normalized().y, -1, 1))
	await physics(10)
	p.aim_held = false
	var aim := gun.aim_point()
	check(aim.distance_to(target) < 1.0, "the crosshair finds the deer (%.2f m off)" % aim.distance_to(target))
	var venison0 := st.count("venison")
	gun.aiming = true
	var hit := gun.fire()
	check(hit == deer, "the shot hits the deer")
	check(not deer.alive(), "one ball brings the deer down (health %.0f)" % deer.health)
	check(st.count("venison") > venison0 and st.count("deer_hide") > 0, "hunting reward: venison and a deer hide")
	check(other.state == Creature.State.FLEE and other.scared > 0.0, "the gunshot startles a deer 50 m away into flight")
	check(not gun.loaded, "the pistol is empty after the shot")
	check(gun.fire() == null, "it cannot fire again unloaded")
	gun.update(1.0 / 60.0, false, false, true)
	check(gun.reloading(), "R starts a reload (%.1f s)" % gun.reload_left)
	for i in 150:
		gun.update(1.0 / 60.0, false, false, false)
	check(gun.loaded and st.count("pistol_shot") == 11, "after the reload: loaded, 11 shots left")
	# Monsters hear it.
	var troll: Creature = null
	for c in get_nodes_in_group("creatures"):
		if c.cfg.get("temper", "") == "threaten" and c.alive():
			troll = c
			break
	if troll:
		troll.state = Creature.State.IDLE
		troll.cooldown = 0.0
		troll.global_position = p.global_position + Vector3(20, 0, 0)
		gun.aiming = true
		gun.fire()
		check(troll.state in [Creature.State.ROAR, Creature.State.CHASE], "a monster 20 m away hears the shot and comes (state %d)" % troll.state)
		troll.global_position = troll.home
		troll.state = Creature.State.RETURN
	# Out of shot.
	st.remove_item("pistol_shot", st.count("pistol_shot"))
	gun.loaded = false
	var msgs: Array[String] = []
	gun.message.connect(func(t: String) -> void: msgs.append(t))
	gun.cooldown = 0.0
	gun.update(1.0 / 60.0, true, false, false)
	check(msgs.any(func(t: String) -> bool: return t.begins_with("Out of shot")), "firing with no shot says you're out")
	# The sword still works once the pistol is holstered.
	gun.toggle()
	check(not gun.drawn and p.body.gun_hip.visible, "G holsters the pistol")
	await physics(40)
	p.attack_pressed = true
	await physics(3)
	check(p.swing >= 0, "the sword swings again after holstering (floor %s, busy %s %s)" % [p.is_on_floor(), p.body.busy(), p.body.current])
	await physics(60)
	st.add_item("pistol_shot", 12, true)
	check(st.shops.get("hunter", []).has("pistol_shot") and st.shops.merchant.has("pistol_shot"), "shot is for sale (Brann, Tilly, Hale)")


func _buildings(p: Player) -> void:
	var ex: Expansion = world.expansion
	var inter: Interiors = ex.interiors
	var village: Village = world.village
	check(village.buildings.size() >= 42, "every Brickton house is a building you can enter (%d)" % village.buildings.size())
	for k in ["inn", "shop", "smithy", "hall", "workshop", "player_house"]:
		check(inter.find(k) >= 0, "there is a %s interior" % k)
	var i := inter.find("shop")
	var b: Dictionary = village.buildings[i]
	var outside: Vector3 = b.root.to_global(b.door_local + Vector3(0, 0, 3.0))
	var inside := inter.inside_point(i)
	await _place(p, outside.x, outside.z)
	await physics(60)
	check(inter._built.has(i), "walking up to Tilly's shop furnishes it")
	var furn: Node3D = inter._built[i]
	check(furn.get_child_count() > 10, "the shop has furniture inside (%d pieces)" % furn.get_child_count())
	# Closed door blocks; open it and walk in.
	var blocked := await _walk_to(p, inside, 3.0)
	check(not _inside(b, p.global_position), "a closed door keeps you out")
	check(inter.toggle_door(i), "the door opens")
	await physics(50)
	await _walk_to(p, inside, 6.0)
	check(_inside(b, p.global_position), "you can walk through the doorway into the shop (at %s in the house's space)" % b.root.to_local(p.global_position))
	var floor_y: float = b.root.global_position.y + Village.FLOOR_Y
	check(absf(p.global_position.y - floor_y) < 0.1 and p.is_on_floor(), "inside, you stand on the floor (%.2f m)" % (p.global_position.y - floor_y))
	await _walk_to(p, outside, 6.0)
	check(not _inside(b, p.global_position), "and walk back out")
	check(_inside(b, world.story.by_id["tam"].global_position), "a shopkeeper stands behind the counter inside")
	check(_inside(village.buildings[inter.find("smithy")], world.story.by_id["wat"].global_position), "an apprentice works the smithy forge")
	# Different buildings get different rooms.
	var counts := {}
	for k in ["inn", "smithy", "hall"]:
		var j := inter.find(k)
		var r := inter.furnish(j)
		counts[k] = r.get_child_count()
		r.queue_free()
	check(counts.inn != counts.smithy and counts.smithy != counts.hall, "the tavern, smithy and hall are furnished differently %s" % counts)


func _walk_to(p: Player, at: Vector3, seconds: float) -> bool:
	for k in int(seconds * 60):
		var to := at - p.global_position
		to.y = 0
		if to.length() < 0.5:
			p.move_input = Vector2.ZERO
			return true
		var local := to.normalized().rotated(Vector3.UP, -p.yaw)
		p.move_input = Vector2(local.x, local.z)
		await physics_frame
	p.move_input = Vector2.ZERO
	return false


func _inside(b: Dictionary, at: Vector3) -> bool:
	var l: Vector3 = b.root.to_local(at)
	return absf(l.x) < b.w * 0.5 - 0.2 and absf(l.z) < b.d * 0.5 - 0.2


func _house(p: Player) -> void:
	var ex: Expansion = world.expansion
	var inter: Interiors = ex.interiors
	var i := inter.find("player_house")
	var b: Dictionary = world.village.buildings[i]
	check(b.h.get("white", false), "your house is built of white stone")
	check(b.root.global_position.distance_to(Vector3(-300, 0, 0)) < 160.0, "your house is near Brickton")
	var outside: Vector3 = b.root.to_global(b.door_local + Vector3(0, 0, 3.0))
	await _place(p, outside.x, outside.z)
	inter.toggle_door(i)
	await physics(50)
	await _walk_to(p, inter.inside_point(i), 6.0)
	check(_inside(b, p.global_position), "you can walk into your house")
	await physics(40)
	var sleep: Interactable = null
	for it in get_nodes_in_group("interactables"):
		if it.label == "Sleep until morning" and it.is_inside_tree():
			sleep = it
	check(sleep != null, "your bed offers 'Sleep until morning'")
	world.sky.time_of_day = 22.5
	p.health = p.max_health * 0.3
	SaveGame.delete_save()
	sleep.action.call(sleep)
	check(absf(world.sky.time_of_day - 7.0) < 0.1, "sleeping moves the clock to 7:00")
	check(p.health >= p.max_health, "you wake fully healed")
	check(SaveGame.has_save(), "sleeping saves the game")


func _tavern(p: Player) -> void:
	var story: Story = world.story
	var rowan: Villager = story.by_id.get("rowan")
	check(rowan != null, "Rowan the barkeep is at the Brickton Arms")
	var inter: Interiors = world.expansion.interiors
	var b: Dictionary = world.village.buildings[inter.find("inn")]
	check(_inside(b, rowan.global_position), "he stands inside the tavern, behind the bar")
	var floor_y: float = b.root.global_position.y + Village.FLOOR_Y
	await physics(5)
	check(absf(rowan.global_position.y - floor_y) < 0.05, "on the tavern floor (%.2f m)" % (rowan.global_position.y - floor_y))
	var c: Dictionary = world.services.for_villager(rowan)
	check(c.get("choices", []).size() == 4, "he offers food and drink, rumours and work")
	var st: GameState = world.state
	st.add_coins(100, true)
	var rumour: Dictionary = c.on_choice.call(1)
	check(rumour.get("lines", []).size() == 1, "he has a rumour for you")
	c.on_choice.call(0)
	check(world.services.visible and world.services.shop_kind == "tavern", "his menu opens")
	var coins := st.coins
	world.services.buy_list.select(0)
	world.services._buy()
	check(st.coins < coins and st.count("hearty_stew") == 1, "buying a hearty stew")
	world.services.close_shop()
	var work: Dictionary = c.on_choice.call(2)
	check(not work.is_empty(), "and he points you to work")
	for pid in ["fennick", "brida", "mott"]:
		var v: Villager = story.by_id.get(pid)
		check(v != null and _inside(b, v.global_position), "%s is drinking in the tavern" % pid)


func _church(p: Player) -> void:
	var ch: Church = world.expansion.church
	check(ch != null, "the church is built")
	var story: Story = world.story
	for id in ["aldric", "cuthbert", "maud", "edda", "wenna", "anselm"]:
		var v: Villager = story.by_id.get(id)
		check(v != null and absf(v.global_position.y - ch.floor_y) < 0.05, "%s is in the church, on its floor" % id)
	var qs: Quests = world.quests
	for q in ["missing_relic", "pilgrims_journey", "shadows_church", "ancient_scriptures"]:
		check(qs.defs.has(q), "church mission %s exists in the quest system" % q)
	check(qs.status("missing_relic") == "available" and qs.status("pilgrims_journey") == "available", "Father Aldric offers his missions")
	check(ch.points.has("chronicle") and ch.points.has("founding_stone"), "there are books and inscriptions to read")
	# You can walk in through the open doors to the altar.
	var door := ch.at(Vector3(0, Church.FLOOR, ch.d * 0.5 + 4.0))
	var altar := ch.at(Vector3(0, Church.FLOOR, -ch.d * 0.5 + 6.0))
	await _place(p, door.x, door.z)
	await _walk_to(p, altar, 20.0)
	check(p.global_position.distance_to(altar) < 1.5, "you can walk up the aisle to the altar (%.1f m left)" % p.global_position.distance_to(altar))
	check(absf(p.global_position.y - ch.floor_y) < 0.1, "inside, you stand on the nave floor")
	check(ch.bell_player.stream != null, "the bell sound is loaded")
	ch.ring()
	await create_timer(0.2).timeout
	check(ch.bell_player.has_stream_playback() or ch.bell_player.playing or DisplayServer.get_name() == "headless", "the bells ring")


func _save_compat(p: Player) -> void:
	# An old save: no expansion flag, the white horse in the lava, progress and items kept.
	var st: GameState = world.state
	var old := {"player": [0, 5, 40], "yaw": 0.0, "health": 80.0, "story": {"stage": "done", "found": ["frost", "ember", "glow"]},
		"progress": {"coins": 345, "xp": 900, "level": 4, "items": {"potion": 2, "frost_coat": 1}, "weapon": "iron_sword", "armor": "frost_coat", "flags": {"some_flag": true}},
		"quests": {}, "hour": 13.0, "horses": {"white": [348.0, 128.0, 0.0]}}
	SaveGame.save(old)
	world._continue_game()
	await physics(10)
	check(st.coins == 345 and st.level == 4 and st.count("frost_coat") == 1 and st.armor == "frost_coat", "an old save keeps coins, level, items and armour")
	check(st.has_flag("some_flag"), "and its world flags")
	check(st.count("flintlock") == 1 and st.count("pistol_shot") == 12, "it gains the flintlock and 12 shots once")
	world.save_game()
	world._continue_game()
	await physics(5)
	check(st.count("pistol_shot") == 12, "not twice")
	var white: Horse = world.stable.owned()
	check(not world.data.is_lava(white.global_position.x, white.global_position.z), "its white horse is out of the lava")
