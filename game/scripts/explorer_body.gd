class_name ExplorerBody
extends Node3D
## Realistic person: Quaternius CC0 base body dressed by painting clothes onto
## body regions (smoothed and slightly inflated), plus accessories attached to
## bones. Used for the explorer and, with a different `outfit`, every villager.
## Plays retargeted UAL animations.

const MODELS := {
	"male": "res://assets/character/Superhero_Male_FullBody.gltf",
	"female": "res://assets/character/Superhero_Female_FullBody.gltf",
}
const ANIM_DIR := "res://assets/character/anims/"
const ANIMS := ["Idle", "Walk", "Jog_Fwd", "Sprint", "Jump_Start", "Jump", "Jump_Land", "Swim_Idle", "Swim_Fwd",
	"Sword_Slash1", "Sword_Slash2", "Sword_Slash3", "Sword_Idle", "Sword_Block", "Hit_Chest", "Death01", "Idle_Talking",
	"PickUp_Table", "Interact", "Roll", "Sitting_Idle", "Crouch_Idle", "Dance", "Ride",
	"Whistle", "Pistol_Aim", "Pistol_Shoot", "Pistol_Reload", "Pistol_Idle", "Pray", "Kneel_Pray"]
## Animations that play once and then hand control back to locomotion.
const ONE_SHOTS := ["Jump_Start", "Jump", "Jump_Land", "Sword_Slash1", "Sword_Slash2", "Sword_Slash3", "Hit_Chest", "Death01", "PickUp_Table", "Roll",
	"Whistle", "Pistol_Shoot", "Pistol_Reload"]
## The explorer's look; villagers pass their own outfit before being added.
const EXPLORER := {
	"model": "male", "jacket": Color(0.29, 0.29, 0.19), "pants": Color(0.16, 0.16, 0.13),
	"boots": Color(0.27, 0.17, 0.10), "hair": Color(0.07, 0.05, 0.035),
	"accessories": ["scarf", "explorer", "sword"],
}
## Upper-chest width factor (1.0 = base superhero build).
const SHOULDER_SLIM := 0.86
## Dressed meshes are expensive to build, so each body model is dressed once.
static var _mesh_cache := {}

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
var outfit: Dictionary = EXPLORER
var outfit_mat: ShaderMaterial
var sword_hand: Node3D
var sword_hip: Node3D
## The flintlock in the hand and in its holster (explorer only).
var gun_hand: Node3D
var gun_hip: Node3D
## Leans the chest up or down to follow the aim (radians, + = up).
var aim_pitch := 0.0
var _aim_mod: AimLean
var blade_mat: StandardMaterial3D
var _busy_left := 0.0   # seconds of game time until a one-shot animation ends
var smooth_normals := PackedVector3Array()


func _ready() -> void:
	var model_path: String = MODELS[outfit.get("model", "male")]
	var model: Node3D = load(model_path).instantiate()
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	for mi: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", false, false):
		var key := model_path + ":" + mi.name
		if not _mesh_cache.has(key):
			_dress(mi)
			_mesh_cache[key] = mi.mesh
		mi.mesh = _mesh_cache[key]
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m is ShaderMaterial:
				# Per-person colours on a copy of the shared outfit material.
				outfit_mat = m.duplicate()
				for k in ["jacket", "pants", "boots", "hair"]:
					outfit_mat.set_shader_parameter(k + "_color", outfit.get(k, EXPLORER[k]))
				mi.set_surface_override_material(s, outfit_mat)
		if outfit.get("hide_hair_mesh", false) and mi.name.to_lower().contains("hair"):
			mi.visible = false
	_add_accessories()
	_slim_shoulders()
	anim = AnimationPlayer.new()
	add_child(anim)
	anim.root_node = anim.get_path_to(model)
	var lib := AnimationLibrary.new()
	for n in ANIMS:
		var path: String = ANIM_DIR + n + ".res"
		if ResourceLoader.exists(path):
			var a: Animation = load(path).duplicate()
			a.loop_mode = Animation.LOOP_NONE if n in ONE_SHOTS else Animation.LOOP_LINEAR
			lib.add_animation(n, a)
	anim.add_animation_library("", lib)
	play("Idle")


## Loops or continues a locomotion animation. Ignored while a one-shot plays.
func play(name: String, blend := 0.2, speed := 1.0) -> void:
	if busy():
		return
	anim.speed_scale = speed
	if name == current or not anim.has_animation(name):
		return
	current = name
	anim.play(name, blend)


