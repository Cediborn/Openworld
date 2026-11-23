class_name WorldFeatures
extends Node3D
## Everything to find and do outside the quest log: built places, named
## discoveries, treasure, shrines with puzzles, rare bosses, the Five
## Fragments trials, Caldor's key trials, resting at camps, the contract
## board and random world events. Content: data/world_features.json and
## data/bosses.json. Progress is kept as GameState flags so it saves with
## the game and unique rewards can only be taken once.

var cfg: Dictionary
var boss_cfg: Dictionary
var species: Dictionary
var data: WorldData
var player: Player
var hud: Hud
var story: Story
var state: GameState
var quests: Quests
var village: Village
var sky: SkyCycle
var audio: GameAudio
var mobile := false

var named_nodes := {}            # id -> Node3D (ashwarden, sanctuary door...)
var chests := {}                 # treasure id -> Interactable
var bosses := {}                 # rare boss id -> Boss
var trial_nodes := {}            # trial id -> Array of nodes
var discovered := {}
var event: Dictionary = {}
var event_nodes: Array = []
var event_timer := 0.0
var _tick := 0.0
var rng := RandomNumberGenerator.new()
var sanctuary_door: Node3D
var door_open := false
var spawned: Array[Creature] = []


func setup(world_data: WorldData, p: Player, h: Hud, s: Story, gs: GameState, qs: Quests, v: Village, sk: SkyCycle, au: GameAudio, is_mobile: bool) -> void:
	data = world_data
	player = p
	hud = h
	story = s
	state = gs
	quests = qs
	village = v
	sky = sk
	audio = au
	mobile = is_mobile
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_features.json"))
	boss_cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/bosses.json")).bosses
	species = JSON.parse_string(FileAccess.get_file_as_string("res://data/creatures.json")).species
	rng.seed = 4242
	for st in cfg.structures:
		_build_structure(st)
	_contract_board()
	_inn_rest()
	refresh()
	event_timer = rng.randf_range(120.0, 240.0)


func _g(a: Array) -> Vector3:
	return Vector3(a[0], data.height(a[0], a[1]), a[1])


## Finds a named world thing (used by quests to watch the peaceful golem).
func named(id: String) -> Node3D:
	return named_nodes.get(id)


## Re-checks what should exist after loading or when progress changes.
func refresh() -> void:
	for t in cfg.treasures:
		_sync_treasure(t)
	for sh in cfg.shrines:
		_sync_shrine(sh)
	_sync_trials()
	_sync_ashwarden()
	_set_door(state.has_flag("sanctuary_open") or quests.status("five_fragments") == "completed")
	for d in cfg.discoveries:
		discovered[d.id] = state.has_flag("disc:" + d.id)


# ---------- Spawning creatures and bosses ----------

## A creature for quests, events, trials and guardians. elite: {tint, scale, health, damage, name}.
func spawn_creature(sp: String, pos: Vector3, tag := "", elite: Dictionary = {}) -> Creature:
	if not species.has(sp):
		push_warning("unknown species " + sp)
		return null
	var c := Creature.new()
	add_child(c)
	var sc: Dictionary = species[sp].duplicate(true)
	if not elite.is_empty():
		sc.health = float(sc.get("health", 60)) * float(elite.get("health", 1.0))
		sc.damage = float(sc.get("damage", 10)) * float(elite.get("damage", 1.0))
		if elite.has("scale"):
			sc.scale = [float(elite.scale), float(elite.scale)]
	if sc.get("temper", "flee") == "flee":
		sc["temper"] = "threaten"   # quest and event animals come looking for a fight
		sc["aggro_radius"] = 18.0
		sc["chase_time"] = 10.0
		sc["leash"] = 60.0
		sc["cooldown"] = 3.0
		sc["roar_time"] = 0.8
	sc["respawn_time"] = 1.0e9
	if float(sc.get("min_height", -INF)) > data.height(pos.x, pos.z) - 0.5:
		sc["min_height"] = -100.0   # the lava limit only matters in the Ember Wastes
	c.setup(sc, rng.randi())
	c.unique = true
	c.quest_tag = tag
	c.home = pos
	c.threat = player
	c.height_at = func(x: float, z: float) -> float: return data.height(x, z)
	c.global_position = Vector3(pos.x, data.height(pos.x, pos.z), pos.z)
	c.rotation.y = rng.randf() * TAU
	if elite.has("tint"):
		var t: Array = elite.tint
		c.mat.set_shader_parameter("glow_color", Color(t[0], t[1], t[2]))
		c.mat.set_shader_parameter("glow_energy", maxf(float(sc.get("glow_energy", 0.0)), 1.6))
	if elite.get("name", "") != "":
		var l := Structures.label(c, elite.name, Vector3(0, c.model_size.y * c.size_scale + 0.6, 0), 56, Color(1.0, 0.8, 0.45))
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	if audio:
		audio.attach_creature(c)
	spawned.append(c)
	return c


func spawn_boss(id: String, pos: Vector3, tag := "") -> Boss:
	if not boss_cfg.has(id):
		push_warning("unknown boss " + id)
		return null
	var def: Dictionary = boss_cfg[id]
	var b := Boss.new()
	add_child(b)
	b.setup_boss(id, def, species[def.base], rng.randi())
	b.quest_tag = tag
	b.home = pos
	b.threat = player
	b.height_at = func(x: float, z: float) -> float: return data.height(x, z)
	b.global_position = Vector3(pos.x, data.height(pos.x, pos.z), pos.z)
	b.spawn_minion = func(sp: String, at: Vector3) -> Creature:
		var m := spawn_creature(sp, at, "minion", {"tint": def.get("crystals", [0.7, 0.4, 1.0]), "health": 0.8})
		if m:
			m.state = Creature.State.CHASE
			m.timer = 30.0
		return m
	if audio:
		audio.attach_creature(b)
	b.killed.connect(func(_c: Creature) -> void: _boss_down(b, def))
	return b


func _boss_down(b: Boss, def: Dictionary) -> void:
	state.set_flag("boss:" + b.boss_id)
	hud.hide_boss()
	hud.show_banner(b.title + " defeated!", "")
	var r: Dictionary = def.get("reward", {})
	for it in r.get("items", {}):
		state.add_item(it, int(r.items[it]))
	for rb in cfg.rare_bosses:
		if rb.id == b.boss_id:
			_loot(rb.loot)
			state.add_xp(int(rb.get("xp", 300)))
	refresh()


func _loot(loot: Dictionary) -> void:
	for k in loot:
		if k == "coins":
			state.add_coins(int(loot.coins))
		else:
			state.add_item(k, int(loot[k]))


# ---------- Built places ----------

