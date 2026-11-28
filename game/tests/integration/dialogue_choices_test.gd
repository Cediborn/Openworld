extends SceneTree
## Quest offer dialogue test (run: godot --headless --path game -s res://tests/integration/dialogue_choices_test.gd).
## Every choice button of a three-choice offer must sit fully on screen at
## common desktop and phone aspect ratios, and Accept / Later / Deny must each
## do the right thing when their button is pressed.

const SIZES := [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(2400, 1080), Vector2i(1920, 1200), Vector2i(800, 600)]

var world: Node
var fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("PASS " if ok else "FAIL ") + msg)


func frames(n: int) -> void:
	for i in n:
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
	await _layout()
	await _offer_choices()
	print("RESULT: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(fails)


func _layout() -> void:
	var hud: Hud = world.hud
	var long := "The bell tower has fallen silent and nobody will say why. ".repeat(4)
	for sz in SIZES:
		root.size = sz
		await frames(3)
		for n in [2, 3, 4]:
			hud.show_dialogue("Captain Harlan", long, ["Accept", "Later", "Deny", "Ask about the reward"].slice(0, n))
			await frames(3)
			var screen := Rect2(Vector2.ZERO, hud.get_viewport().get_visible_rect().size)
			var ok := true
			for i in n:
				var r: Rect2 = hud.choice_buttons[i].get_global_rect()
				ok = ok and screen.encloses(r) and r.size.y >= 40.0
				for j in i:
					ok = ok and not r.intersects(hud.choice_buttons[j].get_global_rect())
			check(ok, "%dx%d: all %d choices fully on screen, tall enough to tap, not overlapping" % [sz.x, sz.y, n])
	hud.hide_dialogue()
	root.size = Vector2i(1600, 900)
	await frames(2)


## Finds a villager who offers a quest, then presses each choice's real button.
func _offer_choices() -> void:
	var qs: Quests = world.quests
	var story: Story = world.story
	var hud: Hud = world.hud
	var id := ""
	var giver: Villager = null
	for qid in qs.defs:
		var d: Dictionary = qs.defs[qid]
		if qs.status(qid) == "available" and d.has("giver") and not d.has("trigger") and story.by_id.has(d.giver):
			id = qid
			giver = story.by_id[d.giver]
			break
	check(id != "", "found a quest on offer (%s)" % id)
	if id == "":
		return

	# Later: closes without accepting or rejecting; the offer stays.
	await _talk_and_pick(giver, 1)
	check(qs.status(id) == "available", "Later leaves '%s' available" % id)
	check(qs.marker_for(giver) == "!", "Later keeps the giver's ! marker")

	# Deny: rejected, marker gone, nothing started.
	await _talk_and_pick(giver, 2)
	check(qs.status(id) == "declined", "Deny marks '%s' declined" % id)
	check(not id in qs.active_ids(), "Deny does not start the quest")
	check(qs.marker_for(giver) != "!", "Deny removes the giver's ! marker")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(qs.save_state()))
	qs.load_state(saved)
	check(qs.status(id) == "declined", "declined state survives save and load")

	# Reconsider: the giver offers again; Accept starts it.
	await _talk_and_pick(giver, 0)
	check(qs.status(id) == "active", "Accept after declining starts '%s'" % id)
	check(not story.in_dialogue() or not hud.has_choices(), "dialogue closed or moved on after Accept")


func _talk_and_pick(v: Villager, choice: int) -> void:
	var story: Story = world.story
	var hud: Hud = world.hud
	story.open(world.quests.handle_talk(v), v)
	var guard := 0
	while story.in_dialogue() and not hud.has_choices() and guard < 50:
		guard += 1
		hud.dialogue_advanced.emit()
		await frames(2)
	check(hud.has_choices() and hud.choice_buttons[choice].visible, "choice %d (%s) is shown" % [choice, hud.choice_buttons[choice].text.strip_edges()])
	hud.choice_buttons[choice].pressed.emit()
	await frames(2)
	guard = 0
	while story.in_dialogue() and guard < 50:
		guard += 1
		hud.dialogue_advanced.emit()
		await frames(2)
