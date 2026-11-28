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
## kit: "ranger" or "peasant" (Quaternius modular outfits); hair: a style from
## HAIR_FILES; skin: index into SKIN_TONES. Colours tint the clothes (see
## shaders/spatial_char_kit.gdshader).
const EXPLORER := {
	"model": "male", "kit": "ranger", "hair_style": "parted", "skin": 1, "face": 2,
	"jacket": Color(0.30, 0.32, 0.19), "pants": Color(0.17, 0.16, 0.12),
	"boots": Color(0.27, 0.17, 0.10), "hair": Color(0.07, 0.05, 0.035),
	"accessories": ["explorer", "sword"],
}
## The hero's second outfit: an original long white open coat over a dark
## shirt, relaxed dark trousers, a wide sash and high boots with silver trim.
const WHITE_COAT := {
	"model": "male", "kit": "coat", "hair_style": "long", "skin": 1, "face": 2,
	"jacket": Color(0.86, 0.86, 0.84), "shirt": Color(0.07, 0.07, 0.08), "pants": Color(0.09, 0.09, 0.1),
	"boots": Color(0.08, 0.07, 0.07), "sash": Color(0.16, 0.16, 0.18), "trim": Color(0.78, 0.8, 0.84),
	"hair": Color(0.2, 0.15, 0.1), "accessories": ["explorer", "sword"],
}

## The explorer's outfits by item id (see GameState.OUTFITS).
const HERO_OUTFITS := {"field_clothes": EXPLORER, "white_coat": WHITE_COAT}

## Clothes: Quaternius Modular Character Outfits - Fantasy (CC0), skinned to
## the same skeleton as the animations. Heads, eyes, hair and brows: Quaternius
## Universal Base Characters (CC0). See assets/character/ASSETS.md.
const KIT_DIR := "res://assets/character/kit/"
const OUTFIT_FILES := {
	"male": {"peasant": "outfits/Male_Peasant.gltf", "ranger": "outfits/Male_Ranger.gltf"},
	"female": {"peasant": "outfits/Female_Peasant.gltf", "ranger": "outfits/Female_Ranger.gltf"},
}
const HAIR_FILES := {
	"parted": "hair/Hair_SimpleParted.gltf", "long": "hair/Hair_Long.gltf", "buzzed": "hair/Hair_Buzzed.gltf",
	"buzzed_f": "hair/Hair_BuzzedFemale.gltf", "buns": "hair/Hair_Buns.gltf", "beard": "hair/Hair_Beard.gltf",
	"brows": "hair/Eyebrows_Regular.gltf", "brows_f": "hair/Eyebrows_Female.gltf",
}
## Skin tones (multiplied onto the painted skin), light to dark.
const SKIN_TONES := [Color(1.0, 0.97, 0.95), Color(0.93, 0.85, 0.78), Color(0.82, 0.68, 0.56),
	Color(0.66, 0.5, 0.39), Color(0.5, 0.36, 0.27), Color(0.38, 0.27, 0.2)]
## Head coverings that would clip through long or full hair.
const HATS := ["helmet", "hat", "cap", "chef_hat", "headscarf", "hood"]
## Mesh parts per kit, by the part's name suffix, and which outfit colour dyes them.
const PART_COLOUR := {"Body": "jacket", "Arms": "jacket", "Legs": "pants", "Feet": "boots", "Boots": "boots", "Hood": "hood_color"}
## Shared head meshes (cut from the full base body once per model) and materials.
static var _parts_cache := {}
static var _head_cache := {}
static var _mat_cache := {}

var anim: AnimationPlayer
var skeleton: Skeleton3D
var current := ""
var outfit: Dictionary = EXPLORER
var sword_hand: Node3D
var sword_hip: Node3D
## The shotgun in the hands and slung on the back (explorer only).
var gun_hand: Node3D
var gun_hip: Node3D
## Leans the chest up or down to follow the aim (radians, + = up).
var aim_pitch := 0.0
var _aim_mod: AimLean
var _grip_ik: ForeGripIK
var blade_mat: StandardMaterial3D
var _busy_left := 0.0   # seconds of game time until a one-shot animation ends
## Everything the current outfit added (swapped out by set_outfit).
var _outfit_nodes: Array[Node] = []
var _model: Node3D
## What _build_outfit picked: {kit, face, skin, hair, beard} (tests and debugging).
var look := {}
var _tone: Color = SKIN_TONES[1]


func _ready() -> void:
	var g: String = outfit.get("model", "male")
	# Any kit file gives the skeleton: every outfit shares the same rest pose.
	_model = load(KIT_DIR + OUTFIT_FILES[g]["peasant"]).instantiate()
	add_child(_model)
	skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
	for mi in skeleton.find_children("*", "MeshInstance3D", false, false):
		mi.free()
	_build_outfit()
	if "sword" in outfit.get("accessories", []):
		_add_sword()
	var model := _model
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


# ---------- Outfit (modelled clothes, head, hair) ----------

## Swaps the clothes, hair and head props for another outfit; skeleton,
## animation and held weapons stay as they are.
func set_outfit(o: Dictionary) -> void:
	for n in _outfit_nodes:
		if is_instance_valid(n):
			n.free()
	_outfit_nodes.clear()
	outfit = o
	_build_outfit()