func _build_structure(st: Dictionary) -> void:
	var p := _g(st.pos)
	var yaw: float = float(st.get("rot", 0.0))
	var root := Node3D.new()
	add_child(root)
	root.global_position = p
	root.rotation.y = yaw
	match st.kind:
		"sanctuary":
			_sanctuary(root)
		"mill":
			Structures.ruin(root, Vector3.ZERO, 0.4, 7.0, 7)
			var hub := Node3D.new()
			hub.position = Vector3(0, 5.0, 3.6)
			root.add_child(hub)
			Structures.cyl(hub, 0.25, 0.25, 0.6, Vector3.ZERO, Structures.wood(), Vector3(PI * 0.5, 0, 0))
			for i in 4:
				Structures.box(hub, Vector3(0.5, 4.5, 0.08), Vector3(0, 2.3, 0.3).rotated(Vector3.FORWARD, TAU * i / 4.0 + 0.4), Structures.wood(Color(0.5, 0.42, 0.32)), Vector3(0, 0, TAU * i / 4.0 + 0.4))
			Structures.cyl(root, 3.2, 3.6, 4.5, Vector3(0, 2.25, 0), Structures.old_stone(), Vector3.ZERO, true, 14)
		"stones":
			for i in int(st.get("count", 2)):
				Structures.standing_stone(root, Vector3(-2.2 + 4.4 * i, 0, 0), 3.6 + i * 0.4, 0.2 * i)
		"oak":
			var r2 := RandomNumberGenerator.new()
			r2.seed = 99
			var parts := Props.make_tree(r2, 13.0)
			var bark := MeshInstance3D.new()
			bark.mesh = parts[0]
			bark.material_override = Props.bark_material()
			root.add_child(bark)
			var leaves := MeshInstance3D.new()
			leaves.mesh = parts[1]
			leaves.material_override = Props.leaf_material(Color(0.12, 0.25, 0.08), Color(0.35, 0.5, 0.18))
			root.add_child(leaves)
			Structures.cyl(root, 0.6, 0.7, 4.0, Vector3(0, 2.0, 0), Structures.plain(Color(0, 0, 0, 0)), Vector3.ZERO, true).visible = false
		"wagon":
			Structures.wagon(root, Vector3.ZERO, 0.0, false)
			Structures.crate(root, Vector3(2.0, 0, 0.5), 0.3)
			Structures.barrel(root, Vector3(2.2, 0, -0.8))
		"camp":
			var tc: Array = st.get("tent", [0.55, 0.5, 0.42])
			Structures.tent(root, Vector3(-3.0, 0, -2.0), 0.5, Color(tc[0], tc[1], tc[2]))
			Structures.tent(root, Vector3(3.2, 0, -2.4), -0.4, Color(tc[0] * 0.9, tc[1] * 0.85, tc[2] * 0.8))
			Structures.campfire(root, Vector3(0, 0, 0.5))
			Structures.crate(root, Vector3(-1.8, 0, 2.6), 0.2)
			Structures.barrel(root, Vector3(2.4, 0, 2.2))
			Structures.bench(root, Vector3(0, 0, 2.2), 0.0)
			if st.get("rest", false):
				_rest_point(root.global_position + Vector3(0, 0, 0.5), "Rest by the fire")
		"ruined_camp":
			Structures.tent(root, Vector3(-3.0, 0, 2.0), 0.3, Color(0.6, 0.3, 0.2), true)
			Structures.campfire(root, Vector3(2.5, 0, 2.5), false)
			Structures.crystal_cluster(root, Vector3(4.0, 0, -3.0), Color(0.7, 0.35, 1.0), 5, 1.4, 31)
		"lodge":
			Structures.hut(root, Vector3(0, 0, -3.0), 0.0, 6.0, 5.0, Color(0.35, 0.3, 0.28))
			for i in 3:
				Structures.box(root, Vector3(0.9, 1.3, 0.05), Vector3(-4.2, 1.0, -1.0 + i * 1.1), Structures.plain(Color(0.55, 0.45, 0.35), 1.0), Vector3(0, PI * 0.5, 0.1))
			Structures.campfire(root, Vector3(3.5, 0, 1.5))
			_rest_point(root.global_position + Vector3(3.5, 0, 1.5), "Rest by the fire")
		"ruin":
			var tint: Array = st.get("tint", [0.72, 0.72, 0.68])
			Structures.ruin(root, Vector3.ZERO, 0.3, float(st.get("size", 10.0)), hash(st.id), Color(tint[0], tint[1], tint[2]))
		"cave":
			var ct: Array = st.get("tint", [0.75, 0.78, 0.85])
			Structures.cave(root, Vector3.ZERO, 0.0, Color(ct[0], ct[1], ct[2]))
		"temple":
			_temple(root)
		"forge":
			Structures.ruin(root, Vector3.ZERO, 0.2, 14.0, 77, Color(0.45, 0.38, 0.35))
			Structures.cyl(root, 1.6, 2.2, 4.0, Vector3(4.0, 2.0, -2.0), Structures.old_stone(Color(0.35, 0.3, 0.28)), Vector3.ZERO, true, 10)
			Structures.box(root, Vector3(1.2, 1.0, 0.3), Vector3(4.0, 0.9, -0.2), Structures.glow_mat(Color(1.0, 0.4, 0.1), 2.0))
			for i in 3:
				Structures.box(root, Vector3(1.6, 0.5, 2.4), Vector3(-5.0, 0.25, -4.0 + i * 3.0), Structures.old_stone(Color(0.4, 0.36, 0.33)), Vector3.ZERO, true)
		"nest":
			for i in 7:
				var a := TAU * i / 7.0
				Structures.sphere(root, 1.0, Vector3(cos(a) * 5.0, 0.2, sin(a) * 5.0), Structures.tex_mat("burned_ground_01", Color(0.5, 0.4, 0.35), 0.8), Vector3(1.4, 0.6, 1.2))
			Structures.wagon(root, Vector3(-3.0, 0, 2.0), 1.0, true)
		"hut":
			Structures.hut(root, Vector3(0, 0, 0), 0.0, 5.5, 4.5, Color(0.3, 0.45, 0.35))
			for i in 6:
				Structures.sphere(root, 0.25, Vector3(-3.5 + i * 0.5, 0.2, 4.0), Structures.glow_mat(Color(0.3, 1.0, 0.8), 1.2), Vector3(1, 0.6, 1))
			if st.get("rest", false):
				_rest_point(root.global_position + Basis(Vector3.UP, yaw) * Vector3(2.5, 0, 3.5), "Rest at Wren's hut")
		"corruption":
			Structures.crystal_cluster(root, Vector3.ZERO, Color(0.72, 0.35, 1.0), 11, 5.5, 5, 3.5)
			for i in 6:
				var a := TAU * i / 6.0
				Structures.crystal_cluster(root, Vector3(cos(a) * 9.0, 0, sin(a) * 9.0), Color(0.72, 0.35, 1.0), 4, 1.6, 50 + i)
		"crystal":
			var cc: Array = st.color
			Structures.crystal_cluster(root, Vector3.ZERO, Color(cc[0], cc[1], cc[2]), 8, float(st.size), 17, 3.0)
			for a in [[113, 322], [137, 322], [125, 345]]:
				Structures.standing_stone(self, _g(a), 2.2, 0.0)
		"sinkhole":
			for i in 12:
				var a := TAU * i / 12.0
				Structures.rock(root, "rock_07" if i % 2 == 0 else "rock_09", Vector3(cos(a) * 17.0, -0.5, sin(a) * 17.0), 2.2, a, Color(0.8, 0.8, 0.85))
			for i in 4:
				var a := TAU * i / 4.0 + 0.5
				Structures.burrow(root, Vector3(cos(a) * 8.0, 0.02, sin(a) * 8.0), 1.5)
		"caldor":
			_caldor(root)
		"burrow":
			pass   # the hole itself is the Queen Beneath trigger
		"crater":
			for i in 10:
				var a := TAU * i / 10.0
				Structures.rock(root, "rock_09", Vector3(cos(a) * 14.0, -0.3, sin(a) * 14.0), 2.0, a, Color(0.45, 0.4, 0.38))
			Structures.crystal_cluster(root, Vector3(5, 0, -4), Color(1.0, 0.45, 0.1), 5, 1.5, 70)
		"overlook":
			Structures.box(root, Vector3(4.0, 0.4, 4.0), Vector3(0, 0.2, 0), Structures.old_stone())
			Structures.pillar(root, Vector3(1.6, 0.4, 1.6), 2.5, 0.25)
			Structures.pillar(root, Vector3(-1.6, 0.4, 1.6), 2.5, 0.25)
	named_nodes[st.id] = root


