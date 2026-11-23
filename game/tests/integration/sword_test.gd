extends SceneTree
## Sword test (run: godot --headless --path game -s res://tests/integration/sword_test.gd).
## The explorer's swings visibly move the blade through an arc, damage lands
## only when the blade's path crosses the creature (not at the button press),
## a creature behind him is not hit, the three-swing combo chains, and the
## dodge roll makes him briefly invulnerable.

var fails := 0

func check(ok: bool, msg: String) -> void:
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok:
		fails += 1


func _init() -> void:
	await process_frame
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/game_config.json"))
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/creatures.json"))
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	col.shape = box
	col.position.y = -0.5
	floor_body.add_child(col)
	root.add_child(floor_body)

	var player := Player.new()
	player.setup(config)
	root.add_child(player)
	player.position = Vector3(0, 0.05, 0)
	player.yaw = PI           # camera looks along +Z
	player.body.rotation.y = 0.0
	for i in 20:
		await physics_frame

	var troll_cfg: Dictionary = cfg.species.ice_troll.duplicate()
	troll_cfg.aggro_radius = 0.0   # stand still for the test
	var front := Creature.new()
	root.add_child(front)
	front.setup(troll_cfg, 1)
	front.global_position = Vector3(0, 0, 2.1)
	var behind := Creature.new()
	root.add_child(behind)
	behind.setup(troll_cfg, 2)
	behind.global_position = Vector3(0, 0, -2.4)
	for i in 5:
		await physics_frame

	# Blade path during the first swing.
	var hp0: float = front.health
	player.attack_pressed = true
	var tips: Array = []
	var hit_frame := -1
	var frame := 0
	for i in 60:
		await physics_frame
		frame += 1
		tips.append(player.body.blade_segment()[1])
		if hit_frame < 0 and front.health < hp0:
			hit_frame = frame
	var span := 0.0
	for a in tips:
		for b in tips:
			span = maxf(span, (a as Vector3).distance_to(b))
	check(span > 1.0, "the blade tip travels through a wide arc (%.2f m)" % span)
	check(front.health < hp0, "the swing damaged the troll in front (%.0f -> %.0f)" % [hp0, front.health])
	check(hit_frame > 6, "damage landed when the blade reached the troll (frame %d), not on the button press" % hit_frame)
	check(behind.health == behind.cfg.health, "the troll behind the explorer was not hit")

	# Combo: three presses chain into three different swings.
	for i in 40:
		await physics_frame
	var anims := {}
	for n in 6:
		player.attack_pressed = true
		for i in 10:
			await physics_frame
			if player.swing >= 0:
				anims[player.body.current] = true
	for i in 40:
		await physics_frame
	check(anims.size() >= 3, "pressing attack repeatedly chains the combo %s" % [anims.keys()])

	# Dodge roll: invulnerable mid-roll.
	var hp: float = player.health
	player.dodge_pressed = true
	for i in 8:
		await physics_frame
	player.take_damage(20.0, player.global_position + Vector3(1, 0, 0))
	check(player.health == hp, "a hit mid-roll does no damage")
	for i in 60:
		await physics_frame
	# Block: a blocked hit from the front does a quarter of the damage.
	player.block_held = true
	for i in 10:
		await physics_frame
	var fwd := Vector3(sin(player.body.rotation.y), 0, cos(player.body.rotation.y))
	hp = player.health
	player.take_damage(20.0, player.global_position + fwd * 2.0)
	check(absf((hp - player.health) - 20.0 * float(config.combat.get("block_factor", 0.25))) < 0.01, "blocking from the front cuts damage (%.1f taken)" % (hp - player.health))
	player.block_held = false
	print("RESULT: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(fails)
