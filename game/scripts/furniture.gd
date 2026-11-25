class_name Furniture
extends RefCounted
## Furniture and fittings for interiors, built from simple shapes with the
## project's materials. Positions are on the floor (y = 0) in the parent's
## space; yaw turns the piece (0 = its front faces +z). Solid pieces block.

static func _iron() -> Material:
	return Structures.plain(Color(0.16, 0.15, 0.14), 0.45, 0.8)


static func _xf(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = yaw
	parent.add_child(n)
	return n


static func bed(parent: Node3D, pos: Vector3, yaw: float, quilt: Color, wood: Material, scale := 1.0) -> Node3D:
	var n := _xf(parent, pos, yaw)
	var w := 1.3 * scale
	Structures.box(n, Vector3(w, 0.35, 2.1), Vector3(0, 0.25, 0), wood, Vector3.ZERO, true)
	Structures.box(n, Vector3(w - 0.1, 0.18, 2.0), Vector3(0, 0.5, 0), Structures.plain(Color(0.85, 0.8, 0.7), 0.95))
	Structures.box(n, Vector3(w - 0.05, 0.08, 1.45), Vector3(0, 0.62, 0.28), Structures.plain(quilt, 0.95))
	Structures.box(n, Vector3(w * 0.7, 0.14, 0.4), Vector3(0, 0.65, -0.75), Structures.plain(Color(0.92, 0.9, 0.85), 0.95))
	Structures.box(n, Vector3(w + 0.1, 1.0, 0.1), Vector3(0, 0.55, -1.05), wood)
	return n


static func chair(parent: Node3D, pos: Vector3, yaw: float, wood: Material, back_h := 0.55) -> void:
	var n := _xf(parent, pos, yaw)
	Structures.box(n, Vector3(0.45, 0.06, 0.45), Vector3(0, 0.46, 0), wood)
	for sx in [-0.19, 0.19]:
		for sz in [-0.19, 0.19]:
			Structures.box(n, Vector3(0.05, 0.46, 0.05), Vector3(sx, 0.23, sz), wood)
	Structures.box(n, Vector3(0.45, back_h, 0.05), Vector3(0, 0.49 + back_h * 0.5, -0.2), wood)


## A table with `seats` chairs (or benches); scale lengthens it.
static func table(parent: Node3D, pos: Vector3, yaw: float, wood: Material, seats := 4, benches := false, scale := 1.0) -> void:
	var n := _xf(parent, pos, yaw)
	var lx := 1.6 * scale
	Structures.box(n, Vector3(lx, 0.08, 0.9), Vector3(0, 0.76, 0), wood, Vector3.ZERO, true)
	for sx in [-1, 1]:
		Structures.box(n, Vector3(0.1, 0.72, 0.7), Vector3(sx * (lx * 0.5 - 0.15), 0.36, 0), wood)
	# A candle and a jug or plates.
	Structures.cyl(n, 0.03, 0.03, 0.15, Vector3(0.1, 0.87, 0), Structures.plain(Color(0.95, 0.92, 0.8)))
	Structures.cyl(n, 0.07, 0.09, 0.22, Vector3(-0.35, 0.91, 0.1), Structures.plain(Color(0.6, 0.45, 0.32), 0.6))
	if benches:
		for sz in [-1, 1]:
			Structures.box(n, Vector3(lx, 0.07, 0.3), Vector3(0, 0.45, sz * 0.7), wood)
			for sx in [-1, 1]:
				Structures.box(n, Vector3(0.08, 0.42, 0.25), Vector3(sx * (lx * 0.5 - 0.15), 0.21, sz * 0.7), wood)
		return
	var per_side := ceili(seats / 2.0)
	for k in seats:
		var side := 1 if k % 2 == 0 else -1
		var slot := k / 2
		var x := (slot - (per_side - 1) * 0.5) * (lx / maxf(per_side, 1))
		chair(n, Vector3(x, 0, side * 0.75), 0.0 if side < 0 else PI, wood)


## Stone hearth with a log fire, its light and crackle.
static func fireplace(parent: Node3D, pos: Vector3, yaw: float, village: Village) -> void:
	var n := _xf(parent, pos, yaw)
	var stone := village._tex_mat("castle_brick_07", Color(0.7, 0.68, 0.65), 0.8)
	Structures.box(n, Vector3(1.8, 1.4, 0.7), Vector3(0, 0.7, 0), stone, Vector3.ZERO, true)
	Structures.box(n, Vector3(1.0, 0.8, 0.5), Vector3(0, 0.45, 0.12), Structures.plain(Color(0.05, 0.04, 0.04), 1.0))
	Structures.box(n, Vector3(2.0, 0.12, 0.85), Vector3(0, 1.45, 0.05), village._tex_mat("weathered_brown_planks", Color(0.4, 0.28, 0.2), 0.8))
	Structures.box(n, Vector3(1.0, 1.6, 0.5), Vector3(0, 2.3, -0.05), stone)
	fire(n, Vector3(0, 0.12, 0.25), 0.8)


## Burning logs: flame meshes, a flickering light and rising sparks.
static func fire(parent: Node3D, pos: Vector3, size := 1.0) -> OmniLight3D:
	for k in 3:
		Structures.cyl(parent, 0.06 * size, 0.06 * size, 0.6 * size, pos + Vector3(0, 0.05, 0), Structures.plain(Color(0.25, 0.16, 0.1)), Vector3(PI * 0.5, k * 1.05, 0))
	var flame := Structures.glow_mat(Color(1.0, 0.5, 0.15), 4.0)
	for k in 3:
		var f := Structures.cyl(parent, 0.0, 0.12 * size, (0.35 + k * 0.08) * size, pos + Vector3((k - 1) * 0.1 * size, 0.25 * size, 0), flame, Vector3.ZERO, false, 6)
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := Structures.flame_light(parent, pos + Vector3(0, 0.5, 0.2), Color(1.0, 0.55, 0.22), 1.6 * size, 6.0 * size)
	var sparks := CPUParticles3D.new()
	sparks.amount = 12
	sparks.lifetime = 1.4
	sparks.position = pos + Vector3(0, 0.2, 0)
	sparks.direction = Vector3.UP
	sparks.spread = 18.0
	sparks.initial_velocity_min = 0.4
	sparks.initial_velocity_max = 0.9
	sparks.gravity = Vector3(0, 0.3, 0)
	sparks.scale_amount_min = 0.02
	sparks.scale_amount_max = 0.04
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 4
	sm.rings = 2
	sm.material = Structures.glow_mat(Color(1.0, 0.6, 0.2), 6.0)
	sparks.mesh = sm
	parent.add_child(sparks)
	return l


static func chest(parent: Node3D, pos: Vector3, yaw: float, wood: Material) -> void:
	var n := _xf(parent, pos, yaw)
	Structures.box(n, Vector3(1.0, 0.5, 0.55), Vector3(0, 0.25, 0), wood, Vector3.ZERO, true)
	Structures.box(n, Vector3(1.02, 0.12, 0.57), Vector3(0, 0.56, 0), wood)
	for x in [-0.35, 0.35]:
		Structures.box(n, Vector3(0.06, 0.64, 0.59), Vector3(x, 0.31, 0), _iron())


## Shelves against a wall, stocked with jars, pots, bottles, books, cloth or goods.
static func shelf(parent: Node3D, pos: Vector3, yaw: float, wood: Material, rng: RandomNumberGenerator, stock := "jars") -> void:
	var n := _xf(parent, pos, yaw)
	Structures.box(n, Vector3(1.6, 2.0, 0.08), Vector3(0, 1.0, -0.18), wood, Vector3.ZERO, true)
	for sx in [-0.78, 0.78]:
		Structures.box(n, Vector3(0.06, 2.0, 0.4), Vector3(sx, 1.0, 0), wood)
	for k in 4:
		var y := 0.15 + k * 0.5
		Structures.box(n, Vector3(1.56, 0.05, 0.38), Vector3(0, y, 0), wood)
		var x := -0.65
		while x < 0.65:
			var c := Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.7), rng.randf_range(0.35, 0.8))
			match stock:
				"books":
					var bw := rng.randf_range(0.04, 0.08)
					Structures.box(n, Vector3(bw, rng.randf_range(0.22, 0.34), 0.25), Vector3(x, y + 0.16, 0), Structures.plain(c, 0.8))
					x += bw + 0.01
				"bottles":
					Structures.cyl(n, 0.025, 0.045, 0.28, Vector3(x, y + 0.16, 0), Structures.plain(Color(c.r * 0.4, c.g * 0.6, c.b * 0.4), 0.15))
					x += 0.12
				"cloth":
					Structures.box(n, Vector3(0.3, 0.14, 0.3), Vector3(x + 0.12, y + 0.1, 0), Structures.plain(c, 0.95))
					x += 0.34
				"goods":
					if rng.randf() < 0.5:
						Structures.box(n, Vector3(0.22, 0.18, 0.22), Vector3(x + 0.1, y + 0.12, 0), Structures.plain(c.darkened(0.3), 0.8))
					else:
						Structures.sphere(n, 0.08, Vector3(x + 0.1, y + 0.11, 0), Structures.plain(c, 0.7))
					x += 0.28
				_:
					Structures.cyl(n, 0.07, 0.08, rng.randf_range(0.16, 0.26), Vector3(x + 0.08, y + 0.13, 0), Structures.plain(c.lerp(Color(0.6, 0.45, 0.3), 0.6), 0.6))
					x += 0.22