## Sanctuary: a ring of stone walls with a great sealed door facing south and
## an altar inside. The door sinks when the five fragments are set.
func _sanctuary(root: Node3D) -> void:
	var m := Structures.old_stone(Color(0.7, 0.7, 0.75))
	var r := 16.0
	var n := 28
	for i in n:
		var a := TAU * i / n
		var dir := Vector3(sin(a), 0, cos(a))
		if absf(a - 0.0) < 0.2 or absf(a - TAU) < 0.2:
			continue   # the doorway (south, +z)
		Structures.box(root, Vector3(3.8, 6.0, 1.4), dir * r + Vector3(0, 3.0, 0), m, Vector3(0, a, 0), true)
	for i in 8:
		var a := TAU * i / 8.0 + 0.2
		Structures.pillar(root, Vector3(sin(a), 0, cos(a)) * 11.0, 5.5, 0.5)
	Structures.box(root, Vector3(36, 0.3, 36), Vector3(0, 0.05, 0), Structures.tex_mat("cobblestone_floor_05", Color(0.65, 0.65, 0.7), 0.4))
	# The sealed door with its five hollows (where the fragments go).
	sanctuary_door = Node3D.new()
	root.add_child(sanctuary_door)
	sanctuary_door.position = Vector3(0, 0, r)
	Structures.box(sanctuary_door, Vector3(4.6, 6.5, 1.0), Vector3(0, 3.25, 0), Structures.old_stone(Color(0.55, 0.55, 0.62)), Vector3.ZERO, true)
	var colors := [Color(0.4, 1.0, 0.4), Color(0.85, 0.95, 1.0), Color(1.0, 0.4, 0.15), Color(0.3, 1.0, 0.9), Color(1.0, 0.85, 0.35)]
	for i in 5:
		Structures.cyl(sanctuary_door, 0.25, 0.25, 0.1, Vector3(-1.6 + i * 0.8, 4.5, 0.52), Structures.glow_mat(colors[i], 0.3), Vector3(PI * 0.5, 0, 0))
	Structures.box(root, Vector3(8.0, 1.2, 1.6), Vector3(0, 6.6, r), m)
	for sx in [-1.0, 1.0]:
		Structures.box(root, Vector3(1.6, 6.6, 1.8), Vector3(sx * 3.1, 3.3, r), m, Vector3.ZERO, true)
	# Inside: the altar, and glowing veins in the floor.
	Structures.box(root, Vector3(2.2, 1.1, 2.2), Vector3(0, 0.55, 0), Structures.old_stone(Color(0.5, 0.48, 0.55)), Vector3.ZERO, true)
	Structures.crystal_cluster(root, Vector3(0, 1.1, 0), Color(0.75, 0.4, 1.0), 5, 1.2, 3, 2.0)
	for i in 5:
		var a := TAU * i / 5.0
		Structures.box(root, Vector3(0.15, 0.02, 9.0), Vector3(sin(a), 0, cos(a)) * 5.5 + Vector3(0, 0.22, 0), Structures.glow_mat(Color(0.7, 0.4, 1.0), 1.5), Vector3(0, a, 0))
	named_nodes["sanctuary_door"] = sanctuary_door


func _set_door(open: bool) -> void:
	if sanctuary_door == null or open == door_open:
		return
	door_open = open
	var t := create_tween()
	t.tween_property(sanctuary_door, "position:y", -6.8 if open else 0.0, 3.0 if is_inside_tree() else 0.0)
	for c in sanctuary_door.get_children():
		if c is StaticBody3D:
			c.process_mode = Node.PROCESS_MODE_DISABLED if open else Node.PROCESS_MODE_INHERIT
			for sh in c.get_children():
				if sh is CollisionShape3D:
					sh.disabled = open


## Ember temple: a stepped stone platform with walls, an open west door and an inner hall.
func _temple(root: Node3D) -> void:
	var m := Structures.old_stone(Color(0.5, 0.42, 0.38))
	Structures.box(root, Vector3(22, 0.6, 18), Vector3(0, 0.3, 0), m)
	Structures.box(root, Vector3(18, 0.4, 14), Vector3(0, 0.8, 0), m)
	var hw := 7.0
	var hd := 6.0
	Structures.box(root, Vector3(0.9, 5.0, hd * 2), Vector3(hw, 3.5, 0), m, Vector3.ZERO, true)
	Structures.box(root, Vector3(hw * 2, 5.0, 0.9), Vector3(0, 3.5, -hd), m, Vector3.ZERO, true)
	Structures.box(root, Vector3(hw * 2, 5.0, 0.9), Vector3(0, 3.5, hd), m, Vector3.ZERO, true)
	for sz in [-1.0, 1.0]:
		Structures.box(root, Vector3(0.9, 5.0, hd - 1.5), Vector3(-hw, 3.5, sz * (hd * 0.5 + 0.75)), m, Vector3.ZERO, true)
	Structures.box(root, Vector3(hw * 2 + 1, 0.6, hd * 2 + 1), Vector3(0, 6.2, 0), m)
	for sz in [-1.0, 1.0]:
		Structures.pillar(root, Vector3(-hw - 1.6, 1.0, sz * 1.8), 5.0, 0.45, false, m)
		Structures.cyl(root, 0.5, 0.4, 0.8, Vector3(-hw - 1.6, 1.4, sz * 4.0), m)
		Structures.box(root, Vector3(0.5, 0.4, 0.5), Vector3(-hw - 1.6, 2.0, sz * 4.0), Structures.glow_mat(Color(1.0, 0.5, 0.15), 3.0))
	Structures.flame_light(root, Vector3(0, 3.5, 0), Color(1.0, 0.55, 0.25), 1.6, 12.0)
	Structures.crystal_cluster(root, Vector3(-hw - 2.5, 0.6, -5.5), Color(0.7, 0.35, 1.0), 5, 1.6, 13)


