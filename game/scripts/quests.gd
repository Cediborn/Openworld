class_name Quests
extends Node3D
## The quest system: main storyline, side quests and special quests from
## data/quests.json, on top of the Elder's original quest (run by Story).
##
## A quest is a list of steps; each step has one or more goals that can be
## done in any order. When every goal of a step is done the next step starts.
## Goals put what they need into the world while their step is active (tracks
## to examine, pickups, monsters, an escort, a boss) and are removed again
## afterwards, so a step can always be finished after loading a save.
##
## Goal types:
##   talk {npc, lines}               speak to someone
##   talk_any {count, lines, hide}   speak to N different townsfolk
##   reach {pos, radius, label}      get to a place
##   inspect {pos, label, lines, model, give}   examine something there
##   collect {item, spots, model}    pick things up (one per spot)
##   have {item, count}              carry items (however you got them)
##   deliver {npc, item, count, lines}   hand items to someone
##   place {pos, item, label, lines} put an item somewhere
##   kill {spawn: {species, count, pos, radius, elite}}   defeat those monsters
##   boss {boss, pos}                defeat a boss
##   defend {pos, radius, waves}     survive waves of attackers there
##   escort {npc, from, to}          bring someone to safety
##   observe {target, pos, radius, seconds}   watch something without fighting it
##   flag {flag}                     a world-feature event (puzzle solved...)
##   night {}                        wait for night (rest at an inn or a camp)
##   encounter {npc, pos, night}     meet someone who only appears there
## States: locked (prerequisites missing), available, active, completed.

signal quest_changed

var cfg: Dictionary = {}
var defs: Dictionary = {}          # id -> quest definition
var q := {}                        # id -> {"state", "step", "prog": {goal key -> value}, "rewarded"}
var tracked := ""
var data: WorldData
var player: Player
var hud: Hud
var story: Story
var state: GameState
var sky: SkyCycle
var features: Node                 # WorldFeatures (bosses, flags)
var spawn_creature: Callable       # (species, pos, tag, overrides) -> Creature
var entities := {}                 # goal key -> Array of nodes in the world
var _tick := 0.0
var _observe := {}                 # goal key -> seconds watched


func setup(world_data: WorldData, p: Player, h: Hud, s: Story, gs: GameState) -> void:
	data = world_data
	player = p
	hud = h
	story = s
	state = gs
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/quests.json"))
	defs = cfg.quests
	story.quests = self


# ---------- State ----------

func status(id: String) -> String:
	if id == "island_heart":
		return "completed" if story.stage == "done" else ("active" if story.stage != "intro" else "available")
	if q.has(id):
		return q[id].state
	return "available" if prerequisites_met(id) else "locked"


func is_done(id: String) -> bool:
	return status(id) == "completed"


func prerequisites_met(id: String) -> bool:
	var d: Dictionary = defs[id]
	for r in d.get("requires", []):
		if not is_done(r):
			return false
	for f in d.get("requires_flags", []):
		if not state.has_flag(f):
			return false
	return true


func current_step(id: String) -> Dictionary:
	var steps: Array = defs[id].steps
	var i: int = q[id].step
	return steps[i] if i < steps.size() else {}


## Goals of a step (a step may itself be a single goal).
static func goals_of(step: Dictionary) -> Array:
	return step.get("goals", [step])


func _key(id: String, step_i: int, gi: int) -> String:
	return "%s/%d/%d" % [id, step_i, gi]


func _need(g: Dictionary) -> int:
	match g.type:
		"talk_any":
			return int(g.get("count", 1))
		"collect":
			return int(g.get("count", g.get("spots", [1]).size()))
		"have", "deliver":
			return int(g.get("count", 1))
		"kill":
			return int(g.get("count", g.get("spawn", {}).get("count", 1)))
		"defend":
			return g.waves.size()
	return 1


func progress(id: String, gi: int) -> int:
	var k := _key(id, q[id].step, gi)
	var v = q[id].prog.get(k, 0)
	return v.size() if v is Array else int(v)


func goal_done(id: String, gi: int) -> bool:
	var g: Dictionary = goals_of(current_step(id))[gi]
	if g.type == "have":
		return state.count(g.item) >= _need(g)
	return progress(id, gi) >= _need(g)


func start(id: String, quiet := false) -> void:
	if q.has(id):
		return
	q[id] = {"state": "active", "step": 0, "prog": {}, "rewarded": false}
	if tracked == "" or defs[id].get("type", "side") == "main":
		tracked = id
	if not quiet:
		hud.show_banner(("New Quest: " if defs[id].get("type") != "main" else "Main Quest: ") + defs[id].title, defs[id].get("region", ""))
		hud.toast("Quest accepted: " + defs[id].title, "quest")
	_enter_step(id)
	quest_changed.emit()


func _bump(id: String, gi: int, amount := 1, tag = null) -> void:
	if not q.has(id) or q[id].state != "active":
		return
	var k := _key(id, q[id].step, gi)
	var g: Dictionary = goals_of(current_step(id))[gi]
	if tag != null:
		var arr: Array = q[id].prog.get(k, [])
		if tag in arr:
			return
		arr.append(tag)
		q[id].prog[k] = arr
	else:
		q[id].prog[k] = int(q[id].prog.get(k, 0)) + amount
	var need := _need(g)
	var have := progress(id, gi)
	if have < need and need > 1:
		hud.toast("%s  (%d/%d)" % [goal_text(g), have, need], "quest")
	_check_step(id)
	quest_changed.emit()