func _build_outfit() -> void:
	var g: String = outfit.get("model", "male")
	var acc: Array = outfit.get("accessories", [])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(outfit.get("seed", 1))
	var skin_i := clampi(int(outfit.get("skin", rng.randi() % SKIN_TONES.size())), 0, SKIN_TONES.size() - 1)
	var tone: Color = SKIN_TONES[skin_i]
	_tone = tone
	var face_i := int(outfit.get("face", rng.randi() % FACES))
	var kit: String = outfit.get("kit", "ranger" if acc.any(func(a): return a in ["sword", "spear", "helmet"]) else "peasant")
	var cloth_kit := "peasant" if kit == "coat" else kit
	var armoured: bool = "helmet" in acc or "armor" in acc
	for part in _kit_parts(KIT_DIR + OUTFIT_FILES[g][cloth_kit]):
		var nm: String = part.name
		if nm.ends_with("Hood") and not ("hood" in acc or "headscarf" in acc):
			continue
		if (nm.contains("Pauldron") or nm.contains("Bracer")) and not armoured:
			continue
		if kit == "coat" and (nm.ends_with("Feet") or nm.ends_with("Arms")):
			continue   # ranger boots and full-length sleeves instead
		_add_part(part, _cloth_colour(nm, kit))
	if kit == "coat":
		for part in _kit_parts(KIT_DIR + OUTFIT_FILES[g]["ranger"]):
			if part.name.ends_with("Boots"):
				_add_part(part, {"tint": outfit.get("boots", Color(0.08, 0.07, 0.07)), "green_only": false})
			elif part.name.ends_with("Arms"):
				_add_part(part, {"tint": outfit.get("shirt", Color(0.07, 0.07, 0.08)), "green_only": false})
	# A peasant in a hood or headscarf borrows the ranger's hood.
	if ("hood" in acc or "headscarf" in acc) and cloth_kit == "peasant":
		for part in _kit_parts(KIT_DIR + OUTFIT_FILES[g]["ranger"]):
			if part.name.ends_with("Hood"):
				_add_part(part, _cloth_colour(part.name, kit))
	if kit == "coat":
		_add_coat(g)
	# Head: face, eyes and ears from the base body; the neck tucks under the collar.
	var head: Dictionary = _head(g, face_i)
	_add_part({"mesh": head.mesh, "skin": head.skin}, {"skin_tone": tone})
	_add_part({"mesh": head.eyes, "skin": head.skin}, {})
	# Hair: style by gender and headwear, brows always, a beard on some men.
	var hair_col: Color = outfit.get("hair", Color(0.15, 0.1, 0.06))
	var style: String = outfit.get("hair_style", "")
	if "bun" in acc:
		style = "buns"
	elif acc.any(func(a): return a in HATS):
		style = "buzzed" if g == "male" else "buzzed_f"
	elif style == "":
		var pool: Array = ["parted", "parted", "buzzed", "long"] if g == "male" else ["long", "long", "buns", "buzzed_f"]
		style = pool[rng.randi() % pool.size()]
	if style != "none":
		_add_hair(style, hair_col)
	_add_hair("brows" if g == "male" else "brows_f", hair_col.darkened(0.1))
	var beard: bool = g == "male" and ("beard" in acc or outfit.get("beard", rng.randf() < 0.3 and not "explorer" in acc))
	if beard:
		_add_hair("beard", hair_col)
	look = {"kit": kit, "face": face_i, "skin": skin_i, "hair": style, "beard": beard}
	_add_villager_props(acc)


func _add_hair(style: String, col: Color) -> void:
	for part in _kit_parts(KIT_DIR + HAIR_FILES[style]):
		_add_part(part, {"hair": col})


## A part's dye: which outfit colour, and how the shader applies it.
func _cloth_colour(part_name: String, kit: String) -> Dictionary:
	for k in PART_COLOUR:
		if part_name.ends_with(k) or part_name.contains("_" + k):
			var key: String = PART_COLOUR[k]
			var c = outfit.get(key, outfit.get("scarf_color" if key == "hood_color" else "jacket", outfit.get("jacket", Color(0.5, 0.4, 0.3))))
			if kit == "coat":
				# Under the coat: dark shirt and sleeves, dark trousers, black boots.
				c = {"jacket": outfit.get("shirt", Color(0.07, 0.07, 0.08)), "pants": outfit.pants, "boots": outfit.boots}.get(key, c)
			return {"tint": c, "green_only": kit == "ranger" and key != "boots", "keep_dark": k == "Arms"}
	return {}


