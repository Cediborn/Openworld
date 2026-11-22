extends SceneTree
## Headless checks for the baked world data. Run:
##   godot --headless --path game -s res://tests/unit/world/world_data_test.gd
## Exits with code 1 if any check fails.

var failures := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("PASS  ", what)
	else:
		failures += 1
		print("FAIL  ", what)


func _init() -> void:
	var d := WorldData.new()
	check(d.load_data(), "baked world data loads (data/*.bin)")

	# Zone weights always sum to 1.
	var worst := 0.0
	for p in [Vector2(0, 0), Vector2(0, -350), Vector2(350, 0), Vector2(0, 350), Vector2(-300, 0), Vector2(170, -170)]:
		var w := WorldData.biome_weights(p.x, p.y)
		var sum := 0.0
		for v in w:
			sum += v
		worst = maxf(worst, absf(sum - 1.0))
	check(worst < 0.001, "zone weights sum to 1 (worst error %.5f)" % worst)

	# Each zone is where the design says it is.
	check(d.dominant_zone(0, 0) == 0, "centre is Hub Meadow")
	check(d.dominant_zone(0, -350) == 1, "north is Frost Peaks")
	check(d.dominant_zone(350, 0) == 2, "east is Ember Wastes")
	check(d.dominant_zone(0, 350) == 3, "south is Glow Hollow")
	check(d.dominant_zone(-300, 0) == 4, "west is Brickton")

	# The spawn point is on dry, walkable ground.
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/game_config.json"))
	var s: Array = cfg.spawn
	check(d.zone(s[0], s[2])[2] < 0.1 or d.height(s[0], s[2]) > WorldData.LAVA_LEVEL + 1.0, "spawn is not in lava")
	check(d.normal(s[0], s[2]).y > 0.85, "spawn ground is not steep")

	# Trails lead into every zone and stay walkable (no slope above ~45 degrees).
	var steep := 0
	for e in [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
		for k in range(10, 300, 5):
			var p: Vector2 = e * k
			if d.on_path(p.x, p.y) > 0.5 and d.normal(p.x, p.y).y < 0.7:
				steep += 1
	check(steep < 6, "trails are walkable (%d steep samples)" % steep)

	check(d.houses.size() >= 10, "village has houses (%d)" % d.houses.size())
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
