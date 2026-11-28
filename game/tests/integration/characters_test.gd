extends SceneTree
## Character test (run: godot --headless --path game -s res://tests/integration/characters_test.gd).
## Everyone is built from modelled parts (clothes, a head with eyes, brows),
## townsfolk don't share one look, and the explorer's second outfit can be
## worn, survives save and load, and still has the sword and the gun.

var world: Node
var fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("PASS " if ok else "FAIL ") + msg)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _init() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	var t0 := Time.get_ticks_msec()
	while not world.booted and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	check(world.booted, "world booted")
	world._new_game()
	await frames(5)
	_townsfolk()
	await _outfits()
	print("RESULT: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(fails)


## Mesh names under a body's skeleton.
func _parts(b: ExplorerBody) -> Array:
	var out := []
	for mi: MeshInstance3D in b.skeleton.find_children("*", "MeshInstance3D", false, false):
		out.append(mi)
	return out


func _townsfolk() -> void:
	var people: Array = world.story.by_id.values()
	check(people.size() >= 30, "%d townsfolk spawned" % people.size())
	var looks := {}
	var faces := {}
	var hair := {}
	var skins := {}
	var beards := 0
	var all_built := true
	var all_tris_ok := true
	for v: Villager in people:
		var b: ExplorerBody = v.body
		var parts := _parts(b)
		var has_eyes := parts.any(func(mi): return mi.mesh.surface_get_material(0) != null and mi.mesh.surface_get_material(0).resource_name.contains("Eyes"))
		var has_head := parts.any(func(mi): return mi.mesh.surface_get_material(0) != null and mi.mesh.surface_get_material(0).resource_name.contains("Superhero"))
		var has_brows := parts.any(func(mi): return mi.mesh.surface_get_material(0) != null and mi.mesh.surface_get_material(0).resource_name.contains("Hair"))
		if not (has_eyes and has_head and has_brows and parts.size() >= 6):
			all_built = false
			print("  incomplete: ", v.name, " parts=", parts.size())
		var tris := 0
		for mi: MeshInstance3D in parts:
			for s in mi.mesh.get_surface_count():
				tris += mi.mesh.surface_get_array_index_len(s) / 3
		if tris > 45000:
			all_tris_ok = false
			print("  heavy: ", v.name, " tris=", tris)
		var l: Dictionary = b.look
		looks[str(l)] = true
		faces[l.face] = true
		hair[l.hair] = true
		skins[l.skin] = true
		beards += 1 if l.beard else 0
	check(all_built, "every townsperson has clothes, a head, eyes and brows")
	check(all_tris_ok, "every townsperson stays under 45k triangles at full detail")
	check(looks.size() >= people.size() * 0.6, "%d distinct looks among %d townsfolk" % [looks.size(), people.size()])
	check(faces.size() >= 5, "%d face shapes in use" % faces.size())
	check(hair.size() >= 5, "%d hairstyles in use" % hair.size())
	check(skins.size() >= 4, "%d skin tones in use" % skins.size())
	check(beards >= 4, "%d men with beards" % beards)


func _outfits() -> void:
	var p: Player = world.player
	var st: GameState = world.state
	var b: ExplorerBody = p.body
	check(b.look.kit == "ranger", "explorer starts in field clothes")
	var before := _parts(b).size()
	st.equip("white_coat")
	await frames(3)
	check(st.outfit == "white_coat", "white coat equipped")
	check(b.look.kit == "coat", "explorer body now wears the coat")
	var coat_parts := _parts(b).size()
	check(coat_parts > before, "coat adds its own meshes (%d -> %d)" % [before, coat_parts])
	check(b.sword_hand != null and is_instance_valid(b.sword_hand), "sword still in hand slot after changing")
	check(b.gun_hand != null and is_instance_valid(b.gun_hand), "gun still in hand slot after changing")
	# The coat follows the legs: play a walk and check the skirt moved with the thighs.
	b.play("Walk")
	await frames(20)
	check(b.skeleton.get_bone_global_pose(b.skeleton.find_bone("LeftUpperLeg")).basis != b.skeleton.get_bone_global_rest(b.skeleton.find_bone("LeftUpperLeg")).basis,
		"legs animate in the coat")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(st.save_state()))
	check(saved.get("outfit") == "white_coat", "outfit written to the save")
	st.equip("field_clothes")
	await frames(2)
	check(b.look.kit == "ranger" and _parts(b).size() == before, "back to field clothes, no leftover coat meshes")
	st.load_state(saved)
	await frames(2)
	check(st.outfit == "white_coat" and b.look.kit == "coat", "loading the save puts the coat back on")
	st.load_state({"coins": 5, "items": {"potion": 1}})
	await frames(2)
	check(st.outfit == "field_clothes" and b.look.kit == "ranger", "an old save without an outfit loads in field clothes")
