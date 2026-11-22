class_name ZoneEffects
extends Node3D
## Particles around the player that depend on the zone: falling snow in Frost
## Peaks, rising embers in Ember Wastes, drifting glowing spores in Glow Hollow,
## and fireflies in the meadow at night.

var snow: GPUParticles3D
var embers: GPUParticles3D
var spores: GPUParticles3D
var fireflies: GPUParticles3D
var target: Node3D


static func _quad(size: float, color: Color, emission: float) -> Array:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	if emission > 0.0:
		m.albedo_color = color * (1.0 + emission)
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(0.5, 0.0)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	g.gradient = grad
	m.albedo_texture = g
	q.material = m
	return [q, m]


func _make(amount: int, size: float, color: Color, emission: float, box: Vector3, gravity: Vector3, life: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var qm := _quad(size, color, emission)
	p.draw_pass_1 = qm[0]
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.local_coords = false
	p.amount_ratio = 0.0
	p.visibility_aabb = AABB(Vector3(-30, -15, -30), Vector3(60, 30, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.gravity = gravity
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.6
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 4.0
	p.process_material = pm
	add_child(p)
	return p


func setup(follow: Node3D, mobile: bool) -> void:
	target = follow
	var k := 0.4 if mobile else 1.0
	snow = _make(int(900 * k), 0.06, Color(1, 1, 1, 0.9), 0.0, Vector3(20, 8, 20), Vector3(0.3, -1.4, 0), 9.0)
	embers = _make(int(260 * k), 0.05, Color(1.0, 0.45, 0.1), 3.0, Vector3(18, 2, 18), Vector3(0, 0.9, 0), 5.0)
	spores = _make(int(260 * k), 0.07, Color(0.4, 0.85, 1.0), 2.5, Vector3(18, 4, 18), Vector3(0, 0.05, 0), 10.0)
	fireflies = _make(int(80 * k), 0.06, Color(0.9, 1.0, 0.4), 3.0, Vector3(16, 1.5, 16), Vector3(0, 0, 0), 6.0)


func update(zone: Array, night: float) -> void:
	if target == null:
		return
	global_position = target.global_position + Vector3(0, 3, 0)
	snow.amount_ratio = clampf(zone[1] * 1.5 - 0.2, 0.0, 1.0)
	embers.amount_ratio = clampf(zone[2] * 1.4 - 0.2, 0.0, 1.0)
	spores.amount_ratio = clampf(zone[3] * 1.4 - 0.2, 0.0, 1.0)
	fireflies.amount_ratio = clampf(zone[0] * night * 1.5, 0.0, 1.0)
	for p in [snow, embers, spores, fireflies]:
		p.emitting = p.amount_ratio > 0.01