## Ruins of Caldor: a courtyard, three halls (west, east, south) and the royal chamber with its sealed door.
func _caldor(root: Node3D) -> void:
	var m := Structures.old_stone(Color(0.7, 0.68, 0.6))
	Structures.box(root, Vector3(40, 0.3, 40), Vector3(0, 0.1, 0), Structures.tex_mat("cobblestone_floor_05", Color(0.55, 0.55, 0.5), 0.4))
	var rr := RandomNumberGenerator.new()
	rr.seed = 1717
	# Royal chamber (centre), door on the north side at z = -9.
	for side in [[Vector3(-6, 0, -9), Vector3(-1.8, 0, -9)], [Vector3(1.8, 0, -9), Vector3(6, 0, -9)], [Vector3(-6, 0, -9), Vector3(-6, 0, 6)],
			[Vector3(6, 0, -9), Vector3(6, 0, 6)], [Vector3(-6, 0, 6), Vector3(6, 0, 6)]]:
		var a: Vector3 = side[0]
		var b: Vector3 = side[1]
		var d := b - a
		Structures.box(root, Vector3(0.9 if absf(d.x) < 0.1 else d.length(), 5.0, 0.9 if absf(d.z) < 0.1 else d.length()), (a + b) * 0.5 + Vector3(0, 2.5, 0), m, Vector3.ZERO, true)
	var door := Node3D.new()
	root.add_child(door)
	door.position = Vector3(0, 0, -9)
	Structures.box(door, Vector3(3.6, 4.6, 0.6), Vector3(0, 2.3, 0), Structures.old_stone(Color(0.5, 0.48, 0.42)), Vector3.ZERO, true)
	named_nodes["caldor_door"] = door
	Structures.box(root, Vector3(1.4, 2.2, 1.0), Vector3(0, 1.1, 4.5), Structures.old_stone(Color(0.15, 0.14, 0.16)), Vector3.ZERO, true)
	# Outbuildings and scattered walls.
	Structures.ruin(root, Vector3(-23, 0, 2), PI * 0.5, 8.0, 21, Color(0.7, 0.68, 0.6))
	Structures.ruin(root, Vector3(23, 0, 2), -PI * 0.5, 8.0, 22, Color(0.7, 0.68, 0.6))
	Structures.ruin(root, Vector3(0, 0, 22), PI, 9.0, 23, Color(0.7, 0.68, 0.6))
	for i in 6:
		var a := rr.randf() * TAU
		Structures.pillar(root, Vector3(cos(a), 0, sin(a)) * rr.randf_range(12.0, 17.0), rr.randf_range(1.5, 4.0), 0.4, true, m)


func _set_caldor_door(open: bool) -> void:
	var d: Node3D = named_nodes.get("caldor_door")
	if d == null:
		return
	d.visible = not open
	for c in d.get_children():
		if c is StaticBody3D:
			for sh in c.get_children():
				if sh is CollisionShape3D:
					sh.disabled = open


# ---------- Rest, board ----------

func _rest_point(pos: Vector3, label: String) -> void:
	var it := Interactable.new(label, 3.0)
	add_child(it)
	it.global_position = pos
	it.action = func(_n: Interactable) -> void: rest_menu("")


## Sleep until a chosen time of day (night-only quests and encounters).
func rest_menu(speaker: String) -> Dictionary:
	var c := {"speaker": speaker, "lines": ["Rest until when?"], "choices": ["Until nightfall", "Until morning", "Don't rest"],
		"on_choice": func(i: int) -> Dictionary:
			if i == 2:
				return {}
			if sky:
				sky.time_of_day = 21.0 if i == 0 else 7.0
			player.health = player.max_health
			player.health_changed.emit(player.health, player.max_health)
			hud.show_banner("You rest...", "It is now " + ("night." if i == 0 else "morning."))
			return {}}
	if speaker == "":
		story.open(c)
	return c


func _inn_rest() -> void:
	pass   # the innkeeper offers rest through services (see world.gd)


func _contract_board() -> void:
	var town: Town = story.town
	if town == null:
		return
	var it := Interactable.new("Read the contract board", 3.0)
	add_child(it)
	it.global_position = town.board_pos
	it.action = func(_n: Interactable) -> void:
		var c := quests.contract_convo("board")
		c["speaker"] = "Contract Board"
		story.open(c)


# ---------- Treasure ----------

func _sync_treasure(t: Dictionary) -> void:
	var opened := state.has_flag("treasure:" + t.id)
	var visible_now := not opened
	if t.kind == "dig" and t.has("needs"):
		visible_now = visible_now and state.count(t.needs) > 0
	if t.has("needs_flag"):
		visible_now = visible_now and state.has_flag(t.needs_flag)
	if visible_now and not chests.has(t.id):
		var label: String = {"dig": "Dig here", "locked": "Open the locked door"}.get(t.kind, "Open the chest")
		var it := Interactable.new(label, 2.6)
		add_child(it)
		it.global_position = _g(t.pos)
		var vis := Node3D.new()
		it.add_child(vis)
		if t.kind == "dig":
			Structures.sphere(vis, 0.6, Vector3(0, 0.05, 0), Structures.tex_mat("dirt_floor", Color(0.5, 0.42, 0.32), 1.0), Vector3(1.3, 0.25, 1.3))
			Structures.box(vis, Vector3(0.08, 0.9, 0.08), Vector3(0.6, 0.45, 0), Structures.wood(), Vector3(0, 0, 0.2))
		elif t.kind == "locked":
			Structures.box(vis, Vector3(1.4, 0.15, 1.2), Vector3(0, 0.08, 0), Structures.wood(Color(0.35, 0.25, 0.18)), Vector3(0.05, 0, 0))
			Structures.box(vis, Vector3(0.2, 0.06, 0.2), Vector3(0, 0.18, 0.3), Structures.plain(Color(0.3, 0.3, 0.32), 0.5, 0.7))
		else:
			Structures.box(vis, Vector3(0.9, 0.55, 0.6), Vector3(0, 0.28, 0), Structures.wood(Color(0.5, 0.35, 0.2)), Vector3.ZERO, true)
			Structures.box(vis, Vector3(0.95, 0.08, 0.65), Vector3(0, 0.58, 0), Structures.plain(Color(0.6, 0.5, 0.25), 0.4, 0.7))
		it.action = func(_n: Interactable) -> void: _open_treasure(t)
		chests[t.id] = it
		if t.kind == "guarded":
			it.enabled = state.has_flag("guard:" + t.id)
	elif not visible_now and chests.has(t.id):
		chests[t.id].queue_free()
		chests.erase(t.id)


func _open_treasure(t: Dictionary) -> void:
	if state.has_flag("treasure:" + t.id):
		return
	if t.kind == "locked" and state.count(t.needs) <= 0:
		story.open({"speaker": "", "lines": ["A heavy cellar door, locked with an iron padlock stamped with a crown."]})
		return
	state.set_flag("treasure:" + t.id)
	player.body.play_once("PickUp_Table", 0.1, 1.2)
	hud.show_banner("Treasure found: " + t.name, "")
	story.open({"speaker": "", "lines": t.get("lines", ["You found treasure!"]), "on_end": func() -> void:
		_loot(t.loot)
		state.add_xp(60)
		refresh()})


## Guardians of guarded treasure wake when the explorer comes near.
func _guardians() -> void:
	for t in cfg.treasures:
		if t.kind != "guarded" or state.has_flag("guard:" + t.id) or state.has_flag("treasure:" + t.id):
			continue
		var p := _g(t.pos)
		if player.global_position.distance_to(p) < 16.0 and not named_nodes.has("guard_" + t.id):
			var g: Dictionary = t.guardian
			var c := spawn_creature(g.species, p + Vector3(2.5, 0, 0), "guard", g.get("elite", {}))
			named_nodes["guard_" + t.id] = c
			hud.toast("Something guards this place!", "warn")
			c.killed.connect(func(_c: Creature) -> void:
				state.set_flag("guard:" + t.id)
				named_nodes.erase("guard_" + t.id)
				if chests.has(t.id):
					chests[t.id].enabled = true
				hud.toast("The way to the treasure is clear", "quest"))


# ---------- Shrines and puzzles ----------

var shrine_nodes := {}


