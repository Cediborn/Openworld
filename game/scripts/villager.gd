class_name Villager
extends Node3D
## A villager: a dressed ExplorerBody that strolls around its home on the
## street, stops and turns to face you when you come to talk, and holds its
## dialogue lines. Defined in data/npcs.json; the Story node runs conversations.

var cfg: Dictionary = {}
var id := ""
var display_name := ""
var body: ExplorerBody
var height_at: Callable = func(_x: float, _z: float) -> float: return 0.0
var player: Node3D
var home := Vector3.ZERO
var target := Vector3.ZERO
var timer := 0.0
var walking := false
var talking := false
var rng := RandomNumberGenerator.new()


## Builds the villager. Colours in cfg.outfit are [r, g, b] arrays.
func setup(villager_cfg: Dictionary, seed_value: int) -> void:
	cfg = villager_cfg
	id = cfg.id
	display_name = cfg.name
	rng.seed = seed_value
	var outfit := {}
	for k in cfg.outfit:
		var v = cfg.outfit[k]
		outfit[k] = Color(v[0], v[1], v[2]) if v is Array and v.size() == 3 and (v[0] is float or v[0] is int) else v
	body = ExplorerBody.new()
	body.outfit = outfit
	body.scale = Vector3.ONE * float(cfg.get("scale", 1.0))
	add_child(body)
	home = Vector3(cfg.home[0], 0, cfg.home[1])
	target = home
	timer = rng.randf_range(1.0, 4.0)
	if cfg.get("anvil", false):
		_add_anvil()
	# A solid body so the player bumps into villagers instead of walking through.
	var blocker := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3 * body.scale.x
	cap.height = 1.7 * body.scale.x
	col.shape = cap
	col.position.y = cap.height * 0.5
	blocker.add_child(col)
	add_child(blocker)


func _add_anvil() -> void:
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.22, 0.22, 0.24)
	iron.metallic = 0.85
	iron.roughness = 0.45
	var anvil := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.7, 0.18, 0.28)
	anvil.mesh = b
	anvil.material_override = iron
	anvil.position = Vector3(0, 0.66, 0.6)
	add_child(anvil)
	var stand := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.22, 0.57, 0.2)
	stand.mesh = sb
	stand.material_override = ExplorerBody._fabric(Color(0.3, 0.2, 0.12))
	stand.position = Vector3(0, 0.285, 0.6)
	add_child(stand)


## Dialogue lines for a quest stage name (intro, hunt, return, forge, done).
func lines_for(stage: String) -> Array:
	var all: Dictionary = cfg.lines
	return all.get(stage, all.get("intro", []))


## Freezes the villager facing the player while talking.
func set_talking(on: bool) -> void:
	talking = on


func _process(delta: float) -> void:
	if body == null:
		return
	if talking and player:
		var to := player.global_position - global_position
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), clampf(delta * 6.0, 0, 1))
		body.play("Idle_Talking", 0.3)
		return
	timer -= delta
	var wander: float = cfg.get("wander", 0.0)
	if walking:
		var to := target - global_position
		to.y = 0
		if to.length() < 0.4:
			walking = false
			timer = rng.randf_range(3.0, 9.0)
		else:
			var speed: float = cfg.get("walk_speed", 1.0)
			global_position += to.normalized() * minf(speed * delta, to.length())
			rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), clampf(delta * 5.0, 0, 1))
			body.play(cfg.get("walk_anim", "Walk"), 0.3, speed / _anim_speed(cfg.get("walk_anim", "Walk")))
	else:
		body.play(cfg.get("idle_anim", "Idle"), 0.3)
		if timer <= 0.0 and wander > 0.2:
			var a := rng.randf() * TAU
			target = home + Vector3(cos(a), 0, sin(a)) * sqrt(rng.randf()) * wander
			walking = true
	global_position.y = height_at.call(global_position.x, global_position.z)


static func _anim_speed(anim_name: String) -> float:
	match anim_name:
		"Jog_Fwd":
			return 3.6
		"Walk_Formal":
			return 1.2
		_:
			return 1.45