static func rug(parent: Node3D, pos: Vector3, size: Vector2, c: Color) -> void:
	Structures.box(parent, Vector3(size.x, 0.015, size.y), pos + Vector3(0, 0.05, 0), Structures.plain(c, 1.0))
	Structures.box(parent, Vector3(size.x * 0.8, 0.017, size.y * 0.7), pos + Vector3(0, 0.051, 0), Structures.plain(c.darkened(0.3), 1.0))


## The tavern bar: a long counter with a brass rail, cups and a pump.
static func bar(parent: Node3D, pos: Vector3, yaw: float, length: float, wood: Material) -> void:
	var n := _xf(parent, pos, yaw)
	Structures.box(n, Vector3(length, 1.05, 0.6), Vector3(0, 0.52, 0), wood, Vector3.ZERO, true)
	Structures.box(n, Vector3(length + 0.1, 0.07, 0.75), Vector3(0, 1.08, 0), wood)
	Structures.cyl(n, 0.025, 0.025, length, Vector3(0, 0.2, 0.36), Structures.plain(Color(0.75, 0.55, 0.25), 0.3, 0.9), Vector3(0, 0, PI * 0.5))
	for k in 4:
		Structures.cyl(n, 0.045, 0.04, 0.14, Vector3(-length * 0.4 + k * 0.5, 1.19, 0.05), Structures.plain(Color(0.55, 0.4, 0.25), 0.5))


