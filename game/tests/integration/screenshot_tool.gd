extends SceneTree
## Saves screenshots of the real game for QA evidence (needs a display, not --headless):
##   xvfb-run -s "-screen 0 1600x900x24" godot --path game --rendering-method gl_compatibility \
##     -s res://tests/integration/screenshot_tool.gd -- <shot> [<shot> ...]
## Shots: dialogue, hero, outfit, npcs, animals, creatures, shotgun. Files go to
## ../production/qa/evidence/.

const OUT := "res://../production/qa/evidence/"

var world: Node


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _init() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	var t0 := Time.get_ticks_msec()
	while not world.booted and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	world._new_game()
	await frames(30)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for shot in OS.get_cmdline_user_args():
		if has_method("_shot_" + shot):
			await call("_shot_" + shot)
		else:
			print("unknown shot: ", shot)
	quit(0)


func _save(name: String) -> void:
	await frames(4)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT + name + ".png")
	img.save_png(path)
	print("saved ", path)


## Points the camera at a spot from a given offset (world space).
func _look(target: Vector3, offset: Vector3) -> void:
	var cam := root.get_camera_3d()
	world.player.set_physics_process(false)
	world.player.set_process(false)
	cam.global_position = target + offset
	cam.look_at(target, Vector3.UP)
	await frames(2)


func _day() -> void:
	if "time_of_day" in world.state:
		world.state.time_of_day = 0.45


func _shot_dialogue() -> void:
	var qs: Quests = world.quests
	for id in qs.defs:
		var d: Dictionary = qs.defs[id]
		if qs.status(id) == "available" and d.has("giver") and not d.has("trigger") and world.story.by_id.has(d.giver):
			var v: Villager = world.story.by_id[d.giver]
			world.story.open(qs.handle_talk(v), v)
			while not world.hud.has_choices():
				world.hud.dialogue_advanced.emit()
				await frames(2)
			break
	await _save("dialogue_accept_later_deny")
	world.story._choose(1)
	await frames(4)
	while world.story.in_dialogue():
		world.hud.dialogue_advanced.emit()
		await frames(2)
