class_name Interiors
extends Node3D
## Furnishes Brickton's walk-in houses and works their doors. Each building
## gets a room that fits what it is: homes (bed, table, hearth, chests),
## Tilly's shop (counter, shelves of goods), the Brickton Arms tavern (bar,
## kegs, tables, guest rooms), Bram's smithy (forge, anvil, tools), the
## carpenter's and tanner's workshops and the town hall. Layout details vary
## per house (seeded). Furniture and the room light are built only while you
## are near (and freed when you leave) so phones keep their memory and only a
## few lights are ever on. Doors: walk up and use the prompt to open or close.

const NEAR := 28.0
const FAR := 45.0

var data: WorldData
var village: Village
var player: Node3D
## Plays a sound effect (name, dB), wired by the world.
var play_sfx: Callable = Callable()
## Called when the player sleeps in their own bed (see Expansion.rest).
var on_rest: Callable = Callable()
## kind per building index ("house", "inn", "shop", "hall", "workshop", "smithy").
var kinds: Array[String] = []
var _built := {}          # building index -> interior root
var _check := 0.0
var _night := 0.0


func setup(world_data: WorldData, v: Village, p: Node3D) -> void:
	data = world_data
	village = v
	player = p
	# Bram works at the anvil in the street; the house behind him is his smithy.
	var smith_at := Vector2(-255, -6)
	var smithy := -1
	var best := INF
	for i in village.buildings.size():
		var h: Dictionary = village.buildings[i].h
		kinds.append(str(h.get("kind", "house")))
		var dd := Vector2(h.x, h.z).distance_to(smith_at)
		if kinds[i] == "house" and dd < best:
			best = dd
			smithy = i
	if smithy >= 0:
		kinds[smithy] = "smithy"
		village.buildings[smithy].h["name"] = "Bram's Smithy"
	for i in village.buildings.size():
		_add_door_prompt(i)


func set_night(amount: float) -> void:
	_night = amount
	for i in _built:
		var l: OmniLight3D = _built[i].get_meta("light")
		l.light_energy = lerpf(0.6, 1.4, amount)


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0 or player == null:
		return
	_check = 0.5
	for i in village.buildings.size():
		var root: Node3D = village.buildings[i].root
		var d := root.global_position.distance_to(player.global_position)
		if d < NEAR and not _built.has(i):
			_built[i] = furnish(i)
		elif d > FAR and _built.has(i):
			_built[i].queue_free()
			_built.erase(i)


# ---------- Doors ----------

func _add_door_prompt(i: int) -> void:
	var b: Dictionary = village.buildings[i]
	var it := Interactable.new("Open the door", 2.4)
	b.root.add_child(it)
	it.position = b.door_local + Vector3(0, 0, 0.5)
	it.action = func(_n: Interactable) -> void: toggle_door(i)
	b["prompt"] = it


## Opens or closes building i's door (swings into the room). Returns true when now open.
func toggle_door(i: int) -> bool:
	var b: Dictionary = village.buildings[i]
	var hinge: Node3D = b.door
	var open := not bool(b.get("open", false))
	b["open"] = open
	var tw := create_tween()
	tw.tween_property(hinge, "rotation:y", deg_to_rad(100.0) if open else 0.0, 0.6).set_trans(Tween.TRANS_SINE)
	(b.prompt as Interactable).label = "Close the door" if open else "Open the door"
	if play_sfx.is_valid():
		play_sfx.call("door", -8.0)
	return open


## World point just inside building i's door (floor level).
func inside_point(i: int) -> Vector3:
	var b: Dictionary = village.buildings[i]
	return b.root.to_global(b.door_local + Vector3(0, 0.05, -1.4))


## Index of the building whose name (or kind) matches, or -1.
func find(name_or_kind: String) -> int:
	for i in village.buildings.size():
		if str(village.buildings[i].h.get("name", "")) == name_or_kind or kinds[i] == name_or_kind:
			return i
	return -1


# ---------- Furnishing ----------