static func keg(parent: Node3D, pos: Vector3) -> void:
	var k := Structures.cyl(parent, 0.32, 0.32, 0.75, pos + Vector3(0, 0.45, 0), Structures.wood(Color(0.5, 0.35, 0.22)), Vector3(PI * 0.5, 0, 0), true)
	k.name = "Keg"
	Structures.box(parent, Vector3(0.7, 0.1, 0.5), pos + Vector3(0, 0.05, 0), Structures.wood(Color(0.35, 0.25, 0.18)))


## A shop counter with a ledger and scales.
static func counter(parent: Node3D, pos: Vector3, yaw: float, length: float, wood: Material) -> void:
	var n := _xf(parent, pos, yaw)
	Structures.box(n, Vector3(length, 1.0, 0.7), Vector3(0, 0.5, 0), wood, Vector3.ZERO, true)
	Structures.box(n, Vector3(0.4, 0.04, 0.3), Vector3(-length * 0.3, 1.02, 0), Structures.plain(Color(0.85, 0.8, 0.65)))
	Structures.cyl(n, 0.12, 0.12, 0.02, Vector3(length * 0.25, 1.15, 0), Structures.plain(Color(0.7, 0.52, 0.22), 0.3, 0.9))
	Structures.cyl(n, 0.015, 0.015, 0.3, Vector3(length * 0.25, 1.15, 0), _iron())