## Adds one skinned mesh to the skeleton with per-person materials.
## style: {} as painted, {"tint", "green_only"} dyed cloth, {"skin_tone"}, {"hair"}.
func _add_part(part: Dictionary, style: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = part.mesh
	mi.skin = part.skin
	skeleton.add_child(mi)
	mi.skeleton = NodePath("..")
	_outfit_nodes.append(mi)
	var mesh: Mesh = part.mesh
	for s in mesh.get_surface_count():
		var src := mesh.surface_get_material(s)
		var nm := src.resource_name if src else ""
		var m: Material = src
		if nm.contains("Regular") or nm.contains("Superhero"):
			m = _skin_material(src, style.get("skin_tone", _tone))
		elif style.has("hair"):
			m = _tinted(src, style.hair)
		elif style.has("tint") and src is BaseMaterial3D:
			m = _cloth_material(src, style.tint, style.green_only, false, style.get("keep_dark", false))
		mi.set_surface_override_material(s, m)
	return mi


static func _key(c: Color) -> String:
	return "%.2f,%.2f,%.2f" % [c.r, c.g, c.b]


static func _skin_material(src: Material, tone: Color) -> Material:
	return _tinted(src, tone)


## A copy of a painted material with its colour multiplied (skin tones, hair colour).
static func _tinted(src: Material, c: Color) -> Material:
	var key := "t:%s:%s" % [src.get_instance_id(), _key(c)]
	if not _mat_cache.has(key):
		var m: BaseMaterial3D = src.duplicate()
		m.albedo_color = c
		_mat_cache[key] = m
	return _mat_cache[key]


## Dyed cloth: the kit's painted texture recoloured by spatial_char_kit.
static func _cloth_material(src: BaseMaterial3D, c: Color, green_only: bool, whiten := false, keep_dark := false) -> Material:
	var key := "c:%s:%s:%s:%s:%s" % [src.get_instance_id(), _key(c), green_only, whiten, keep_dark]
	if not _mat_cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/spatial_char_kit.gdshader")
		m.set_shader_parameter("albedo_tex", src.albedo_texture)
		m.set_shader_parameter("normal_tex", src.normal_texture)
		m.set_shader_parameter("orm_tex", src.roughness_texture)
		m.set_shader_parameter("tint", c)
		m.set_shader_parameter("recolor", 1.0)
		m.set_shader_parameter("green_only", 1.0 if green_only else 0.0)
		m.set_shader_parameter("whiten", 1.0 if whiten else 0.0)
		m.set_shader_parameter("keep_dark", 1.0 if keep_dark else 0.0)
		_mat_cache[key] = m
	return _mat_cache[key]


## The skinned meshes of a kit file: [{name, mesh, skin}], loaded once.
static func _kit_parts(path: String) -> Array:
	if not _parts_cache.has(path):
		var n: Node = load(path).instantiate()
		var out := []
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			out.append({"name": String(mi.name), "mesh": mi.mesh, "skin": mi.skin})
		n.free()
		_parts_cache[path] = out
	return _parts_cache[path]


## Face shapes: each one nudges the base face (nose, jaw, cheekbones, chin,
## brow) so townsfolk don't share one face. Values are metres, kept small.
const FACES := 6
## Triangles whose corners carry at least this much head + neck weight belong
## to the head (lower = the neck reaches further down under open collars).
const NECK_KEEP := 0.15
const FACE_SHAPES := [
	{"nose": 0.0, "jaw": 0.0, "cheek": 0.0, "chin": 0.0, "brow": 0.0},
	{"nose": 0.006, "jaw": 0.07, "cheek": 0.02, "chin": -0.006, "brow": 0.003},
	{"nose": 0.003, "jaw": -0.04, "cheek": 0.04, "chin": 0.004, "brow": 0.002},
	{"nose": -0.003, "jaw": 0.03, "cheek": -0.03, "chin": -0.01, "brow": -0.002},
	{"nose": 0.008, "jaw": -0.06, "cheek": -0.02, "chin": 0.008, "brow": 0.004},
	{"nose": -0.002, "jaw": 0.1, "cheek": 0.05, "chin": -0.004, "brow": 0.0},
]


## The base body's head and neck (face, ears, skin) as its own mesh, reshaped
## by FACE_SHAPES[face], plus the eyes. {mesh, eyes, skin}; built once per shape.
static func _head(g: String, face: int) -> Dictionary:
	var key := "%s:%d" % [g, face]
	if _head_cache.has(key):
		return _head_cache[key]
	var src: Node = load(MODELS[g]).instantiate()
	var sk: Skeleton3D = src.find_children("*", "Skeleton3D", true, false)[0]
	var body: MeshInstance3D = null
	var eyes: MeshInstance3D = null
	for mi: MeshInstance3D in sk.find_children("*", "MeshInstance3D", false, false):
		if mi.name.contains("Eyes"):
			eyes = mi
		elif mi.name.to_lower().contains("superhero"):
			body = mi
	var arrays := body.mesh.surface_get_arrays(0)
	var mat := body.mesh.surface_get_material(0)
	var head_bones := {}
	for i in body.skin.get_bind_count():
		var nm := String(body.skin.get_bind_name(i))
		if nm == "":
			nm = sk.get_bone_name(body.skin.get_bind_bone(i))
		if nm in ["Head", "Neck"]:
			head_bones[i] = nm
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per: int = bones.size() / verts.size()
	var hw := PackedFloat32Array()   # weight on head + neck
	var headonly := PackedFloat32Array()   # weight on the head bone alone
	hw.resize(verts.size())
	headonly.resize(verts.size())
	for v in verts.size():
		for k in per:
			var b := bones[v * per + k]
			if head_bones.has(b):
				hw[v] += weights[v * per + k]
				if head_bones[b] == "Head":
					headonly[v] += weights[v * per + k]
	_shape_face(verts, headonly, FACE_SHAPES[face % FACE_SHAPES.size()])
	arrays[Mesh.ARRAY_VERTEX] = verts
	# Keep triangles that are mostly head or neck.
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var keep := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if hw[idx[t]] >= NECK_KEEP and hw[idx[t + 1]] >= NECK_KEEP and hw[idx[t + 2]] >= NECK_KEEP:
			keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
	arrays[Mesh.ARRAY_INDEX] = keep
	for c in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		arrays[c] = null
	# Through ImporterMesh so the head gets distance LODs like the imported parts.
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mat, "", body.mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	im.generate_lods(25.0, 60.0, [])
	var mesh := im.get_mesh()
	var out := {"mesh": mesh, "eyes": eyes.mesh, "skin": body.skin}
	src.free()
	_head_cache[key] = out
	return out


## Moves face vertices for one face shape. Landmarks (nose tip, chin) are
## found on the mesh itself, so the same shapes work on both base heads.
static func _shape_face(verts: PackedVector3Array, w: PackedFloat32Array, f: Dictionary) -> void:
	var nose := Vector3(0, 0, -INF)
	var chin := Vector3(0, INF, 0)
	var top := -INF
	for v in verts.size():
		if w[v] < 0.9:
			continue
		var p := verts[v]
		top = maxf(top, p.y)
		if absf(p.x) < 0.012 and p.z > nose.z:
			nose = p
	for v in verts.size():
		var p := verts[v]
		if w[v] >= 0.9 and absf(p.x) < 0.012 and p.z > nose.z - 0.05 and p.y < chin.y:
			chin = p
	if nose.z == -INF:
		return
	var face_h := nose.y - chin.y
	for v in verts.size():
		if w[v] <= 0.0:
			continue
		var p := verts[v]
		var front := clampf((p.z - (nose.z - 0.12)) / 0.08, 0.0, 1.0)
		# Nose length: pull the tip and bridge forward.
		p.z += f.nose * exp(-p.distance_squared_to(nose) / (2.0 * 0.018 * 0.018))
		# Jaw width: widen the lower face, most at the jaw angle.
		var below := clampf((nose.y - p.y) / face_h, 0.0, 1.0)
		p.x *= 1.0 + f.jaw * below * (1.0 - below * 0.4) * w[v]
		# Cheekbones: wider at nose height, fading up and down.
		var cheek_k := exp(-pow((p.y - nose.y) / 0.025, 2.0)) * front
		p.x *= 1.0 + f.cheek * cheek_k * w[v]
		# Chin: longer or shorter.
		p.y -= f.chin * exp(-p.distance_squared_to(chin) / (2.0 * 0.025 * 0.025))
		# Brow ridge: forward above the eyes.
		var brow_y := nose.y + face_h * 0.75
		p.z += f.brow * exp(-pow((p.y - brow_y) / 0.015, 2.0)) * front
		verts[v] = p


## The white coat outfit: dark peasant shirt, sleeves and trousers under a
## white coat (the shirt's own mesh pushed out and opened at the front, with
## long white sleeves), a flared skirt to mid-calf with folds, silver trim
## along its opening and hem, and a wide dark sash with a hanging tail.
## Everything is skinned to the same skeleton, so it moves with the animations.
func _add_coat(g: String) -> void:
	var body: Dictionary = {}
	var arms: Dictionary = {}
	for p in _kit_parts(KIT_DIR + OUTFIT_FILES[g]["peasant"]):
		if p.name.ends_with("Body"):
			body = p
	for p in _kit_parts(KIT_DIR + OUTFIT_FILES[g]["ranger"]):
		if p.name.ends_with("Arms"):
			arms = p   # full-length sleeves
	var white: Color = outfit.get("jacket", Color(0.95, 0.95, 0.93))
	var src_mat: BaseMaterial3D = body.mesh.surface_get_material(0)
	var coat_mat := _cloth_material(src_mat, white, false, true)
	var key := "coat:" + g
	if not _head_cache.has(key):
		_head_cache[key] = _build_coat(g, body, arms)
	var built: Dictionary = _head_cache[key]
	var trim := StandardMaterial3D.new()
	trim.albedo_color = outfit.get("trim", Color(0.78, 0.8, 0.84))
	trim.metallic = 0.85
	trim.roughness = 0.32
	var sash := _fabric(outfit.get("sash", Color(0.16, 0.16, 0.18)), 0.7)
	sash.cull_mode = BaseMaterial3D.CULL_DISABLED
	var skirt_mat := _fabric(white, 0.85)
	skirt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	skirt_mat.rim_enabled = true
	skirt_mat.rim = 0.15
	_add_part({"mesh": built.torso, "skin": body.skin}, {}).set_surface_override_material(0, coat_mat)
	_add_part({"mesh": built.sleeves, "skin": arms.skin}, {}).set_surface_override_material(0, coat_mat)
	var skirt := _add_part({"mesh": built.skirt, "skin": body.skin}, {})
	skirt.set_surface_override_material(0, skirt_mat)
	skirt.set_surface_override_material(1, trim)
	_add_part({"mesh": built.sash, "skin": body.skin}, {}).set_surface_override_material(0, sash)


## Coat meshes for one body model: {torso, sleeves, skirt, sash}. Built once.
static func _build_coat(_g: String, body: Dictionary, arms: Dictionary) -> Dictionary:
	# Torso: the shirt pushed 1.4 cm out, opened in a V from the collar down.
	var torso := _shell(body.mesh, 0, 0.014, func(c: Vector3) -> bool:
		return c.z > 0.0 and c.y < 1.43 and absf(c.x) < 0.045 + (1.43 - c.y) * 0.16)
	var sleeves := _shell(arms.mesh, 0, 0.011, func(_c: Vector3) -> bool: return false)
	var skin: Skin = body.skin
	var b := {}
	for nm in ["Hips", "Spine", "LeftUpperLeg", "RightUpperLeg"]:
		b[nm] = _bind_of(skin, nm)
	return {"torso": torso, "sleeves": sleeves, "skirt": _skirt(b), "sash": _sash(b)}


## A work apron: cloth hanging in front from the waist to the knees, skinned
## so it swings with the legs.
func _add_apron(col: Color) -> void:
	var g: String = outfit.get("model", "male")
	var body: Dictionary = _kit_parts(KIT_DIR + OUTFIT_FILES[g]["peasant"]).filter(func(p): return p.name.ends_with("Body"))[0]
	var key := "apron:" + g
	if not _head_cache.has(key):
		var b := {}
		for nm in ["Hips", "Spine", "LeftUpperLeg", "RightUpperLeg"]:
			b[nm] = _bind_of(body.skin, nm)
		var w := 1.0 if g == "male" else 0.94
		_head_cache[key] = _drape(b, func(_f: float, _r: Vector2) -> float: return -1.15, func(_f: float, _r: Vector2) -> float: return 1.15,
			1.06 * w, 0.5 * w, Vector2(0.185, 0.155) * w, Vector2(0.22, 0.2) * w, 0.04, 8, 16)[0]
	var mat := _fabric(col, 0.9)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add_part({"mesh": _head_cache[key], "skin": body.skin}, {}).set_surface_override_material(0, mat)


## Copies one surface of a skinned mesh, every vertex pushed out along its
## normal, minus the triangles whose centre `drop` rejects.
static func _shell(mesh: Mesh, surface: int, push: float, drop: Callable) -> ArrayMesh:
	var a := mesh.surface_get_arrays(surface)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	for i in v.size():
		v[i] += n[i] * push
	a[Mesh.ARRAY_VERTEX] = v
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var keep := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if not drop.call((v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0):
			keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
	a[Mesh.ARRAY_INDEX] = keep
	for c in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		a[c] = null
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	return out


static func _bind_of(skin: Skin, bone: String) -> int:
	for i in skin.get_bind_count():
		if String(skin.get_bind_name(i)) == bone:
			return i
	return 0


## Hanging cloth around the hips (coat skirt, apron): rows from `top` down to
## `hem`, an arc from angle th0 to th1 (0 = straight ahead, +PI/2 = left),
## radii growing from r_top to r_hem, with folds that deepen towards the hem.
## Returns the mesh and its vertex grid ([row][col] positions).
## Top rows follow the hips; lower rows follow the thigh on their side.
static func _drape(b: Dictionary, th0: Callable, th1: Callable, top: float, hem: float, r_top: Vector2, r_hem: Vector2, fold_amt: float, rows := 14, cols := 40) -> Array:
	var grid := []
	var st := SurfaceTool.new()
	st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rows + 1:
		var f := float(r) / rows
		var y := lerpf(top, hem, f)
		var rad := r_top.lerp(r_hem, pow(f, 0.85))
		var row := []
		for c in cols + 1:
			var th := lerpf(th0.call(f, rad), th1.call(f, rad), float(c) / cols)
			var fold := 1.0 + fold_amt * f * sin(th * 9.0 + 0.6) + fold_amt * 0.5 * f * sin(th * 17.0)
			var p := Vector3(rad.x * fold * sin(th), y, -0.03 + rad.y * fold * cos(th))
			row.append(p)
			st.set_uv(Vector2(float(c) / cols * 4.0, f * 2.0))
			_skirt_weights(st, p, f, b)
			st.add_vertex(p)
		grid.append(row)
	for r in rows:
		for c in cols:
			var i := r * (cols + 1) + c
			st.add_index(i)
			st.add_index(i + cols + 1)
			st.add_index(i + 1)
			st.add_index(i + 1)
			st.add_index(i + cols + 1)
			st.add_index(i + cols + 2)
	st.generate_normals()
	st.generate_tangents()
	return [st.commit(), grid]


## Coat skirt from the waist to mid-calf, open at the front. Surface 0 is
## cloth, surface 1 the silver trim on the opening and hem.
const SKIRT_TOP := 1.07
const SKIRT_HEM := 0.36
static func _skirt(b: Dictionary) -> ArrayMesh:
	var rows := 14
	var cols := 40
	var gap := func(f: float, rad: Vector2) -> float: return atan2(lerpf(0.11, 0.2, f), rad.y)
	var d := _drape(b, gap, func(f: float, rad: Vector2) -> float: return TAU - gap.call(f, rad),
		SKIRT_TOP, SKIRT_HEM, Vector2(0.185, 0.15), Vector2(0.31, 0.27), 0.06, rows, cols)
	var mesh: ArrayMesh = d[0]
	var grid: Array = d[1]
	# Trim: thin bands along both front edges and the hem, just proud of the cloth.
	var tr := SurfaceTool.new()
	tr.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	tr.begin(Mesh.PRIMITIVE_TRIANGLES)
	var strips := [[], [], []]
	for r in rows + 1:
		strips[0].append([grid[r][0], grid[r][1], float(r) / rows])
		strips[1].append([grid[r][cols], grid[r][cols - 1], float(r) / rows])
	for c in cols + 1:
		strips[2].append([grid[rows][c], grid[rows - 1][c], 1.0])
	var base := 0
	for s in strips:
		for e in s:
			var edge: Vector3 = e[0]
			var inward: Vector3 = (e[1] - edge).normalized() * 0.03
			var out_n := Vector3(edge.x, 0, edge.z + 0.03).normalized() * 0.004
			for p in [edge + out_n, edge + inward + out_n]:
				tr.set_uv(Vector2.ZERO)
				_skirt_weights(tr, p, e[2], b)
				tr.add_vertex(p)
		for k in s.size() - 1:
			var i: int = base + k * 2
			tr.add_index(i)
			tr.add_index(i + 2)
			tr.add_index(i + 1)
			tr.add_index(i + 1)
			tr.add_index(i + 2)
			tr.add_index(i + 3)
		base += s.size() * 2
	tr.generate_normals()
	return tr.commit(mesh)


static func _skirt_weights(st: SurfaceTool, p: Vector3, f: float, b: Dictionary) -> void:
	# Weight moves from the hips to the thigh on the same side as you go down;
	# the back seam stays mostly on the hips so the two halves don't tear apart.
	var leg := clampf(f * 1.6, 0.0, 1.0) * clampf(absf(p.x) / 0.12, 0.0, 1.0) * 0.9
	var thigh: int = b.LeftUpperLeg if p.x > 0.0 else b.RightUpperLeg
	st.set_bones(PackedInt32Array([b.Hips, thigh, b.Spine, 0]))
	st.set_weights(PackedFloat32Array([1.0 - leg, leg, 0.0, 0.0]))


## Wide sash around the waist with a knot and a hanging tail at the left hip.
static func _sash(b: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 36
	for r in 3:
		var y := lerpf(1.0, 1.13, r / 2.0)
		var bulge := 1.0 + 0.04 * sin(PI * r / 2.0)   # cloth bunches out in the middle
		for c in cols + 1:
			var th := TAU * c / cols
			var p := Vector3(0.19 * bulge * sin(th), y, -0.025 + 0.165 * bulge * cos(th))
			st.set_uv(Vector2(float(c) / cols * 6.0, r / 2.0))
			st.set_bones(PackedInt32Array([b.Hips, b.Spine, 0, 0]))
			st.set_weights(PackedFloat32Array([1.0 - r * 0.25, r * 0.25, 0.0, 0.0]))
			st.add_vertex(p)
	for r in 2:
		for c in cols:
			var i := r * (cols + 1) + c
			st.add_index(i)
			st.add_index(i + cols + 1)
			st.add_index(i + 1)
			st.add_index(i + 1)
			st.add_index(i + cols + 1)
			st.add_index(i + cols + 2)
	# Two tails from the knot at the front-left of the waist.
	var base := 3 * (cols + 1)
	for tail in [[0.11, 0.62, 0.065, 0.0], [0.135, 0.7, 0.055, 0.3]]:
		var rows := 8
		for r in rows + 1:
			var f := float(r) / rows
			var y := lerpf(1.05, tail[1], f)
			var cx: float = tail[0] + 0.03 * f + 0.01 * sin(f * 5.0 + tail[3])
			var cz := 0.15 - 0.03 * f
			for side in [-1.0, 1.0]:
				var p := Vector3(cx + side * tail[2] * (0.6 + 0.4 * f), y, cz + 0.02 * side * f)
				st.set_uv(Vector2(side * 0.5 + 0.5, f * 2.0))
				var leg := clampf(f * 1.3, 0.0, 0.8)
				st.set_bones(PackedInt32Array([b.Hips, b.LeftUpperLeg, 0, 0]))
				st.set_weights(PackedFloat32Array([1.0 - leg, leg, 0.0, 0.0]))
				st.add_vertex(p)
		for r in rows:
			var i := base + r * 2
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + 2)
			st.add_index(i + 1)
			st.add_index(i + 3)
			st.add_index(i + 2)
		base += (rows + 1) * 2
	st.generate_normals()
	st.generate_tangents()
	return st.commit()


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


## A pump-action shotgun: blued steel receiver, barrel and magazine tube,
## walnut fore-end (the "Pump" node slides back and forward), pistol grip and
## stock with a rubber butt pad, trigger and guard, ejection port and bead
## sight. Barrel along local +Y (like the sword blade), top of the gun +Z, the
## grip in the hand at the origin.
func _shotgun_mesh() -> Node3D:
	var root := Node3D.new()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.17, 0.18, 0.21)   # blued steel
	steel.metallic = 0.85
	steel.roughness = 0.33
	var walnut := StandardMaterial3D.new()
	walnut.albedo_color = Color(0.3, 0.16, 0.07)
	walnut.roughness = 0.45
	walnut.clearcoat_enabled = true
	walnut.clearcoat = 0.4
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0.05, 0.05, 0.05)
	rubber.roughness = 0.9
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.02, 0.02, 0.02)
	dark.roughness = 0.6
	for m in [steel, walnut, rubber]:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED   # extruded parts are seen from both sides
	# Receiver: side profile (y along the gun, z up), 3.6 cm thick.
	_piece(root, _extrude(PackedVector2Array([Vector2(-0.03, 0.0), Vector2(0.17, 0.0), Vector2(0.17, 0.072),
		Vector2(0.15, 0.08), Vector2(-0.02, 0.08), Vector2(-0.03, 0.065)]), 0.036, 0.004), steel, Vector3.ZERO)
	_piece(root, _box(Vector3(0.003, 0.07, 0.03)), dark, Vector3(-0.0185, 0.07, 0.05))   # ejection port
	_piece(root, _box(Vector3(0.02, 0.06, 0.004)), dark, Vector3(0.0, 0.06, 0.0))         # loading gate underneath
	# Barrel, magazine tube under it, cap and bead sight.
	_piece(root, _cyl(0.0115, 0.0115, 0.49), steel, Vector3(0, 0.415, 0.058))
	_piece(root, _cyl(0.0125, 0.0125, 0.39), steel, Vector3(0, 0.365, 0.026))
	_piece(root, _cyl(0.014, 0.014, 0.02), steel, Vector3(0, 0.565, 0.026))
	_piece(root, _cyl(0.0125, 0.0125, 0.03), steel, Vector3(0, 0.55, 0.042), Vector3.ZERO, Vector3(0.6, 1, 1))   # barrel band
	var bead := SphereMesh.new()
	bead.radius = 0.004
	bead.height = 0.008
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.8, 0.62, 0.28)
	brass.metallic = 0.9
	brass.roughness = 0.3
	_piece(root, bead, brass, Vector3(0, 0.655, 0.071))
	# Fore-end: ribbed walnut sleeve around the magazine tube; slides when pumped.
	var pump := Node3D.new()
	pump.name = "Pump"
	root.add_child(pump)
	_piece(pump, _cyl(0.024, 0.022, 0.15), walnut, Vector3(0, 0.33, 0.03), Vector3.ZERO, Vector3(0.9, 1, 1.1))
	for k in 6:
		_piece(pump, _cyl(0.0255, 0.0255, 0.006), walnut, Vector3(0, 0.275 + k * 0.022, 0.03), Vector3.ZERO, Vector3(0.92, 1, 1.12))
	var grip_mark := Marker3D.new()
	grip_mark.name = "ForeGrip"
	grip_mark.position = Vector3(0, 0.29, 0.0)
	pump.add_child(grip_mark)
	# Trigger and guard.
	_piece(root, _torus(0.016, 0.02), steel, Vector3(0, 0.02, -0.008), Vector3(0, 0, PI * 0.5), Vector3(1, 1.3, 1))
	_piece(root, _box(Vector3(0.005, 0.006, 0.022)), steel, Vector3(0, 0.022, -0.006), Vector3(0.3, 0, 0))
	# Pistol grip and stock in walnut, black rubber butt pad.
	# Stock: comb dropping gently to the heel, a curved pistol grip, a slim wrist.
	_piece(root, _extrude(PackedVector2Array([Vector2(-0.03, 0.068), Vector2(-0.03, 0.0), Vector2(-0.042, -0.045), Vector2(-0.058, -0.088),
		Vector2(-0.078, -0.106), Vector2(-0.1, -0.104), Vector2(-0.112, -0.075), Vector2(-0.13, -0.045), Vector2(-0.25, -0.06),
		Vector2(-0.37, -0.085), Vector2(-0.372, 0.045), Vector2(-0.2, 0.058), Vector2(-0.08, 0.068)]), 0.04, 0.008), walnut, Vector3.ZERO)
	_piece(root, _extrude(PackedVector2Array([Vector2(-0.37, -0.085), Vector2(-0.392, -0.088), Vector2(-0.392, 0.047), Vector2(-0.372, 0.045)]), 0.043, 0.004), rubber, Vector3.ZERO)
	var tip := Marker3D.new()
	tip.name = "Muzzle"
	tip.position = Vector3(0, 0.665, 0.058)
	root.add_child(tip)
	var port := Marker3D.new()
	port.name = "Port"
	port.position = Vector3(-0.02, 0.07, 0.05)
	root.add_child(port)
	return root