## Builds the furniture and light inside building i. Returns its root.
func furnish(i: int) -> Node3D:
	var b: Dictionary = village.buildings[i]
	var root := Node3D.new()
	root.name = "Interior"
	b.root.add_child(root)
	root.position.y = Village.FLOOR_Y
	var w: float = b.w - Village.WALL * 2.0
	var d: float = b.d - Village.WALL * 2.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(b.h.x) + str(b.h.z))
	var door_x: float = b.door_local.x
	match kinds[i]:
		"inn":
			_tavern(root, w, d, door_x, rng)
		"shop":
			_shop(root, w, d, door_x, rng)
		"smithy":
			_smithy(root, w, d, door_x, rng)
		"workshop":
			_workshop(root, w, d, door_x, rng, str(b.h.get("name", "")))
		"hall":
			_hall(root, w, d, door_x, rng)
		"player_house":
			_player_house(root, w, d, door_x, rng)
		_:
			_home(root, w, d, door_x, rng)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.48)
	light.omni_range = maxf(w, d) * 0.9
	light.light_energy = lerpf(0.6, 1.4, _night)
	light.shadow_enabled = false
	light.position = Vector3(0, 2.4, 0)
	root.add_child(light)
	root.set_meta("light", light)
	return root


# Material shortcuts (cached by Structures/village).
func _wood(tint := Color(0.55, 0.4, 0.28)) -> Material:
	return village._tex_mat("weathered_brown_planks", tint, 0.9)


func _cloth(c: Color) -> Material:
	return Structures.plain(c, 0.95)


func _home(root: Node3D, w: float, d: float, door_x: float, rng: RandomNumberGenerator) -> void:
	var back := -d * 0.5
	var quilt: Color = [Color(0.55, 0.2, 0.18), Color(0.25, 0.35, 0.55), Color(0.35, 0.45, 0.28), Color(0.6, 0.5, 0.3)][rng.randi() % 4]
	Furniture.fireplace(root, Vector3(-w * 0.2, 0, back + 0.45), 0.0, village)
	Furniture.bed(root, Vector3(w * 0.5 - 1.1, 0, back + 1.2), 0.0, quilt, _wood())
	if w > 8.0 and rng.randf() < 0.6:
		Furniture.bed(root, Vector3(w * 0.5 - 1.1, 0, back + 3.4), 0.0, quilt.darkened(0.2), _wood(), 0.8)
	Furniture.table(root, Vector3(-w * 0.15, 0, d * 0.05), rng.randf_range(-0.2, 0.2), _wood(), rng.randi_range(2, 4))
	Furniture.chest(root, Vector3(w * 0.5 - 0.6, 0, d * 0.5 - 1.6), -PI * 0.5, _wood(Color(0.45, 0.3, 0.2)))
	Furniture.shelf(root, Vector3(-w * 0.5 + 0.3, 0, -d * 0.1), PI * 0.5, _wood(), rng, ["jars", "pots"][rng.randi() % 2])
	Furniture.rug(root, Vector3(0, 0, d * 0.05), Vector2(2.4, 1.6), quilt.lightened(0.15))
	if rng.randf() < 0.5:
		Structures.barrel(root, Vector3(-w * 0.5 + 0.6, 0, d * 0.5 - 0.8))


func _tavern(root: Node3D, w: float, d: float, door_x: float, rng: RandomNumberGenerator) -> void:
	var back := -d * 0.5
	# Guest rooms behind a timber partition across the back third.
	var part_z := back + d * 0.36
	var timber := _wood(Color(0.42, 0.3, 0.2))
	for seg in [[-w * 0.5, -w * 0.12], [-w * 0.12 + 1.1, w * 0.18], [w * 0.18 + 1.1, w * 0.5]]:
		var len: float = seg[1] - seg[0]
		Structures.box(root, Vector3(len, 2.6, 0.12), Vector3(seg[0] + len * 0.5, 1.3, part_z), timber, Vector3.ZERO, true)
	Structures.box(root, Vector3(0.12, 2.6, part_z - back), Vector3(w * 0.03, 1.3, (part_z + back) * 0.5), timber, Vector3.ZERO, true)
	Furniture.bed(root, Vector3(-w * 0.5 + 1.0, 0, back + 1.0), PI * 0.5, Color(0.5, 0.22, 0.2), _wood())
	Furniture.bed(root, Vector3(w * 0.5 - 1.0, 0, back + 1.0), -PI * 0.5, Color(0.25, 0.32, 0.5), _wood())
	Structures.label(root, "Rooms", Vector3(-w * 0.12 + 0.55, 2.45, part_z + 0.08), 28)
	# The bar along the right wall, kegs and bottles behind it.
	Furniture.bar(root, Vector3(w * 0.5 - 1.4, 0, part_z + 2.2), PI * 0.5, 3.6, _wood(Color(0.4, 0.26, 0.16)))
	for k in 3:
		Furniture.keg(root, Vector3(w * 0.5 - 0.45, 0, part_z + 0.8 + k * 1.1))
	Furniture.shelf(root, Vector3(w * 0.5 - 0.25, 0, part_z + 3.8), -PI * 0.5, timber, rng, "bottles")
	Furniture.fireplace(root, Vector3(-w * 0.5 + 0.45, 0, part_z + 2.0), PI * 0.5, village)
	# Tables for the patrons.
	for t in [Vector3(-w * 0.18, 0, part_z + 2.0), Vector3(-w * 0.2, 0, d * 0.5 - 1.6), Vector3(w * 0.1, 0, d * 0.5 - 2.0)]:
		Furniture.table(root, t, rng.randf_range(-0.3, 0.3), _wood(), 4, true)
	Furniture.banner(root, Vector3(0, 2.2, back + 0.05), Color(0.55, 0.15, 0.12))