## Plays an action (attack, hit, death, pick up) once; locomotion waits for it.
func play_once(name: String, blend := 0.1, speed := 1.0) -> float:
	if not anim.has_animation(name):
		return 0.0
	anim.speed_scale = speed
	current = name
	anim.play(name, blend)
	anim.seek(0.0, true)
	var length := anim.get_animation(name).length / speed
	_busy_left = length
	return length


## True while a one-shot action is still playing.
func busy() -> bool:
	return _busy_left > 0.0


func _process(delta: float) -> void:
	if _busy_left > 0.0:
		_busy_left -= delta


## Ends a one-shot early (used when respawning).
func cancel_action() -> void:
	_busy_left = 0.0
	current = ""


## World-space line along the drawn blade, from just above the guard to the tip.
func blade_segment() -> Array:
	if sword_hand == null:
		return [global_position, global_position]
	var x := sword_hand.global_transform
	return [x * Vector3(0, 0.15, 0), x * Vector3(0, 0.8, 0)]


## Makes both copies of the blade glow (quest reward).
func set_blade_glow(c: Color) -> void:
	if blade_mat:
		blade_mat.emission_enabled = true
		blade_mat.emission = c
		blade_mat.emission_energy_multiplier = 1.6


func clear_blade_glow() -> void:
	if blade_mat:
		blade_mat.emission_enabled = false


## Shows the sword in the hand (fighting) or in its scabbard (exploring).
func set_sword_drawn(drawn: bool) -> void:
	if sword_hand:
		sword_hand.visible = drawn
		sword_hip.visible = not drawn


## The base body is built like a superhero; narrow the upper chest a little so
## the explorer and villagers look like ordinary people.
func _slim_shoulders() -> void:
	var i := skeleton.find_bone("UpperChest")
	if i == -1:
		return
	var rest := skeleton.get_bone_rest(i)
	rest.basis = rest.basis.scaled_local(Vector3(SHOULDER_SLIM, 1.0, 0.96))
	skeleton.set_bone_rest(i, rest)
	skeleton.set_bone_pose_scale(i, Vector3(SHOULDER_SLIM, 1.0, 0.96))


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
	var acc: Array = outfit.get("accessories", [])
	_add_boots()
	if "scarf" in acc:
		_add_scarf()
	if "explorer" in acc:
		_add_explorer_kit()
	if "sword" in acc:
		_add_sword()
	_add_villager_props(acc)


func _add_scarf() -> void:
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


## Boot soles, laced cuffs and toe caps (the boots themselves are painted on the feet).
func _add_boots() -> void:
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


## The explorer's backpack, sleeping mat, pockets and jacket details.
func _add_explorer_kit() -> void:
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


# ---------- Weapons and villager props ----------

## Builds a short sword. Blade points along +Y of the returned node.
func _sword_mesh() -> Node3D:
	var root := Node3D.new()
	if blade_mat == null:
		blade_mat = StandardMaterial3D.new()
	var steel := blade_mat
	steel.albedo_color = Color(0.72, 0.74, 0.78)
	steel.metallic = 0.9
	steel.roughness = 0.28
	var leather := _fabric(Color(0.22, 0.14, 0.08), 0.7)
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.62, 0.48, 0.22)
	brass.metallic = 0.8
	brass.roughness = 0.4
	_piece(root, _box(Vector3(0.045, 0.62, 0.008)), steel, Vector3(0, 0.42, 0))
	var tip := PrismMesh.new()
	tip.size = Vector3(0.045, 0.07, 0.008)
	_piece(root, tip, steel, Vector3(0, 0.765, 0))
	_piece(root, _box(Vector3(0.16, 0.025, 0.03)), brass, Vector3(0, 0.1, 0))
	var grip := CylinderMesh.new()
	grip.top_radius = 0.016
	grip.bottom_radius = 0.016
	grip.height = 0.14
	_piece(root, grip, leather, Vector3(0, 0.02, 0))
	var pommel := SphereMesh.new()
	pommel.radius = 0.024
	pommel.height = 0.048
	_piece(root, pommel, brass, Vector3(0, -0.06, 0))
	return root


func _add_sword() -> void:
	var hand := _attach("RightHand")
	sword_hand = _sword_mesh()
	# Hand bone: +Y runs along the fingers; the grip crosses the palm.
	sword_hand.position = Vector3(-0.01, 0.08, 0.02)
	sword_hand.rotation = Vector3(0, 0, PI * 0.5)
	hand.add_child(sword_hand)
	var hips := _attach("Hips")
	sword_hip = Node3D.new()
	hips.add_child(sword_hip)
	var sheathed := _sword_mesh()
	sword_hip.add_child(sheathed)
	var scab := _box(Vector3(0.06, 0.62, 0.025))
	_piece(sheathed, scab, _fabric(Color(0.2, 0.13, 0.08), 0.7), Vector3(0, 0.42, 0))
	sword_hip.position = Vector3(0.19, -0.02, 0.04)
	sword_hip.rotation = Vector3(0.35, 0, PI * 0.88)
	set_sword_drawn(false)
	if "explorer" in outfit.get("accessories", []):
		_add_pistol(hand, hips)