func _check_step(id: String) -> void:
	if q[id].state != "active":
		return
	var step := current_step(id)
	for gi in goals_of(step).size():
		if not goal_done(id, gi):
			return
	_leave_step(id)
	q[id].step += 1
	if q[id].step >= defs[id].steps.size():
		_complete(id)
		_sync_quest_npcs(id)
		return
	var nxt := current_step(id)
	hud.toast("Objective: " + step_text(nxt), "quest")
	_enter_step(id)
	if nxt.has("on_start_lines"):
		narrate(nxt.on_start_lines, nxt.get("speaker", ""))


func _complete(id: String) -> void:
	q[id].state = "completed"
	q[id].step = defs[id].steps.size()
	if tracked == id:
		tracked = ""
		for other in q:
			if q[other].state == "active":
				tracked = other
				if defs[other].get("type") == "main":
					break
	var d: Dictionary = defs[id]
	hud.show_banner("Quest Complete: " + d.title, _reward_text(d.get("rewards", {})))
	_give_rewards(id)
	for f in d.get("on_complete_flags", []):
		state.set_flag(f)
	if d.has("epilogue"):
		narrate(d.epilogue, d.get("epilogue_speaker", ""))
	if d.get("unhide", false):
		for v in story.villagers:
			if v.hiding:
				v.set_hiding(false)
				v.global_position = Vector3(v.home.x, data.height(v.home.x, v.home.z), v.home.z)
	quest_changed.emit()


## Rewards are given exactly once, even if completion is somehow repeated.
func _give_rewards(id: String) -> void:
	if q[id].get("rewarded", false):
		return
	q[id].rewarded = true
	var r: Dictionary = defs[id].get("rewards", {})
	if r.has("coins"):
		state.add_coins(int(r.coins))
	if r.has("xp"):
		state.add_xp(int(r.xp))
	if r.has("rep"):
		state.add_reputation(int(r.rep))
	for it in r.get("items", {}):
		state.add_item(it, int(r.items[it]))
	for f in r.get("flags", []):
		state.set_flag(f)
	if r.has("smith"):
		state.smith_level += int(r.smith)
		state.apply_stats()
		hud.toast("Sword upgraded (+%d%% damage)" % int(12 * int(r.smith)), "item")


func _reward_text(r: Dictionary) -> String:
	var parts := []
	if r.has("coins"):
		parts.append("%d coins" % int(r.coins))
	if r.has("xp"):
		parts.append("%d XP" % int(r.xp))
	for it in r.get("items", {}):
		var n := int(r.items[it])
		parts.append(("%d× " % n if n > 1 else "") + state.item_name(it))
	if r.has("rep"):
		parts.append("+%d reputation" % int(r.rep))
	if r.has("smith"):
		parts.append("sword upgrade")
	if r.has("text"):
		parts.append(r.text)
	return ", ".join(parts)


func reward_text(id: String) -> String:
	return _reward_text(defs[id].get("rewards", {}))


## Shows narration as a conversation, or queues it if one is already open.
func narrate(lines: Array, speaker := "") -> void:
	if story.in_dialogue():
		for l in lines:
			hud.show_notice(l)
	else:
		story.open({"speaker": speaker, "lines": lines})


# ---------- Text ----------

func goal_text(g: Dictionary) -> String:
	return g.get("text", g.type.capitalize())


func step_text(step: Dictionary) -> String:
	return step.get("text", goal_text(goals_of(step)[0]))


## Lines for the tracker: title and the current goals with progress.
func tracker_text(id: String) -> String:
	if id == "island_heart":
		return story.original_tracker()
	if not q.has(id) or q[id].state != "active":
		return ""
	var t: String = defs[id].title + "\n"
	var goals := goals_of(current_step(id))
	if goals.size() > 1 and current_step(id).has("text"):
		t += current_step(id).text + "\n"
	for gi in goals.size():
		var g: Dictionary = goals[gi]
		var need := _need(g)
		var have := state.count(g.item) if g.type == "have" else progress(id, gi)
		t += ("✔ " if goal_done(id, gi) else "○ ") + goal_text(g) + (" (%d/%d)" % [mini(have, need), need] if need > 1 else "") + "\n"
	return t


func refresh_tracker() -> void:
	var t := ""
	if story.stage != "done" and (tracked == "" or tracked == "island_heart"):
		t = story.original_tracker()
	elif tracked != "":
		t = tracker_text(tracked)
	hud.set_quest(t)


func active_ids() -> Array:
	var out := []
	for id in q:
		if q[id].state == "active":
			out.append(id)
	return out


func track(id: String) -> void:
	tracked = id
	_update_beacons()
	refresh_tracker()


# ---------- Talking ----------

