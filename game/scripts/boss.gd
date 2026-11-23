class_name Boss
extends Creature
## A named, much stronger creature: a big variant of an island species with
## crystal growths, its own move set and phases. Built from data/bosses.json.
##
## Extra moves on top of the normal ones:
##   volley  - hurls glowing shards that land where warning circles show
##   quake   - slams the ground; a ring around the boss hurts (centre "self")
##   burrow  - sinks out of sight, tunnels under the explorer, bursts out
##   summon  - calls minions (cfg.summon = [species, count])
##   charge  - a long rush with a warning line on the ground
## Phases (cfg.phases): at a health fraction the boss roars and gets faster,
## learns new moves and may call help.

signal phase_changed(index: int)

var boss_id := ""
var title := ""
var phase_i := 0
var spawn_minion: Callable      # (species, pos) -> Creature
var engaged := false
var burrowed := false
var line_tele: MeshInstance3D
var max_health := 1.0


func setup_boss(id: String, def: Dictionary, base_species: Dictionary, seed_value: int) -> void:
	boss_id = id
	title = def.name
	var c: Dictionary = base_species.duplicate(true)
	for k in def:
		if k in ["name", "base", "crystals", "phases", "reward", "intro", "outro", "pos", "tint"]:
			continue
		c[k] = def[k]
	c["phases"] = def.get("phases", [])
	c["temper"] = "threaten"
	c["respawn_time"] = 1.0e9
	setup(c, seed_value)
	unique = true
	max_health = health
	_decorate(def)
	add_to_group("bosses")


## Crystal growths on the back and head so a boss is recognisable at a glance.
func _decorate(def: Dictionary) -> void:
	var cc: Array = def.get("crystals", [0.7, 0.4, 1.0])
	var col := Color(cc[0], cc[1], cc[2])
	var m := Structures.glow_mat(col, 3.0)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = hash(boss_id)
	for b in ["Spine", "Chest", "Head", "Hips"]:
		if not bone.has(b):
			continue
		var ba := BoneAttachment3D.new()
		skeleton.add_child(ba)
		ba.bone_name = b
		var n := 4 if b != "Head" else 3
		for i in n:
			var h := rng2.randf_range(0.25, 0.55) / maxf(size_scale, 0.5) * 1.6
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = h * 0.16
			cm.height = h
			cm.radial_segments = 5
			mi.mesh = cm
			mi.material_override = m
			var a := rng2.randf() * TAU
			mi.position = Vector3(cos(a) * 0.12, 0.08 + h * 0.4, sin(a) * 0.12 + (0.15 if body in ["biped", "float"] else 0.0))
			mi.rotation = Vector3(rng2.randf_range(-0.6, 0.6) + (0.5 if body in ["biped", "float"] else 0.0), rng2.randf() * TAU, rng2.randf_range(-0.5, 0.5))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ba.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 1.5
	l.omni_range = 6.0 * size_scale
	l.position.y = model_size.y * size_scale * 0.6
	add_child(l)
	if def.has("tint"):
		var t: Array = def.tint
		mat.set_shader_parameter("glow_color", Color(t[0], t[1], t[2]))


func fraction() -> float:
	return clampf(health / max_health, 0.0, 1.0)


func take_hit(amount: float, from_pos: Vector3) -> void:
	if burrowed:
		return   # underground: the blade passes over
	# Bosses don't get shoved around.
	var before := global_position
	super.take_hit(amount, from_pos)
	global_position = global_position.lerp(before, 0.8)
	engaged = true
	var phases: Array = cfg.get("phases", [])
	while phase_i < phases.size() and fraction() <= float(phases[phase_i].at) and alive():
		_enter_phase(phases[phase_i])
		phase_i += 1
		phase_changed.emit(phase_i)


func _enter_phase(p: Dictionary) -> void:
	vocal.emit("roar")
	flinch = 1.0
	if p.has("speed"):
		cfg.run_speed = float(cfg.run_speed) * float(p.speed)
		cfg.attack_rate = float(cfg.get("attack_rate", 2.0)) / float(p.speed)
	if p.has("add"):
		var list: Array = cfg.get("attacks", []).duplicate(true)
		for m in p.add:
			list.append(m)
		cfg.attacks = list
	if p.has("summon") and spawn_minion.is_valid():
		for i in int(p.summon[1]):
			var a := TAU * i / float(p.summon[1])
			spawn_minion.call(p.summon[0], global_position + Vector3(cos(a), 0, sin(a)) * (4.0 + size_scale))
	# Interrupt whatever it was doing and roar.
	atk = {}
	atk_off.clear()
	_show_telegraph(false)
	state = State.ROAR
	timer = 1.4


func _think(delta: float) -> void:
	# Bosses stay on the explorer while he is in their arena.
	if threat and alive() and _threat_distance() < float(cfg.get("arena", 30.0)) and threat.get("dead") != true:
		if state in [State.IDLE, State.GRAZE, State.WALK, State.RETURN]:
			engaged = true
			state = State.CHASE
			timer = 999.0
		elif state == State.CHASE:
			timer = 999.0
	super._think(delta)


