extends Node3D
## The green-valley test zone: the Terrain3D proving ground for Openworld.
## Rolling FastNoise2 hills around a valley, a spring-fed brook that drops
## over a waterfall into a plunge pool and runs on to a pond, forests,
## meadows and rocks, a player and a horse. Everything the main world will
## need from Terrain3D is exercised here first: heightmap import, texture
## painting, collision, LOD, foliage instancing, water on the terrain.
##
## Run it: open this scene in the editor and press F6, or launch the game
## with  -- --test-zone  (works in exported builds too).
## The terrain data is built by tools/build_terrain.gd from
## green_valley.json; this script only dresses and plays it.

const DESC := "res://world/test_zone/green_valley.json"
const TEX := "res://assets/vendor/polyhaven/textures/"
## Texture slots, the same as tools/build_terrain.gd paints.
## [texture, repeats per metre, colour grade] (grades as in the main world's terrain).
const SLOTS := [["sparse_grass", 0.12, Color(0.95, 1.05, 0.8)], ["leafy_grass", 0.1, Color(0.8, 0.95, 0.6)], ["rock_face_03", 0.08, Color(0.85, 0.85, 0.88)],
	["forest_floor", 0.12, Color(0.75, 0.7, 0.6)], ["dirt_floor", 0.15, Color(0.85, 0.8, 0.75)], ["dark_rock_02", 0.1, Color(0.55, 0.55, 0.58)]]

var desc: Dictionary
var terrain: Terrain3D
var player: Player
var horse: Horse
var sky: SkyCycle
var water: Water
var mobile := false
## How many of each foliage kind were planted (oak, pine, rock, tall grass).
var planted := [0, 0, 0, 0]


func _ready() -> void:
	mobile = OS.has_feature("mobile") or "--mobile" in OS.get_cmdline_user_args()
	desc = JSON.parse_string(FileAccess.get_file_as_string(DESC))
	GameAudio.ensure_buses()
	_build_terrain()
	sky = SkyCycle.new()
	add_child(sky)
	sky.setup(mobile, {"start_hour": 9.5, "day_minutes": 24.0})
	water = Water.new()
	add_child(water)
	water.build(desc, ground, mobile)
	_plant()
	_spawn()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tour="):
			_tour = a.substr(7).split(";")
		elif a.begins_with("--shot="):
			_shot = a.substr(7)


# ---------- Screenshot tour (dev): --shot=path --tour="x,y,z,yaw,pitch,hour;..." ----------

var _tour: PackedStringArray = []
var _shot := ""
var _frame := 0
var _cam: Camera3D


func _process(_delta: float) -> void:
	if _tour.is_empty():
		return
	var idx := _frame / 40
	var f := _frame % 40
	_frame += 1
	if idx >= _tour.size():
		get_tree().quit()
		return
	var v := _tour[idx].split(",")
	if f == 0:
		if _cam == null:
			_cam = Camera3D.new()
			_cam.far = 2000.0
			add_child(_cam)
			_cam.current = true
		_cam.position = Vector3(float(v[0]), ground(float(v[0]), float(v[2])) + float(v[1]), float(v[2]))
		_cam.rotation_degrees = Vector3(float(v[4]), float(v[3]), 0)
		sky.time_of_day = float(v[5])
	if f == 39:
		get_viewport().get_texture().get_image().save_png(_shot.get_basename() + "_%d.png" % idx)


## Ground height from Terrain3D (NaN outside the zone becomes 0).
func ground(x: float, z: float) -> float:
	var h: float = terrain.data.get_height(Vector3(x, 0, z))
	return 0.0 if is_nan(h) else h


# ---------- Terrain ----------

func _build_terrain() -> void:
	terrain = Terrain3D.new()
	terrain.name = "Terrain3D"
	terrain.data_directory = desc.data_dir
	# Full collision: the zone is small, and tests run without a camera.
	terrain.collision_mode = Terrain3DCollision.FULL_GAME
	terrain.material.world_background = Terrain3DMaterial.NONE
	terrain.material.auto_shader_enabled = false
	terrain.mesh_lods = 5 if mobile else 7
	terrain.mesh_size = 32 if mobile else 48
	for i in SLOTS.size():
		var ta := _texture_asset(SLOTS[i][0])
		if ta:
			ta.uv_scale = SLOTS[i][1]
			ta.albedo_color = SLOTS[i][2]
			terrain.assets.set_texture_asset(i, ta)
	add_child(terrain)


## Packs a Poly Haven set the way Terrain3D wants it: albedo + height (from
## the AO map) and normal + roughness. Missing textures (no vendor assets)
## leave the slot empty: Terrain3D then shows its checker, nothing breaks.
func _texture_asset(name: String) -> Terrain3DTextureAsset:
	var base := TEX + name + "/"
	if not ResourceLoader.exists(base + "albedo.jpg"):
		return null
	var alb := _img(base + "albedo.jpg")
	var ao := _img(base + "ao.jpg")
	var nrm := _img(base + "normal.jpg")
	var rough := _img(base + "rough.jpg")
	var ta := Terrain3DTextureAsset.new()
	ta.name = name
	ta.albedo_texture = ImageTexture.create_from_image(Terrain3DUtil.pack_image(alb, ao, null, false, false, true, 0, 0))
	ta.normal_texture = ImageTexture.create_from_image(Terrain3DUtil.pack_image(nrm, rough, null, false, false, false, 0, 0))
	return ta


