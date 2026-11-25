class_name Church
extends Node3D
## The Church of the Mended Isle, south of Brickton (data/landmarks.json).
## A Gothic stone church on a raised plinth: twin towers with spires and
## bells, a pointed-arch entrance under a rose window, buttressed walls with
## tall stained-glass windows, and a walk-in nave with columns, pews, an
## altar, candles and chandeliers. At the back: the priest's chamber and the
## library (archive). A walled churchyard with graves and lanterns outside.
## The bells ring the hour from 7:00 to 21:00. Interior lights switch on only
## while you are close.
##
## Local space: the door faces +z; the altar is at -z. FLOOR is the nave floor
## height above the root.

const FLOOR := 0.6
const WALL_H := 12.0
const T := 0.6               ## wall thickness
const DOOR_W := 3.0
const DOOR_H := 5.0

var data: WorldData
var info: Dictionary = {}
var w := 16.0
var d := 40.0
var floor_y := 0.0           ## world height of the nave floor
var stone: Material
var dark_stone: Material
var oak: Material
var lights: Array[Light3D] = []
var outside_lights: Array[Light3D] = []
var bell_player: AudioStreamPlayer3D
var _last_hour := -1
var _lights_on := false
## Read points (lore) and their text, built as Interactables: id -> node.
var points := {}
## Opens a conversation box: Callable(dict) (wired by the world to Story.open).
var open_text: Callable = Callable()
var player: Node3D
var sky: SkyCycle


func setup(world_data: WorldData, entry: Dictionary, village: Village) -> void:
	data = world_data
	info = entry
	w = float(entry.w)
	d = float(entry.d)
	var ground := data.terrain_height(float(entry.x), float(entry.z))
	position = Vector3(entry.x, ground, entry.z)
	rotation.y = float(entry.rot)
	floor_y = ground + FLOOR
	stone = village._tex_mat("castle_brick_07", Color(0.92, 0.9, 0.86), 0.35)
	dark_stone = village._tex_mat("castle_brick_07", Color(0.62, 0.6, 0.58), 0.4)
	oak = village._tex_mat("weathered_brown_planks", Color(0.5, 0.36, 0.24), 0.9)
	_plinth()
	_nave()
	_roof(village)
	_towers(village)
	_facade()
	_interior(village)
	_side_rooms()
	_churchyard()
	data.add_floor(Vector2(entry.x, entry.z), float(entry.rot), Vector2(w + 2.0, d + 2.0), floor_y)
	bell_player = AudioStreamPlayer3D.new()
	bell_player.stream = load("res://assets/audio/sfx/church_bell.ogg") if ResourceLoader.exists("res://assets/audio/sfx/church_bell.ogg") else null
	bell_player.max_distance = 600.0
	bell_player.unit_size = 40.0
	bell_player.bus = "Effects"
	bell_player.position = Vector3(-w * 0.5 + 2.5, FLOOR + 22.0, d * 0.5 - 2.5)
	add_child(bell_player)
	_set_lights(false)


## World position of a point given in church space.
func at(local: Vector3) -> Vector3:
	return to_global(local)


func _process(_delta: float) -> void:
	if player:
		var near := player.global_position.distance_to(global_position) < 70.0
		if near != _lights_on:
			_set_lights(near)
	if sky and bell_player.stream:
		var hour := int(sky.time_of_day)
		if hour != _last_hour:
			if _last_hour >= 0 and hour >= 7 and hour <= 21:
				ring(1 if hour == 12 else 0)
			_last_hour = hour


## Rings the bells: n extra strokes (noon gets a longer peal).
func ring(extra := 0) -> void:
	for k in 3 + extra * 3:
		get_tree().create_timer(k * 2.2).timeout.connect(func() -> void:
			if is_instance_valid(bell_player):
				bell_player.pitch_scale = 1.0 if k % 2 == 0 else 0.84
				bell_player.play())