func _sync_shrine(sh: Dictionary) -> void:
	# Rebuilt from the saved flags every time (after loading or a new game).
	if shrine_nodes.has(sh.id):
		var old: Node3D = shrine_nodes[sh.id].get_parent()
		old.queue_free()
		shrine_nodes.erase(sh.id)
	var holder := Node3D.new()
	add_child(holder)
	var root := Node3D.new()
	holder.add_child(root)
	root.global_position = _g(sh.pos)
	shrine_nodes[sh.id] = root
	var m := Structures.old_stone(Color(0.66, 0.66, 0.7))
	Structures.box(root, Vector3(7.0, 0.4, 7.0), Vector3(0, 0.2, 0), m)
	for c in [[-3, -3], [3, -3], [-3, 3], [3, 3]]:
		Structures.pillar(root, Vector3(c[0], 0.4, c[1]), 3.2, 0.3, false, m)
	Structures.box(root, Vector3(7.6, 0.4, 7.6), Vector3(0, 4.1, 0), m)
	Structures.box(root, Vector3(1.2, 2.4, 0.6), Vector3(0, 1.6, -2.4), m, Vector3.ZERO, true)
	var glow := Structures.box(root, Vector3(0.7, 0.7, 0.1), Vector3(0, 2.2, -2.08), Structures.glow_mat(Color(0.6, 0.8, 1.0), 0.4 if not state.has_flag("shrine:" + sh.id) else 3.0))
	glow.name = "Glow"
	Structures.label(root, sh.name, Vector3(0, 3.3, -2.05), 40, Color(0.95, 0.9, 0.8))
	# Hint tablet.
	var hint := Interactable.new("Read the carving", 2.4)
	root.add_child(hint)
	hint.position = Vector3(0, 0.4, -1.6)
	hint.action = func(_n: Interactable) -> void: story.open({"speaker": sh.name, "lines": [sh.hint]})
	if state.has_flag("shrine:" + sh.id):
		_shrine_reward(sh, root)
		return
	var solved := func() -> void: _solve_shrine(sh)
	match sh.puzzle:
		"order":
			var stones := []
			for i in sh.glyphs.size():
				var a: float = TAU * i / sh.glyphs.size() + PI * 0.25
				stones.append([sh.pos[0] + cos(a) * 6.0, sh.pos[1] + sin(a) * 6.0])
			_order_puzzle(sh.id, stones, sh.glyphs, sh.order, solved, root)
		"align":
			_align_puzzle(sh, solved, root)
		"switches":
			_switch_puzzle(sh, solved, root)
		"components":
			_components_puzzle(sh, solved, root)
		"guardian":
			root.set_meta("guardian", sh.guardian)
		"route":
			_route_puzzle(sh, solved, root)


func _solve_shrine(sh: Dictionary) -> void:
	if state.has_flag("shrine:" + sh.id):
		return
	state.set_flag("shrine:" + sh.id)
	var root: Node3D = shrine_nodes[sh.id]
	var g := root.get_node_or_null("Glow") as MeshInstance3D
	if g:
		g.material_override = Structures.glow_mat(Color(0.6, 0.8, 1.0), 3.0)
	hud.show_banner(sh.name + " awakened", "Shrine puzzle solved")
	state.add_xp(150)
	_shrine_reward(sh, root)


func _shrine_reward(sh: Dictionary, root: Node3D) -> void:
	if state.has_flag("shrine_loot:" + sh.id):
		return
	var it := Interactable.new("Open the shrine's offering chest", 2.6)
	root.add_child(it)
	it.position = Vector3(0, 0.4, 0)
	Structures.box(it, Vector3(0.9, 0.55, 0.6), Vector3(0, 0.28, 0), Structures.wood(Color(0.45, 0.4, 0.5)))
	Structures.box(it, Vector3(0.95, 0.08, 0.65), Vector3(0, 0.58, 0), Structures.glow_mat(Color(0.6, 0.8, 1.0), 1.0))
	it.action = func(n: Interactable) -> void:
		if state.has_flag("shrine_loot:" + sh.id):
			return
		state.set_flag("shrine_loot:" + sh.id)
		_loot(sh.loot)
		n.queue_free()


## Stones with words on them; touch them in the right order. A wrong touch resets.
func _order_puzzle(id: String, spots: Array, glyphs: Array, order_in: Array, on_solved: Callable, parent: Node3D, landmarks := false) -> Array:
	var order: Array = []
	for v in order_in:
		order.append(int(v))
	var nodes := []
	var pressed := []
	var lights := []
	for i in spots.size():
		var it := Interactable.new("Touch the %s stone" % glyphs[i] if not landmarks else "Visit: %s" % glyphs[i], 2.8 if not landmarks else 4.0)
		parent.add_child(it)
		it.global_position = _g(spots[i])
		if not landmarks:
			Structures.standing_stone(it, Vector3.ZERO, 2.0, 0.0)
		var l := Structures.label(it, glyphs[i], Vector3(0, 2.3 if not landmarks else 3.0, 0), 64, Color(0.9, 0.9, 0.95))
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lights.append(l)
		var idx := i
		it.action = func(_n: Interactable) -> void:
			if idx in pressed:
				return
			if order[pressed.size()] == idx:
				pressed.append(idx)
				l.modulate = Color(0.4, 1.0, 0.5)
				hud.toast("%s... (%d/%d)" % [glyphs[idx], pressed.size(), order.size()], "quest")
				if pressed.size() == order.size():
					state.set_flag("puzzle:" + id)
					on_solved.call()
			else:
				pressed.clear()
				for ll in lights:
					ll.modulate = Color(0.9, 0.9, 0.95)
				hud.toast("The stones go dark. Wrong order.", "warn")
		nodes.append(it)
	return nodes


## Rotating stones: each use turns to the next word; solved when all match the plaque.
func _align_puzzle(sh: Dictionary, on_solved: Callable, root: Node3D) -> void:
	var symbols: Array = sh.symbols
	var target: Array = []
	for v in sh.target:
		target.append(int(v))
	var cur := []
	var labels := []
	for i in int(sh.rings):
		cur.append((target[i] + 1 + i) % symbols.size())
		var it := Interactable.new("Turn the stone drum", 2.4)
		root.add_child(it)
		it.position = Vector3(-2.2 + i * 2.2, 0.4, 1.6)
		Structures.cyl(it, 0.6, 0.6, 1.4, Vector3(0, 0.7, 0), Structures.old_stone(Color(0.6, 0.62, 0.7)), Vector3.ZERO, true, 8)
		var l := Structures.label(it, symbols[cur[i]], Vector3(0, 1.8, 0), 64)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		labels.append(l)
		var idx := i
		it.action = func(_n: Interactable) -> void:
			if state.has_flag("shrine:" + sh.id):
				return
			cur[idx] = (cur[idx] + 1) % symbols.size()
			labels[idx].text = symbols[cur[idx]]
			for k in cur.size():
				if cur[k] != target[k]:
					return
			on_solved.call()


func _switch_puzzle(sh: Dictionary, on_solved: Callable, root: Node3D) -> void:
	var pulled := [0]
	for s in sh.switches:
		var it := Interactable.new("Pull the hidden lever", 2.2)
		root.get_parent().add_child(it)
		it.global_position = _g(s)
		Structures.box(it, Vector3(0.3, 0.3, 0.3), Vector3(0, 0.15, 0), Structures.old_stone(Color(0.5, 0.5, 0.5)))
		var lever := Structures.cyl(it, 0.04, 0.04, 0.7, Vector3(0, 0.5, 0), Structures.plain(Color(0.35, 0.3, 0.25), 0.6, 0.5), Vector3(0.6, 0, 0))
		Structures.rock(it, "rock_07", Vector3(0.8, -0.2, 0.6), 0.8, 0.5)
		it.action = func(n: Interactable) -> void:
			if not n.enabled:
				return
			n.enabled = false
			lever.rotation.x = -0.6
			pulled[0] += 1
			hud.toast("Click. Something shifts in the shrine. (%d/%d)" % [pulled[0], sh.switches.size()], "quest")
			if pulled[0] >= sh.switches.size():
				on_solved.call()


