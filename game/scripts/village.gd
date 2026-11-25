class_name Village
extends Node3D
## Brickton: timber-framed houses with plaster walls, stone bases and tiled
## roofs, placed from data/village.json. Windows light up at night.
##
## Every house is a real building you can walk into: hollow walls with a door
## opening on the street side, a hinged wooden door, a ramp up to the stone
## threshold, a boarded floor and a ceiling. Interiors (furniture, lights and
## the people inside) are added by Interiors when you come close.

const TEX := "res://assets/vendor/polyhaven/textures/"
const PLASTER_TINTS := [Color(0.95, 0.92, 0.85), Color(0.95, 0.82, 0.45), Color(0.85, 0.5, 0.4), Color(0.7, 0.8, 0.6)]

var window_mat: StandardMaterial3D
var data: WorldData
var mats := {}
## One entry per house: {"root", "h" (village.json entry), "w", "d", "floors",
## "door": Node3D hinge, "door_local": Vector3 (centre of the doorway, floor level)}.
var buildings: Array[Dictionary] = []
const WALL := 0.25          ## wall thickness (m)
const DOOR_W := 1.25        ## doorway width (m)
const DOOR_H := 2.25        ## doorway height (m)
const FLOOR_Y := 0.5        ## floor level above the house origin (top of the stone base)
const GRASS_CLEAR := 0.45   ## floor height above the highest ground under it (grass is ~0.4 m)


func setup(world_data: WorldData) -> void:
	data = world_data
	window_mat = StandardMaterial3D.new()
	window_mat.albedo_color = Color(0.12, 0.13, 0.15)
	window_mat.roughness = 0.1
	window_mat.emission_enabled = true
	window_mat.emission = Color(1.0, 0.7, 0.35)
	window_mat.emission_energy_multiplier = 0.0
	for h in data.houses:
		if not h.get("reserved", false):
			_house(h)


## Builds one more house from the same parts (used for lodges and halls outside the village).
func build_house(h: Dictionary) -> Node3D:
	return _house(h)


func set_night(amount: float) -> void:
	window_mat.emission_energy_multiplier = amount * 3.0
	for l in night_lights:
		l.visible = amount > 0.3
		l.light_energy = 1.4 * amount


var night_lights: Array[Light3D] = []


## Signs, awnings, the town hall's bell tower and workshop sheds.
func _extras(root: Node3D, h: Dictionary, w: float, d: float, top: float, rise: float) -> void:
	var kind: String = h.get("kind", "")
	if kind == "":
		return
	var timber := _tex_mat("weathered_brown_planks", Color(0.55, 0.45, 0.38), 0.8)
	if h.has("name"):
		var board := Structures.box(root, Vector3(2.6, 0.7, 0.08), Vector3(w * 0.25, 3.1, d * 0.5 + 0.45), timber)
		board.name = "Sign"
		var l := Structures.label(root, h.name, Vector3(w * 0.25, 3.1, d * 0.5 + 0.5), 54, Color(1.0, 0.92, 0.75))
		l.double_sided = false
		Structures.box(root, Vector3(0.08, 0.08, 0.5), Vector3(w * 0.25, 3.5, d * 0.5 + 0.25), timber)
	match kind:
		"inn":
			var lan := Structures.box(root, Vector3(0.3, 0.4, 0.3), Vector3(-w * 0.32, 2.6, d * 0.5 + 0.35), window_mat)
			lan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var light := Structures.flame_light(root, Vector3(-w * 0.32, 2.4, d * 0.5 + 1.0), Color(1.0, 0.7, 0.4), 1.4, 12.0)
			night_lights.append(light)
		"shop":
			Structures.box(root, Vector3(w * 0.8, 0.06, 1.8), Vector3(0, 2.75, d * 0.5 + 0.8), Structures.plain(Color(0.7, 0.25, 0.2), 0.9), Vector3(0.25, 0, 0))
			for sx in [-1.0, 1.0]:
				Structures.cyl(root, 0.05, 0.05, 2.6, Vector3(sx * w * 0.38, 1.8, d * 0.5 + 1.6), timber)
		"hall":
			# Bell tower over the roof ridge.
			var tz := -d * 0.1
			Structures.box(root, Vector3(2.4, 3.2, 2.4), Vector3(0, top + rise + 1.4, tz), _tex_mat("plastered_stone_wall", Color(0.9, 0.88, 0.82), 0.35))
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					Structures.box(root, Vector3(0.3, 2.0, 0.3), Vector3(sx * 1.05, top + rise + 4.0, tz + sz * 1.05), timber)
			Structures.cyl(root, 0.55, 0.3, 0.7, Vector3(0, top + rise + 3.9, tz), Structures.plain(Color(0.65, 0.5, 0.25), 0.35, 0.8))
			Structures.prism(root, Vector3(3.0, 2.0, 3.0), Vector3(0, top + rise + 6.0, tz), _tex_mat("clay_roof_tiles_02", Color(0.55, 0.58, 0.62), 0.5))
		"workshop":
			# Open lean-to on the street side with a workbench.
			for sx in [-1.0, 1.0]:
				Structures.cyl(root, 0.08, 0.08, 2.6, Vector3(sx * w * 0.42, 1.8, d * 0.5 + 2.6), timber)
			Structures.box(root, Vector3(w * 0.95, 0.1, 3.0), Vector3(0, 3.15, d * 0.5 + 1.4), _tex_mat("clay_roof_tiles_02", Color(0.8, 0.7, 0.65), 0.5), Vector3(-0.2, 0, 0))
			Structures.box(root, Vector3(2.2, 0.9, 0.8), Vector3(w * 0.2, 0.95, d * 0.5 + 1.2), timber, Vector3.ZERO, true)
			for i in 3:
				Structures.cyl(root, 0.15, 0.15, 2.0, Vector3(-w * 0.3, 0.65 + i * 0.28, d * 0.5 + 1.0), _tex_mat("bark_brown_02", Color(0.7, 0.6, 0.5), 1.0), Vector3(0, 0, PI * 0.5))