func set_night(amount: float) -> void:
	for l in outside_lights:
		l.visible = amount > 0.3
		l.light_energy = 1.5 * amount


func _set_lights(on: bool) -> void:
	_lights_on = on
	for l in lights:
		l.visible = on


func _solid(size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	return Structures.box(self, size, pos, mat, rot, true)


# ---------- Shell ----------

func _plinth() -> void:
	_solid(Vector3(w + 2.0, FLOOR + 1.0, d + 2.0), Vector3(0, FLOOR * 0.5 - 0.5, 0), dark_stone)
	# Broad steps up to the doors, over a ramp.
	for i in 3:
		var depth := 2.4 - i * 0.8
		Structures.box(self, Vector3(DOOR_W + 3.0, FLOOR / 3.0, depth), Vector3(0, FLOOR / 6.0 + i * FLOOR / 3.0 - 0.0, d * 0.5 + 1.0 + depth * 0.5), dark_stone)
	var run := 2.4
	var ang := atan2(FLOOR + 0.2, run)
	var ramp := Structures.collider(self, Vector3(DOOR_W + 2.6, 0.1, sqrt(run * run + (FLOOR + 0.2) * (FLOOR + 0.2))), Vector3(0, FLOOR * 0.5 - 0.1, d * 0.5 + 1.0 + run * 0.5), Vector3(ang, 0, 0))
	ramp.set_meta("walkable", true)
	# Flagstone floor.
	Structures.box(self, Vector3(w - T * 2.0, 0.04, d - T * 2.0), Vector3(0, FLOOR + 0.02, 0), Structures.tex_mat("castle_brick_07", Color(0.55, 0.52, 0.5), 0.6))


func _nave() -> void:
	var hw := w * 0.5 - T * 0.5
	var hd := d * 0.5 - T * 0.5
	var y := FLOOR + WALL_H * 0.5
	_solid(Vector3(w, WALL_H, T), Vector3(0, y, -hd), stone)
	# Side walls: solid between the windows (window openings are glazed, see _windows).
	for sx in [-1.0, 1.0]:
		_solid(Vector3(T, WALL_H, d - T * 2.0), Vector3(sx * hw, y, 0), stone)
		# Buttresses: stepped piers between the windows.
		for k in 6:
			var z := -d * 0.5 + 3.0 + k * (d - 6.0) / 5.0
			_solid(Vector3(1.4, WALL_H * 0.85, 1.0), Vector3(sx * (w * 0.5 + 0.7), FLOOR + WALL_H * 0.425, z), dark_stone)
			Structures.box(self, Vector3(1.0, 2.0, 1.0), Vector3(sx * (w * 0.5 + 0.55), FLOOR + WALL_H * 0.85 + 0.6, z), dark_stone, Vector3(0, 0, -sx * 0.5))
	# Front wall with the doorway.
	var side_w := (w - DOOR_W) * 0.5
	for sx in [-1.0, 1.0]:
		_solid(Vector3(side_w, WALL_H, T), Vector3(sx * (DOOR_W * 0.5 + side_w * 0.5), y, hd), stone)
	_solid(Vector3(DOOR_W, WALL_H - DOOR_H, T), Vector3(0, FLOOR + DOOR_H + (WALL_H - DOOR_H) * 0.5, hd), stone)
	_windows()


## Tall lancet windows of stained glass down both sides and at the altar end.
func _windows() -> void:
	var palette := [Color(0.2, 0.35, 0.9), Color(0.85, 0.2, 0.2), Color(0.95, 0.75, 0.2), Color(0.25, 0.7, 0.35), Color(0.6, 0.3, 0.8)]
	var lead := Structures.plain(Color(0.08, 0.08, 0.08), 0.5, 0.6)
	for sx in [-1.0, 1.0]:
		for k in 5:
			var z := -d * 0.5 + 3.0 + (k + 0.5) * (d - 6.0) / 5.0
			_lancet(Vector3(sx * (w * 0.5 + 0.01), FLOOR + 5.5, z), sx * PI * 0.5, 1.6, 5.5, palette, k + int(sx > 0) * 3, lead)
	_lancet(Vector3(0, FLOOR + 6.5, -d * 0.5 - 0.01), PI, 3.2, 6.5, palette, 7, lead)


func _lancet(pos: Vector3, yaw: float, width: float, height: float, palette: Array, seed_value: int, lead: Material) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = yaw
	add_child(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# A grid of coloured panes inside a lead frame, a pointed top over it; both faces.
	var cols := 3
	var rows := 6
	for face in [-1.0, 1.0]:
		for j in rows:
			for i in cols:
				var c: Color = palette[rng.randi() % palette.size()]
				var pane := Structures.glow_mat(c, 0.9)
				pane.albedo_color = c
				var b := Structures.box(n, Vector3(width / cols - 0.05, height / rows - 0.05, 0.02), Vector3(-width * 0.5 + (i + 0.5) * width / cols, -height * 0.5 + (j + 0.5) * height / rows, face * 0.33), pane)
				b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var arch := Structures.prism(n, Vector3(width, width * 0.7, 0.03), Vector3(0, height * 0.5 + width * 0.35, face * 0.33), Structures.glow_mat(palette[seed_value % palette.size()], 0.9))
		arch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Structures.box(n, Vector3(0.08, height, 0.05), Vector3(0, 0, face * 0.35), lead)
		Structures.box(n, Vector3(width, 0.08, 0.05), Vector3(0, 0, face * 0.35), lead)
	# Stone surround.
	for sx in [-1.0, 1.0]:
		Structures.box(n, Vector3(0.25, height + 0.4, 0.8), Vector3(sx * (width * 0.5 + 0.12), 0, 0), dark_stone)
	Structures.box(n, Vector3(width + 0.5, 0.3, 0.9), Vector3(0, -height * 0.5 - 0.15, 0.1), dark_stone)


func _roof(village: Village) -> void:
	var tiles := village._tex_mat("clay_roof_tiles_02", Color(0.45, 0.47, 0.52), 0.5)
	var pitch := deg_to_rad(55.0)
	var half_span := w * 0.5 + 0.8
	var rise := tan(pitch) * half_span
	var slope_len := half_span / cos(pitch)
	var top := FLOOR + WALL_H
	for sx in [-1.0, 1.0]:
		Structures.box(self, Vector3(slope_len, 0.3, d + 0.6), Vector3(sx * half_span * 0.5, top + rise * 0.5, 0), tiles, Vector3(0, 0, -sx * pitch))
	# Gable ends in stone.
	for sz in [-1.0, 1.0]:
		Structures.prism(self, Vector3(w, rise, T), Vector3(0, top + rise * 0.5, sz * (d * 0.5 - T * 0.5)), stone)
	Structures.collider(self, Vector3(w, rise, d), Vector3(0, top + rise * 0.5, 0))
	# A slim flèche (spirelet) over the crossing.
	Structures.cyl(self, 0.0, 0.9, 7.0, Vector3(0, top + rise + 3.0, -d * 0.15), tiles, Vector3.ZERO, false, 8)


func _towers(village: Village) -> void:
	var tiles := village._tex_mat("clay_roof_tiles_02", Color(0.35, 0.38, 0.42), 0.5)
	var bronze := Structures.plain(Color(0.55, 0.42, 0.2), 0.35, 0.85)
	for sx in [-1.0, 1.0]:
		var c := Vector3(sx * (w * 0.5 - 2.5), 0, d * 0.5 - 2.5)
		var tw := 5.5
		var th := 24.0
		_solid(Vector3(tw, th, tw), c + Vector3(0, FLOOR + th * 0.5, 0), stone)
		# Corner buttresses.
		for bx in [-1.0, 1.0]:
			for bz in [-1.0, 1.0]:
				Structures.box(self, Vector3(0.8, th * 0.8, 0.8), c + Vector3(bx * tw * 0.5, FLOOR + th * 0.4, bz * tw * 0.5), dark_stone)
		# Belfry: open arches on each face (dark recesses) with a bell inside.
		for f in 4:
			var dir := Vector3(sin(f * PI * 0.5), 0, cos(f * PI * 0.5))
			var arch := Structures.box(self, Vector3(1.6, 3.2, 0.1), c + dir * (tw * 0.5 + 0.02) + Vector3(0, FLOOR + th - 4.0, 0), Structures.plain(Color(0.04, 0.04, 0.05), 1.0), Vector3(0, f * PI * 0.5, 0))
			arch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			Structures.prism(self, Vector3(1.6, 0.9, 0.1), c + dir * (tw * 0.5 + 0.02) + Vector3(0, FLOOR + th - 2.0, 0), Structures.plain(Color(0.04, 0.04, 0.05), 1.0), Vector3(0, f * PI * 0.5, 0))
		Structures.cyl(self, 0.55, 1.0, 1.4, c + Vector3(0, FLOOR + th - 4.2, 0), bronze)
		# Spire with a gilded finial: the silhouette you see from across the island.
		Structures.box(self, Vector3(tw + 0.6, 0.6, tw + 0.6), c + Vector3(0, FLOOR + th + 0.3, 0), dark_stone)
		Structures.cyl(self, 0.0, tw * 0.62, 14.0, c + Vector3(0, FLOOR + th + 7.6, 0), tiles, Vector3.ZERO, false, 8)
		Structures.sphere(self, 0.3, c + Vector3(0, FLOOR + th + 14.8, 0), bronze)
		Structures.box(self, Vector3(0.12, 1.6, 0.12), c + Vector3(0, FLOOR + th + 15.7, 0), bronze)
		Structures.box(self, Vector3(0.8, 0.12, 0.12), c + Vector3(0, FLOOR + th + 15.9, 0), bronze)


func _facade() -> void:
	var z := d * 0.5 + 0.05
	# Pointed arch over the doors, in layered mouldings.
	for k in 3:
		var s := 1.0 + k * 0.18
		for sx in [-1.0, 1.0]:
			Structures.box(self, Vector3(0.35, DOOR_H, 0.5), Vector3(sx * (DOOR_W * 0.5 + 0.15) * s, FLOOR + DOOR_H * 0.5, z + 0.1 + k * 0.12), dark_stone)
		Structures.prism(self, Vector3((DOOR_W + 0.6) * s, 2.2 * s, 0.4), Vector3(0, FLOOR + DOOR_H + 1.0 * s, z + 0.1 + k * 0.12), dark_stone)
	# Twin oak doors, swung open: the church welcomes everyone.
	for sx in [-1.0, 1.0]:
		var leaf := Structures.box(self, Vector3(DOOR_W * 0.5, DOOR_H - 0.1, 0.12), Vector3(sx * (DOOR_W * 0.5 + 0.1), FLOOR + DOOR_H * 0.5, d * 0.5 - T - DOOR_W * 0.25), oak, Vector3(0, sx * PI * 0.5, 0))
		leaf.name = "DoorLeaf"
	# Rose window above the doors.
	var rose := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.2
	cm.bottom_radius = 2.2
	cm.height = 0.1
	cm.radial_segments = 24
	rose.mesh = cm
	var rm := Structures.glow_mat(Color(0.75, 0.35, 0.85), 1.1)
	rose.material_override = rm
	rose.rotation.x = PI * 0.5
	rose.position = Vector3(0, FLOOR + DOOR_H + 4.2, z + 0.05)
	rose.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rose)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.2
	tm.outer_radius = 2.6
	ring.mesh = tm
	ring.material_override = dark_stone
	ring.rotation.x = PI * 0.5
	ring.position = rose.position + Vector3(0, 0, 0.05)
	add_child(ring)
	for k in 8:
		Structures.box(self, Vector3(0.12, 4.3, 0.12), rose.position + Vector3(0, 0, 0.1), dark_stone, Vector3(0, 0, k * PI / 8.0))
	# Lanterns either side of the entrance.
	for sx in [-1.0, 1.0]:
		var p := Vector3(sx * (DOOR_W * 0.5 + 1.6), FLOOR + 3.2, z + 0.4)
		Structures.box(self, Vector3(0.3, 0.45, 0.3), p, Structures.glow_mat(Color(1.0, 0.72, 0.4), 2.5))
		outside_lights.append(Structures.flame_light(self, p + Vector3(0, 0, 0.6), Color(1.0, 0.7, 0.4), 1.5, 12.0))
	Structures.label(self, "Church of the Mended Isle", Vector3(0, FLOOR + DOOR_H + 1.0, z + 0.55), 40, Color(0.95, 0.9, 0.75))


# ---------- Inside ----------

func _interior(village: Village) -> void:
	# Columns down the nave with pointed arcades above.
	for sx in [-1.0, 1.0]:
		for k in 7:
			var z := -d * 0.5 + 7.0 + k * 4.0
			if z > d * 0.5 - 6.0:
				break
			Structures.cyl(self, 0.42, 0.5, WALL_H - 1.0, Vector3(sx * 4.2, FLOOR + (WALL_H - 1.0) * 0.5, z), stone, Vector3.ZERO, true, 12)
			Structures.box(self, Vector3(1.1, 0.4, 1.1), Vector3(sx * 4.2, FLOOR + 0.2, z), dark_stone)
			Structures.box(self, Vector3(0.9, 0.35, 0.9), Vector3(sx * 4.2, FLOOR + WALL_H - 1.2, z), dark_stone)
	# Pews in two blocks with a central aisle.
	for row in 8:
		var z := -d * 0.5 + 9.5 + row * 2.1
		for sx in [-1.0, 1.0]:
			Furniture.pew(self, Vector3(sx * 2.0, FLOOR, z), 0.0, 2.9, oak)
	# Chancel: a raised step, the altar, candles, the triptych behind it.
	var chancel_z := -d * 0.5 + 4.0
	_solid(Vector3(w - T * 2.0, 0.3, 6.0), Vector3(0, FLOOR + 0.15, chancel_z - 0.2), dark_stone)
	var altar_top := FLOOR + 0.3
	_solid(Vector3(3.0, 1.05, 1.2), Vector3(0, altar_top + 0.52, chancel_z - 1.0), stone)
	Structures.box(self, Vector3(3.1, 0.05, 1.3), Vector3(0, altar_top + 1.07, chancel_z - 1.0), Structures.plain(Color(0.92, 0.9, 0.84), 0.95))
	Structures.box(self, Vector3(1.0, 0.8, 0.04), Vector3(0, altar_top + 0.6, chancel_z - 0.38), Structures.plain(Color(0.55, 0.12, 0.12), 0.9))
	var gold := Structures.plain(Color(0.85, 0.66, 0.25), 0.3, 0.9)
	Structures.box(self, Vector3(0.08, 0.7, 0.08), Vector3(0, altar_top + 1.45, chancel_z - 1.2), gold)
	Structures.box(self, Vector3(0.4, 0.08, 0.08), Vector3(0, altar_top + 1.6, chancel_z - 1.2), gold)
	for sx in [-1.0, 1.0]:
		Furniture.candles(self, Vector3(sx * 2.2, altar_top, chancel_z - 0.6), 3)
		Structures.cyl(self, 0.03, 0.03, 0.3, Vector3(sx * 1.2, altar_top + 1.22, chancel_z - 1.1), Structures.plain(Color(0.95, 0.92, 0.82)))
	_triptych(Vector3(0, FLOOR + 3.4, -d * 0.5 + T + 0.08), gold)
	# Paintings between the side windows and a statue of the Mender.
	var scenes := [Color(0.3, 0.4, 0.6), Color(0.55, 0.35, 0.25), Color(0.3, 0.5, 0.35)]
	for k in 3:
		for sx in [-1.0, 1.0]:
			_painting(Vector3(sx * (w * 0.5 - T - 0.06), FLOOR + 2.6, -d * 0.5 + 9.0 + k * 9.0), -sx * PI * 0.5, scenes[k], gold)
	_statue(Vector3(-w * 0.5 + 1.6, FLOOR + 0.3, chancel_z + 1.6))
	# Chandeliers and the room's lights (only while you are near).
	for k in 3:
		var p := Vector3(0, FLOOR + 6.5, -d * 0.5 + 10.0 + k * 9.0)
		Furniture.chandelier(self, p, 1.0)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.78, 0.5)
		l.light_energy = 1.6
		l.omni_range = 14.0
		l.shadow_enabled = false
		l.position = p + Vector3(0, -0.5, 0)
		add_child(l)
		lights.append(l)
	# Stained-glass light: soft coloured glows inside the windows.
	var glass_cols := [Color(0.35, 0.45, 1.0), Color(1.0, 0.4, 0.35), Color(1.0, 0.8, 0.35)]
	for k in 3:
		for sx in [-1.0, 1.0]:
			var l := OmniLight3D.new()
			l.light_color = glass_cols[(k + int(sx > 0)) % 3]
			l.light_energy = 0.7
			l.omni_range = 6.0
			l.shadow_enabled = false
			l.position = Vector3(sx * (w * 0.5 - 1.5), FLOOR + 4.5, -d * 0.5 + 8.0 + k * 10.0)
			add_child(l)
			lights.append(l)
	# Inscription by the door (lore).
	_point("founding_stone", "Read the founding stone", Vector3(DOOR_W * 0.5 + 1.2, FLOOR + 1.4, d * 0.5 - T - 0.1), [
		"'This house was raised in the year of the Mending, when the island was made whole again.'",
		"'Let all who cross the waters find rest here, and remember what was broken.'",
		"Below, in smaller letters: 'Built on the stones of the Wardens' hall.'"])
	_point("mender_statue", "Look at the statue", Vector3(-w * 0.5 + 1.6, FLOOR + 1.6, chancel_z + 2.6), [
		"A robed figure with both hands pressed to the ground, as if holding something together.",
		"The plaque reads: 'The Mender. She bound the five lands with her own hands.'"])