static func forge(parent: Node3D, pos: Vector3, village: Village) -> void:
	var stone := village._tex_mat("castle_brick_07", Color(0.55, 0.5, 0.48), 0.8)
	Structures.box(parent, Vector3(1.8, 0.9, 1.2), pos + Vector3(0, 0.45, 0), stone, Vector3.ZERO, true)
	Structures.box(parent, Vector3(1.2, 0.08, 0.8), pos + Vector3(0, 0.92, 0), Structures.glow_mat(Color(1.0, 0.35, 0.05), 3.0))
	Structures.cyl(parent, 0.45, 0.7, 1.6, pos + Vector3(0, 2.0, -0.2), stone)
	fire(parent, pos + Vector3(0, 0.9, 0), 0.7)


static func anvil(parent: Node3D, pos: Vector3) -> void:
	Structures.cyl(parent, 0.28, 0.32, 0.55, pos + Vector3(0, 0.28, 0), Structures.wood(Color(0.4, 0.3, 0.2)), Vector3.ZERO, true)
	Structures.box(parent, Vector3(0.7, 0.25, 0.28), pos + Vector3(0, 0.68, 0), _iron())
	Structures.prism(parent, Vector3(0.28, 0.3, 0.2), pos + Vector3(0.48, 0.7, 0), _iron(), Vector3(0, 0, -PI * 0.5))
	Structures.box(parent, Vector3(0.05, 0.05, 0.35), pos + Vector3(-0.1, 0.83, 0.1), _iron())


static func workbench(parent: Node3D, pos: Vector3, yaw: float, wood: Material) -> void:
	var n := _xf(parent, pos, yaw)
	Structures.box(n, Vector3(2.0, 0.1, 0.8), Vector3(0, 0.85, 0), wood, Vector3.ZERO, true)
	for sx in [-0.9, 0.9]:
		Structures.box(n, Vector3(0.1, 0.85, 0.7), Vector3(sx, 0.42, 0), wood)
	Structures.box(n, Vector3(0.5, 0.06, 0.12), Vector3(-0.4, 0.93, 0.1), _iron())
	Structures.cyl(n, 0.04, 0.04, 0.35, Vector3(0.4, 0.93, 0), Structures.wood(Color(0.6, 0.45, 0.3)), Vector3(0, 0, PI * 0.5))


## Hammers, tongs and saws hung on pegs.
static func tool_rack(parent: Node3D, pos: Vector3) -> void:
	Structures.box(parent, Vector3(1.6, 0.1, 0.05), pos, Structures.wood(Color(0.4, 0.3, 0.2)))
	for k in 5:
		var x := -0.6 + k * 0.3
		Structures.box(parent, Vector3(0.04, 0.5, 0.04), pos + Vector3(x, -0.3, 0.05), Structures.wood(Color(0.55, 0.42, 0.3)))
		Structures.box(parent, Vector3(0.14 if k % 2 == 0 else 0.06, 0.08, 0.06), pos + Vector3(x, -0.58, 0.05), _iron())