func _img(path: String) -> Image:
	var img: Image = (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


# ---------- Foliage ----------

## Trees in forest patches and scattered over the meadows, rocks on steep
## ground, tall grass and reeds along the water: Terrain3D's instancer
## draws them all in a few multimesh calls with distance LODs.
func _plant() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4117
	var forest := FastNoiseLite.new()
	forest.seed = 77
	forest.frequency = 0.012
	var assets := [
		_mesh_asset("oak", _tree(false), 180.0), _mesh_asset("pine", _tree(true), 200.0),
		_mesh_asset("rock", [[Props.make_rock(rng), Props.rock_material()]], 120.0),
		_mesh_asset("tall_grass", [[Props.make_grass_tuft(), _grass_material()]], 40.0)]
	for i in assets.size():
		terrain.assets.set_mesh_asset(i, assets[i])
	var xf := [[], [], [], []]
	var half := 250.0
	var step := 7.0 if not mobile else 10.0
	var x := -half
	while x < half:
		var z := -half
		while z < half:
			var p := Vector3(x + rng.randf_range(-3, 3), 0, z + rng.randf_range(-3, 3))
			z += step
			p.y = ground(p.x, p.z)
			var slope := _slope(p)
			var wet := Water.depth_at(p + Vector3(0, -0.05, 0))
			var near_water := Water.depth_at(p + Vector3(0, -0.8, 0)) > 0.0
			if wet > 0.0:
				continue
			var f := forest.get_noise_2d(p.x, p.z)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.25))
			if slope > 0.75:
				if rng.randf() < 0.35:
					xf[2].append(Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(0.8, 2.2)), p - Vector3(0, 0.3, 0)))
			elif f > 0.25 and rng.randf() < 0.75 and not near_water:
				xf[0 if rng.randf() < 0.6 else 1].append(Transform3D(basis, p - Vector3(0, 0.2, 0)))
			elif f > -0.1 and rng.randf() < 0.06 and not near_water:
				xf[0].append(Transform3D(basis, p - Vector3(0, 0.2, 0)))
			elif slope < 0.5 and rng.randf() < 0.08:
				xf[2].append(Transform3D(basis.scaled(Vector3.ONE * 0.6), p - Vector3(0, 0.15, 0)))
			# Tall grass and reeds, thickest on the banks.
			var tufts := (10 if near_water else (8 if f < 0.25 else 3)) / (2 if mobile else 1)
			for k in tufts:
				var q := p + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
				q.y = ground(q.x, q.z)
				if Water.depth_at(q) == 0.0 and _slope(q) < 0.6:
					xf[3].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1, rng.randf_range(1.2, 2.6) if near_water else 1.0, 1)), q))
		x += step
	for i in xf.size():
		var arr: Array[Transform3D] = []
		arr.assign(xf[i])
		planted[i] = arr.size()
		terrain.instancer.add_transforms(i, arr)


func _slope(p: Vector3) -> float:
	var dx := ground(p.x + 1.0, p.z) - ground(p.x - 1.0, p.z)
	var dz := ground(p.x, p.z + 1.0) - ground(p.x, p.z - 1.0)
	return Vector2(dx, dz).length() * 0.5


func _tree(conifer: bool) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11 if conifer else 7
	var bark := Trees.bark_material()
	if not Trees.has_photo_leaves():
		var t := Props.make_pine(rng, 14.0) if conifer else Props.make_tree(rng, 12.0)
		return [[t[0], bark], [t[1], Props.leaf_material(Color(0.06, 0.14, 0.05), Color(0.25, 0.4, 0.12))]]
	var leaf := Trees.leaf_material(Trees.LEAF_TEX, Color(0.32, 0.45, 0.38) if conifer else Color(0.62, 0.78, 0.5), conifer)
	var t := Trees.conifer(rng, 15.0, 70) if conifer else Trees.broadleaf(rng, 12.0, 130)
	return [[t[0], bark], [t[1], leaf]]


func _grass_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.36, 0.5, 0.18)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.9
	return m


## A Terrain3D mesh asset from [mesh, material] parts (packed into a scene).
func _mesh_asset(asset_name: String, parts: Array, lod0_range: float) -> Terrain3DMeshAsset:
	var root := Node3D.new()
	root.name = asset_name
	var mi := MeshInstance3D.new()
	mi.name = "LOD0"
	var mesh := ArrayMesh.new()
	for p in parts:
		var src: Mesh = p[0]
		for s in src.get_surface_count():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(s))
			mesh.surface_set_material(mesh.get_surface_count() - 1, p[1])
	mi.mesh = mesh
	root.add_child(mi)
	mi.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	var ma := Terrain3DMeshAsset.new()
	ma.name = asset_name
	ma.scene_file = scene
	ma.lod0_range = lod0_range
	ma.cast_shadows = RenderingServer.SHADOW_CASTING_SETTING_OFF if asset_name == "tall_grass" else RenderingServer.SHADOW_CASTING_SETTING_ON
	return ma


# ---------- Player and horse ----------

func _spawn() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/game_config.json"))
	player = Player.new()
	player.setup(config)
	var sp := Vector2(desc.spawn[0], desc.spawn[1])
	player.position = Vector3(sp.x, ground(sp.x, sp.y) + 0.3, sp.y)
	add_child(player)
	var hcfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/horses.json"))
	player.ride = hcfg.get("ride", {})
	horse = Horse.new()
	add_child(horse)
	horse.setup_horse(hcfg.horses[0], hcfg.gait, hcfg.ride, 4242)
	horse.height_at = ground
	horse.global_position = Vector3(sp.x + 4.0, ground(sp.x + 4.0, sp.y + 2.0), sp.y + 2.0)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_E:
			if player.horse:
				player.dismount()
			elif horse.global_position.distance_to(player.global_position) < 3.0:
				player.mount(horse)
		KEY_ESCAPE:
			get_tree().quit()