## A flintlock pistol: walnut stock, browned iron barrel, brass furniture and
## a working-looking lock (hammer, frizzen, pan). Barrel along local +Y, like
## the sword blade, so the baked aim poses point it where the "blade" goes.
func _pistol_mesh() -> Node3D:
	var root := Node3D.new()
	var walnut := StandardMaterial3D.new()
	walnut.albedo_color = Color(0.32, 0.17, 0.08)
	walnut.roughness = 0.45
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.2, 0.19, 0.18)
	iron.metallic = 0.85
	iron.roughness = 0.35
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.7, 0.52, 0.22)
	brass.metallic = 0.85
	brass.roughness = 0.3
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.011
	barrel.bottom_radius = 0.014
	barrel.height = 0.26
	barrel.radial_segments = 10
	_piece(root, barrel, iron, Vector3(0, 0.2, 0.022))
	var muzzle := CylinderMesh.new()
	muzzle.top_radius = 0.015
	muzzle.bottom_radius = 0.015
	muzzle.height = 0.018
	muzzle.radial_segments = 10
	_piece(root, muzzle, brass, Vector3(0, 0.325, 0.022))
	# Fore-stock under the barrel, then the grip curving down to a brass butt cap.
	_piece(root, _box(Vector3(0.026, 0.2, 0.022)), walnut, Vector3(0, 0.17, 0.004))
	_piece(root, _box(Vector3(0.03, 0.07, 0.04)), walnut, Vector3(0, 0.05, 0.012))
	_piece(root, _box(Vector3(0.028, 0.11, 0.034)), walnut, Vector3(0, 0.0, -0.035), Vector3(-0.9, 0, 0))
	var cap := SphereMesh.new()
	cap.radius = 0.024
	cap.height = 0.04
	_piece(root, cap, brass, Vector3(0, -0.035, -0.085))
	# Lock plate, hammer (cock), frizzen, trigger and its guard.
	_piece(root, _box(Vector3(0.006, 0.06, 0.022)), iron, Vector3(0.016, 0.06, 0.02))
	_piece(root, _box(Vector3(0.006, 0.012, 0.035)), iron, Vector3(0.018, 0.035, 0.045), Vector3(0.6, 0, 0))
	_piece(root, _box(Vector3(0.006, 0.02, 0.012)), iron, Vector3(0.018, 0.085, 0.04))
	_piece(root, _box(Vector3(0.004, 0.006, 0.02)), iron, Vector3(0, 0.04, -0.02), Vector3(0.4, 0, 0))
	var guard := TorusMesh.new()
	guard.inner_radius = 0.014
	guard.outer_radius = 0.018
	_piece(root, guard, brass, Vector3(0, 0.04, -0.022), Vector3(0, 0, PI * 0.5))
	var tip := Marker3D.new()
	tip.name = "Muzzle"
	tip.position = Vector3(0, 0.34, 0.022)
	root.add_child(tip)
	return root


func _add_pistol(hand: BoneAttachment3D, hips: BoneAttachment3D) -> void:
	gun_hand = _pistol_mesh()
	# Same hand frame as the sword: the barrel runs out past the knuckles.
	gun_hand.position = Vector3(-0.01, 0.07, 0.02)
	gun_hand.rotation = Vector3(0, 0, PI * 0.5)
	hand.add_child(gun_hand)
	gun_hip = Node3D.new()
	hips.add_child(gun_hip)
	var holstered := _pistol_mesh()
	gun_hip.add_child(holstered)
	_piece(holstered, _box(Vector3(0.045, 0.2, 0.05)), _fabric(Color(0.24, 0.15, 0.08), 0.7), Vector3(0, 0.2, 0.02))
	gun_hip.position = Vector3(-0.2, 0.02, 0.02)
	gun_hip.rotation = Vector3(0.25, 0, -PI * 0.92)
	_aim_mod = AimLean.new()
	skeleton.add_child(_aim_mod)
	_aim_mod.body = self
	set_gun_drawn(false)


## Shows the pistol in the hand (aiming) or in its holster.
func set_gun_drawn(drawn: bool) -> void:
	if gun_hand:
		gun_hand.visible = drawn
		gun_hip.visible = not drawn


