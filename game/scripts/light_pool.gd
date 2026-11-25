class_name LightPool
extends Node3D
## Night light for Brickton's lamp posts and lanterns without a light per
## lamp: a small pool of shared OmniLights (8 on PC, 4 on phones, no shadows)
## is moved every half second to the lanterns nearest the player. Each lamp
## still glows by its emissive glass; the pool adds the warm pool of light on
## the ground around the closest ones. Off in daylight.

var player: Node3D
var spots: Array[Vector3] = []
var pool: Array[OmniLight3D] = []
var energy := 0.0
var _t := 0.0


func setup(p: Node3D, mobile: bool) -> void:
	player = p
	for i in (4 if mobile else 8):
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.72, 0.42)
		l.omni_range = 11.0
		l.omni_attenuation = 1.4
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		pool.append(l)


func add_spot(at: Vector3) -> void:
	spots.append(at)


func set_night(amount: float) -> void:
	energy = smoothstep(0.25, 0.7, amount) * 1.6
	for l in pool:
		l.light_energy = energy


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or player == null:
		return
	_t = 0.5
	if energy < 0.02 or spots.is_empty():
		for l in pool:
			l.visible = false
		return
	var p := player.global_position
	var near := spots.duplicate()
	near.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(p) < b.distance_squared_to(p))
	for i in pool.size():
		var on: bool = i < near.size() and near[i].distance_to(p) < 60.0
		pool[i].visible = on
		if on:
			pool[i].global_position = near[i] + Vector3(0, -0.3, 0)