## What to show above a villager: "!" quest to offer, "?" someone to report to.
func marker_for(v: Villager) -> String:
	for id in q:
		if q[id].state != "active":
			continue
		for g in goals_of(current_step(id)):
			if g.get("npc", "") == v.id and g.type in ["talk", "deliver"]:
				return "?"
	if story.stage == "intro" and v.id == "elder":
		return "!"
	if story.stage in ["return"] and v.id == "elder" or story.stage == "forge" and v.id == "smith":
		return "?"
	for id in defs:
		var d: Dictionary = defs[id]
		if d.get("giver", "") == v.id and status(id) == "available" and not d.has("trigger"):
			return "!"
	return ""


## Called by Story when talking to a villager; returns a conversation or {}.
func handle_talk(v: Villager) -> Dictionary:
	# 1. Someone an active quest wants you to talk to (or hand something to).
	for id in active_ids():
		var goals := goals_of(current_step(id))
		for gi in goals.size():
			var g: Dictionary = goals[gi]
			if goal_done(id, gi) or g.get("npc", "") != v.id:
				continue
			if g.type == "talk":
				var qid: String = id
				var gidx: int = gi
				var gift: Dictionary = g.get("give", {})
				return {"lines": g.get("lines", ["..."]), "on_end": func() -> void:
					for it in gift:
						state.add_item(it, int(gift[it]))
					_bump(qid, gidx)}
			if g.type == "deliver" and g.has("items"):
				var all_there := true
				for it in g.items:
					if state.count(it) < int(g.items[it]):
						all_there = false
				if all_there:
					var qid4: String = id
					var gidx4: int = gi
					var need_items: Dictionary = g.items
					return {"lines": g.get("lines", ["Thank you."]), "on_end": func() -> void:
						for it in need_items:
							state.remove_item(it, int(need_items[it]))
						_bump(qid4, gidx4, _need(goals_of(current_step(qid4))[gidx4]))}
				var missing := []
				for it in g.items:
					if state.count(it) < int(g.items[it]):
						missing.append("%d %s (have %d)" % [int(g.items[it]), state.item_name(it), state.count(it)])
				return {"lines": [g.get("waiting", "Not yet. Still need: " + ", ".join(missing) + ".")]}
			if g.type == "deliver":
				if state.count(g.item) >= int(g.get("count", 1)):
					var qid2: String = id
					var gidx2: int = gi
					var item: String = g.item
					var n := int(g.get("count", 1))
					return {"lines": g.get("lines", ["Thank you."]), "on_end": func() -> void:
						state.remove_item(item, n)
						_bump(qid2, gidx2, n)}
				return {"lines": [g.get("waiting", "Do you have it? Bring me %s." % state.item_name(g.item))]}
	# 2. A quest this person can give you.
	for id in defs:
		var d: Dictionary = defs[id]
		if d.get("giver", "") == v.id and status(id) == "available" and not d.has("trigger"):
			return offer(id)
	# 3. Townsfolk who count for a "speak to N people" goal.
	for id in active_ids():
		var goals := goals_of(current_step(id))
		for gi in goals.size():
			var g: Dictionary = goals[gi]
			if g.type != "talk_any" or goal_done(id, gi) or v.id in g.get("exclude", []):
				continue
			if g.has("only"):
				if not v.id in g.only:
					continue
			elif v.role in ["merchant"] or not v.home.x < -180.0:
				continue   # townsfolk of Brickton only
			var done: Array = q[id].prog.get(_key(id, q[id].step, gi), [])
			if v.id in done:
				continue
			var pool: Array = g.get("lines", ["Sorry, I don't know anything about that."])
			var line: String = g.get("by_npc", {}).get(v.id, pool[done.size() % pool.size()])
			var qid3: String = id
			var gidx3: int = gi
			var hide: bool = g.get("hide", false)
			return {"lines": [line], "on_end": func() -> void:
				_bump(qid3, gidx3, 1, v.id)
				if hide:
					v.set_hiding(true, _shelter_for(v))}
	# 4. A quest giver whose quest is under way: a reminder.
	for id in active_ids():
		var d: Dictionary = defs[id]
		if d.get("giver", "") == v.id and d.has("progress_lines"):
			return {"lines": d.progress_lines}
	return {}


## The offer conversation: description, then Accept / Not now.
func offer(id: String) -> Dictionary:
	var d: Dictionary = defs[id]
	var lines: Array = d.get("offer", [d.description])
	var reward := reward_text(id)
	return {"lines": lines + ["(Reward: %s)" % reward] if reward != "" else lines, "choices": ["Accept", "Not now"],
		"on_choice": func(i: int) -> Dictionary:
			if i == 0:
				start(id)
				var acc: Array = d.get("accept", [])
				return {"lines": acc} if not acc.is_empty() else {}
			return {"lines": d.get("decline", ["Come back if you change your mind."])}}


## Where a villager runs to during an attack: their own front door, or the nearest house.
func _shelter_for(v: Villager) -> Vector3:
	var best := Vector3.INF
	for h in data.houses:
		var door: Vector3 = Vector3(h.x, 0, h.z) + Vector3(sin(h.rot), 0, cos(h.rot)) * (h.d * 0.5 + 0.4)
		if best == Vector3.INF or door.distance_to(v.global_position) < best.distance_to(v.global_position):
			best = door
	return best


