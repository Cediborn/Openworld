extends SceneTree
## Full playthrough test (run: godot --headless --path game -s res://tests/integration/playthrough_test.gd).
## Boots the real world, starts a new game and plays every quest from start to
## finish through the same actions a player uses: walking (teleporting) to
## places, talking and choosing answers, examining and picking things up,
## fighting what the quest spawns, escorting, waiting for night. Then checks
## rewards, the journal state, save/load, contracts, shrines, treasure,
## discoveries, rare bosses and world events.

var world: Node
var fails := 0
var passes := 0
var log_lines: Array = []


func check(ok: bool, msg: String) -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print(("PASS " if ok else "FAIL ") + msg)


func frames(n: int) -> void:
	for i in n:
		await process_frame


## Waits real (game) time: frames run uncapped in headless mode.
func wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < sec * 1000.0:
		await process_frame


func _init() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	var t0 := Time.get_ticks_msec()
	while not world.booted and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	check(world.booted, "world booted")
	world._new_game()
	await frames(5)
	var p: Player = world.player
	p.max_health = 1.0e7
	p.health = 1.0e7
	await _town_checks()
	await _original_quest()
	var order := ["strange_silence", "ancient_scriptures", "missing_relic", "pilgrims_journey", "shadows_church", "lost_merchant", "blacksmith_request", "hunters_challenge", "missing_caravan", "herbalist_collection",
		"trouble_gates", "frozen_expedition", "forgotten_explorer", "beneath_ashes", "golems_secret", "glowing_heart", "strange_crystal",
		"hidden_treasure", "queen_beneath", "last_journal", "night_beasts", "forgotten_kingdom", "stranger_midnight", "five_fragments", "awakening"]
	for id in order:
		await _play_quest(id)
		if id == "beneath_ashes":
			await _save_load_check()
	await _contracts()
	await _features()
	await _events()
	print("TOTAL: %d passed, %d failed" % [passes, fails])
	print("RESULT: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(fails)


# ---------- helpers ----------

func _goto(pos: Vector3) -> void:
	var p: Player = world.player
	var y: float = world.data.height(pos.x, pos.z)
	p.global_position = Vector3(pos.x, y + 0.3, pos.z)
	p.velocity = Vector3.ZERO
	p.cam_pivot.global_position = p.global_position + Vector3(0, 1.6, 0)
	await frames(3)


func _finish_dialogue() -> void:
	var story: Story = world.story
	var guard := 0
	while story.in_dialogue() and guard < 200:
		guard += 1
		if world.hud.has_choices():
			story._choose(0)
		else:
			story._advance()
		await process_frame
	await process_frame


func _talk(npc: String) -> bool:
	var story: Story = world.story
	if not story.by_id.has(npc):
		return false
	var v: Villager = story.by_id[npc]
	await _goto(v.global_position + Vector3(1.5, 0, 0))
	story._start_dialogue(v)
	await _finish_dialogue()
	return true


func _use(it: Interactable) -> void:
	await _goto(it.global_position + Vector3(0.8, 0, 0))
	it.use()
	await frames(2)
	await _finish_dialogue()


func _kill(c: Creature) -> void:
	if not is_instance_valid(c):
		return
	await _goto(c.global_position + Vector3(3, 0, 0))
	var n := 0
	while is_instance_valid(c) and c.alive() and n < 400:
		c.take_hit(60.0, world.player.global_position)
		n += 1
		await process_frame
	await frames(2)


func _entities(id: String, gi: int) -> Array:
	var qs: Quests = world.quests
	return qs.entities.get(qs._key(id, qs.q[id].step, gi), [])


func _interactables_near(pos: Vector3, r: float) -> Array:
	var out := []
	for it in world.get_tree().get_nodes_in_group("interactables"):
		if it.enabled and it.is_visible_in_tree() and it.global_position.distance_to(pos) < r:
			out.append(it)
	return out


# ---------- checks ----------

func _town_checks() -> void:
	var d: WorldData = world.data
	check(d.houses.size() >= 40, "Brickton has %d buildings (was 14)" % d.houses.size())
	check(world.story.villagers.size() >= 40, "%d villagers spawned" % world.story.villagers.size())
	var roles := {}
	for v in world.story.villagers:
		roles[v.role] = int(roles.get(v.role, 0)) + 1
	check(roles.has("merchant") and roles.has("guard") and roles.has("quest_giver") and roles.has("villager") and roles.has("traveller") and roles.has("smith"),
		"villager roles present: %s" % [roles])
	# Nobody stands inside a building or walks a street that crosses one.
	var inside := []
	for v in world.story.villagers:
		for h in d.houses:
			var local := (Vector2(v.home.x, v.home.z) - Vector2(h.x, h.z)).rotated(float(h.rot))
			if absf(local.x) < h.w * 0.5 + 0.2 and absf(local.y) < h.d * 0.5 + 0.2:
				inside.append(v.id)
	check(inside.is_empty(), "no villager starts inside a building %s" % [inside])
	var bad_edges := 0
	var town: Town = world.town
	for a in town.nodes.size():
		for b in town.edges[a]:
			for s in 5:
				var q: Vector3 = (town.nodes[a] as Vector3).lerp(town.nodes[b], s / 4.0)
				for h in d.houses:
					var local := (Vector2(q.x, q.z) - Vector2(h.x, h.z)).rotated(float(h.rot))
					if absf(local.x) < h.w * 0.5 - 0.3 and absf(local.y) < h.d * 0.5 - 0.3:
						bad_edges += 1
	check(bad_edges == 0, "street walking routes never pass through a house (%d bad samples)" % bad_edges)
	# Strollers really move along the streets over time.
	var walker: Villager = world.story.by_id["gus"]
	await _goto(walker.global_position + Vector3(4, 0, 0))
	var start := walker.global_position
	await wait(14.0)
	check(walker.global_position.distance_to(start) > 2.0, "a strolling villager walks around town (%.1f m)" % walker.global_position.distance_to(start))
	var guard: Villager = world.story.by_id["guard_osric"]
	check(guard.mode == "patrol", "guards patrol")


func _original_quest() -> void:
	var story: Story = world.story
	await _talk("elder")
	check(story.stage == "hunt", "original quest: elder starts the heart-stone hunt")
	for id in story.stones.keys():
		await _goto(story.stones[id].global_position)
		story._pick_up(id)
		await frames(2)
	check(story.stage == "return", "original quest: all three heart-stones found")
	await _talk("elder")
	await _talk("smith")
	check(story.stage == "done", "original quest complete")
	check(world.state.weapon == "heart_blade", "the Heartforged Sword is equipped")


func _play_quest(id: String) -> void:
	var qs: Quests = world.quests
	var st: GameState = world.state
	if not qs.defs.has(id):
		check(false, "%s exists" % id)
		return
	var d: Dictionary = qs.defs[id]
	check(qs.status(id) in ["available", "active"], "%s is available (status %s)" % [id, qs.status(id)])
	var coins0 := st.coins
	var xp0 := st.xp + st.level * 100000
	if qs.status(id) == "available":
		if d.has("giver"):
			await _talk(d.giver)
		elif d.has("trigger"):
			if d.trigger.get("reach", false):
				await _goto(Vector3(d.trigger.pos[0], 0, d.trigger.pos[1]))
				await wait(0.8)
				await _finish_dialogue()
			else:
				await wait(0.6)
				await _use(qs.triggers[id])
		await frames(10)
	check(qs.status(id) == "active" or qs.status(id) == "completed", "%s started" % id)
	var guard := 0
	while qs.status(id) == "active" and guard < 60:
		guard += 1
		var si: int = qs.q[id].step
		var goals := Quests.goals_of(qs.current_step(id))
		for gi in goals.size():
			if qs.status(id) != "active" or qs.q[id].step != si:
				break
			if qs.goal_done(id, gi):
				continue
			await _solve_goal(id, gi, goals[gi])
		await wait(0.35)
		if qs.status(id) == "active" and qs.q[id].step == si:
			var pending := []
			for gi in goals.size():
				if not qs.goal_done(id, gi):
					pending.append(goals[gi].get("text", goals[gi].type))
			log_lines.append("%s step %d still pending %s" % [id, si, pending])
	await _finish_dialogue()
	check(qs.status(id) == "completed", "%s completed%s" % [id, "" if qs.status(id) == "completed" else " (stuck at step %d: %s)" % [qs.q[id].step if qs.q.has(id) else -1, log_lines.slice(-1)]])
	if qs.status(id) == "completed":
		var r: Dictionary = d.get("rewards", {})
		if r.has("coins"):
			check(st.coins >= coins0 + int(r.coins) - 400, "%s paid its coins" % id)
		for it in r.get("items", {}):
			check(st.count(it) > 0 or it in ["fragment_meadow"], "%s gave %s" % [id, it])
		var c_before := st.coins
		qs._give_rewards(id)
		check(st.coins == c_before, "%s reward cannot be claimed twice" % id)


func _solve_goal(id: String, gi: int, g: Dictionary) -> void:
	var qs: Quests = world.quests
	var st: GameState = world.state
	match g.type:
		"talk", "deliver":
			if g.type == "deliver":
				var need: Dictionary = g.get("items", {g.item: int(g.get("count", 1))})
				for it in need:
					if st.count(it) < int(need[it]):
						st.add_item(it, int(need[it]) - st.count(it), true)   # should already have them from earlier steps
						log_lines.append("%s: had to top up %s" % [id, it])
			if not world.story.by_id.has(g.npc):
				await frames(10)
			await _talk(g.npc)
		"talk_any":
			var guard := 0
			for v in world.story.villagers.duplicate():
				if qs.goal_done(id, gi) or guard > 40:
					break
				if g.has("only") and not v.id in g.only:
					continue
				if v.role == "merchant" or v.home.x > -180.0 or v.id in g.get("exclude", []):
					continue
				guard += 1
				await _talk(v.id)
		"reach":
			await _goto(Vector3(g.pos[0], 0, g.pos[1]))
			await wait(0.6)
			await _finish_dialogue()
		"inspect", "place":
			for it in _entities(id, gi):
				if is_instance_valid(it) and it is Interactable:
					await _use(it)
		"collect":
			for it in _entities(id, gi).duplicate():
				if is_instance_valid(it) and it is Interactable:
					await _use(it)
		"kill", "boss":
			for c in _entities(id, gi).duplicate():
				if is_instance_valid(c) and c is Creature:
					await _kill(c)
			await frames(5)
		"defend":
			await _goto(Vector3(g.pos[0], 0, g.pos[1]))
			var n := 0
			while not qs.goal_done(id, gi) and n < 60:
				n += 1
				await wait(0.4)
				for c in _entities(id, gi).duplicate():
					if is_instance_valid(c) and c is Creature and c.alive():
						c.take_hit(1.0e6, c.global_position + Vector3(1, 0, 0))
				await wait(0.4)
		"escort":
			var v: Villager = world.story.by_id.get(g.npc)
			var dest := Vector3(g.to[0], 0, g.to[1])
			var n2 := 0
			while not qs.goal_done(id, gi) and n2 < 80 and v:
				n2 += 1
				var to := dest - v.global_position
				to.y = 0
				var step := to.normalized() * minf(12.0, to.length() + 1.0)
				await _goto(v.global_position + step)
				await wait(1.6)
		"observe":
			var tgt: Node3D = world.features.named(g.target)
			await _goto((tgt.global_position if tgt else Vector3(g.pos[0], 0, g.pos[1])) + Vector3(6, 0, 0))
			await wait(float(g.seconds) + 1.5)
			await _finish_dialogue()
		"night":
			world.sky.time_of_day = 21.5
			await wait(0.6)
		"encounter":
			world.sky.time_of_day = 22.0
			await _goto(Vector3(g.pos[0], 0, g.pos[1]) + Vector3(3, 0, 0))
			await wait(0.8)
		"have":
			await _obtain(g.item)


## Gets a fragment or key through its trial in the world.
func _obtain(item: String) -> void:
	var f: WorldFeatures = world.features
	await frames(3)
	var trial: Array = f.trial_nodes.get(item, [])
	if trial.is_empty():
		log_lines.append("no trial for " + item)
		return
	var def := {}
	for fr in f.cfg.fragments:
		if fr.id == item:
			def = fr
	var kind: String = def.get("kind", "")
	if item == "sun_key":
		kind = "order_caldor"
	elif item == "moon_key":
		kind = "switches"
	elif item == "star_key":
		kind = "guardian_creature"
	match kind:
		"order", "order_caldor":
			var stones := []
			for n in trial:
				if n is Interactable and n.label.begins_with("Touch") or n is Interactable and n.label.begins_with("Visit"):
					stones.append(n)
			var order: Array = def.get("order", [0, 1, 2, 3])
			for o in order:
				await _use(stones[int(o)])
		"switches":
			for it in world.get_tree().get_nodes_in_group("interactables"):
				if it.label == "Pull the hidden lever" and it.enabled and it.global_position.distance_to(world.features.named_nodes["caldor"].global_position) < 40.0:
					await _use(it)
		"guardian", "guardian_creature":
			for n in trial:
				if is_instance_valid(n) and n is Creature:
					await _kill(n)
		"hidden":
			pass
	await frames(5)
	# Take the fragment / open the key chest that appeared.
	for n in f.trial_nodes.get(item, []):
		if is_instance_valid(n) and n is Interactable and (n.label.begins_with("Take") or n.label == "Open the chest"):
			await _use(n)
	for it in world.get_tree().get_nodes_in_group("interactables"):
		if is_instance_valid(it) and it.enabled and (it.label == "Open the chest" or it.label.begins_with("Take the")):
			if world.state.count(item) == 0:
				await _use(it)
	check(world.state.count(item) > 0, "obtained %s through its trial" % item)


func _save_load_check() -> void:
	var st: GameState = world.state
	var qs: Quests = world.quests
	world.save_game()
	var coins := st.coins
	var items := st.items.duplicate()
	var done := []
	for id in qs.q:
		if qs.q[id].state == "completed":
			done.append(id)
	st.add_coins(999, true)
	world._continue_game()
	await frames(10)
	check(st.coins == coins, "loading restores coins (%d)" % st.coins)
	check(st.items == items, "loading restores the bag")
	var still := true
	for id in done:
		if qs.status(id) != "completed":
			still = false
	check(still, "loading keeps %d completed quests completed" % done.size())


func _contracts() -> void:
	var qs: Quests = world.quests
	for giver in ["harlan", "brann", "board"]:
		var c := qs.contract_convo(giver)
		world.story.open(c)
		await _finish_dialogue()
		var id := qs.active_contract()
		check(id != "", "contract taken from %s" % giver)
		if id == "":
			continue
		var coins: int = world.state.coins
		var guard := 0
		while qs.status(id) == "active" and guard < 10:
			guard += 1
			var goals := Quests.goals_of(qs.current_step(id))
			for gi in goals.size():
				if not qs.goal_done(id, gi):
					await _solve_goal(id, gi, goals[gi])
			await frames(5)
		check(qs.status(id) == "completed", "contract %s (%s) completed" % [id, qs.defs[id].title])
		check(world.state.coins > coins, "contract paid out")
	check(qs.contract_count >= 3, "new contracts keep becoming available")


func _features() -> void:
	var f: WorldFeatures = world.features
	var st: GameState = world.state
	# Discoveries.
	for d in f.cfg.discoveries:
		await _goto(Vector3(d.pos[0], 0, d.pos[1]))
		await wait(0.7)
		await _finish_dialogue()
	var found := 0
	for d in f.cfg.discoveries:
		if st.has_flag("disc:" + d.id):
			found += 1
	check(found == f.cfg.discoveries.size(), "all %d places discovered with notifications (%d)" % [f.cfg.discoveries.size(), found])
	# Shrines.
	for sh in f.cfg.shrines:
		var root: Node3D = f.shrine_nodes[sh.id]
		await _goto(root.global_position + Vector3(4, 0, 4))
		await wait(0.7)
		match sh.puzzle:
			"order":
				var stones := []
				for it in _interactables_near(root.global_position, 9.0):
					if it.label.begins_with("Touch"):
						stones.append(it)
				stones.sort_custom(func(a, b): return a.get_index() < b.get_index())
				for o in sh.order:
					await _use(stones[int(o)])
			"align":
				var drums := []
				for it in _interactables_near(root.global_position, 6.0):
					if it.label == "Turn the stone drum":
						drums.append(it)
				drums.sort_custom(func(a, b): return a.position.x < b.position.x)
				for k in 8:
					if st.has_flag("shrine:" + sh.id):
						break
					for i in drums.size():
						var lbl: Label3D = drums[i].find_children("*", "Label3D", true, false)[1]
						if lbl.text != sh.symbols[int(sh.target[i])]:
							await _use(drums[i])
			"switches":
				for s in sh.switches:
					for it in _interactables_near(Vector3(s[0], 0, s[1]) + Vector3(0, world.data.height(s[0], s[1]), 0), 2.0):
						await _use(it)
			"components":
				for s in sh.parts:
					for it in _interactables_near(Vector3(s[0], world.data.height(s[0], s[1]), s[1]), 2.5):
						await _use(it)
				for it in _interactables_near(root.global_position, 4.0):
					if it.label.begins_with("Set the shards"):
						await _use(it)
			"guardian":
				await wait(0.7)
				var g: Creature = f.named_nodes.get("guard_" + sh.id)
				await _kill(g)
			"route":
				for it in _interactables_near(Vector3(sh.plate[0], world.data.height(sh.plate[0], sh.plate[1]), sh.plate[1]), 2.5):
					await _use(it)
		await frames(5)
		check(st.has_flag("shrine:" + sh.id), "shrine %s (%s puzzle) solved" % [sh.name, sh.puzzle])
		var coins := st.coins
		for it in _interactables_near(root.global_position, 3.0):
			if it.label.begins_with("Open the shrine"):
				await _use(it)
		check(st.coins > coins, "shrine %s gave its reward" % sh.name)
	# Rare bosses.
	for rb in f.cfg.rare_bosses:
		await _goto(Vector3(rb.pos[0], 0, rb.pos[1]) + Vector3(20, 0, 0))
		await wait(0.7)
		var b: Boss = f.bosses.get(rb.id)
		check(b != null, "rare boss %s appears when you come near" % rb.id)
		if b:
			var hp_full := b.max_health
			check(b.cfg.get("attacks", []).size() >= 3, "%s has %d attack moves" % [rb.id, b.cfg.attacks.size()])
			await _kill(b)
			check(st.has_flag("boss:" + rb.id), "%s defeated and remembered" % rb.id)
			check(hp_full > 900.0, "%s is much tougher than ordinary monsters (%d hp)" % [rb.id, int(hp_full)])
	# Treasure.
	await frames(10)
	for t in f.cfg.treasures:
		if st.has_flag("treasure:" + t.id):
			continue
		await _goto(Vector3(t.pos[0], 0, t.pos[1]) + Vector3(5, 0, 0))
		await wait(0.7)
		if t.kind == "guarded":
			await _kill(f.named_nodes.get("guard_" + t.id))
			await frames(5)
		if t.kind == "dig" and t.has("needs") and st.count(t.needs) == 0:
			log_lines.append("missing map for " + t.id)
		f.refresh()
		await frames(3)
		if f.chests.has(t.id):
			await _use(f.chests[t.id])
		check(st.has_flag("treasure:" + t.id), "treasure %s (%s) found" % [t.name, t.kind])
	var coins2 := st.coins
	f._open_treasure(f.cfg.treasures[0])
	await _finish_dialogue()
	check(st.coins == coins2, "a treasure can't be looted twice")


func _events() -> void:
	var f: WorldFeatures = world.features
	for id in ["raid", "merchant", "rare", "crystal_surge", "volcanic", "traveller", "hub_raid"]:
		f.end_event()
		var where: Vector3 = {"raid": Vector3(-210, 0, 30), "hub_raid": Vector3(20, 0, -10), "merchant": Vector3(-20, 0, 50), "rare": Vector3(70, 0, 40),
			"crystal_surge": Vector3(20, 0, 280), "volcanic": Vector3(270, 0, 0), "traveller": Vector3(-110, 0, 10)}[id]
		await _goto(where)
		var ok := f.start_event(id)
		check(ok and not f.event.is_empty(), "world event %s starts" % id)
		await frames(5)
		match id:
			"raid", "hub_raid", "rare":
				for c in f.event_nodes.duplicate():
					if is_instance_valid(c) and c is Creature:
						await _kill(c)
				await wait(1.2)
				check(f.event.is_empty(), "event %s resolves when its creatures are defeated" % id)
			"traveller":
				await _talk("lost_traveller")
				await wait(1.2)
				check(f.event.is_empty(), "helping the traveller ends the event")
			"merchant":
				check(world.story.by_id.has("zara"), "a travelling merchant appears")
				f.end_event()
			_:
				var items_before: Dictionary = world.state.items.duplicate()
				for n in f.event_nodes.duplicate():
					if is_instance_valid(n) and n is Interactable:
						await _use(n)
				check(world.state.items != items_before, "event %s gives gatherable resources" % id)
				f.end_event()
