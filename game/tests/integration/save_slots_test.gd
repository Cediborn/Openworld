extends SceneTree
## Save slots (run: godot --headless --path game -s res://tests/integration/save_slots_test.gd).
## Works in a scratch folder (user://test_saves) so a player's real saves are
## never touched. Checks that every adventure is independent: two new games
## make two slots, each keeps its own coins, place and quests, switching back
## and forth restores each exactly, a save from before slots existed becomes
## a slot without the old file changing, rename and delete work, a damaged
## file falls back to its backup, and the title screen never saves.

var fails := 0
var world: Node


func check(ok: bool, msg: String) -> void:
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok:
		fails += 1


func _clean() -> void:
	for d in ["user://test_saves"]:
		var dir := DirAccess.open(d)
		if dir:
			for f in dir.get_files():
				DirAccess.remove_absolute(ProjectSettings.globalize_path(d + "/" + f))
	if FileAccess.file_exists("user://test_legacy_save.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_legacy_save.json"))


func _init() -> void:
	SaveGame.save_dir = "user://test_saves"
	SaveGame.legacy_path = "user://test_legacy_save.json"
	_clean()
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	var t0 := Time.get_ticks_msec()
	while not world.booted and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	check(world.booted, "world booted")
	var st: GameState = world.state

	# The title screen is not an adventure: closing the game there saves nothing.
	world.save_game()
	check(SaveGame.list_slots().is_empty(), "nothing is saved from the title screen")

	# Adventure A: some coins, a quest flag, standing in Brickton.
	world._new_game("Alda's journey")
	var a: String = world.current_slot
	st.coins = 111
	st.set_flag("met:elder")
	world.player.global_position = Vector3(-300, world.data.height(-300, 0) + 0.2, 0)
	world.playtime = 600.0
	world.save_game()
	# Adventure B starts fresh and never touches A.
	world._new_game("Second try")
	var b: String = world.current_slot
	check(a != b, "a new game makes a new slot")
	check(st.coins == 0 and not st.has_flag("met:elder"), "the new adventure starts from nothing")
	st.coins = 222
	world.save_game()
	check(SaveGame.list_slots().size() == 2, "two independent saves exist")
	var meta: Dictionary = SaveGame.load_save(a).get("meta", {})
	check(meta.get("name") == "Alda's journey" and meta.get("region") == "Brickton" and float(meta.get("playtime", 0)) >= 600.0,
		"slot info: name, region and playtime (%s)" % str(meta))

	# Switch back to A: everything as it was left.
	world._load_slot(a)
	await physics_frame
	check(st.coins == 111 and st.has_flag("met:elder"), "loading A restores its coins and progress")
	var here: Vector3 = world.player.global_position
	check(Vector2(here.x, here.z).distance_to(Vector2(-300, 0)) < 1.0, "and where you stood")
	world._load_slot(b)
	check(st.coins == 222 and not st.has_flag("met:elder"), "and B is still B")
	check(SaveGame.latest_slot() == b, "Continue picks the adventure saved last")

	# "Restart the app": everything comes back from disk.
	var names := SaveGame.list_slots().map(func(s): return s.name)
	check("Alda's journey" in names and "Second try" in names, "slots are still listed after a restart (%s)" % str(names))

	# A save from before slots existed becomes a slot; the old file is left alone.
	var old := {"player": [0, 5, 40], "progress": {"coins": 345, "level": 4, "items": {"potion": 2}}, "quests": {}, "hour": 13.0}
	var f := FileAccess.open(SaveGame.legacy_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	var before := FileAccess.get_file_as_string(SaveGame.legacy_path)
	var slots := SaveGame.list_slots()
	check(slots.size() == 3 and slots.any(func(s): return s.id == SaveGame.LEGACY_SLOT and s.level == 4), "the old save appears as its own adventure")
	check(FileAccess.get_file_as_string(SaveGame.legacy_path) == before, "the old save file is unchanged")
	world._load_slot(SaveGame.LEGACY_SLOT)
	check(st.coins == 345 and st.level == 4, "and it loads (coins %d, level %d)" % [st.coins, st.level])
	SaveGame.list_slots()
	check(SaveGame.list_slots().size() == 3, "it is copied only once")

	# Rename and delete.
	SaveGame.rename_slot(b, "Renamed run")
	check(SaveGame.load_save(b).meta.name == "Renamed run", "a slot can be renamed")
	SaveGame.delete_slot(b)
	check(not SaveGame.list_slots().any(func(s): return s.id == b), "a slot can be deleted")
	check(SaveGame.load_save(a).get("progress", {}).get("coins", 0) == 111, "deleting one leaves the others")

	# A damaged file (a phone killed mid-write) falls back to the previous save.
	world._load_slot(a)
	world.save_game()
	var g := FileAccess.open(SaveGame.save_dir + "/" + a + ".json", FileAccess.WRITE)
	g.store_string("{\"progress\": {\"coi")
	g.close()
	check(SaveGame.load_save(a).get("progress", {}).get("coins", 0) == 111, "a damaged save falls back to its backup")

	_clean()
	print("RESULT: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(fails)