# ---------- World entities for the active step ----------

## Quest characters who stay in the world for a range of steps ("present": [first, last]).
func _sync_quest_npcs(id: String) -> void:
	var npcs: Dictionary = defs[id].get("npcs", {})
	for nid in npcs:
		var pr: Array = npcs[nid].get("present", [])
		if pr.is_empty():
			continue
		var want: bool = q[id].state == "active" and q[id].step >= int(pr[0]) and q[id].step <= int(pr[1])
		if want and not story.by_id.has(nid):
			var nd: Dictionary = npcs[nid].duplicate(true)
			nd["id"] = nid
			var pos: Array = nd.get("home", [])
			for g in goals_of(defs[id].steps[int(pr[0])]):
				if g.get("npc", "") == nid and g.has("pos"):
					pos = g.pos
			if q[id].prog.has(nid + "/pos"):
				pos = q[id].prog[nid + "/pos"]
			nd["home"] = pos
			story.spawn_villager(nd, 989)
		elif not want and story.by_id.has(nid):
			story.remove_villager(nid)


func _enter_step(id: String) -> void:
	_sync_quest_npcs(id)
	var step := current_step(id)
	var goals := goals_of(step)
	for gi in goals.size():
		if goal_done(id, gi):
			continue
		_spawn_goal(id, q[id].step, gi, goals[gi])
	_update_beacons()
	_check_step(id)


func _leave_step(id: String) -> void:
	var si: int = q[id].step
	var prefix := "%s/%d/" % [id, si]
	# Characters the next step talks to stay where they are (encounter -> talk).
	var keep := {}
	if si + 1 < defs[id].steps.size():
		for g2 in goals_of(defs[id].steps[si + 1]):
			if g2.has("npc"):
				keep[g2.npc] = true
	for k in entities.keys():
		if (k as String).begins_with(prefix):
			for n in entities[k]:
				if not is_instance_valid(n):
					continue
				if n is Villager and keep.has(n.id):
					_add_entity(_key(id, si + 1, 0), n)
				else:
					_despawn(n)
			entities.erase(k)


func _despawn(n: Node) -> void:
	if n is Villager:
		story.remove_villager(n.id)
	elif n is Creature and n.alive():
		n.unique = true
		n.queue_free()
	elif n is Creature:
		pass   # let the body finish falling; it frees itself
	else:
		n.queue_free()


func _add_entity(k: String, n: Node) -> void:
	if not entities.has(k):
		entities[k] = []
	entities[k].append(n)


func _v3(a: Array) -> Vector3:
	return Vector3(a[0], data.height(a[0], a[1]), a[1])


func _spawn_goal(id: String, si: int, gi: int, g: Dictionary) -> void:
	var k := _key(id, si, gi)
	match g.type:
		"inspect", "place":
			var it := Interactable.new(g.get("label", "Examine"), float(g.get("range", 2.6)))
			add_child(it)
			it.global_position = _v3(g.pos)
			_build_model(it, g.get("model", "marker"), g)
			it.action = func(node: Interactable) -> void: _use_inspect(id, gi, g, node)
			_add_entity(k, it)
		"collect":
			var done: Array = q[id].prog.get(k, [])
			var spots: Array = g.spots
			for si2 in spots.size():
				if si2 in done:
					continue
				var it := Interactable.new(g.get("label", "Pick up " + state.item_name(g.item)), 2.4)
				add_child(it)
				it.global_position = _v3(spots[si2])
				_build_model(it, g.get("model", "pickup"), g)
				it.bob = g.get("model", "pickup") in ["pickup", "page", "fragment", "shard"]
				var spot_i: int = si2
				it.action = func(node: Interactable) -> void:
					player.body.play_once("PickUp_Table", 0.1, 1.3)
					state.add_item(g.item, 1)
					node.queue_free()
					_bump(id, gi, 1, spot_i)
				_add_entity(k, it)
		"kill":
			var sp: Dictionary = g.get("spawn", {})
			if sp.is_empty():
				return
			var left := _need(g) - progress(id, gi)
			var centre := Vector3(sp.pos[0], 0, sp.pos[1])
			for n in left:
				var a := TAU * n / maxf(left, 1)
				var r: float = float(sp.get("radius", 6.0)) * (0.4 + 0.6 * fmod(n * 0.618, 1.0))
				var pos := centre + Vector3(cos(a) * r, 0, sin(a) * r)
				var c: Creature = spawn_creature.call(sp.species, pos, "q:" + k, sp.get("elite", {}))
				if c:
					var gift: Dictionary = g.get("give", {})
					c.killed.connect(func(_c: Creature) -> void:
						for it in gift:
							state.add_item(it, int(gift[it]))
						_bump(id, gi))
					_add_entity(k, c)
		"boss":
			if features and features.has_method("spawn_boss"):
				var b: Creature = features.spawn_boss(g.boss, Vector3(g.pos[0], 0, g.pos[1]), "q:" + k)
				if b:
					b.killed.connect(func(_c: Creature) -> void: _bump(id, gi))
					_add_entity(k, b)
		"escort":
			var npc_def: Dictionary = defs[id].npcs[g.npc]
			if not story.by_id.has(g.npc):
				var nd := npc_def.duplicate(true)
				nd["id"] = g.npc
				nd.home = q[id].prog.get(g.npc + "/pos", g.from)
				var v := story.spawn_villager(nd, 991)
				v.set_meta("escort", true)
				_add_entity(k, v)
		"encounter", "talk":
			# Characters who only exist for this quest step.
			if g.has("npc") and defs[id].get("npcs", {}).has(g.npc) and not story.by_id.has(g.npc):
				if g.type == "encounter" and g.get("night", false) and not _is_night():
					return
				var nd: Dictionary = defs[id].npcs[g.npc].duplicate(true)
				if not nd.get("present", []).is_empty():
					return   # kept by _sync_quest_npcs
				nd["id"] = g.npc
				if g.has("pos"):
					nd.home = g.pos
				var v := story.spawn_villager(nd, 990)
				_add_entity(k, v)

		"defend":
			pass   # waves start when the explorer arrives (see _process)