func _shop(root: Node3D, w: float, d: float, door_x: float, rng: RandomNumberGenerator) -> void:
	var back := -d * 0.5
	Furniture.counter(root, Vector3(0, 0, back + 1.6), 0.0, w * 0.55, _wood(Color(0.5, 0.34, 0.22)))
	for x in [-w * 0.3, 0.0, w * 0.3]:
		Furniture.shelf(root, Vector3(x, 0, back + 0.25), 0.0, _wood(), rng, ["jars", "cloth", "goods"][rng.randi() % 3])
	Furniture.shelf(root, Vector3(-w * 0.5 + 0.25, 0, d * 0.1), PI * 0.5, _wood(), rng, "goods")
	Furniture.shelf(root, Vector3(w * 0.5 - 0.25, 0, d * 0.1), -PI * 0.5, _wood(), rng, "cloth")
	for c in 3:
		Structures.crate(root, Vector3(w * 0.5 - 0.7, 0, d * 0.5 - 0.9 - c * 0.9), rng.randf(), 0.7)
	Structures.barrel(root, Vector3(-w * 0.5 + 0.6, 0, d * 0.5 - 0.8))
	Structures.barrel(root, Vector3(-w * 0.5 + 1.3, 0, d * 0.5 - 0.7))


func _smithy(root: Node3D, w: float, d: float, door_x: float, rng: RandomNumberGenerator) -> void:
	var back := -d * 0.5
	Furniture.forge(root, Vector3(-w * 0.15, 0, back + 0.9), village)
	Furniture.anvil(root, Vector3(-w * 0.15, 0, back + 2.6))
	Furniture.workbench(root, Vector3(w * 0.5 - 0.6, 0, -d * 0.05), -PI * 0.5, _wood())
	Furniture.tool_rack(root, Vector3(w * 0.25, 1.5, back + 0.08))
	Structures.barrel(root, Vector3(-w * 0.5 + 0.6, 0, back + 2.8))   # quench barrel
	Furniture.chest(root, Vector3(w * 0.5 - 0.6, 0, d * 0.5 - 1.0), -PI * 0.5, _wood(Color(0.35, 0.25, 0.18)))
	for c in 2:
		Structures.crate(root, Vector3(-w * 0.5 + 0.6, 0, d * 0.5 - 0.8 - c * 0.85), rng.randf(), 0.7)


func _workshop(root: Node3D, w: float, d: float, door_x: float, rng: RandomNumberGenerator, name: String) -> void:
	var back := -d * 0.5
	Furniture.workbench(root, Vector3(0, 0, back + 0.6), 0.0, _wood())
	Furniture.tool_rack(root, Vector3(-w * 0.3, 1.5, back + 0.08))
	if name == "Tannery":
		for x in [-w * 0.3, w * 0.25]:
			Furniture.hide_rack(root, Vector3(x, 0, d * 0.1), rng.randf_range(-0.3, 0.3))
		Furniture.vat(root, Vector3(w * 0.5 - 0.9, 0, d * 0.5 - 1.0))
	else:
		for k in 4:
			Structures.box(root, Vector3(2.6, 0.08, 0.3), Vector3(-w * 0.5 + 1.6, 0.06 + k * 0.09, d * 0.3 - k * 0.05), _wood(Color(0.7, 0.55, 0.38)))
		Furniture.workbench(root, Vector3(w * 0.5 - 0.6, 0, 0), -PI * 0.5, _wood())
	Structures.barrel(root, Vector3(w * 0.5 - 0.6, 0, back + 0.6))