static func hide_rack(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var n := _xf(parent, pos, yaw)
	for sx in [-0.8, 0.8]:
		Structures.box(n, Vector3(0.08, 1.9, 0.08), Vector3(sx, 0.95, 0), Structures.wood())
	Structures.box(n, Vector3(1.7, 0.08, 0.08), Vector3(0, 1.85, 0), Structures.wood())
	Structures.box(n, Vector3(1.2, 1.3, 0.03), Vector3(0, 1.1, 0), Structures.plain(Color(0.6, 0.45, 0.32), 0.9), Vector3.ZERO, true)


static func vat(parent: Node3D, pos: Vector3) -> void:
	Structures.cyl(parent, 0.6, 0.55, 0.8, pos + Vector3(0, 0.4, 0), Structures.wood(Color(0.45, 0.32, 0.22)), Vector3.ZERO, true)
	Structures.cyl(parent, 0.55, 0.55, 0.02, pos + Vector3(0, 0.75, 0), Structures.plain(Color(0.3, 0.22, 0.12), 0.2))


static func banner(parent: Node3D, pos: Vector3, c: Color) -> void:
	Structures.box(parent, Vector3(0.9, 1.4, 0.03), pos, Structures.plain(c, 0.95))
	Structures.prism(parent, Vector3(0.9, 0.3, 0.03), pos + Vector3(0, -0.85, 0), Structures.plain(c, 0.95), Vector3(0, 0, PI))
	Structures.cyl(parent, 0.025, 0.025, 1.1, pos + Vector3(0, 0.72, 0.02), Structures.wood(), Vector3(0, 0, PI * 0.5))


## A church pew: seat, back and ends.
static func pew(parent: Node3D, pos: Vector3, yaw: float, length: float, wood: Material) -> void:
	var n := _xf(parent, pos, yaw)
	Structures.box(n, Vector3(length, 0.07, 0.42), Vector3(0, 0.45, 0), wood, Vector3.ZERO, true)
	Structures.box(n, Vector3(length, 0.6, 0.06), Vector3(0, 0.78, -0.2), wood)
	for sx in [-1, 1]:
		Structures.box(n, Vector3(0.07, 0.95, 0.5), Vector3(sx * length * 0.5, 0.47, 0), wood)


## A tall iron candle stand with lit candles (emissive; light comes from the room).
static func candles(parent: Node3D, pos: Vector3, n := 3) -> void:
	Structures.cyl(parent, 0.02, 0.18, 1.2, pos + Vector3(0, 0.6, 0), _iron())
	var wax := Structures.plain(Color(0.95, 0.92, 0.82), 0.6)
	var flame := Structures.glow_mat(Color(1.0, 0.75, 0.35), 5.0)
	for k in n:
		var o := Vector3(cos(k * TAU / n), 0, sin(k * TAU / n)) * (0.12 if n > 1 else 0.0)
		Structures.cyl(parent, 0.025, 0.025, 0.22, pos + o + Vector3(0, 1.32, 0), wax)
		var f := Structures.sphere(parent, 0.025, pos + o + Vector3(0, 1.47, 0), flame, Vector3(1, 1.8, 1))
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A ring chandelier of candles hanging on a chain.
static func chandelier(parent: Node3D, pos: Vector3, r := 0.8) -> void:
	Structures.cyl(parent, 0.015, 0.015, 3.0, pos + Vector3(0, 1.5, 0), _iron())
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.04
	tm.outer_radius = r
	ring.mesh = tm
	ring.material_override = _iron()
	ring.position = pos
	parent.add_child(ring)
	var flame := Structures.glow_mat(Color(1.0, 0.75, 0.35), 5.0)
	for k in 8:
		var o := Vector3(cos(k * TAU / 8), 0, sin(k * TAU / 8)) * r
		Structures.cyl(parent, 0.025, 0.025, 0.18, pos + o + Vector3(0, 0.1, 0), Structures.plain(Color(0.95, 0.92, 0.82), 0.6))
		Structures.sphere(parent, 0.025, pos + o + Vector3(0, 0.23, 0), flame, Vector3(1, 1.8, 1))