func _triptych(pos: Vector3, gold: Material) -> void:
	var panels := [Color(0.25, 0.35, 0.65), Color(0.75, 0.6, 0.3), Color(0.25, 0.35, 0.65)]
	for k in 3:
		var x := (k - 1) * 1.7
		var tall := 3.0 if k == 1 else 2.4
		Structures.box(self, Vector3(1.55, tall, 0.06), pos + Vector3(x, 0, 0), Structures.plain(panels[k], 0.8))
		Structures.box(self, Vector3(1.7, tall + 0.15, 0.04), pos + Vector3(x, 0, -0.03), gold)
		# A simple figure on each panel.
		Structures.box(self, Vector3(0.35, 1.2, 0.02), pos + Vector3(x, -0.2, 0.04), Structures.plain(Color(0.9, 0.85, 0.7), 0.8))
		Structures.sphere(self, 0.18, pos + Vector3(x, 0.55, 0.04), Structures.plain(Color(0.95, 0.85, 0.55), 0.6), Vector3(1, 1, 0.2))


func _painting(pos: Vector3, yaw: float, c: Color, gold: Material) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = yaw
	add_child(n)
	Structures.box(n, Vector3(1.8, 1.3, 0.05), Vector3.ZERO, gold)
	Structures.box(n, Vector3(1.6, 1.1, 0.06), Vector3(0, 0, 0.01), Structures.plain(c, 0.85))
	Structures.box(n, Vector3(1.6, 0.35, 0.065), Vector3(0, -0.35, 0.01), Structures.plain(c.darkened(0.35), 0.85))
	Structures.sphere(n, 0.15, Vector3(0.45, 0.25, 0.04), Structures.plain(Color(1.0, 0.9, 0.6), 0.6), Vector3(1, 1, 0.2))


