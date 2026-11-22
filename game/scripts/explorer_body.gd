class_name ExplorerBody
extends Node3D
## Realistic explorer: Quaternius CC0 base body dressed in a field jacket, cargo
## pants and boots (clothes are painted per body part and slightly inflated),
## with a scarf and backpack attached to bones. Plays retargeted UAL animations.

const MODEL := "res://assets/character/Superhero_Male_FullBody.gltf"
const ANIM_DIR := "res://assets/character/anims/"
const ANIMS := ["Idle", "Walk", "Jog_Fwd", "Sprint", "Jump_Start", "Jump", "Jump_Land", "Swim_Idle", "Swim_Fwd"]

enum Region { SKIN, JACKET, PANTS, BOOTS, HAIR }

## How far each region is pushed out along the normal (metres) and how many
## smoothing passes it gets. Smoothing hides the base body's muscles under cloth.
const INFLATE := [0.0, 0.034, 0.02, 0.016, 0.009]
const SMOOTH_PASSES := [0, 24, 16, 18, 2]

const JACKET_BONES := ["Spine", "Chest", "UpperChest", "LeftShoulder", "RightShoulder",
	"LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm"]
const LEG_BONES := ["LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg"]
const FOOT_BONES := ["LeftFoot", "RightFoot", "LeftToes", "RightToes"]

var anim: AnimationPlayer
var skeleton: Skeleton3D
var current := ""
var smooth_normals := PackedVector3Array()


func _ready() -> void:
	var model: Node3D = load(MODEL).instantiate()
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	for mi: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", false, false):
		_dress(mi)
	_add_accessories()
	anim = AnimationPlayer.new()
	add_child(anim)
	anim.root_node = anim.get_path_to(model)
	var lib := AnimationLibrary.new()
	for n in ANIMS:
		var path: String = ANIM_DIR + n + ".res"
		if ResourceLoader.exists(path):
			var a: Animation = load(path).duplicate()
			a.loop_mode = Animation.LOOP_NONE if n.begins_with("Jump") else Animation.LOOP_LINEAR
			lib.add_animation(n, a)
	anim.add_animation_library("", lib)
	play("Idle")


func play(name: String, blend := 0.2, speed := 1.0) -> void:
	anim.speed_scale = speed
	if name == current or not anim.has_animation(name):
		return
	current = name
	anim.play(name, blend)


# ---------- Clothing ----------

func _region_of_bone(b: String, y: float) -> int:
	if b in FOOT_BONES:
		return Region.BOOTS
	if b in LEG_BONES:
		return Region.BOOTS if y < 0.36 else Region.PANTS
	if b == "Hips":
		return Region.JACKET if y > 0.93 else Region.PANTS   # jacket hem falls over the hips
	if b in JACKET_BONES:
		return Region.JACKET
	return Region.SKIN


func _dress(mi: MeshInstance3D) -> void:
	var mesh: ArrayMesh = mi.mesh
	var skin := mi.skin
	if mesh == null or skin == null:
		return
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var mat := mesh.surface_get_material(s)
		var is_body := mat != null and mat.resource_name.to_lower().contains("superhero")
		if is_body:
			arrays = _paint_regions(arrays, skin)
			mat = _outfit_material(mat)
		var flags: int = mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		for c in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			arrays[c] = null   # custom channels need extra format flags; the body doesn't use them
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		out.surface_set_material(s, mat)
	mi.mesh = out