## The characters' arms are a little short for a full-size long gun.
const GUN_SCALE := 0.9


static func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 14
	return c


## A flat shape (points in the gun's y/z side view) extruded `thick` wide in x,
## its outline edges bevelled by `bevel`.
static func _extrude(poly: PackedVector2Array, thick: float, bevel: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri := Geometry2D.triangulate_polygon(poly)
	var inner := Geometry2D.offset_polygon(poly, -bevel)
	var face: PackedVector2Array = inner[0] if inner.size() > 0 else poly
	var ftri := Geometry2D.triangulate_polygon(face)
	var hx := thick * 0.5
	for side in [-1.0, 1.0]:
		for i in range(0, ftri.size(), 3):
			var v := [Vector3(side * hx, face[ftri[i]].x, face[ftri[i]].y), Vector3(side * hx, face[ftri[i + 1]].x, face[ftri[i + 1]].y),
				Vector3(side * hx, face[ftri[i + 2]].x, face[ftri[i + 2]].y)]
			# Keep every face wound the same way as the bevel strips (front side outwards).
			if (v[1] - v[0]).cross(v[2] - v[0]).x * side < 0.0:
				v.reverse()
			for q in v:
				st.add_vertex(q)
	# Bevelled sides: outline at half-thickness - bevel, face outline at full thickness.
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var fa := _nearest(face, a)
		var fb := _nearest(face, b)
		for side in [-1.0, 1.0]:
			var ra := Vector3(side * (hx - bevel), a.x, a.y)
			var rb := Vector3(side * (hx - bevel), b.x, b.y)
			var qa := Vector3(side * hx, fa.x, fa.y)
			var qb := Vector3(side * hx, fb.x, fb.y)
			var quad := [ra, rb, qb, qa] if side > 0 else [rb, ra, qa, qb]
			for k in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(quad[k])
		var la := Vector3(-(hx - bevel), a.x, a.y)
		var lb := Vector3(-(hx - bevel), b.x, b.y)
		var ra2 := Vector3(hx - bevel, a.x, a.y)
		var rb2 := Vector3(hx - bevel, b.x, b.y)
		for v in [la, ra2, rb2, la, rb2, lb]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


static func _nearest(pts: PackedVector2Array, q: Vector2) -> Vector2:
	var best := pts[0]
	for p in pts:
		if p.distance_squared_to(q) < best.distance_squared_to(q):
			best = p
	return best


func _add_pistol(hand: BoneAttachment3D, _hips: BoneAttachment3D) -> void:
	gun_hand = _shotgun_mesh()
	gun_hand.scale = Vector3.ONE * GUN_SCALE
	# Same hand frame as the sword: the barrel runs out past the knuckles.
	gun_hand.position = Vector3(-0.01, 0.07, 0.02)
	gun_hand.rotation = Vector3(0, 0, PI * 0.5)
	hand.add_child(gun_hand)
	# Slung across the back, muzzle up over the right shoulder.
	var back := _attach("UpperChest")
	gun_hip = Node3D.new()
	back.add_child(gun_hip)
	gun_hip.add_child(_shotgun_mesh())
	gun_hip.scale = Vector3.ONE * GUN_SCALE
	gun_hip.position = Vector3(0.0, 0.02, -0.17)
	gun_hip.rotation = Vector3(0.0, PI, -0.6)
	_aim_mod = AimLean.new()
	skeleton.add_child(_aim_mod)
	_aim_mod.body = self
	_grip_ik = ForeGripIK.new()
	skeleton.add_child(_grip_ik)
	_grip_ik.body = self
	set_gun_drawn(false)


## Shows the shotgun in the hands (aiming) or slung on the back.
func set_gun_drawn(drawn: bool) -> void:
	if gun_hand:
		gun_hand.visible = drawn
		gun_hip.visible = not drawn


## World position of the muzzle (shots and the flash start here).
func muzzle_position() -> Vector3:
	if gun_hand == null:
		return global_position + Vector3.UP * 1.4
	return (gun_hand.get_node("Muzzle") as Node3D).global_position


## Pump stroke, 0 = forward, 0.5 = all the way back, 1 = forward again.
func set_pump(t: float) -> void:
	if gun_hand:
		(gun_hand.get_node("Pump") as Node3D).position.y = -0.08 * sin(clampf(t, 0.0, 1.0) * PI)


## Recoil: the gun jumps up and back for a moment.
func kick() -> void:
	if gun_hand == null:
		return
	var tw := create_tween()
	gun_hand.rotation.x = 0.0
	tw.tween_property(gun_hand, "rotation:x", -0.35, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(gun_hand, "rotation:x", 0.0, 0.25).set_trans(Tween.TRANS_SINE)


## A spent red hull flies out of the ejection port and falls away.
func eject_shell() -> void:
	if gun_hand == null or not gun_hand.visible:
		return
	var port: Node3D = gun_hand.get_node("Port")
	var shell := _shell_mesh()
	get_tree().current_scene.add_child(shell) if get_tree().current_scene else add_child(shell)
	shell.global_transform = port.global_transform
	var side := -gun_hand.global_basis.x.normalized()
	var to := shell.global_position + side * 0.6 + Vector3.UP * 0.25
	var tw := shell.create_tween().set_parallel()
	tw.tween_property(shell, "global_position", to, 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_property(shell, "rotation", shell.rotation + Vector3(6, 3, 0), 0.6)
	tw.chain().tween_property(shell, "global_position:y", to.y - 1.6, 0.4).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(shell.queue_free)


## A fresh shell appears under the receiver and slides into the loading gate.
func load_shell() -> void:
	if gun_hand == null or not gun_hand.visible:
		return
	var shell := _shell_mesh()
	gun_hand.add_child(shell)
	shell.position = Vector3(0.0, 0.0, -0.09)
	var tw := shell.create_tween()
	tw.tween_property(shell, "position", Vector3(0.0, 0.08, 0.0), 0.14)
	tw.tween_callback(shell.queue_free)


static func _shell_mesh() -> Node3D:
	var root := Node3D.new()
	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.62, 0.08, 0.06)
	hull.roughness = 0.5
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.82, 0.64, 0.3)
	brass.metallic = 0.9
	brass.roughness = 0.3
	var h := MeshInstance3D.new()
	h.mesh = _cyl(0.0105, 0.0105, 0.055)
	h.material_override = hull
	root.add_child(h)
	var b := MeshInstance3D.new()
	b.mesh = _cyl(0.0115, 0.0115, 0.014)
	b.material_override = brass
	b.position.y = -0.03
	root.add_child(b)
	return root


func anim_length(name: String) -> float:
	return anim.get_animation(name).length if anim and anim.has_animation(name) else 0.0


## Holds the drawn shotgun like a long gun, after the animation: the right
## hand pulls back so the stock sits at the shoulder (the gun keeps pointing
## where the animation aimed it), then the left hand reaches the fore-end.
## Two-bone IK on each arm; elbows stay on the side the animation gave them.
## Weight fades in and out (off while loading shells).
class ForeGripIK:
	extends SkeletonModifier3D
	var body: ExplorerBody
	var weight := 0.0
	## How far in front of the right shoulder the grip hand sits (metres).
	const GRIP_FORWARD := 0.34
	## Shooter's stance: the chest turns this far (radians) to bring the left shoulder forward.
	const TWIST := -0.55
	const GRIP_DOWN := 0.07

	func _process_modification() -> void:
		if body == null or body.gun_hand == null:
			return
		var want := 1.0 if body.gun_hand.visible and body.current != "Pistol_Reload" else 0.0
		weight = move_toward(weight, want, 0.12)
		if weight <= 0.0:
			return
		var sk := get_skeleton()
		var r := [sk.find_bone("RightUpperArm"), sk.find_bone("RightLowerArm"), sk.find_bone("RightHand")]
		var l := [sk.find_bone("LeftUpperArm"), sk.find_bone("LeftLowerArm"), sk.find_bone("LeftHand")]
		if -1 in r or -1 in l:
			return
		# Where the animation points the barrel (skeleton space).
		var hand_g: Transform3D = sk.get_bone_global_pose(r[2])
		var gun_local: Transform3D = body.gun_hand.transform
		var barrel := (hand_g.basis * (gun_local.basis * Vector3.UP)).normalized()
		# Bladed stance: turn the chest (half each on Chest and UpperChest) about the up axis.
		for nm in ["Chest", "UpperChest"]:
			var i := sk.find_bone(nm)
			if i >= 0:
				var parent := sk.get_bone_parent(i)
				var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
				var axis := (pg.basis.inverse() * Vector3.UP).normalized()
				sk.set_bone_pose_rotation(i, Quaternion(axis, TWIST * 0.5 * weight) * sk.get_bone_pose_rotation(i))
		var shoulder: Vector3 = sk.get_bone_global_pose(r[0]).origin
		var grip_target := shoulder + barrel * GRIP_FORWARD + Vector3.DOWN * GRIP_DOWN
		_reach(sk, r, hand_g.origin.lerp(grip_target - hand_g.basis * gun_local.origin, weight))
		# Keep the hand (and so the gun) turned the way the animation had it.
		_set_global_basis(sk, r[2], hand_g.basis)
		# Left hand to the fore-end, wherever the gun now is.
		var grip: Node3D = body.gun_hand.get_node("Pump/ForeGrip")
		var fore: Vector3 = sk.get_bone_global_pose(r[2]) * (gun_local * ((grip.get_parent() as Node3D).transform * grip.position))
		var lh: Vector3 = sk.get_bone_global_pose(l[2]).origin
		_reach(sk, l, lh.lerp(fore, weight))

	## Two-bone IK: bones [upper, lower, end] so `end` reaches `target`.
	func _reach(sk: Skeleton3D, b: Array, target: Vector3) -> void:
		var a: Vector3 = sk.get_bone_global_pose(b[0]).origin
		var e: Vector3 = sk.get_bone_global_pose(b[1]).origin
		var c: Vector3 = sk.get_bone_global_pose(b[2]).origin
		var l1 := a.distance_to(e)
		var l2 := e.distance_to(c)
		var to := target - a
		var d := clampf(to.length(), 0.05, l1 + l2 - 0.001)
		var dir := to.normalized()
		var pole := (e - a) - dir * (e - a).dot(dir)
		if pole.length_squared() < 1e-6:
			pole = Vector3.DOWN
		pole = pole.normalized()
		var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
		var elbow := a + dir * (cos_a * l1) + pole * (sqrt(1.0 - cos_a * cos_a) * l1)
		_aim_bone(sk, b[0], e - a, elbow - a)
		_aim_bone(sk, b[1], sk.get_bone_global_pose(b[2]).origin - sk.get_bone_global_pose(b[1]).origin, a + dir * d - elbow)

	func _set_global_basis(sk: Skeleton3D, i: int, basis: Basis) -> void:
		var parent := sk.get_bone_parent(i)
		var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
		sk.set_bone_pose_rotation(i, (pg.basis.orthonormalized().inverse() * basis.orthonormalized()).get_rotation_quaternion())

	## Turns a bone so its child, now along `from`, lies along `to` (skeleton space).
	func _aim_bone(sk: Skeleton3D, i: int, from: Vector3, to: Vector3) -> void:
		if from.length_squared() < 1e-8 or to.length_squared() < 1e-8:
			return
		var q := Quaternion(from.normalized(), to.normalized())
		var g := sk.get_bone_global_pose(i)
		var parent := sk.get_bone_parent(i)
		var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
		var new_basis := Basis(q) * g.basis
		sk.set_bone_pose_rotation(i, (pg.basis.inverse() * new_basis).get_rotation_quaternion())


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
	var head := _attach("Head") if acc.any(func(a): return a in ["chef_hat", "cap", "helmet", "hat"]) else null
	if head:
		_outfit_nodes.append(head)
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
		_add_apron(outfit.get("apron_color", Color(0.9, 0.88, 0.82)))
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