func _use_inspect(id: String, gi: int, g: Dictionary, node: Interactable) -> void:
	if g.type == "place":
		var need_items: Dictionary = g.get("items", {g.item: int(g.get("count", 1))})
		for it in need_items:
			if state.count(it) < int(need_items[it]):
				story.open({"speaker": "", "lines": [g.get("missing", "You need %s." % state.item_name(it))]})
				return
		for it in need_items:
			state.remove_item(it, int(need_items[it]))
	if g.has("needs") and state.count(g.needs) <= 0:
		story.open({"speaker": "", "lines": [g.get("missing", "You need %s." % state.item_name(g.needs))]})
		return
	node.enabled = false
	if g.get("pickup_anim", true):
		player.body.play_once("PickUp_Table", 0.1, 1.3)
	var lines: Array = g.get("lines", [])
	var finish := func() -> void:
		if g.has("give"):
			for it in g.give:
				state.add_item(it, int(g.give[it]))
		if g.get("remove_model", false) and is_instance_valid(node):
			node.queue_free()
		_bump(id, gi)
	if lines.is_empty():
		finish.call()
	else:
		story.open({"speaker": g.get("speaker", ""), "lines": lines, "on_end": finish})


func _build_model(it: Interactable, model: String, g: Dictionary) -> void:
	var col: Color = Color(g.color[0], g.color[1], g.color[2]) if g.has("color") else Color(1.0, 0.85, 0.4)
	var vis := Node3D.new()
	it.add_child(vis)
	it.visual = vis
	match model:
		"tracks":
			var dir := Vector3(g.get("dir", [1, 0])[0], 0, g.get("dir", [1, 0])[1]).normalized()
			Structures.footprints(it, it.global_position - dir * 3.0, it.global_position + dir * 3.0, data.height)
			for c in it.get_children():
				if c is MeshInstance3D:
					c.global_position.y = data.height(c.global_position.x, c.global_position.z) + 0.03
		"campsite":
			Structures.tent(vis, Vector3(-2.5, 0, -1.5), 0.4, Color(0.55, 0.5, 0.4), true)
			Structures.campfire(vis, Vector3(0.5, 0, 0.5), false)
			Structures.bedroll(vis, Vector3(1.5, 0, -1.8), 0.2, Color(0.35, 0.3, 0.45))
			Structures.crate(vis, Vector3(-0.8, 0, 2.0), 0.4, 0.7, true)
		"equipment":
			Structures.tent(vis, Vector3(-2.0, 0, 0), 0.9, Color(0.75, 0.3, 0.2), true)
			Structures.crate(vis, Vector3(1.2, 0, 0.5), 0.2, 0.7, true)
			Structures.barrel(vis, Vector3(1.8, 0, -0.8), true)
			Structures.cyl(vis, 0.02, 0.02, 1.6, Vector3(0.5, 0.2, -1.2), Structures.wood(), Vector3(PI * 0.45, 0.3, 0))
		"inscription", "tablet":
			Structures.tablet(vis, Vector3(0, 0, -0.9), 0.0, col)
		"bag":
			Structures.sphere(vis, 0.3, Vector3(0, 0.25, 0), Structures.plain(Color(0.5, 0.38, 0.22), 0.95), Vector3(1.0, 0.8, 0.8))
		"journal", "page", "pickup", "fragment", "shard":
			var m := Structures.glow_mat(col, 1.2) if model in ["fragment", "shard"] else Structures.plain(Color(0.9, 0.85, 0.7), 1.0)
			if model in ["fragment", "shard"]:
				Structures.prism(vis, Vector3(0.25, 0.4, 0.12), Vector3.ZERO, m)
			elif model == "journal":
				Structures.box(vis, Vector3(0.25, 0.06, 0.34), Vector3.ZERO, Structures.plain(Color(0.4, 0.15, 0.12), 0.9))
			else:
				Structures.box(vis, Vector3(0.24, 0.01, 0.32), Vector3.ZERO, m, Vector3(0.2, 0.3, 0.1))
			vis.position.y = 0.5
		"crystal":
			Structures.crystal_cluster(vis, Vector3.ZERO, col, 7, float(g.get("size", 1.8)), hash(g.get("label", "c")))
		"plant":
			Structures.cyl(vis, 0.02, 0.02, 0.4, Vector3(0, 0.2, 0), Structures.plain(Color(0.2, 0.45, 0.25)))
			Structures.sphere(vis, 0.12, Vector3(0, 0.45, 0), Structures.glow_mat(col, 1.5), Vector3(1, 0.6, 1))
		"burrow":
			Structures.burrow(vis, Vector3.ZERO, 1.2)
		"altar":
			Structures.box(vis, Vector3(1.2, 1.0, 1.2), Vector3(0, 0.5, 0), Structures.old_stone(), Vector3.ZERO, true)
			Structures.sphere(vis, 0.2, Vector3(0, 1.15, 0), Structures.glow_mat(col, 1.5))
		"chest":
			Structures.box(vis, Vector3(0.9, 0.55, 0.6), Vector3(0, 0.28, 0), Structures.wood(Color(0.5, 0.35, 0.2)), Vector3.ZERO, true)
			Structures.box(vis, Vector3(0.95, 0.08, 0.65), Vector3(0, 0.58, 0), Structures.plain(Color(0.6, 0.5, 0.25), 0.4, 0.7))
		"stone":
			Structures.standing_stone(vis, Vector3.ZERO, 2.6, 0.3)
		"wagon":
			Structures.wagon(vis, Vector3(0, 0, -1.5), 0.6, true)
		"marker":
			Structures.sphere(vis, 0.35, Vector3(0, 0.05, 0), Structures.tex_mat("dirt_floor", Color(0.5, 0.42, 0.32), 1.0), Vector3(1.4, 0.25, 1.4))
		"bell":
			pass
		_:
			pass