func _paint_regions(arrays: Array, skin: Skin) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var per: int = bones.size() / verts.size()
	var bind_names := []
	for i in skin.get_bind_count():
		var nm: StringName = skin.get_bind_name(i)
		if nm == &"":
			nm = skeleton.get_bone_name(skin.get_bind_bone(i))
		bind_names.append(String(nm))
	var region := PackedInt32Array()
	region.resize(verts.size())
	var head_w := PackedFloat32Array()
	head_w.resize(verts.size())
	for v in verts.size():
		var score := [0.0, 0.0, 0.0, 0.0]
		for k in per:
			var w: float = weights[v * per + k]
			if w <= 0.0:
				continue
			var bi: int = bones[v * per + k]
			var bname: String = bind_names[bi] if bi < bind_names.size() else ""
			score[_region_of_bone(bname, verts[v].y)] += w
			if bname == "Head":
				head_w[v] += w
		var r := 0
		for i in 4:
			if score[i] > score[r]:
				r = i
		region[v] = r
	_mark_hair(verts, head_w, region)
	smooth_normals = norms.duplicate()
	verts = _smooth_cloth(verts, indices, region)
	# Winding check: keep the new normals pointing the same way as the originals.
	for v in verts.size():
		if smooth_normals[v].dot(norms[v]) < 0.0:
			smooth_normals[v] = -smooth_normals[v]
	norms = smooth_normals
	arrays[Mesh.ARRAY_NORMAL] = norms
	var cols := PackedColorArray()
	cols.resize(verts.size())
	for v in verts.size():
		cols[v] = Color(region[v] / 4.0, 0, 0, 1)
		var push: float = INFLATE[region[v]]
		if region[v] == Region.JACKET:
			# Fill the base body's narrow waist so the jacket hangs straight like a parka.
			push += 0.035 * clampf(1.0 - absf(verts[v].y - 1.05) / 0.18, 0.0, 1.0)
		verts[v] += norms[v] * push
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	return arrays


## Short hair: the top and back of the skull, above the brow and ears.
func _mark_hair(verts: PackedVector3Array, head_w: PackedFloat32Array, region: PackedInt32Array) -> void:
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for v in verts.size():
		if head_w[v] > 0.6:
			lo = lo.min(verts[v])
			hi = hi.max(verts[v])
	if lo == Vector3.INF:
		return
	var h := hi - lo
	var cx := (lo.x + hi.x) * 0.5
	for v in verts.size():
		if head_w[v] < 0.5:
			continue
		var q := (verts[v] - lo) / h   # 0..1 inside the head's box; face is +Z
		var crown := q.y > 0.70 - 0.10 * (1.0 - q.z)          # hairline sweeps lower towards the back
		var back := q.z < 0.42 and q.y > 0.36
		var side := absf(verts[v].x - cx) / (h.x * 0.5) > 0.82 and q.y > 0.62 and q.z < 0.6   # temples, above the ears
		if crown or back or side:
			region[v] = Region.HAIR


## Taubin smoothing on clothing only. Vertices are welded by position first,
## so UV seams don't tear apart.
func _smooth_cloth(verts: PackedVector3Array, indices: PackedInt32Array, region: PackedInt32Array) -> PackedVector3Array:
	var key_of := {}
	var weld := PackedInt32Array()
	weld.resize(verts.size())
	var uniq: Array[Vector3] = []
	for v in verts.size():
		var key := Vector3i((verts[v] * 2000.0).round())
		if not key_of.has(key):
			key_of[key] = uniq.size()
			uniq.append(verts[v])
		weld[v] = key_of[key]
	var n := uniq.size()
	var reg := PackedInt32Array()
	reg.resize(n)
	for v in verts.size():
		reg[weld[v]] = maxi(reg[weld[v]], region[v])
	var nbrs: Array = []
	nbrs.resize(n)
	for i in n:
		nbrs[i] = []   # plain Array: packed arrays are copied on access, so append() would be lost
	for t in range(0, indices.size(), 3):
		for e in 3:
			var a := weld[indices[t + e]]
			var b := weld[indices[t + (e + 1) % 3]]
			nbrs[a].append(b)
			nbrs[b].append(a)
	var pos := PackedVector3Array(uniq)
	for pass_i in SMOOTH_PASSES.max():
		var nxt := pos.duplicate()
		for i in n:
			if pass_i >= SMOOTH_PASSES[reg[i]] or nbrs[i].is_empty():
				continue
			var avg := Vector3.ZERO
			for j in nbrs[i]:
				avg += pos[j]
			avg /= nbrs[i].size()
			# Taubin smoothing: alternate shrink and grow steps so cloth keeps its volume.
			nxt[i] = pos[i].lerp(avg, 0.6 if pass_i % 2 == 0 else -0.63)
		pos = nxt
	# Fresh normals from the smoothed surface, so cloth no longer shades like muscle.
	var nrm := PackedVector3Array()
	nrm.resize(n)
	for t in range(0, indices.size(), 3):
		var a := weld[indices[t]]
		var b := weld[indices[t + 1]]
		var c := weld[indices[t + 2]]
		var fn := (pos[b] - pos[a]).cross(pos[c] - pos[a])
		nrm[a] += fn
		nrm[b] += fn
		nrm[c] += fn
	var out := verts.duplicate()
	for v in verts.size():
		out[v] = pos[weld[v]]
		if region[v] != Region.SKIN and nrm[weld[v]].length_squared() > 0.0:
			smooth_normals[v] = nrm[weld[v]].normalized()
	return out


