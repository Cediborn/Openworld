class_name Vegetation
extends Node3D
## Scatters trees, plants, rocks, mushrooms and crystals over the island using
## the rules in data/vegetation.json. Instances are grouped per 128 m tile and
## drawn with MultiMesh, each tile hiding itself beyond its view distance.

const TILE := 128.0
const PH_MODELS := "res://assets/vendor/polyhaven/models/"

var data: WorldData
var mobile := false
var rng := RandomNumberGenerator.new()
var bodies := {}     # tile key -> StaticBody3D for trunks and rocks


var cfg: Dictionary = {}


func begin() -> void:
	rng.seed = 4242
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/vegetation.json"))


## Adds one group of items. Groups: oak, pine, mushroom, crystal,
## model_rock (rocks, stumps, dead trees) and model_plant (ferns, shrubs, flowers).
func add_kinds(groups: Array) -> void:
	var scale_mul: float = cfg.mobile_scale if mobile else 1.0
	for item in cfg["items"]:
		if not _group_of(item) in groups:
			continue
		if mobile and not item.get("mobile", true):
			continue
		var parts := _parts_for(item)
		if parts.is_empty():
			continue
		var xforms := _scatter(item, scale_mul)
		_emit(item, parts, xforms)


static func _group_of(item: Dictionary) -> String:
	if item.kind != "model":
		return item.kind
	return "model_plant" if item.id in ["fern", "shrub_a", "shrub_b", "nettle", "dandelion"] else "model_rock"


# ---------- What each item looks like ----------

## Returns {"near": [[mesh, material], ...], "far": [...]} or {} if unavailable.
func _parts_for(item: Dictionary) -> Dictionary:
	var vrng := RandomNumberGenerator.new()
	vrng.seed = hash(item.id)
	match item.kind:
		"oak":
			var leaf := Trees.leaf_material(Trees.LEAF_TEX, Color(0.62, 0.78, 0.5)) if Trees.has_photo_leaves() else Props.leaf_material(Color(0.07, 0.15, 0.04), Color(0.3, 0.43, 0.12))
			var bark := Trees.bark_material()
			if not Trees.has_photo_leaves():
				var t := Props.make_tree(vrng, 12.0)
				return {"near": [[t[0], bark], [t[1], leaf]], "far": [[t[0], bark], [t[1], leaf]]}
			var near := Trees.broadleaf(vrng, 12.0, 170 if not mobile else 110)
			vrng.seed = hash(item.id)
			var far := Trees.broadleaf(vrng, 12.0, 45)
			return {"near": [[near[0], bark], [near[1], leaf]], "far": [[far[0], bark], [far[1], leaf]]}
		"pine":
			var bark := Trees.bark_material()
			if not ResourceLoader.exists(Trees.NEEDLE_TEX):
				var p := Props.make_pine(vrng, 15.0)
				var pl := Props.leaf_material(Color(0.04, 0.1, 0.06), Color(0.13, 0.24, 0.12))
				return {"near": [[p[0], bark], [p[1], pl]], "far": [[p[0], bark], [p[1], pl]]}
			var needle := Trees.leaf_material(Trees.NEEDLE_TEX, Color(0.32, 0.45, 0.38), true)
			var near := Trees.conifer(vrng, 15.0, 84 if not mobile else 60)
			vrng.seed = hash(item.id)
			var far := Trees.conifer(vrng, 15.0, 36)
			return {"near": [[near[0], bark], [near[1], needle]], "far": [[far[0], bark], [far[1], needle]]}
		"model":
			var path: String = PH_MODELS + item.model + "/" + item.model + ".gltf"
			if not ResourceLoader.exists(path):
				return {}
			return {"near": _model_parts(path, item.get("tint", null)), "far": []}
		"mushroom":
			var m := Glow.mushroom(vrng)
			return {"near": m, "far": m}
		"crystal":
			return {"near": Glow.crystals(vrng), "far": []}
	return {}


## Flattens a gltf scene into (mesh, material) pairs at the scene's transforms.
func _model_parts(path: String, tint) -> Array:
	var scene: Node3D = load(path).instantiate()
	var out := []
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D()
		var n: Node = mi
		while n != scene and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		for s in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(s)
			if tint != null and mat is BaseMaterial3D:
				mat = mat.duplicate()
				mat.albedo_color = Color(tint[0], tint[1], tint[2])
			var single := ArrayMesh.new()
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			if not xf.is_equal_approx(Transform3D()):
				var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var nr: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				for i in v.size():
					v[i] = xf * v[i]
					nr[i] = (xf.basis * nr[i]).normalized()
				arrays[Mesh.ARRAY_VERTEX] = v
				arrays[Mesh.ARRAY_NORMAL] = nr
			single.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			# Phones skip building extra detail levels at load time (slow and memory hungry).
			out.append([single if mobile else _with_lods(single), mat])
	scene.free()
	return out