func _is_night() -> bool:
	if sky == null:
		return false
	return sky.time_of_day >= 20.0 or sky.time_of_day < 5.0


## Beacons above the tracked quest's targets only (keeps the screen clear).
func _update_beacons() -> void:
	for k in entities:
		var on := tracked != "" and (k as String).begins_with(tracked + "/")
		for n in entities[k]:
			if is_instance_valid(n) and n is Interactable:
				n.set_beacon(on)


## Position of the tracked quest's nearest unfinished goal (or INF).
func objective_position() -> Vector3:
	if tracked == "" or tracked == "island_heart":
		return story.original_target() if story.stage != "done" else Vector3.INF
	if not q.has(tracked) or q[tracked].state != "active":
		return Vector3.INF
	var best := Vector3.INF
	var goals := goals_of(current_step(tracked))
	for gi in goals.size():
		if goal_done(tracked, gi):
			continue
		var g: Dictionary = goals[gi]
		var cands: Array = []
		match g.type:
			"talk", "deliver":
				if story.by_id.has(g.npc):
					cands.append(story.by_id[g.npc].global_position)
			"collect":
				for n in entities.get(_key(tracked, q[tracked].step, gi), []):
					if is_instance_valid(n):
						cands.append(n.global_position)
			"kill", "boss":
				for n in entities.get(_key(tracked, q[tracked].step, gi), []):
					if is_instance_valid(n) and n is Creature and n.alive():
						cands.append(n.global_position)
				if cands.is_empty() and g.has("pos"):
					cands.append(_v3(g.pos))
				elif cands.is_empty() and g.has("spawn"):
					cands.append(_v3(g.spawn.pos))
			"escort":
				cands.append(_v3(g.to))
			"have":
				if g.has("pos"):
					cands.append(_v3(g.pos))
			_:
				if g.has("pos"):
					cands.append(_v3(g.pos))
		for c in cands:
			if best == Vector3.INF or c.distance_to(player.global_position) < best.distance_to(player.global_position):
				best = c
	return best


# ---------- Quests that start by themselves ----------

var triggers := {}       # quest id -> Interactable

## Quests started by finding something (a map, a hole in the ground) and
## quests that start as soon as their prerequisites are done.
func _starters() -> void:
	for id in defs:
		var d: Dictionary = defs[id]
		if q.has(id) or d.get("virtual", false):
			if triggers.has(id):
				triggers[id].queue_free()
				triggers.erase(id)
			continue
		if status(id) != "available":
			continue
		if d.get("auto", false):
			start(id)
			continue
		if not d.has("trigger"):
			continue
		var tr: Dictionary = d.trigger
		if tr.get("reach", false):
			if not story.in_dialogue() and Vector2(player.global_position.x - tr.pos[0], player.global_position.z - tr.pos[1]).length() < float(tr.get("radius", 10.0)):
				if not _declined.has(id) or Time.get_ticks_msec() - _declined[id] > 60000:
					_offer_trigger(id)
		elif not triggers.has(id):
			var it := Interactable.new(tr.get("label", "Examine"), 2.8)
			add_child(it)
			it.global_position = _v3(tr.pos)
			_build_model(it, tr.get("model", "marker" if id != "queen_beneath" else "burrow"), tr)
			var qid: String = id
			it.action = func(_n: Interactable) -> void: _offer_trigger(qid)
			triggers[id] = it


var _declined := {}