func _statue(pos: Vector3) -> void:
	var marble := Structures.plain(Color(0.88, 0.87, 0.84), 0.5)
	_solid(Vector3(1.0, 1.0, 1.0), pos + Vector3(0, 0.5, 0), dark_stone)
	Structures.cyl(self, 0.25, 0.45, 1.6, pos + Vector3(0, 1.8, 0), marble)
	Structures.sphere(self, 0.2, pos + Vector3(0, 2.8, 0), marble)
	for sx in [-1.0, 1.0]:
		Structures.box(self, Vector3(0.12, 0.7, 0.12), pos + Vector3(sx * 0.3, 1.9, 0.15), marble, Vector3(0.6, 0, sx * 0.2))


## The priest's chamber (left) and the library (right), behind the chancel's side walls.
func _side_rooms() -> void:
	var room_d := 6.0
	var z0 := -d * 0.5 + T
	for sx in [-1.0, 1.0]:
		var inner_x: float = sx * 4.4
		var wall_len := w * 0.5 - T - 4.4
		# Front wall of the room with a doorway towards the aisle.
		Structures.box(self, Vector3(wall_len - 1.2, 3.4, 0.2), Vector3(sx * (4.4 + 1.2 + (wall_len - 1.2) * 0.5), FLOOR + 1.7, z0 + room_d), stone, Vector3.ZERO, true)
		Structures.box(self, Vector3(1.2, 1.0, 0.2), Vector3(sx * (4.4 + 0.6), FLOOR + 2.9, z0 + room_d), stone)
		Structures.box(self, Vector3(0.2, 3.4, room_d), Vector3(inner_x, FLOOR + 1.7, z0 + room_d * 0.5), stone, Vector3.ZERO, true)
		Structures.box(self, Vector3(wall_len, 0.2, room_d), Vector3(sx * (4.4 + wall_len * 0.5), FLOOR + 3.5, z0 + room_d * 0.5), oak)
		var cx: float = sx * (4.4 + wall_len * 0.5)
		var rng := RandomNumberGenerator.new()
		rng.seed = 90 + int(sx > 0)
		if sx < 0:
			# Priest's chamber: bed, desk, chest, a prayer stool.
			Furniture.bed(self, Vector3(cx - 0.4, FLOOR, z0 + 1.2), 0.0, Color(0.35, 0.3, 0.28), oak, 0.85)
			Furniture.table(self, Vector3(cx + 0.3, FLOOR, z0 + 4.4), 0.0, oak, 1)
			Furniture.chest(self, Vector3(cx + 0.9, FLOOR, z0 + 0.6), 0.0, oak)
			Furniture.candles(self, Vector3(cx - 1.0, FLOOR, z0 + 4.8), 1)
			Structures.label(self, "Priest's Chamber", Vector3(sx * (4.4 + 0.6), FLOOR + 3.2, z0 + room_d + 0.12), 26)
		else:
			# Library and archive: shelves of books and scrolls, a reading desk.
			for k in 3:
				Furniture.shelf(self, Vector3(cx - 1.2 + k * 1.2, FLOOR, z0 + 0.25), 0.0, oak, rng, "books")
			Furniture.shelf(self, Vector3(w * 0.5 - T - 0.25, FLOOR, z0 + 3.4), -PI * 0.5, oak, rng, "books")
			Furniture.table(self, Vector3(cx - 0.4, FLOOR, z0 + 3.6), 0.0, oak, 2)
			Furniture.candles(self, Vector3(cx + 1.2, FLOOR, z0 + 4.8), 3)
			Structures.label(self, "Library", Vector3(sx * (4.4 + 0.6), FLOOR + 3.2, z0 + room_d + 0.12), 26)
			_point("chronicle", "Read the island chronicle", Vector3(cx - 0.4, FLOOR + 1.0, z0 + 3.6), [
				"'Before the Mending there were five lands and no sea between them, only light.'",
				"'The Wardens kept the light beneath the hollow hill. When it broke, the land broke with it: the Shattering.'",
				"'The Mender bound the lands with the heart-stones: frost, ember and glow. The rest is lost.'",
				"Several pages have been torn out."])
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.75, 0.48)
		l.light_energy = 1.0
		l.omni_range = 6.0
		l.shadow_enabled = false
		l.position = Vector3(cx, FLOOR + 2.6, z0 + room_d * 0.5)
		add_child(l)
		lights.append(l)