func _outfit_material(body: Material) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/spatial_char_outfit.gdshader")
	if body is BaseMaterial3D:
		m.set_shader_parameter("skin_albedo", body.albedo_texture)
		m.set_shader_parameter("skin_normal", body.normal_texture)
		m.set_shader_parameter("skin_rough", body.roughness_texture)
	m.set_shader_parameter("weave_noise", Props.noise())
	return m


# ---------- Accessories ----------

func _attach(bone: String) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	skeleton.add_child(ba)
	ba.bone_name = bone
	return ba


static func _fabric(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.normal_enabled = true
	var nt := NoiseTexture2D.new()
	var n := FastNoiseLite.new()
	n.frequency = 0.25
	nt.noise = n
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 3.0
	m.normal_texture = nt
	m.uv1_scale = Vector3(6, 6, 1)
	return m


func _add_accessories() -> void:
	# Scarf around the neck.
	var neck := _attach("Neck")
	var scarf := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.055
	tor.outer_radius = 0.105
	tor.rings = 24
	tor.ring_segments = 10
	scarf.mesh = tor
	scarf.material_override = _fabric(Color(0.45, 0.10, 0.08))
	scarf.position = Vector3(0, 0.02, 0.0)
	scarf.scale = Vector3(1.05, 0.75, 1.0)
	neck.add_child(scarf)
	var tail := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.07, 0.22, 0.02)
	tail.mesh = tb
	tail.material_override = scarf.material_override
	tail.position = Vector3(0.05, -0.1, 0.1)
	tail.rotation.z = 0.25
	neck.add_child(tail)

	# Boot soles and laced cuffs (the boots themselves are painted on the feet).
	for side in ["Left", "Right"]:
		var foot := _attach(side + "Foot")
		var leather := _fabric(Color(0.25, 0.16, 0.09), 0.6)
		var sole := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.105, 0.26, 0.03)
		sole.mesh = sm
		sole.material_override = _fabric(Color(0.07, 0.06, 0.05), 0.85)
		# Foot bone: local +Y points to the toes, local +Z points up.
		sole.position = Vector3(0, 0.06, -0.075)
		foot.add_child(sole)
		var cuff := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.066
		cm.bottom_radius = 0.058
		cm.height = 0.07
		cuff.mesh = cm
		cuff.material_override = leather
		cuff.position = Vector3(0, -0.01, 0.1)
		cuff.rotation.x = PI * 0.5
		foot.add_child(cuff)
		# Rounded toe cap hides the base body's toes.
		var cap := SphereMesh.new()
		cap.radius = 0.06
		cap.height = 0.12
		_piece(foot, cap, leather, Vector3(0, 0.13, -0.035), Vector3.ZERO, Vector3(0.95, 1.45, 0.7))

	# Backpack with a rolled sleeping mat on top.
	var chest := _attach("UpperChest")
	var pack := MeshInstance3D.new()
	var pm := CapsuleMesh.new()
	pm.radius = 0.15
	pm.height = 0.48
	pack.mesh = pm
	pack.material_override = _fabric(Color(0.42, 0.33, 0.20))
	pack.position = Vector3(0, -0.12, -0.2)
	pack.scale = Vector3(1.15, 1.0, 0.75)
	chest.add_child(pack)
	var pocket := MeshInstance3D.new()
	var pkm := BoxMesh.new()
	pkm.size = Vector3(0.2, 0.14, 0.06)
	pocket.mesh = pkm
	pocket.material_override = pack.material_override
	pocket.position = Vector3(0, -0.2, -0.32)
	chest.add_child(pocket)
	var roll := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.075
	rm.bottom_radius = 0.075
	rm.height = 0.44
	roll.mesh = rm
	roll.material_override = _fabric(Color(0.30, 0.33, 0.25))
	roll.position = Vector3(0, 0.14, -0.2)
	roll.rotation.z = PI * 0.5
	chest.add_child(roll)
	for side in [-1.0, 1.0]:
		var strap := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.04, 0.42, 0.012)
		strap.mesh = sm
		strap.material_override = _fabric(Color(0.22, 0.17, 0.11))
		strap.position = Vector3(0.1 * side, -0.05, 0.11)
		strap.rotation.x = -0.12
		chest.add_child(strap)

	_add_jacket_details()