func _offer_trigger(id: String) -> void:
	var d: Dictionary = defs[id]
	var lines: Array = d.trigger.get("lines", []) + d.get("offer", ["Begin this quest?"])
	var reward := reward_text(id)
	if reward != "":
		lines[-1] = lines[-1] + "  (Reward: %s)" % reward
	story.open({"speaker": "", "lines": lines, "choices": ["Yes, follow the trail", "Not now"],
		"on_choice": func(i: int) -> Dictionary:
			if i == 0:
				start(id)
			else:
				_declined[id] = Time.get_ticks_msec()
			return {}})


# ---------- Monster contracts ----------

var contract_count := 0


func active_contract() -> String:
	for id in active_ids():
		if defs[id].get("type") == "contract":
			return id
	return ""


## A conversation offering the next contract (or a reminder of the current one).
func contract_convo(giver: String) -> Dictionary:
	var cur := active_contract()
	if cur != "":
		return {"lines": ["You already have a contract: %s. %s" % [defs[cur].title, step_text(current_step(cur))]]}
	var d := _make_contract(contract_count, giver)
	return {"lines": ["Contract: %s." % d.title, d.description, "Pay: %s. Danger: %s." % [reward_text_of(d), ["", "low", "moderate", "high"][int(d.tier)]]],
		"choices": ["Take the contract", "Not now"],
		"on_choice": func(i: int) -> Dictionary:
			if i != 0:
				return {}
			var id := "contract_%d" % contract_count
			contract_count += 1
			defs[id] = d
			start(id)
			q[id]["def"] = d
			return {"lines": ["Good hunting. You'll be paid as soon as it's done."]}}


func reward_text_of(d: Dictionary) -> String:
	return _reward_text(d.get("rewards", {}))


## Builds contract number n: template and site rotate, difficulty follows the explorer's level.
func _make_contract(n: int, giver: String) -> Dictionary:
	var tpls: Array = cfg.contracts.templates
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = n * 7919 + hash(giver)
	var t: Dictionary = tpls[(n + rng2.randi() % tpls.size()) % tpls.size()]
	var tier := clampi(1 + (state.level - 1) / 3, 1, 3)
	var mult := 1.0 + 0.35 * (tier - 1)
	var elite := {"health": mult * (1.8 if t.get("elite", false) else 1.0), "damage": 1.0 + 0.15 * (tier - 1) + (0.2 if t.get("elite", false) else 0.0)}
	if t.get("elite", false):
		elite["scale"] = 1.3
		elite["tint"] = [1.0, 0.75, 0.3]
		elite["name"] = t.get("elite_name", "")
	var step := {}
	if t.get("defend", false):
		var waves: Array = []
		for w in t.waves:
			var ww := []
			for grp in w:
				ww.append([grp[0], int(grp[1]) + (tier - 1), {"health": mult}])
			waves.append(ww)
		step = {"type": "defend", "text": t.title, "pos": t.pos, "radius": 25, "waves": waves, "from": [1, 1]}
	else:
		var site: Array = t.sites[rng2.randi() % t.sites.size()]
		step = {"type": "kill", "text": "%s (%s)" % [t.title, ["", "Tier I", "Tier II", "Tier III"][tier]],
			"spawn": {"species": t.species, "count": int(t.count) + (tier - 1 if int(t.count) > 1 else 0), "pos": site, "radius": 5, "elite": elite}}
	return {"title": t.title, "type": "contract", "region": "Contract", "description": t.desc, "giver": "", "tier": tier,
		"steps": [step], "rewards": {"coins": int(t.base_coins) * tier + 20, "xp": int(t.xp) * tier}}


# ---------- Per-frame checks ----------

func _process(delta: float) -> void:
	if player == null:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.25
	var dt := 0.25
	_starters()
	for id in active_ids():
		var goals := goals_of(current_step(id))
		for gi in goals.size():
			if not q.has(id) or q[id].state != "active" or gi >= goals_of(current_step(id)).size():
				break
			if goal_done(id, gi):
				continue
			var g: Dictionary = goals[gi]
			var k := _key(id, q[id].step, gi)
			match g.type:
				"reach":
					if Vector2(player.global_position.x - g.pos[0], player.global_position.z - g.pos[1]).length() < float(g.get("radius", 8.0)):
						if g.has("lines"):
							narrate(g.lines, g.get("speaker", ""))
						_bump(id, gi)
				"have":
					if state.count(g.item) >= _need(g):
						_check_step(id)
						quest_changed.emit()
				"flag":
					if state.has_flag(g.flag):
						_bump(id, gi)
				"night":
					if _is_night():
						_bump(id, gi)
				"encounter":
					if not story.by_id.has(g.npc):
						if not g.get("night", false) or _is_night():
							_spawn_goal(id, q[id].step, gi, g)
							_update_beacons()
					elif story.by_id[g.npc].global_position.distance_to(player.global_position) < float(g.get("radius", 7.0)):
						_bump(id, gi)
				"escort":
					_escort_update(id, gi, g, k, dt)
				"observe":
					_observe_update(id, gi, g, k, dt)
				"defend":
					_defend_update(id, gi, g, k)
		if q.has(id) and q[id].state == "active":
			_check_step(id)   # e.g. "have" goals satisfied by items found elsewhere
	var pos := objective_position()
	hud.set_objective(pos)
	refresh_tracker()