func _tex_mat(name: String, tint := Color.WHITE, scale := 0.5) -> StandardMaterial3D:
	var key := name + str(tint)
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.roughness = 0.9
	if ResourceLoader.exists(TEX + name + "/albedo.jpg"):
		m.albedo_texture = load(TEX + name + "/albedo.jpg")
		m.normal_enabled = true
		m.normal_texture = load(TEX + name + "/normal.jpg")
	mats[key] = m
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _house(h: Dictionary) -> Node3D:
	# The floor must clear the highest ground under the house (and the grass on it).
	if data:
		h["y"] = maxf(float(h.get("y", 0.0)), _footprint_top(h) - FLOOR_Y + GRASS_CLEAR)
	var root := Node3D.new()
	root.position = Vector3(h.x, h.get("y", 0.0), h.z)
	root.rotation.y = h.rot
	add_child(root)
	var w: float = h.w
	var d: float = h.d
	var floors: int = h.floors
	var wall_h := 3.0 * floors
	if data:
		data.add_floor(Vector2(h.x, h.z), h.rot, Vector2(w + 0.4, d + 0.4), h.get("y", 0.0) + FLOOR_Y)
	var stone := _tex_mat("castle_brick_07", Color(0.85, 0.85, 0.85), 0.6)
	var plaster := _tex_mat("plastered_stone_wall", PLASTER_TINTS[int(h.style) % 4], 0.35)
	if h.get("white", false):
		# Your house: whitewashed stone walls on a pale grey stone base.
		plaster = _tex_mat("plastered_stone_wall", Color(1.25, 1.24, 1.2), 0.3)
		stone = _tex_mat("rock_face_03", Color(1.15, 1.13, 1.1), 0.5)
	var timber := _tex_mat("weathered_brown_planks", Color(0.55, 0.45, 0.38), 0.8)
	var roof := _tex_mat("clay_roof_tiles_02", Color(0.85, 0.75, 0.7) if int(h.style) % 2 == 0 else Color(0.55, 0.58, 0.62), 0.5)

	_box(root, Vector3(w + 0.4, 2.0, d + 0.4), Vector3(0, -0.5, 0), stone)
	var door_x := -w * 0.15
	_hollow_walls(root, w, d, wall_h, floors, plaster, door_x)
	# Timber frame: corner posts, floor beams and a few braces.
	var t := 0.22
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_box(root, Vector3(t, wall_h, t), Vector3(sx * w * 0.5, 0.5 + wall_h * 0.5, sz * d * 0.5), timber)
	for f in floors + 1:
		var y := 0.5 + f * 3.0
		_box(root, Vector3(w + 0.05, t, t), Vector3(0, y, d * 0.5), timber)
		_box(root, Vector3(w + 0.05, t, t), Vector3(0, y, -d * 0.5), timber)
		_box(root, Vector3(t, t, d + 0.05), Vector3(w * 0.5, y, 0), timber)
		_box(root, Vector3(t, t, d + 0.05), Vector3(-w * 0.5, y, 0), timber)
	for f in floors:
		for sx in [-1, 1]:
			_box(root, Vector3(t, 3.4, t), Vector3(sx * w * 0.3, 0.5 + f * 3.0 + 1.5, d * 0.5 + 0.02), timber, Vector3(0, 0, sx * 0.55))
	# Gable roof.
	var pitch := 0.65
	var half_span := w * 0.5 + 0.6
	var rise := tan(pitch) * half_span
	var slope_len := half_span / cos(pitch)
	var top := 0.5 + wall_h
	for sx in [-1, 1]:
		_box(root, Vector3(slope_len, 0.25, d + 1.2), Vector3(sx * half_span * 0.5, top + rise * 0.5, 0), roof, Vector3(0, 0, -sx * pitch))
	# Gable ends.
	var gable := SurfaceTool.new()
	gable.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sz in [-1, 1]:
		var z: float = sz * d * 0.5
		var tri := [Vector3(-w * 0.5, top, z), Vector3(w * 0.5, top, z), Vector3(0, top + tan(pitch) * w * 0.5, z)]
		if sz < 0:
			tri = [tri[1], tri[0], tri[2]]
		for v in tri:
			gable.add_vertex(v)
	gable.generate_normals()
	var gm := MeshInstance3D.new()
	gm.mesh = gable.commit()
	gm.material_override = plaster
	root.add_child(gm)
	# Chimney.
	_box(root, Vector3(0.7, 2.2, 0.7), Vector3(w * 0.25, top + rise * 0.6 + 0.6, -d * 0.2), stone)
	# Door and windows on the street side (+z).
	var door := _tex_mat("weathered_brown_planks", Color(0.4, 0.28, 0.2), 1.2)
	var hinge := _door(root, door_x, d, door, timber)
	_steps(root, h, door_x, d, stone)
	for f in floors:
		for wx in [-0.35, 0.2, 0.38]:
			if f == 0 and wx < -0.2:
				continue
			_box(root, Vector3(0.9, 1.1, 0.1), Vector3(w * wx, 0.5 + f * 3.0 + 1.7, d * 0.5 + 0.04), window_mat)
			_box(root, Vector3(1.1, 0.12, 0.2), Vector3(w * wx, 0.5 + f * 3.0 + 1.1, d * 0.5 + 0.08), timber)
	_extras(root, h, w, d, top, rise)
	# Roof: one solid block above the walls so nothing walks or sees through it.
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(w + 0.4, rise + 0.4, d + 0.4)
	col.shape = shape
	col.position = Vector3(0, top + rise * 0.5, 0)
	body.add_child(col)
	root.add_child(body)
	buildings.append({"root": root, "h": h, "w": w, "d": d, "floors": floors, "door": hinge,
		"door_local": Vector3(door_x, FLOOR_Y, d * 0.5)})
	return root


