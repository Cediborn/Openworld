class_name ExplorerBody
extends Node3D
## Realistic explorer: Quaternius CC0 base body dressed in a field jacket, cargo
## pants and boots (clothes are painted per body part and slightly inflated),
## with a scarf and backpack attached to bones. Plays retargeted UAL animations.

const MODEL := "res://assets/character/Superhero_Male_FullBody.gltf"
const ANIM_DIR := "res://assets/character/anims/"
const ANIMS := ["Idle", "Walk", "Jog_Fwd", "Sprint", "Jump_Start", "Jump", "Jump_Land", "Swim_Idle", "Swim_Fwd"]

enum Region { SKIN, JACKET, PANTS, BOOTS }

const JACKET_BONES := ["Spine", "Chest", "UpperChest", "LeftShoulder", "RightShoulder",
	"LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm"]
const LEG_BONES := ["LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg"]
const FOOT_BONES := ["LeftFoot", "RightFoot", "LeftToes", "RightToes"]

var anim: AnimationPlayer
var skeleton: Skeleton3D
var current := ""


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
		return Region.JACKET if y > 1.02 else Region.PANTS
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
	var per: int = bones.size() / verts.size()
	var bind_names := []
	for i in skin.get_bind_count():
		var nm: StringName = skin.get_bind_name(i)
		if nm == &"":
			nm = skeleton.get_bone_name(skin.get_bind_bone(i))
		bind_names.append(String(nm))
	var cols := PackedColorArray()
	cols.resize(verts.size())
	var inflate := [0.0, 0.03, 0.018, 0.02]
	for v in verts.size():
		var score := [0.0, 0.0, 0.0, 0.0]
		for k in per:
			var w: float = weights[v * per + k]
			if w <= 0.0:
				continue
			var bi: int = bones[v * per + k]
			var bname: String = bind_names[bi] if bi < bind_names.size() else ""
			score[_region_of_bone(bname, verts[v].y)] += w
		var r := 0
		for i in 4:
			if score[i] > score[r]:
				r = i
		cols[v] = Color(r / 3.0, 0, 0, 1)
		verts[v] += norms[v] * inflate[r]
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	return arrays


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

	# Short dark hair: a slightly squashed cap over the skull.
	var head := _attach("Head")
	var hair := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.112
	hm.height = 0.21
	hm.radial_segments = 24
	hm.rings = 12
	hair.mesh = hm
	var hair_mat := _fabric(Color(0.09, 0.07, 0.05), 0.75)
	hair_mat.uv1_scale = Vector3(30, 30, 1)
	hair.material_override = hair_mat
	hair.position = Vector3(0, 0.145, -0.03)
	hair.scale = Vector3(1.03, 0.7, 1.1)
	head.add_child(hair)

	# Leather boots over the feet.
	for side in ["Left", "Right"]:
		var foot := _attach(side + "Foot")
		var boot := MeshInstance3D.new()
		var bm := CapsuleMesh.new()
		bm.radius = 0.072
		bm.height = 0.31
		boot.mesh = bm
		boot.material_override = _fabric(Color(0.25, 0.16, 0.09), 0.6)
		# Foot bone: local +Y points to the toes, local +Z points up.
		boot.position = Vector3(0, 0.07, -0.045)
		boot.scale = Vector3(1.25, 1.0, 1.0)
		foot.add_child(boot)
		var shaft := MeshInstance3D.new()
		var shm := CapsuleMesh.new()
		shm.radius = 0.062
		shm.height = 0.24
		shaft.mesh = shm
		shaft.material_override = boot.material_override
		shaft.position = Vector3(0, -0.005, 0.06)
		shaft.rotation.x = PI * 0.5
		foot.add_child(shaft)

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