## Adds automatic level-of-detail versions so distant copies draw fewer triangles.
static func _with_lods(mesh: ArrayMesh) -> ArrayMesh:
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(0))
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()


# ---------- Where it goes ----------

func _scatter(item: Dictionary, scale_mul: float) -> Array:
	var zones: Array = item.zones
	var area_ha := WorldData.SIZE * WorldData.SIZE / 10000.0
	var tries := int(item.per_ha * area_ha * scale_mul)
	var out := []
	var half := WorldData.SIZE * 0.5 - 40.0
	for t in tries:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var w := data.zone(x, z)
		var p := 0.0
		for i in 5:
			p += w[i] * zones[i]
		if rng.randf() > p:
			continue
		if 1.0 - data.normal(x, z).y > item.max_slope:
			continue
		if _near_path(x, z, item.path_clear):
			continue
		var y := data.height(x, z)
		if w[2] > 0.3 and y < WorldData.LAVA_LEVEL + 0.5:
			continue    # nothing grows in the lava
		if Vector2(x, z).length() > 470.0:
			continue
		if _near_house(x, z):
			continue
		var s := rng.randf_range(item.scale[0], item.scale[1])
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
		out.append(Transform3D(basis, Vector3(x, y - 0.1 * s, z)))
	return out


func _near_path(x: float, z: float, clear: float) -> bool:
	for o in [Vector2.ZERO, Vector2(clear, 0), Vector2(-clear, 0), Vector2(0, clear), Vector2(0, -clear)]:
		if data.on_path(x + o.x, z + o.y) > 0.2:
			return true
	return false


func _near_house(x: float, z: float) -> bool:
	for h in data.houses:
		if Vector2(h.x - x, h.z - z).length() < maxf(h.w, h.d) * 0.85 + 2.0:
			return true
	return false


# ---------- Drawing ----------

func _emit(item: Dictionary, parts: Dictionary, xforms: Array) -> void:
	var tiles := {}
	for xf in xforms:
		var key := Vector2i(floori(xf.origin.x / TILE), floori(xf.origin.z / TILE))
		if not tiles.has(key):
			tiles[key] = []
		tiles[key].append(xf)
	var near_d: float = item.near * (0.7 if mobile else 1.0)
	var far_d: float = item.far * (0.6 if mobile else 1.0)
	var collide: bool = item.kind in ["oak", "pine", "mushroom"] or item.id in ["dead_tree", "rock_mid", "boulder", "basalt_a", "basalt_b", "crystal"]
	for key in tiles:
		var list: Array = tiles[key]
		var centre := Vector3((key.x + 0.5) * TILE, 0, (key.y + 0.5) * TILE)
		var has_far: bool = far_d > 0.0 and not parts.far.is_empty()
		for part in parts.near:
			_tile_multimesh(part, list, centre, 0.0, near_d + TILE * 0.5, item.kind != "model" or item.id.begins_with("rock") or item.id.begins_with("basalt") or item.id == "boulder")
		if has_far:
			for part in parts.far:
				_tile_multimesh(part, list, centre, near_d + TILE * 0.5, far_d, false)
		if collide:
			_add_colliders(key, list, item)


func _tile_multimesh(part: Array, list: Array, centre: Vector3, begin: float, end: float, shadows: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = part[0]
	mm.instance_count = list.size()
	for i in list.size():
		var xf: Transform3D = list[i]
		mm.set_instance_transform(i, Transform3D(xf.basis, xf.origin - centre))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = part[1]
	mmi.position = centre
	mmi.visibility_range_begin = begin
	mmi.visibility_range_end = end
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (shadows or begin == 0.0) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _add_colliders(key: Vector2i, list: Array, item: Dictionary) -> void:
	if not bodies.has(key):
		var b := StaticBody3D.new()
		add_child(b)
		bodies[key] = b
	var body: StaticBody3D = bodies[key]
	for xf in list:
		var s: float = xf.basis.get_scale().x
		var col := CollisionShape3D.new()
		if item.kind in ["oak", "pine", "mushroom"] or item.id == "dead_tree":
			var c := CylinderShape3D.new()
			c.radius = 0.4 * s
			c.height = 4.0
			col.shape = c
			col.position = xf.origin + Vector3(0, 2.0, 0)
		else:
			var sp := SphereShape3D.new()
			sp.radius = 0.55 * s
			col.shape = sp
			col.position = xf.origin + Vector3(0, 0.2 * s, 0)
		body.add_child(col)