## Plaster walls with a doorway in the front (+z) wall, a boarded floor on
## the stone base and a ceiling over the ground floor. All solid.
func _hollow_walls(root: Node3D, w: float, d: float, wall_h: float, floors: int, plaster: Material, door_x: float) -> void:
	var y0 := FLOOR_Y
	var hw := w * 0.5 - WALL * 0.5
	var hd := d * 0.5 - WALL * 0.5
	# Back, left and right walls.
	Structures.box(root, Vector3(w, wall_h, WALL), Vector3(0, y0 + wall_h * 0.5, -hd), plaster, Vector3.ZERO, true)
	Structures.box(root, Vector3(WALL, wall_h, d - WALL * 2.0), Vector3(-hw, y0 + wall_h * 0.5, 0), plaster, Vector3.ZERO, true)
	Structures.box(root, Vector3(WALL, wall_h, d - WALL * 2.0), Vector3(hw, y0 + wall_h * 0.5, 0), plaster, Vector3.ZERO, true)
	# Front wall in three pieces around the doorway.
	var left_w := (door_x - DOOR_W * 0.5) + w * 0.5
	var right_w := w * 0.5 - (door_x + DOOR_W * 0.5)
	Structures.box(root, Vector3(left_w, wall_h, WALL), Vector3(-w * 0.5 + left_w * 0.5, y0 + wall_h * 0.5, hd), plaster, Vector3.ZERO, true)
	Structures.box(root, Vector3(right_w, wall_h, WALL), Vector3(w * 0.5 - right_w * 0.5, y0 + wall_h * 0.5, hd), plaster, Vector3.ZERO, true)
	Structures.box(root, Vector3(DOOR_W, wall_h - DOOR_H, WALL), Vector3(door_x, y0 + DOOR_H + (wall_h - DOOR_H) * 0.5, hd), plaster, Vector3.ZERO, true)
	# Occluders: houses hide what's behind them (used when occlusion culling is on, PC).
	for o in [[Vector3(w, wall_h, WALL), Vector3(0, y0 + wall_h * 0.5, -hd)], [Vector3(WALL, wall_h, d), Vector3(-hw, y0 + wall_h * 0.5, 0)], [Vector3(WALL, wall_h, d), Vector3(hw, y0 + wall_h * 0.5, 0)]]:
		var oi := OccluderInstance3D.new()
		var bo := BoxOccluder3D.new()
		bo.size = o[0]
		oi.occluder = bo
		oi.position = o[1]
		root.add_child(oi)
	# Floor boards and the ceiling of the ground floor (upper floors are private).
	var boards := _tex_mat("weathered_brown_planks", Color(0.62, 0.5, 0.4), 0.9)
	Structures.box(root, Vector3(w - WALL * 2.0, 0.04, d - WALL * 2.0), Vector3(0, y0 + 0.02, 0), boards)
	var ceil_y := y0 + 3.0 if floors > 1 else y0 + wall_h
	Structures.box(root, Vector3(w - WALL * 2.0, 0.2, d - WALL * 2.0), Vector3(0, ceil_y + 0.1, 0), boards, Vector3.ZERO, true)
	# Beams across the ceiling.
	var beam := _tex_mat("weathered_brown_planks", Color(0.45, 0.35, 0.28), 0.8)
	for i in int(w / 1.8):
		Structures.box(root, Vector3(0.18, 0.2, d - WALL * 2.0), Vector3(-w * 0.5 + 1.2 + i * 1.8, ceil_y - 0.1, 0), beam)
	# The stone base is the floor: solid.
	var base := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(w + 0.4, 2.0, d + 0.4)
	col.shape = shape
	col.position.y = -0.5
	base.add_child(col)
	root.add_child(base)