## Field-jacket details from the concept sheet: collar, chest pockets with
## flaps, front zip, thigh cargo pockets and the backpack's flap and side pockets.
func _add_jacket_details() -> void:
	var jacket := _fabric(Color(0.27, 0.28, 0.18))
	var seam := _fabric(Color(0.17, 0.17, 0.11))
	var neck := _attach("Neck")
	_piece(neck, _torus(0.075, 0.118), jacket, Vector3(0, -0.035, -0.005), Vector3.ZERO, Vector3(1.0, 1.1, 1.0))
	var chest := _attach("UpperChest")
	for sx in [-1.0, 1.0]:
		_piece(chest, _box(Vector3(0.1, 0.11, 0.03)), jacket, Vector3(0.085 * sx, 0.0, 0.125), Vector3(-0.12, 0, 0))
		_piece(chest, _box(Vector3(0.11, 0.035, 0.035)), seam, Vector3(0.085 * sx, 0.06, 0.132), Vector3(-0.12, 0, 0))
	_piece(chest, _box(Vector3(0.014, 0.5, 0.012)), seam, Vector3(0, -0.2, 0.135), Vector3(-0.1, 0, 0))
	var pants := _fabric(Color(0.15, 0.15, 0.12))
	for side in ["Left", "Right"]:
		var leg := _attach(side + "UpperLeg")
		var sx := -1.0 if side == "Left" else 1.0   # outer side of each thigh
		_piece(leg, _box(Vector3(0.035, 0.16, 0.13)), pants, Vector3(0.085 * sx, 0.24, 0.02))
		_piece(leg, _box(Vector3(0.04, 0.035, 0.14)), pants, Vector3(0.087 * sx, 0.155, 0.02))
	var canvas := _fabric(Color(0.42, 0.33, 0.20))
	_piece(chest, _box(Vector3(0.3, 0.06, 0.22)), _fabric(Color(0.36, 0.28, 0.17)), Vector3(0, 0.07, -0.21))
	for sx in [-1.0, 1.0]:
		var pocket := CapsuleMesh.new()
		pocket.radius = 0.06
		pocket.height = 0.22
		_piece(chest, pocket, canvas, Vector3(0.19 * sx, -0.2, -0.2))
	# Straps that hold the sleeping mat.
	for sx in [-1.0, 1.0]:
		_piece(chest, _torus(0.074, 0.084), _fabric(Color(0.22, 0.17, 0.11)), Vector3(0.12 * sx, 0.14, -0.2), Vector3(0, 0, PI * 0.5))


func _piece(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 24
	t.ring_segments = 8
	return t