func _components_puzzle(sh: Dictionary, on_solved: Callable, root: Node3D) -> void:
	var key: String = "shrine_parts:" + sh.id
	for i in sh.parts.size():
		if state.has_flag("%s:%d" % [key, i]):
			continue
		var it := Interactable.new("Pick up the shrine shard", 2.2)
		root.get_parent().add_child(it)
		it.global_position = _g(sh.parts[i])
		var vis := Node3D.new()
		it.add_child(vis)
		Structures.prism(vis, Vector3(0.3, 0.45, 0.12), Vector3.ZERO, Structures.glow_mat(Color(0.6, 0.85, 1.0), 2.0))
		it.visual = vis
		it.bob = true
		var idx: int = i
		it.action = func(n: Interactable) -> void:
			state.set_flag("%s:%d" % [key, idx])
			state.add_item("shrine_shard", 1)
			n.queue_free()
	var socket := Interactable.new("Set the shards in the shrine", 2.6)
	root.add_child(socket)
	socket.position = Vector3(0, 0.4, -1.8)
	socket.action = func(_n: Interactable) -> void:
		if state.count("shrine_shard") >= sh.parts.size():
			state.remove_item("shrine_shard", sh.parts.size())
			on_solved.call()
		else:
			story.open({"speaker": sh.name, "lines": ["The lens has %d empty slots. You carry %d shard(s)." % [sh.parts.size(), state.count("shrine_shard")]]})


func _route_puzzle(sh: Dictionary, on_solved: Callable, root: Node3D) -> void:
	# A wall of rock seals the shrine's inner niche until the hollow plate is pressed.
	var wall := Node3D.new()
	root.add_child(wall)
	Structures.box(wall, Vector3(7.4, 3.6, 0.8), Vector3(0, 2.2, 3.6), Structures.tex_mat("rock_face_03", Color(0.7, 0.7, 0.72), 0.35), Vector3.ZERO, true)
	Structures.box(wall, Vector3(0.8, 3.6, 7.4), Vector3(-3.6, 2.2, 0), Structures.tex_mat("rock_face_03", Color(0.7, 0.7, 0.72), 0.35), Vector3.ZERO, true)
	Structures.box(wall, Vector3(0.8, 3.6, 7.4), Vector3(3.6, 2.2, 0), Structures.tex_mat("rock_face_03", Color(0.7, 0.7, 0.72), 0.35), Vector3.ZERO, true)
	var plate := Interactable.new("Press on the hollow-sounding stone", 2.0)
	root.get_parent().add_child(plate)
	plate.global_position = _g(sh.plate)
	Structures.box(plate, Vector3(1.0, 0.08, 1.0), Vector3(0, 0.04, 0), Structures.old_stone(Color(0.55, 0.55, 0.5)))
	plate.action = func(n: Interactable) -> void:
		n.enabled = false
		var tw := create_tween()
		tw.tween_property(wall, "position:y", -4.0, 2.5)
		for b in wall.find_children("*", "CollisionShape3D", true, false):
			b.disabled = true
		hud.toast("Stone grinds on stone: a passage opens!", "quest")
		on_solved.call()


## Guardian shrines wake their guardian when the explorer comes close.
func _shrine_guardians() -> void:
	for sh in cfg.shrines:
		if sh.puzzle != "guardian" or state.has_flag("shrine:" + sh.id):
			continue
		var root: Node3D = shrine_nodes.get(sh.id)
		if root == null or named_nodes.has("guard_" + sh.id):
			continue
		if player.global_position.distance_to(root.global_position) < 18.0:
			var g: Dictionary = sh.guardian
			var c := spawn_creature(g.species, root.global_position + Vector3(0, 0, 5), "guard", g.get("elite", {}))
			named_nodes["guard_" + sh.id] = c
			hud.show_banner(g.get("elite", {}).get("name", "Guardian"), sh.name)
			c.killed.connect(func(_c: Creature) -> void:
				named_nodes.erase("guard_" + sh.id)
				_solve_shrine(sh))


# ---------- Fragment trials and Caldor's keys ----------

func _sync_trials() -> void:
	var want := {}
	if quests.status("five_fragments") == "active" and quests.q["five_fragments"].step == 0:
		for f in cfg.fragments:
			if state.count(f.id) == 0 and not state.has_flag("fragment:" + f.id):
				want[f.id] = f
	var caldor_step: int = quests.q["forgotten_kingdom"].step if quests.q.has("forgotten_kingdom") else -1
	var caldor_active: bool = quests.status("forgotten_kingdom") == "active" and caldor_step >= 3
	_set_caldor_door(quests.status("forgotten_kingdom") == "completed" or caldor_step >= 5)
	if caldor_active and caldor_step == 3:
		for k in [["sun_key", "order"], ["moon_key", "switches"], ["star_key", "guardian"]]:
			if state.count(k[0]) == 0 and not state.has_flag("got:" + k[0]):
				want[k[0]] = {"id": k[0], "kind": "caldor_" + k[1]}
	for id in trial_nodes.keys():
		if not want.has(id):
			for n in trial_nodes[id]:
				if is_instance_valid(n):
					n.queue_free()
			trial_nodes.erase(id)
	for id in want:
		if not trial_nodes.has(id):
			trial_nodes[id] = _build_trial(want[id])


func _give_fragment_at(id: String, pos: Array) -> Interactable:
	var it := Interactable.new("Take the " + state.item_name(id), 2.4)
	add_child(it)
	it.global_position = _g(pos)
	var vis := Node3D.new()
	it.add_child(vis)
	Structures.prism(vis, Vector3(0.3, 0.5, 0.15), Vector3.ZERO, Structures.glow_mat(Color(1.0, 0.9, 0.5), 2.5))
	it.visual = vis
	it.bob = true
	it.action = func(n: Interactable) -> void:
		state.set_flag("fragment:" + id)
		state.set_flag("got:" + id)
		state.add_item(id, 1)
		hud.show_banner(state.item_name(id), "Ancient fragment recovered")
		n.queue_free()
	return it