func _hall(root: Node3D, w: float, d: float, door_x: float, rng: RandomNumberGenerator) -> void:
	var back := -d * 0.5
	Furniture.table(root, Vector3(0, 0, 0), PI * 0.5, _wood(Color(0.42, 0.28, 0.18)), 6, false, 1.7)
	Furniture.shelf(root, Vector3(-w * 0.5 + 0.25, 0, -d * 0.15), PI * 0.5, _wood(), rng, "books")
	Furniture.shelf(root, Vector3(-w * 0.5 + 0.25, 0, d * 0.2), PI * 0.5, _wood(), rng, "books")
	Furniture.chair(root, Vector3(0, 0, back + 0.9), 0.0, _wood(Color(0.35, 0.2, 0.12)), 1.4)
	for x in [-w * 0.3, w * 0.3]:
		Furniture.banner(root, Vector3(x, 2.1, back + 0.05), Color(0.2, 0.3, 0.55))
	Furniture.fireplace(root, Vector3(w * 0.5 - 0.45, 0, 0), -PI * 0.5, village)


## Your house: a living room at the front (hearth, table, cupboards, a
## bookshelf and a rug) and a bedroom behind a partition, with the bed you
## can sleep in, a wardrobe chest and a wash stand.
func _player_house(root: Node3D, w: float, d: float, door_x: float, rng: RandomNumberGenerator) -> void:
	var back := -d * 0.5
	var part_z := back + d * 0.42
	var oak := _wood(Color(0.62, 0.46, 0.32))
	var white := village._tex_mat("plastered_stone_wall", Color(0.97, 0.96, 0.93), 0.35)
	# Partition with a doorway into the bedroom.
	Structures.box(root, Vector3(w * 0.5 - 0.6, 2.9, 0.15), Vector3(-w * 0.25 - 0.3, 1.45, part_z), white, Vector3.ZERO, true)
	Structures.box(root, Vector3(w * 0.5 - 0.6, 2.9, 0.15), Vector3(w * 0.25 + 0.3, 1.45, part_z), white, Vector3.ZERO, true)
	Structures.box(root, Vector3(1.2, 0.6, 0.15), Vector3(0, 2.6, part_z), white)
	# Bedroom.
	var bed := Furniture.bed(root, Vector3(-w * 0.25, 0, back + 1.25), 0.0, Color(0.2, 0.3, 0.55), oak, 1.25)
	Furniture.chest(root, Vector3(-w * 0.25, 0, back + 2.65), 0.0, oak)
	Furniture.shelf(root, Vector3(w * 0.5 - 0.25, 0, back + 1.4), -PI * 0.5, oak, rng, "cloth")
	Furniture.candles(root, Vector3(-w * 0.25 + 1.3, 0, back + 0.4), 1)
	Furniture.rug(root, Vector3(-w * 0.25, 0, back + 2.0), Vector2(2.6, 1.4), Color(0.55, 0.25, 0.2))
	var sleep := Interactable.new("Sleep until morning", 2.2)
	root.add_child(sleep)
	sleep.position = bed.position + Vector3(0.9, 0, 0.3)
	sleep.action = func(_n: Interactable) -> void:
		if on_rest.is_valid():
			on_rest.call()
	# Living room.
	Furniture.fireplace(root, Vector3(-w * 0.5 + 0.45, 0, part_z + 2.2), PI * 0.5, village)
	Furniture.table(root, Vector3(w * 0.1, 0, part_z + 2.6), 0.0, oak, 4)
	Furniture.shelf(root, Vector3(w * 0.5 - 0.25, 0, part_z + 2.0), -PI * 0.5, oak, rng, "books")
	Furniture.shelf(root, Vector3(w * 0.5 - 0.25, 0, part_z + 3.7), -PI * 0.5, oak, rng, "jars")
	Furniture.chest(root, Vector3(-w * 0.5 + 0.6, 0, d * 0.5 - 1.0), PI * 0.5, oak)
	Furniture.chest(root, Vector3(-w * 0.5 + 0.6, 0, d * 0.5 - 2.2), PI * 0.5, oak)
	Furniture.rug(root, Vector3(-w * 0.15, 0, part_z + 2.3), Vector2(3.0, 2.0), Color(0.3, 0.42, 0.6))
	Furniture.chair(root, Vector3(-w * 0.5 + 1.7, 0, part_z + 1.2), PI * 0.6, oak, 0.75)
	Furniture.banner(root, Vector3(w * 0.1, 2.2, part_z + 0.09), Color(0.2, 0.35, 0.6))
	Furniture.candles(root, Vector3(w * 0.5 - 0.6, 0, d * 0.5 - 0.6), 3)
