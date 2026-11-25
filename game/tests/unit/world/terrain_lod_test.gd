extends SceneTree
## Terrain level-of-detail under the player (run: godot --headless --path game -s res://tests/unit/world/terrain_lod_test.gd).
## Regression test for "the player sinks into the ground": the collision is a
## 2 m heightmap, so the ground mesh drawn under the player must use the same
## 2 m grid on PC and on phones. Godot picks a visibility range by the distance
## from the camera to each tile's AABB centre, so this test applies that same
## rule for a camera a few metres behind the player, at low and high ground,
## at tile centres and corners.

var fails := 0


func check(ok: bool, msg: String) -> void:
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok:
		fails += 1


func _init() -> void:
	var data := WorldData.new()
	check(data.load_data(), "baked world data loads")
	for mobile in [false, true]:
		var t := Terrain.new()
		t.setup(data, mobile, false)
		var label := "phone" if mobile else "PC"
		# Player spots: tile centres, tile corners, valleys and peaks.
		var spots := [Vector2(0, 40), Vector2(-256, 0), Vector2(-320, -64), Vector2(10, -300),
			Vector2(120, -380), Vector2(20, 300), Vector2(-311, -30), Vector2(127, 127)]
		for s in spots:
			var ground := data.height(s.x, s.y)
			var player := Vector3(s.x, ground, s.y)
			var cam := player + Vector3(0, 3.2, 6.0)
			var res := _drawn_resolution(t, player, cam)
			check(is_equal_approx(res, WorldData.STEP), "%s at (%d, %d), ground %.0f m: mesh under the feet uses a %.0f m grid (collision %.0f m)" % [label, s.x, s.y, ground, res, WorldData.STEP])
		t.free()
	print("RESULT: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(fails)


## Grid spacing (m) of the tile mesh Godot would draw under `player` for a camera at `cam`.
func _drawn_resolution(t: Terrain, player: Vector3, cam: Vector3) -> float:
	for c in t.get_children():
		if not c is MeshInstance3D or not c.mesh is PlaneMesh:
			continue
		var mi: MeshInstance3D = c
		var half := Terrain.TILE * 0.5
		if absf(player.x - mi.position.x) > half or absf(player.z - mi.position.z) > half:
			continue
		var aabb := mi.custom_aabb if mi.custom_aabb.has_volume() else mi.get_aabb()   # what the renderer uses
		var centre := mi.position + aabb.position + aabb.size * 0.5
		var d := cam.distance_to(centre)
		var shown := d >= mi.visibility_range_begin and (mi.visibility_range_end <= 0.0 or d < mi.visibility_range_end)
		if shown:
			var p: PlaneMesh = mi.mesh
			return p.size.x / (p.subdivide_width + 1)
	return -1.0