func _churchyard() -> void:
	var yard_w := w + 14.0
	var yard_d := d + 16.0
	var wall_mat := dark_stone
	var gate_gap := 4.0
	for side in [[Vector3(-yard_w * 0.5, 0, -yard_d * 0.5), Vector3(yard_w * 0.5, 0, -yard_d * 0.5)],
			[Vector3(-yard_w * 0.5, 0, -yard_d * 0.5), Vector3(-yard_w * 0.5, 0, yard_d * 0.5)],
			[Vector3(yard_w * 0.5, 0, -yard_d * 0.5), Vector3(yard_w * 0.5, 0, yard_d * 0.5)],
			[Vector3(-yard_w * 0.5, 0, yard_d * 0.5), Vector3(-gate_gap * 0.5, 0, yard_d * 0.5)],
			[Vector3(gate_gap * 0.5, 0, yard_d * 0.5), Vector3(yard_w * 0.5, 0, yard_d * 0.5)]]:
		_low_wall(side[0], side[1], wall_mat)
	# Graves in rows on the east side, and two lanterns at the gate.
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	for row in 4:
		for k in 5:
			var p := Vector3(w * 0.5 + 3.0 + k * 1.3, 0, -d * 0.3 + row * 4.0 + rng.randf_range(-0.3, 0.3))
			var g := global_transform * p
			var y := data.terrain_height(g.x, g.z) - global_position.y
			Structures.box(self, Vector3(0.6, 0.8 + rng.randf() * 0.3, 0.15), p + Vector3(0, y + 0.4, 0), Structures.old_stone(), Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.06, 0.06)))
			Structures.box(self, Vector3(0.7, 0.08, 1.6), p + Vector3(0, y + 0.03, 0.85), Structures.plain(Color(0.3, 0.38, 0.22), 1.0))
	for sx in [-1.0, 1.0]:
		var p := Vector3(sx * (gate_gap * 0.5 + 0.4), 0, yard_d * 0.5)
		var g := global_transform * p
		Structures.lamp_post(self, Vector3(p.x, data.terrain_height(g.x, g.z) - global_position.y, p.z), Structures.glow_mat(Color(1.0, 0.72, 0.4), 2.0))
		outside_lights.append(Structures.flame_light(self, p + Vector3(0, 3.0, 0), Color(1.0, 0.7, 0.4), 1.3, 12.0))


func _low_wall(a: Vector3, b: Vector3, mat: Material) -> void:
	var n := int(a.distance_to(b) / 2.0) + 1
	for k in n:
		var p := a.lerp(b, (k + 0.5) / n)
		var g := global_transform * p
		var y := data.terrain_height(g.x, g.z) - global_position.y
		var seg := a.distance_to(b) / n
		var dir := (b - a).normalized()
		Structures.box(self, Vector3(seg + 0.05, 1.0, 0.5), p + Vector3(0, y + 0.3, 0), mat, Vector3(0, atan2(dir.x, dir.z) + PI * 0.5, 0), true)


## A spot you can read (lore); text appears in the dialogue box.
func _point(id: String, label: String, local: Vector3, lines: Array) -> void:
	var it := Interactable.new(label, 2.2)
	add_child(it)
	it.position = local
	it.action = func(_n: Interactable) -> void:
		if open_text.is_valid():
			open_text.call({"speaker": "", "lines": lines})
	points[id] = it
