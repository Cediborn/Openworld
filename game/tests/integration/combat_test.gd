extends SceneTree
## Combat smoke test (run: godot --headless --path game -s res://tests/integration/combat_test.gd).
## Checks a troll chases, hits and hurts a dummy target, takes sword hits and dies.

class Dummy extends Node3D:
	var dead := false
	var taken := 0.0
	func take_damage(amount: float, _from: Vector3, _burn := false) -> void:
		taken += amount

var fails := 0

func check(ok: bool, msg: String) -> void:
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok:
		fails += 1

func _init() -> void:
	await process_frame
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/creatures.json"))
	var troll_cfg: Dictionary = cfg.species.ice_troll
	var dummy := Dummy.new()
	root.add_child(dummy)
	dummy.position = Vector3(0, 0, -8)
	var troll := Creature.new()
	root.add_child(troll)
	troll.setup(troll_cfg, 1)
	troll.threat = dummy
	var closest := INF
	for i in 600:   # 10 s at 60 fps
		troll._process(1.0 / 60.0)
		closest = minf(closest, troll.global_position.distance_to(dummy.position))
	check(closest < 3.0, "troll closed in on the target (%.1f m)" % closest)
	check(dummy.taken > 0.0, "troll hit the target (damage %.0f)" % dummy.taken)
	var hp: float = troll.health
	troll.take_hit(34.0, dummy.position)
	check(troll.health < hp, "sword hit lowers troll health")
	for i in 10:
		troll.take_hit(34.0, dummy.position)
	check(not troll.alive(), "troll dies at zero health")
	var deer := Creature.new()
	root.add_child(deer)
	deer.setup(cfg.species.deer, 2)
	deer.threat = dummy
	deer.global_position = dummy.position + Vector3(5, 0, 0)
	deer.take_hit(10.0, dummy.position)
	check(deer.state == Creature.State.FLEE, "a hit deer runs away")
	var boar := Creature.new()
	root.add_child(boar)
	boar.setup(cfg.species.boar, 3)
	boar.threat = dummy
	boar.take_hit(10.0, dummy.position)
	check(boar.state == Creature.State.CHASE, "a hit boar fights back")
	print("RESULT: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(fails)