func _build_trial(f: Dictionary) -> Array:
	var nodes := []
	var holder := Node3D.new()
	add_child(holder)
	nodes.append(holder)
	if f.has("clue"):
		var clue := Interactable.new("Read the Warden stone", 2.6)
		holder.add_child(clue)
		clue.global_position = _g(f.clue)
		if f.id != "fragment_town":
			Structures.tablet(clue, Vector3(0, 0, -0.8), 0.0, Color(0.7, 0.85, 1.0))
		clue.action = func(_n: Interactable) -> void:
			state.set_flag("clue:" + f.id)
			story.open({"speaker": "", "lines": f.clue_text})
	var done := func(at: Array) -> void:
		nodes.append(_give_fragment_at(f.id, at))
	match f.kind:
		"order":
			nodes += _order_puzzle(f.id, f.stones, f.get("glyphs", ["I", "II", "III"]), f.order,
				func() -> void: done.call(f.reward_pos), holder, f.get("landmarks", false))
		"guardian":
			var b := spawn_boss(f.boss, Vector3(f.boss_pos[0], 0, f.boss_pos[1]), "trial")
			if b:
				nodes.append(b)
				b.killed.connect(func(_c: Creature) -> void: state.set_flag("fragment:" + f.id))
		"hidden":
			# Moths: a trail of little lights; the last leads into the grotto.
			for i in f.path.size():
				var moth := OmniLight3D.new()
				moth.light_color = Color(0.5, 1.0, 0.9)
				moth.light_energy = 2.0
				moth.omni_range = 4.0
				holder.add_child(moth)
				moth.global_position = _g(f.path[i]) + Vector3(0, 1.6, 0)
				Structures.sphere(moth, 0.08, Vector3.ZERO, Structures.glow_mat(Color(0.6, 1.0, 0.9), 4.0))
			done.call(f.reward_pos)
		"caldor_order":
			var c0: Vector3 = named_nodes["caldor"].global_position
			var spots := []
			for i in 4:
				spots.append([c0.x - 23.0 + (i % 2) * 3.0 - 1.5, c0.z + 2.0 + (i / 2) * 3.0 - 1.5])
			nodes += _order_puzzle("caldor_sun", spots, ["DAWN", "NOON", "DUSK", "NIGHT"], [0, 1, 2, 3],
				func() -> void: nodes.append(_key_chest(f.id, [c0.x - 23.0, c0.z + 5.5])), holder)
			var hint := Interactable.new("Read the inscription", 2.4)
			holder.add_child(hint)
			hint.global_position = _g([c0.x - 26.0, c0.z + 2.0])
			hint.action = func(_n: Interactable) -> void: story.open({"speaker": "", "lines": ["'The sun rises in order: from first light to last.'"]})
		"caldor_switches":
			var c1: Vector3 = named_nodes["caldor"].global_position
			var sh := {"id": "caldor_moon", "switches": [[c1.x + 26.0, c1.z - 1.0], [c1.x + 21.0, c1.z + 7.0], [c1.x + 18.5, c1.z - 4.0]]}
			var sub := Node3D.new()
			holder.add_child(sub)
			_switch_puzzle(sh, func() -> void: nodes.append(_key_chest(f.id, [c1.x + 23.0, c1.z + 2.0])), sub)
		"caldor_guardian":
			var c2: Vector3 = named_nodes["caldor"].global_position
			var g := spawn_creature("lava_golem", c2 + Vector3(0, 0, 22), "guard", {"tint": [1.0, 0.85, 0.4], "health": 1.6, "scale": 1.2, "name": "Star Warden"})
			nodes.append(g)
			g.killed.connect(func(_c: Creature) -> void: _give_key(f.id))
	return nodes


func _key_chest(key: String, pos: Array) -> Interactable:
	var it := Interactable.new("Open the chest", 2.4)
	add_child(it)
	it.global_position = _g(pos)
	Structures.box(it, Vector3(0.8, 0.5, 0.55), Vector3(0, 0.25, 0), Structures.wood(Color(0.45, 0.35, 0.25)))
	it.action = func(n: Interactable) -> void:
		_give_key(key)
		n.queue_free()
	return it


func _give_key(key: String) -> void:
	if state.has_flag("got:" + key):
		return
	state.set_flag("got:" + key)
	state.add_item(key, 1)
	hud.show_banner(state.item_name(key), "Ruins of Caldor")


# ---------- The peaceful golem ----------

func _sync_ashwarden() -> void:
	var want: bool = quests.status("golems_secret") in ["available", "active"] or quests.status("golems_secret") == "completed"
	if want and not named_nodes.has("ashwarden"):
		var sc: Dictionary = species.lava_golem.duplicate(true)
		sc.temper = "flee"
		sc.flee_radius = -1.0
		sc.calm_radius = 0.0
		sc.wander_radius = 10.0
		sc.graze_chance = 0.6
		sc.fights_back = false
		var c := Creature.new()
		add_child(c)
		c.setup(sc, 55)
		c.home = Vector3(233, 0, -107)
		c.height_at = func(x: float, z: float) -> float: return data.height(x, z)
		c.global_position = _g([233, -107])
		c.threat = player
		c.remove_from_group("creatures")   # never a target, never in a fight
		c.mat.set_shader_parameter("glow_color", Color(0.4, 1.0, 0.5))
		var l := Structures.label(c, "Ashwarden", Vector3(0, 2.8, 0), 56, Color(0.6, 1.0, 0.6))
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		named_nodes["ashwarden"] = c


# ---------- Rare bosses ----------

func _rare_bosses() -> void:
	for rb in cfg.rare_bosses:
		if state.has_flag("boss:" + rb.id):
			continue
		var p := _g(rb.pos)
		var d := player.global_position.distance_to(p)
		if d < 70.0 and not bosses.has(rb.id):
			bosses[rb.id] = spawn_boss(rb.id, p, "rare")
		elif d > 110.0 and bosses.has(rb.id) and is_instance_valid(bosses[rb.id]) and bosses[rb.id].alive():
			bosses[rb.id].unique = true
			bosses[rb.id].queue_free()
			bosses.erase(rb.id)


## Boss health bar for the nearest boss that's fighting the explorer.
func _boss_bar() -> void:
	var best: Boss = null
	var bd := 45.0
	for b in get_tree().get_nodes_in_group("bosses"):
		if not is_instance_valid(b) or not b.alive() or not b.is_inside_tree():
			continue
		var d: float = b.global_position.distance_to(player.global_position)
		if d < bd and (b.engaged or d < 25.0):
			bd = d
			best = b
	if best:
		if not best.has_meta("announced"):
			best.set_meta("announced", true)
			hud.show_banner(best.title, "")
		hud.show_boss(best.title, best.fraction())
	else:
		hud.hide_boss()


# ---------- Discoveries ----------

func _discoveries() -> void:
	for d in cfg.discoveries:
		if discovered.get(d.id, false):
			continue
		if Vector2(player.global_position.x - d.pos[0], player.global_position.z - d.pos[1]).length() < float(d.radius):
			discovered[d.id] = true
			state.set_flag("disc:" + d.id)
			hud.show_banner("Discovered: " + d.name, "")
			state.add_xp(int(d.get("xp", 30)))
			if d.has("coins"):
				state.add_coins(int(d.coins))
			if d.has("lines") and not story.in_dialogue():
				story.open({"speaker": "", "lines": d.lines})


# ---------- World events ----------

func _events(dt: float) -> void:
	if not event.is_empty():
		_event_update(dt)
		return
	event_timer -= dt
	if event_timer > 0.0:
		return
	var ev: Dictionary = cfg.events
	event_timer = rng.randf_range(ev.every[0], ev.every[1])
	# Never during a quest battle, a boss fight or a conversation.
	if story.in_dialogue() or hud.boss_box.visible:
		return
	for id in quests.active_ids():
		var st := quests.current_step(id)
		for g in Quests.goals_of(st):
			if g.type in ["defend", "boss"]:
				return
	start_event(ev.types[rng.randi() % ev.types.size()].id)