func _escort_update(id: String, gi: int, g: Dictionary, k: String, dt: float) -> void:
	var v: Villager = story.by_id.get(g.npc)
	if v == null:
		_spawn_goal(id, q[id].step, gi, g)
		return
	v.mode = "escorted"
	q[id].prog[g.npc + "/pos"] = [v.global_position.x, v.global_position.z]
	var to := player.global_position - v.global_position
	to.y = 0
	var dest := _v3(g.to)
	if Vector2(v.global_position.x - dest.x, v.global_position.z - dest.z).length() < float(g.get("radius", 8.0)):
		v.walking = false
		_bump(id, gi)
		return
	# Follow a few steps behind the explorer; wait if left far behind.
	if to.length() > 2.5 and to.length() < 30.0:
		v.path = [player.global_position - to.normalized() * 2.0]
		v.walking = true
		v.cfg.walk_speed = clampf(to.length() * 0.9, 1.2, 6.0)
	elif to.length() >= 30.0:
		v.walking = false
		if int(Time.get_ticks_msec() / 1000) % 8 == 0:
			hud.toast(v.display_name + " is waiting for you", "quest")


func _observe_update(id: String, gi: int, g: Dictionary, k: String, dt: float) -> void:
	var target: Node3D = features.named(g.target) if features and features.has_method("named") else null
	var p: Vector3 = target.global_position if target else _v3(g.pos)
	var d := player.global_position.distance_to(p)
	if d < float(g.get("radius", 12.0)) and not player.swing >= 0:
		_observe[k] = float(_observe.get(k, 0.0)) + dt
		if int(_observe[k] * 4.0) % 8 == 0:
			hud.set_prompt("Watching... %d%%" % int(100.0 * _observe[k] / float(g.get("seconds", 8.0))), story.touch)
		if _observe[k] >= float(g.get("seconds", 8.0)):
			if g.has("lines"):
				narrate(g.lines)
			_bump(id, gi)


## Waves arrive one at a time once the explorer is at the place to defend.
func _defend_update(id: String, gi: int, g: Dictionary, k: String) -> void:
	var centre := _v3(g.pos)
	var alive := 0
	for n in entities.get(k, []):
		if is_instance_valid(n) and n is Creature and n.alive():
			alive += 1
	if alive > 0:
		return
	var wave := progress(id, gi)
	var spawned := int(q[id].prog.get(k + "/spawned", 0))
	if spawned > wave:
		# The current wave is down.
		_bump(id, gi)
		if goal_done(id, gi):
			hud.show_banner("Defended!", defs[id].title)
		return
	if player.global_position.distance_to(centre) > float(g.get("radius", 30.0)):
		return
	var w: Array = g.waves[wave]
	q[id].prog[k + "/spawned"] = spawned + 1
	hud.show_banner("Wave %d of %d" % [wave + 1, g.waves.size()], g.get("wave_text", "Here they come!"))
	var from_dir: Array = g.get("from", [1, 0])
	var base := centre + Vector3(from_dir[0], 0, from_dir[1]).normalized() * float(g.get("spawn_dist", 22.0))
	var n := 0
	for group in w:
		for i in int(group[1]):
			var off := Vector3(cos(n * 2.4) * (2.0 + n), 0, sin(n * 2.4) * (2.0 + n))
			var elite: Dictionary = group[2] if group.size() > 2 else {}
			var c: Creature = spawn_creature.call(group[0], base + off, ("raid:" if g.get("raid", false) else "q:") + k, elite)
			if c:
				c.home = centre
				c.cfg = c.cfg.duplicate()
				c.cfg.aggro_radius = 60.0
				c.cfg.leash = 90.0
				c.cfg.chase_time = 60.0
				c.state = Creature.State.CHASE
				c.timer = 60.0
				_add_entity(k, c)
			n += 1


# ---------- Saving ----------

func save_state() -> Dictionary:
	return {"quests": q, "tracked": tracked, "contracts": contract_count}


func load_state(s: Dictionary) -> void:
	for k in entities.keys():
		for n in entities[k]:
			if is_instance_valid(n):
				_despawn(n)
	entities.clear()
	for id in defs:
		for nid in defs[id].get("npcs", {}):
			story.remove_villager(nid)
	for id in triggers.keys():
		triggers[id].queue_free()
	triggers.clear()
	q = s.get("quests", {}).duplicate(true)
	contract_count = int(s.get("contracts", 0))
	for id in q.keys():
		if q[id].has("def"):
			defs[id] = q[id].def   # generated contracts carry their own definition
		if not defs.has(id):
			q.erase(id)
			continue
		q[id].step = int(q[id].step)
		q[id]["rewarded"] = q[id].get("rewarded", q[id].state == "completed")
		# Waves that were spawned but not finished start again after a load.
		for k in q[id].prog.keys():
			if (k as String).ends_with("/spawned"):
				q[id].prog.erase(k)
	tracked = s.get("tracked", "")
	for id in q:
		if q[id].state == "active":
			_enter_step(id)
	quest_changed.emit()