## A plank door on an iron-strapped frame, hinged at the left of the doorway.
## Returns the hinge (rotate it to open; see Interiors).
func _door(root: Node3D, door_x: float, d: float, planks: Material, timber: Material) -> Node3D:
	var hinge := Node3D.new()
	hinge.name = "DoorHinge"
	hinge.position = Vector3(door_x - DOOR_W * 0.5 + 0.04, FLOOR_Y, d * 0.5 - WALL * 0.5)
	root.add_child(hinge)
	var leaf_w := DOOR_W - 0.08
	Structures.box(hinge, Vector3(leaf_w, DOOR_H - 0.04, 0.08), Vector3(leaf_w * 0.5, DOOR_H * 0.5, 0), planks)
	var iron := Structures.plain(Color(0.12, 0.11, 0.1), 0.5, 0.7)
	for y in [0.45, DOOR_H - 0.5]:
		Structures.box(hinge, Vector3(leaf_w * 0.85, 0.07, 0.1), Vector3(leaf_w * 0.45, y, 0), iron)
	Structures.sphere(hinge, 0.05, Vector3(leaf_w - 0.15, 1.05, 0.07), iron)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(leaf_w, DOOR_H - 0.04, 0.1)
	col.shape = shape
	col.position = Vector3(leaf_w * 0.5, DOOR_H * 0.5, 0)
	body.add_child(col)
	hinge.add_child(body)
	# Door frame.
	for sx in [-1.0, 1.0]:
		Structures.box(root, Vector3(0.14, DOOR_H + 0.1, 0.34), Vector3(door_x + sx * (DOOR_W * 0.5 + 0.03), FLOOR_Y + DOOR_H * 0.5, d * 0.5 - WALL * 0.5), timber)
	Structures.box(root, Vector3(DOOR_W + 0.3, 0.16, 0.34), Vector3(door_x, FLOOR_Y + DOOR_H + 0.05, d * 0.5 - WALL * 0.5), timber)
	return hinge


## Stone steps up to the threshold, over a gentle ramp you can walk up.
func _steps(root: Node3D, h: Dictionary, door_x: float, d: float, stone: Material) -> void:
	var run := 2.2
	for i in 2:
		Structures.box(root, Vector3(DOOR_W + 0.6, 0.25, run * (1.0 - i * 0.5)), Vector3(door_x, 0.125 + i * 0.25 - 0.25, d * 0.5 + 0.2 + run * (1.0 - i * 0.5) * 0.5), stone)
	var drop := FLOOR_Y + 0.9   # reaches below the ground in front, however it slopes
	var ang := atan2(drop, run)
	var ramp_len := sqrt(run * run + drop * drop)
	var ramp := Structures.collider(root, Vector3(DOOR_W + 0.4, 0.1, ramp_len), Vector3(door_x, FLOOR_Y - drop * 0.5 - 0.05, d * 0.5 + 0.2 + run * 0.5), Vector3(ang, 0, 0))
	ramp.set_meta("walkable", true)


## Highest terrain under a house's footprint.
func _footprint_top(h: Dictionary) -> float:
	var top := -INF
	for i in 5:
		for j in 5:
			var l := Vector3((i / 4.0 - 0.5) * (float(h.w) + 0.4), 0, (j / 4.0 - 0.5) * (float(h.d) + 0.4)).rotated(Vector3.UP, float(h.rot))
			top = maxf(top, data.terrain_height(float(h.x) + l.x, float(h.z) + l.z))
	return top
