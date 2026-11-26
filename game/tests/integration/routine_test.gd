extends SceneTree
## Townsfolk daily routine (run: godot --headless --path game -s res://tests/integration/routine_test.gd).
## At night a strolling villager walks to a door and goes indoors (no invisible
## body left in the doorway), comes out after dawn, and evening tavern-goers
## walk to the tavern. Shopkeepers and quest people keep their posts.

var fails := 0

func check(ok: bool, msg: String) -> void:
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok:
		fails += 1


func make(mode: String, role: String, seed_value: int) -> Villager:
	var v := Villager.new()
	v.setup({"id": "v%d" % seed_value, "name": "V", "role": role, "mode": mode, "outfit": {}, "home": [0, 0]}, seed_value)
	root.add_child(v)
	return v


func run(v: Villager, seconds: float) -> void:
	for i in int(seconds * 30.0):
		v._process(1.0 / 30.0)


func _init() -> void:
	await process_frame
	Villager.doors = [Vector3(8, 0, 0), Vector3(-40, 0, 0)]
	Villager.places = {"tavern": Vector3(0, 0, 25), "church": Vector3(0, 0, -25)}
	var walker := make("stroll", "villager", 1)
	var smith := make("work", "smith", 2)

	Villager.hour = 23.0
	run(walker, 20.0)
	check(walker.routine == "home" and walker.hiding and not walker.visible, "at 23:00 a townsperson has gone indoors")
	check(walker.global_position.distance_to(Vector3(8, 0, 0)) < 1.0, "through their own (nearest) door")
	await physics_frame
	check(walker._col.disabled, "and leaves no invisible body in the doorway")
	run(smith, 2.0)
	check(smith.visible and smith.routine == "", "the smith keeps his post")

	Villager.hour = 7.0
	run(walker, 2.0)
	check(walker.visible and not walker.hiding and walker.routine == "", "after dawn they come back out")

	# Find a tavern-goer and send them at dusk.
	var goer: Villager = null
	for s in range(3, 40):
		var v := make("wander", "villager", s)
		if v._likes.tavern:
			goer = v
			break
	goer._shift = 0.0
	Villager.hour = 19.0
	run(goer, 25.0)
	check(goer.routine == "tavern" and goer.global_position.distance_to(Vector3(0, 0, 25)) < 4.0, "in the evening a tavern-goer is at the tavern (%.1f m)" % goer.global_position.distance_to(Vector3(0, 0, 25)))
	check(goer.mode == "visit" and not goer.walking, "and stays there")
	goer.marker.visible = true   # someone with a job for you never leaves
	Villager.hour = 23.0
	run(goer, 3.0)
	check(goer.routine == "" and goer.visible, "a villager with a mission for you stays out")
	print("RESULT: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(fails)
