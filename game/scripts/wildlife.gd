class_name Wildlife
extends Node3D
## Spawns the green-valley animals listed in data/creatures.json and keeps
## only the ones near the player awake, so phones don't animate the whole island.

var data: WorldData
var player: Node3D
var mobile := false
var active_distance := 140.0
var max_active := 999
var animals: Array[Creature] = []
var _check := 0.0


## Reads the spawn list and places every herd on meadow ground.
func setup(world_data: WorldData, p: Node3D, is_mobile: bool) -> void:
	data = world_data
	player = p
	mobile = is_mobile
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/creatures.json"))
	active_distance = cfg.get("active_distance", 140.0)
	if mobile:
		max_active = int(cfg.get("max_active_mobile", 10))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for sp: Dictionary in cfg.spawns:
		var species: Dictionary = cfg.species[sp.species]
		var center := Vector3(sp.center[0], 0, sp.center[1])
		for i in int(sp.count):
			var pos := Vector3.INF
			for attempt in 12:
				var a := rng.randf() * TAU
				var r := sqrt(rng.randf()) * float(sp.radius)
				var q := center + Vector3(cos(a) * r, 0, sin(a) * r)
				if data.dominant_zone(q.x, q.z) == 0 and data.on_path(q.x, q.z) < 0.5:
					pos = q
					break
			if pos == Vector3.INF:
				continue
			var c := Creature.new()
			add_child(c)
			c.setup(species, rng.randi())
			c.home = center
			c.threat = player
			c.height_at = func(x: float, z: float) -> float: return data.height(x, z)
			c.global_position = Vector3(pos.x, data.height(pos.x, pos.z), pos.z)
			c.rotation.y = rng.randf() * TAU
			animals.append(c)


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0 or player == null:
		return
	_check = 0.5
	var p := player.global_position
	var near: Array = []
	for c in animals:
		near.append([c.global_position.distance_squared_to(p), c])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for i in near.size():
		var c: Creature = near[i][1]
		var awake: bool = i < max_active and near[i][0] < active_distance * active_distance
		c.visible = awake
		c.process_mode = Node.PROCESS_MODE_INHERIT if awake else Node.PROCESS_MODE_DISABLED
