extends SceneTree
## Combat test (run: godot --headless --path game -s res://tests/integration/combat_test.gd).
## Every hostile species chases and hits a target with a real attack move;
## damage only lands at the impact moment of an attack, never while idle,
## and a target that steps out of the way during the wind-up is missed.

class Dummy extends Node3D:
	var dead := false
	var taken := 0.0
	var hits := 0
	func take_damage(amount: float, _from: Vector3, _burn := false, _element := "") -> void:
		taken += amount
		hits += 1

var fails := 0

func check(ok: bool, msg: String) -> void:
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok:
		fails += 1


func make(cfg: Dictionary, sp: String, seed_value: int, target: Node3D) -> Creature:
	var c := Creature.new()
	root.add_child(c)
	var sc: Dictionary = cfg.species[sp].duplicate()
	sc.erase("min_height")   # the test ground is flat at 0 m, below lava-zone limits
	c.setup(sc, seed_value)
	c.threat = target
	return c


func _init() -> void:
	await process_frame
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/creatures.json"))
	var dt := 1.0 / 60.0

	# 1. Every hostile species attacks with recognisable moves and connects.
	for sp in ["ice_troll", "lava_golem", "frost_spirit", "fire_salamander", "mushroom_beetle", "wolf", "boar"]:
		var dummy := Dummy.new()
		root.add_child(dummy)
		dummy.position = Vector3(0, 0, -7)
		var c := make(cfg, sp, 1, dummy)
		if cfg.species[sp].get("temper") == "flee":
			c.take_hit(1.0, dummy.position)   # provoke animals that fight back
		var moves_seen := {}
		var idle_damage := false
		var prev := 0.0
		for i in 900:
			c._process(dt)
			if c.state == Creature.State.ATTACK:
				moves_seen[c.atk.get("name", "")] = true
			if dummy.taken > prev and c.state != Creature.State.ATTACK:
				idle_damage = true
			prev = dummy.taken
		check(dummy.hits > 0, "%s hit a target standing in front of it (%d hits)" % [sp, dummy.hits])
		check(not idle_damage, "%s only deals damage during an attack" % sp)
		check(moves_seen.size() >= 1, "%s used attack moves %s" % [sp, moves_seen.keys()])
		c.queue_free()
		dummy.queue_free()
		await process_frame

	# 2. A troll's blow misses a target that steps aside during the wind-up.
	var dummy2 := Dummy.new()
	root.add_child(dummy2)
	dummy2.position = Vector3(0, 0, -2.0)
	var troll := make(cfg, "ice_troll", 5, dummy2)
	troll.state = Creature.State.CHASE
	troll.timer = 10.0
	troll.attack_cd = 0.0
	var dodged := false
	for i in 240:
		troll._process(dt)
		if troll.state == Creature.State.ATTACK and troll.atk_t > float(troll.atk.windup) * 0.8 and not dodged:
			dummy2.position += troll.global_transform.basis.x * 4.0   # sidestep
			dodged = true
		if troll.atk_done:
			break
	check(dodged and dummy2.hits == 0, "a sidestepped troll attack misses (hits %d)" % dummy2.hits)

	# 3. Sword damage and death.
	var hp: float = troll.health
	troll.take_hit(34.0, dummy2.position)
	check(troll.health < hp, "sword hit lowers troll health")
	for i in 10:
		troll.take_hit(34.0, dummy2.position)
	check(not troll.alive(), "troll dies at zero health")
	var deer := make(cfg, "deer", 2, dummy2)
	deer.global_position = dummy2.position + Vector3(5, 0, 0)
	deer.take_hit(10.0, dummy2.position)
	check(deer.state == Creature.State.FLEE, "a hit deer runs away")
	var boar := make(cfg, "boar", 3, dummy2)
	boar.take_hit(10.0, dummy2.position)
	check(boar.state == Creature.State.CHASE, "a hit boar fights back")
	print("RESULT: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(fails)