## Starts a world event by id (also used by tests). Returns false if it can't run here.
func start_event(id: String) -> bool:
	var t: Dictionary = {}
	for e in cfg.events.types:
		if e.id == id:
			t = e
	if t.is_empty():
		return false
	var p := player.global_position
	event = {"id": id, "t": 0.0, "def": t}
	match id:
		"raid", "hub_raid":
			var site: Array = _nearest(t.sites, p)
			if Vector2(site[0] - p.x, site[1] - p.z).length() > 120.0:
				event = {}
				return false
			for grp in t.groups:
				for i in int(grp[1]):
					var c := spawn_creature(grp[0], _g(site) + Vector3(i * 2.0, 0, i * 1.5), "raid:event")
					if c:
						c.cfg = c.cfg.duplicate()
						c.cfg.aggro_radius = 40.0
						event_nodes.append(c)
			event["pos"] = site
		"merchant":
			var site2: Array = _nearest(t.sites, p)
			var v := story.spawn_villager({"id": "zara", "name": "Zara the Wayfarer", "role": "merchant", "shop": "travelling", "mode": "work", "face": 0,
				"home": site2, "outfit": {"model": "female", "jacket": [0.6, 0.2, 0.45], "pants": [0.3, 0.25, 0.3], "boots": [0.25, 0.17, 0.1], "hair": [0.1, 0.07, 0.05],
				"accessories": ["hat", "satchel"], "hat_color": [0.35, 0.15, 0.3]}, "lines": {"default": ["Rare goods from across the sea! Only while I'm here, friend."]}}, 777)
			event_nodes.append(v)
			event["pos"] = site2
			var w := Structures.wagon(self, _g(site2) + Vector3(2.5, 0, 1.0), 0.8, false)
			event_nodes.append(w)
		"rare":
			var opts: Array = t.options
			var pick: Dictionary = opts[rng.randi() % opts.size()]
			if pick.get("night", false) and not quests._is_night():
				pick = opts[0]
			var c2 := spawn_creature(pick.species, _g(pick.where), "rare", pick.elite)
			if c2:
				event_nodes.append(c2)
				var loot: Dictionary = pick.loot
				c2.killed.connect(func(_c: Creature) -> void:
					_loot(loot)
					state.add_xp(120)
					hud.show_banner(pick.elite.name + " defeated", "Rare creature"))
			event["pos"] = pick.where
			t = t.duplicate()
			t.name = "Rare creature sighted: " + pick.elite.name
		"crystal_surge", "volcanic":
			for i in int(t.count):
				var a := rng.randf() * TAU
				var r := rng.randf_range(4.0, 18.0)
				var at := [t.centre[0] + cos(a) * r, t.centre[1] + sin(a) * r]
				var it := Interactable.new("Gather " + state.item_name(t.item), 2.4)
				add_child(it)
				it.global_position = _g(at)
				var vis := Node3D.new()
				it.add_child(vis)
				it.visual = vis
				it.bob = true
				Structures.prism(vis, Vector3(0.3, 0.5, 0.2), Vector3.ZERO, Structures.glow_mat(Color(0.3, 1.0, 0.8) if id == "crystal_surge" else Color(1.0, 0.4, 0.1), 2.5))
				var item: String = t.item
				it.action = func(n: Interactable) -> void:
					state.add_item(item, 1)
					n.queue_free()
				event_nodes.append(it)
			event["pos"] = t.centre
		"traveller":
			var site3: Array = _nearest(t.sites, p)
			var v2 := story.spawn_villager({"id": "lost_traveller", "name": "Injured Traveller", "role": "traveller", "mode": "sit", "face": 0, "home": site3,
				"outfit": {"model": "male", "jacket": [0.4, 0.38, 0.3], "pants": [0.3, 0.28, 0.25], "boots": [0.22, 0.15, 0.1], "hair": [0.3, 0.2, 0.1], "accessories": ["satchel"]},
				"lines": {"default": ["Please... I was attacked on the road. Do you have a healing draught?"]}}, 778)
			event_nodes.append(v2)
			event["pos"] = site3
	hud.show_banner(t.name, t.get("region", ""))
	return true


func _nearest(sites: Array, p: Vector3) -> Array:
	var best: Array = sites[0]
	for s in sites:
		if Vector2(s[0] - p.x, s[1] - p.z).length() < Vector2(best[0] - p.x, best[1] - p.z).length():
			best = s
	return best


func _event_update(dt: float) -> void:
	event.t += dt
	var t: Dictionary = event.def
	var done := false
	match event.id:
		"raid", "hub_raid":
			var alive := 0
			for c in event_nodes:
				if is_instance_valid(c) and c is Creature and c.alive():
					alive += 1
			if alive == 0:
				_loot(t.reward)
				state.add_xp(int(t.reward.get("xp", 60)))
				hud.show_banner("Attack repelled!", "")
				done = true
		"merchant", "crystal_surge", "volcanic":
			if event.t > float(t.get("duration", 200)):
				done = true
			if event.id == "volcanic" and int(event.t) % 6 == 0 and event.t - floor(event.t) < dt and player.global_position.distance_to(_g(t.centre)) < 40.0:
				_ember_rain()
		"rare":
			var any := false
			for c in event_nodes:
				if is_instance_valid(c) and c is Creature and c.alive():
					any = true
			done = not any or event.t > 400.0
		"traveller":
			done = event.t > 400.0 or event.get("helped", false)
	if event.has("pos") and player.global_position.distance_to(_g(event.pos)) > 200.0 and event.t > 30.0:
		done = true
	if done:
		end_event()


## Glowing embers fall around the explorer; each marks where it will land.
func _ember_rain() -> void:
	for i in 3:
		var s := Boss.Shard.new()
		var tp := player.global_position + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6))
		tp.y = data.height(tp.x, tp.z)
		s.from = tp + Vector3(rng.randf_range(-8, 8), 25, rng.randf_range(-8, 8))
		s.to = tp
		s.delay = i * 0.4
		s.flight = 1.6
		s.radius = 1.5
		s.damage = 8.0
		s.element = "fire"
		s.threat = player
		s.color = Color(1.0, 0.45, 0.1)
		add_child(s)


func end_event() -> void:
	for n in event_nodes:
		if not is_instance_valid(n):
			continue
		if n is Villager:
			story.remove_villager(n.id)
		elif n is Creature:
			if n.alive():
				n.queue_free()
		else:
			n.queue_free()
	event_nodes.clear()
	event = {}


## The injured traveller: give a potion to help (services call this).
func help_traveller() -> Dictionary:
	if state.count("potion") + state.count("elixir") == 0:
		return {"lines": ["You have nothing to give. Maybe a merchant has a healing draught."]}
	return {"lines": ["You kneel and hand over a healing draught."], "on_end": func() -> void:
		if state.count("potion") > 0:
			state.remove_item("potion")
		else:
			state.remove_item("elixir")
		event["helped"] = true
		_loot(event.def.reward)
		state.add_xp(int(event.def.reward.get("xp", 90)))
		state.add_reputation(5)
		hud.show_banner("Traveller helped", "They limp off toward town, thanking you.")}


# ---------- Per-frame ----------

func _process(delta: float) -> void:
	if player == null:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	_discoveries()
	_guardians()
	_shrine_guardians()
	_rare_bosses()
	_boss_bar()
	_sync_trials()
	_sync_ashwarden()
	_events(0.5)
	for t in cfg.treasures:
		if t.kind == "dig" or t.has("needs_flag"):
			_sync_treasure(t)
	_set_door(state.has_flag("sanctuary_open") or quests.status("five_fragments") == "completed")
	# Forget finished creatures so the list doesn't grow.
	var keep: Array[Creature] = []
	for c in spawned:
		if is_instance_valid(c):
			keep.append(c)
	spawned = keep


## Positions of places for the map: [name, Vector2, known].
func map_points() -> Array:
	var out := []
	var compass := state.count("explorer_compass") > 0
	for d in cfg.discoveries:
		var known: bool = discovered.get(d.id, false)
		if known or not d.get("hidden", false) or compass:
			out.append([d.name, Vector2(d.pos[0], d.pos[1]), known])
	for sh in cfg.shrines:
		out.append([sh.name, Vector2(sh.pos[0], sh.pos[1]), state.has_flag("shrine:" + sh.id)])
	return out