## World position of the pistol's muzzle (shots and the flash start here).
func muzzle_position() -> Vector3:
	if gun_hand == null:
		return global_position + Vector3.UP * 1.4
	return (gun_hand.get_node("Muzzle") as Node3D).global_position


## Leans the upper body to aim up or down (SkeletonModifier3D, after the animation).
class AimLean:
	extends SkeletonModifier3D
	var body: ExplorerBody

	func _process_modification() -> void:
		if body == null or absf(body.aim_pitch) < 0.001:
			return
		var sk := get_skeleton()
		for b in [["Spine", 0.3], ["Chest", 0.35], ["UpperChest", 0.35]]:
			var i := sk.find_bone(b[0])
			if i < 0:
				continue
			# Pitch about the character's right (-X) axis, expressed in the bone's parent space.
			var parent := sk.get_bone_parent(i)
			var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
			var axis := (pg.basis.inverse() * Vector3(-1, 0, 0)).normalized()
			var pose := sk.get_bone_pose_rotation(i)
			sk.set_bone_pose_rotation(i, Quaternion(axis, body.aim_pitch * b[1]) * pose)


## Props for villagers: apron, chef hat, beard, cane, basket, hammer, hair bun.
func _add_villager_props(acc: Array) -> void:
	var head := _attach("Head") if acc.any(func(a): return a in ["chef_hat", "beard", "bun", "headscarf", "cap", "helmet", "hood", "hat"]) else null
	if "helmet" in acc:
		var steel := StandardMaterial3D.new()
		steel.albedo_color = Color(0.55, 0.56, 0.6)
		steel.metallic = 0.85
		steel.roughness = 0.35
		var dome := SphereMesh.new()
		dome.radius = 0.125
		dome.height = 0.16
		dome.is_hemisphere = true
		_piece(head, dome, steel, Vector3(0, 0.1, -0.01), Vector3.ZERO, Vector3(1.05, 1.1, 1.12))
		_piece(head, _box(Vector3(0.025, 0.09, 0.02)), steel, Vector3(0, 0.07, 0.125))
	if "hood" in acc:
		var hood := SphereMesh.new()
		hood.radius = 0.14
		hood.height = 0.3
		_piece(head, hood, _fabric(outfit.get("hood_color", Color(0.18, 0.16, 0.2))), Vector3(0, 0.08, -0.04), Vector3.ZERO, Vector3(1.05, 1.0, 1.15))
	if "hat" in acc:
		var brim := CylinderMesh.new()
		brim.top_radius = 0.2
		brim.bottom_radius = 0.2
		brim.height = 0.015
		var hc: Color = outfit.get("hat_color", Color(0.3, 0.22, 0.15))
		_piece(head, brim, _fabric(hc), Vector3(0, 0.15, -0.01))
		var crown := CylinderMesh.new()
		crown.top_radius = 0.09
		crown.bottom_radius = 0.11
		crown.height = 0.12
		_piece(head, crown, _fabric(hc), Vector3(0, 0.21, -0.01))
	if "spear" in acc:
		var hand4 := _attach("RightHand")
		var sp := Node3D.new()
		sp.position = Vector3(-0.01, 0.08, 0.02)
		sp.rotation = Vector3(0, 0, PI * 0.5)
		hand4.add_child(sp)
		var shaft := CylinderMesh.new()
		shaft.top_radius = 0.016
		shaft.bottom_radius = 0.018
		shaft.height = 2.0
		_piece(sp, shaft, _fabric(Color(0.35, 0.24, 0.14), 0.8), Vector3(0, 0.3, 0))
		var tip := PrismMesh.new()
		tip.size = Vector3(0.06, 0.2, 0.01)
		var steel2 := StandardMaterial3D.new()
		steel2.albedo_color = Color(0.7, 0.72, 0.75)
		steel2.metallic = 0.9
		steel2.roughness = 0.3
		_piece(sp, tip, steel2, Vector3(0, 1.38, 0))
	if "staff" in acc:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.02
		cyl.bottom_radius = 0.025
		cyl.height = 1.7
		_piece(self, cyl, _fabric(Color(0.25, 0.2, 0.18), 0.8), Vector3(-0.3, 0.85, 0.15), Vector3(0.05, 0, 0.05))
		var orb := SphereMesh.new()
		orb.radius = 0.06
		orb.height = 0.12
		var om := StandardMaterial3D.new()
		om.albedo_color = Color(0.6, 0.8, 1.0)
		om.emission_enabled = true
		om.emission = Color(0.5, 0.75, 1.0)
		om.emission_energy_multiplier = 2.5
		_piece(self, orb, om, Vector3(-0.26, 1.74, 0.19))
	if "satchel" in acc:
		var hips2 := _attach("Hips")
		_piece(hips2, _box(Vector3(0.22, 0.2, 0.08)), _fabric(Color(0.45, 0.32, 0.2)), Vector3(0.2, 0.0, 0.08), Vector3(0, -0.4, 0))
	if "book" in acc:
		var lh := _attach("LeftHand")
		_piece(lh, _box(Vector3(0.16, 0.04, 0.22)), _fabric(Color(0.45, 0.15, 0.12)), Vector3(0, 0.08, 0.04))
	if "apron" in acc:
		var spine := _attach("Spine")
		var col: Color = outfit.get("apron_color", Color(0.9, 0.88, 0.82))
		_piece(spine, _box(Vector3(0.34, 0.6, 0.02)), _fabric(col), Vector3(0, -0.12, 0.165), Vector3(-0.05, 0, 0))
	if "chef_hat" in acc:
		var c := CylinderMesh.new()
		c.top_radius = 0.13
		c.bottom_radius = 0.1
		c.height = 0.2
		_piece(head, c, _fabric(Color(0.95, 0.94, 0.9)), Vector3(0, 0.22, -0.01))
	if "cap" in acc:
		var sph := SphereMesh.new()
		sph.radius = 0.11
		sph.height = 0.12
		_piece(head, sph, _fabric(outfit.get("cap_color", Color(0.3, 0.2, 0.15))), Vector3(0, 0.16, -0.01), Vector3.ZERO, Vector3(1.05, 0.8, 1.1))
	if "headscarf" in acc:
		var sph2 := SphereMesh.new()
		sph2.radius = 0.12
		sph2.height = 0.2
		_piece(head, sph2, _fabric(outfit.get("scarf_color", Color(0.6, 0.25, 0.2))), Vector3(0, 0.13, -0.02), Vector3.ZERO, Vector3(1.05, 0.9, 1.1))
	if "beard" in acc:
		var b := SphereMesh.new()
		b.radius = 0.07
		b.height = 0.16
		_piece(head, b, _fabric(Color(0.82, 0.8, 0.76), 1.0), Vector3(0, 0.0, 0.09), Vector3(0.25, 0, 0), Vector3(1.0, 1.25, 0.7))
	if "bun" in acc:
		var bun := SphereMesh.new()
		bun.radius = 0.06
		bun.height = 0.12
		_piece(head, bun, _fabric(outfit.get("hair", Color(0.2, 0.12, 0.06))), Vector3(0, 0.17, -0.1))
	if "cane" in acc:
		# Held upright at the right side (character's right is -X).
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.017
		cyl.bottom_radius = 0.014
		cyl.height = 0.92
		_piece(self, cyl, _fabric(Color(0.32, 0.2, 0.1), 0.8), Vector3(-0.3, 0.46, 0.12), Vector3(0.05, 0, 0.06))
	if "hammer" in acc:
		var hand2 := _attach("RightHand")
		var handle := CylinderMesh.new()
		handle.top_radius = 0.016
		handle.bottom_radius = 0.016
		handle.height = 0.4
		var h := Node3D.new()
		h.position = Vector3(0, 0.08, 0.02)
		h.rotation = Vector3(0, 0, PI * 0.5)
		hand2.add_child(h)
		_piece(h, handle, _fabric(Color(0.35, 0.22, 0.12)), Vector3(0, 0.1, 0))
		var iron := StandardMaterial3D.new()
		iron.albedo_color = Color(0.25, 0.25, 0.27)
		iron.metallic = 0.8
		iron.roughness = 0.5
		_piece(h, _box(Vector3(0.14, 0.06, 0.06)), iron, Vector3(0, 0.3, 0))
	if "basket" in acc:
		var hand3 := Node3D.new()   # carried at the left hip
		hand3.position = Vector3(0.33, 0.78, 0.05)
		add_child(hand3)
		var bk := CylinderMesh.new()
		bk.top_radius = 0.16
		bk.bottom_radius = 0.12
		bk.height = 0.14
		var wicker := _fabric(Color(0.55, 0.4, 0.22), 1.0)
		_piece(hand3, bk, wicker, Vector3.ZERO)
		_piece(hand3, _torus(0.12, 0.135), wicker, Vector3(0, 0.12, 0), Vector3(0, 0, PI * 0.5))
		var bread := CapsuleMesh.new()
		bread.radius = 0.04
		bread.height = 0.18
		_piece(hand3, bread, _fabric(Color(0.75, 0.52, 0.25)), Vector3(0.0, 0.07, 0.03), Vector3(0, 0, PI * 0.5))