func _impact_point() -> Vector3:
	if atk.get("centre", "") == "self":
		return global_position
	if atk.get("name", "") == "burrow" and threat:
		return Vector3(threat.global_position.x, global_position.y, threat.global_position.z)
	return super._impact_point()


func _attack_update(delta: float) -> void:
	var nm: String = atk.get("name", "")
	var w := float(atk.windup)
	if nm == "burrow":
		# Sink during the wind-up, travel under the target, burst up at the impact.
		var sink := clampf(atk_t / w, 0.0, 1.0)
		model.position.y = -model_size.y * size_scale * sink * 1.1
		burrowed = sink > 0.6 and not atk_done
		if sink >= 1.0 and not atk_done and threat:
			var tp := threat.global_position
			global_position = global_position.lerp(Vector3(tp.x, global_position.y, tp.z), clampf(delta * 3.0, 0.0, 1.0))
		if atk_done:
			model.position.y = lerpf(model.position.y, 0.0, clampf(delta * 8.0, 0.0, 1.0))
	if nm == "charge" and atk_t < w:
		_show_line(true)
	super._attack_update(delta)
	if atk.is_empty():
		model.position.y = 0.0
		burrowed = false
		_show_line(false)


func _resolve_impact() -> void:
	var nm: String = atk.get("name", "")
	_show_line(false)
	if nm == "volley":
		_volley()
		attack_landed.emit(false, nm)
		return
	if nm == "summon":
		var sm: Array = cfg.get("summon", ["fire_salamander", 2])
		if spawn_minion.is_valid():
			for i in int(sm[1]):
				var a := rng.randf() * TAU
				spawn_minion.call(sm[0], global_position + Vector3(cos(a), 0, sin(a)) * 4.0)
		attack_landed.emit(false, nm)
		return
	super._resolve_impact()


## Throws shards at (and around) the explorer; each lands on its warning circle.
func _volley() -> void:
	if threat == null:
		return
	var n := int(atk.get("count", 5))
	for i in n:
		var target := threat.global_position + (Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4)) if i > 0 else Vector3.ZERO)
		target.y = height_at.call(target.x, target.z)
		var p := Shard.new()
		p.from = global_position + Vector3.UP * model_size.y * size_scale * 0.8
		p.to = target
		p.delay = i * 0.12
		p.radius = float(atk.get("aoe", 1.8))
		p.damage = float(cfg.get("damage", 10.0)) * float(atk.get("damage", 0.6))
		p.threat = threat
		p.color = mat.get_shader_parameter("glow_color")
		p.element = cfg.get("element", "")
		get_parent().add_child(p)


func _show_line(on: bool) -> void:
	if on and line_tele == null:
		line_tele = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(1.0, 1.0)
		line_tele.mesh = pm
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/spatial_fx_telegraph.gdshader")
		m.set_shader_parameter("fill", 1.0)
		line_tele.material_override = m
		line_tele.top_level = true
		line_tele.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(line_tele)
	if line_tele:
		line_tele.visible = on
		if on:
			var length := float(atk.get("lunge", 6.0)) * size_scale + 2.0
			line_tele.global_position = global_position + atk_dir * length * 0.5 + Vector3.UP * 0.08
			line_tele.global_position.y = height_at.call(line_tele.global_position.x, line_tele.global_position.z) + 0.08
			line_tele.global_transform.basis = Basis(Vector3.UP, atan2(atk_dir.x, atk_dir.z)).scaled(Vector3(1.6 * size_scale, 1, length))
			(line_tele.material_override as ShaderMaterial).set_shader_parameter("fill", clampf(atk_t / float(atk.windup), 0.0, 1.0))


## A glowing shard thrown by a boss: arcs to its target, which is marked on
## the ground while it flies, and hurts whoever is still standing there.
class Shard extends Node3D:
	var from := Vector3.ZERO
	var to := Vector3.ZERO
	var delay := 0.0
	var flight := 1.1
	var radius := 1.8
	var damage := 10.0
	var element := ""
	var threat: Node3D
	var color := Color(0.8, 0.4, 1.0)
	var t := 0.0
	var orb: MeshInstance3D
	var ring: MeshInstance3D

	func _ready() -> void:
		top_level = true
		orb = MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.28
		s.height = 0.56
		orb.mesh = s
		orb.material_override = Structures.glow_mat(color, 4.0)
		orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(orb)
		ring = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2.ONE * 2.0 * radius
		ring.mesh = pm
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/spatial_fx_telegraph.gdshader")
		m.set_shader_parameter("color", color)
		ring.material_override = m
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		ring.global_position = to + Vector3.UP * 0.07
		orb.global_position = from

	func _process(delta: float) -> void:
		t += delta
		var f := clampf((t - delay) / flight, 0.0, 1.0)
		var p := from.lerp(to, f)
		p.y += sin(f * PI) * 5.0
		orb.global_position = p
		(ring.material_override as ShaderMaterial).set_shader_parameter("fill", f)
		if f >= 1.0:
			if threat and threat.has_method("take_damage") and Vector2(threat.global_position.x - to.x, threat.global_position.z - to.z).length() < radius:
				threat.take_damage(damage, to, false, element)
			queue_free()
