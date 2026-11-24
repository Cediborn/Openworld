extends SceneTree
## Bakes the explorer's combat and gesture animations onto the humanoid rig.
##
## Some animations shipped with the project were exported from a different rig
## (bone names "DEF-hips", "DEF-upper_arm.R", ...). The explorer's skeleton uses
## humanoid names ("Hips", "RightUpperArm", ...), so those clips moved nothing:
## the explorer held the sword still while attacks landed, and villagers stood in
## a T-pose while talking. This tool authors replacements directly on this rig.
##
## Poses are written in character space (the explorer faces +Z, +X is his left,
## -X his right): torso joints get rotations, arms are aimed with directions,
## the blade direction is solved through the wrist, and legs use two-bone IK so
## the feet stay planted while the hips move. Keys are joined with cubic
## quaternion interpolation and sampled at 30 fps.
##
## Run: godot --headless --path game -s res://tools/bake_anims.gd

const MODEL := "res://assets/character/Superhero_Male_FullBody.gltf"
const OUT := "res://assets/character/anims/"
const FPS := 30.0
const PATH_PREFIX := "%GeneralSkeleton:"
## Sword attached to the hand bone: blade runs along hand-local -X (see ExplorerBody._add_sword).
const BLADE_LOCAL := Vector3(-1, 0, 0)

var sk: Skeleton3D
var idle: Animation
var nbones := 0
var parent := PackedInt32Array()
var rest: Array[Transform3D] = []
var order: Array[int] = []      # parents before children
var foot_rest := {}             # side -> idle foot global position


func _init() -> void:
	var model: Node3D = load(MODEL).instantiate()
	sk = model.find_children("*", "Skeleton3D", true, false)[0]
	nbones = sk.get_bone_count()
	for i in nbones:
		parent.append(sk.get_bone_parent(i))
		rest.append(sk.get_bone_rest(i))
	_build_order()
	idle = load(OUT + "Idle.res")
	var base := _idle_pose(0.0)
	var g := _globals(base)
	for s in ["Left", "Right"]:
		foot_rest[s] = g[_b(s + "Foot")].origin
	var made := []
	var only := OS.get_cmdline_user_args()   # bake just these names, if given
	for spec in _specs():
		if not only.is_empty() and not spec.name in only:
			continue
		var a := _bake(spec)
		ResourceSaver.save(a, OUT + spec.name + ".res")
		made.append("%s (%.2fs)" % [spec.name, a.length])
	print("baked: ", ", ".join(made))
	model.free()
	quit()


# ---------- Animation specs ----------
# Each key: t (seconds), ease ("smooth", "in" = accelerate, "out" = decelerate,
# "linear") and pose fields:
#   hips [x,y,z] offset (m), hips_rot / spine / chest / upper / neck / head [pitch,yaw,roll] deg
#   r_upper / r_fore / l_upper / l_fore: direction the bone points (character space)
#   blade: direction the sword blade points, l_hand: left hand direction
#   foot_l / foot_r: offset of each foot from its idle spot (m), stays flat

func _guard() -> Dictionary:
	return {
		"hips": [0, -0.05, 0], "hips_rot": [0, -14, 0], "spine": [6, 4, 0], "chest": [4, 4, 0], "upper": [0, 2, 0],
		"head": [-4, 8, 0],
		"r_upper": [-0.32, -0.75, 0.42], "r_fore": [0.05, 0.1, 1.0], "blade": [0.25, 0.75, 0.62],
		"l_upper": [0.35, -0.85, 0.2], "l_fore": [0.1, -0.25, 1.0],
		"foot_l": [0.02, 0, 0.12], "foot_r": [-0.02, 0, -0.12],
	}


func _specs() -> Array:
	var guard := _guard()
	var specs := []
	# Ready stance with the sword out (loops; a slow breath).
	specs.append({"name": "Sword_Idle", "loop": true, "keys": [
		_k(0.0, "smooth", guard),
		_k(1.1, "smooth", guard, {"hips": [0, -0.06, 0], "chest": [6, 4, 0], "blade": [0.28, 0.78, 0.56]}),
		_k(2.2, "smooth", guard),
	]})
	# Combo 1: forehand diagonal cut from high right to low left.
	specs.append({"name": "Sword_Slash1", "keys": [
		_k(0.0, "smooth", guard),
		_k(0.15, "out", guard, {"hips_rot": [0, -40, 0], "spine": [-4, -14, 0], "chest": [-4, -16, 0], "upper": [0, -10, 0], "head": [0, 26, 0],
			"r_upper": [-0.75, 0.45, -0.25], "r_fore": [-0.35, 0.9, 0.15], "blade": [-0.15, 0.55, -0.82],
			"l_upper": [0.15, -0.6, 0.75], "l_fore": [-0.3, 0.1, 0.95], "hips": [0, -0.07, -0.03]}),
		_k(0.24, "in", guard, {"hips_rot": [0, -4, 0], "spine": [10, 6, 0], "chest": [8, 8, 0], "upper": [4, 6, 0], "head": [0, -6, 0],
			"r_upper": [-0.2, 0.05, 1.0], "r_fore": [0.25, -0.05, 1.0], "blade": [0.55, -0.1, 0.85],
			"l_upper": [0.45, -0.75, -0.1], "l_fore": [0.4, -0.3, -0.3], "hips": [0, -0.09, 0.06], "foot_l": [0.02, 0, 0.2]}),
		_k(0.34, "out", guard, {"hips_rot": [0, 26, 0], "spine": [14, 12, 0], "chest": [10, 14, 0], "upper": [6, 10, 0], "head": [0, -18, 0],
			"r_upper": [0.55, -0.45, 0.7], "r_fore": [0.9, -0.4, 0.15], "blade": [0.75, -0.5, -0.45],
			"l_upper": [0.5, -0.8, -0.3], "l_fore": [0.3, -0.5, -0.6], "hips": [0, -0.1, 0.08], "foot_l": [0.02, 0, 0.2]}),
		_k(0.62, "smooth", guard),
	]})
	# Combo 2: backhand rising cut from low left to high right.
	specs.append({"name": "Sword_Slash2", "keys": [
		_k(0.0, "smooth", guard),
		_k(0.14, "out", guard, {"hips_rot": [0, 30, 0], "spine": [8, 14, 0], "chest": [6, 16, 0], "upper": [4, 10, 0], "head": [0, -22, 0],
			"r_upper": [0.65, -0.35, 0.65], "r_fore": [0.95, 0.1, -0.2], "blade": [0.55, -0.35, -0.75],
			"l_upper": [0.6, -0.7, -0.35], "l_fore": [0.2, -0.6, -0.6], "hips": [0, -0.08, 0.02]}),
		_k(0.23, "in", guard, {"hips_rot": [0, 0, 0], "spine": [4, 0, 0], "chest": [2, 0, 0], "upper": [0, -4, 0], "head": [0, 0, 0],
			"r_upper": [-0.15, -0.2, 1.0], "r_fore": [-0.35, 0.15, 1.0], "blade": [-0.6, 0.25, 0.75],
			"l_upper": [0.55, -0.8, 0.1], "l_fore": [0.5, -0.2, 0.5], "hips": [0, -0.08, 0.05], "foot_r": [-0.02, 0, 0.0]}),
		_k(0.33, "out", guard, {"hips_rot": [0, -32, 0], "spine": [-2, -14, 0], "chest": [-4, -16, 0], "upper": [-4, -10, 0], "head": [0, 20, 0],
			"r_upper": [-0.85, 0.3, 0.3], "r_fore": [-0.55, 0.8, -0.1], "blade": [-0.45, 0.6, -0.65],
			"l_upper": [0.3, -0.7, 0.6], "l_fore": [-0.2, -0.1, 1.0], "hips": [0, -0.06, 0.02]}),
		_k(0.62, "smooth", guard),
	]})
	# Combo 3: two-handed overhead chop with a step in.
	specs.append({"name": "Sword_Slash3", "keys": [
		_k(0.0, "smooth", guard),
		_k(0.3, "out", guard, {"hips_rot": [-6, -8, 0], "spine": [-10, -4, 0], "chest": [-12, -4, 0], "upper": [-8, 0, 0], "head": [-10, 4, 0],
			"r_upper": [-0.3, 0.92, 0.1], "r_fore": [0.1, 0.85, -0.5], "blade": [0.05, 0.2, -0.98],
			"l_upper": [0.25, 0.92, 0.1], "l_fore": [-0.25, 0.85, -0.5], "hips": [0, -0.02, -0.06], "foot_l": [0.02, 0, 0.12]}),
		_k(0.44, "in", guard, {"hips_rot": [8, -2, 0], "spine": [9, 0, 0], "chest": [7, 0, 0], "upper": [3, 0, 0], "head": [-6, 0, 0],
			"r_upper": [-0.1, -0.05, 1.0], "r_fore": [0.0, -0.35, 1.0], "blade": [0.0, -0.3, 1.0],
			"l_upper": [0.15, -0.1, 1.0], "l_fore": [-0.15, -0.35, 1.0], "hips": [0, -0.16, 0.14], "foot_l": [0.02, 0, 0.42]}),
		_k(0.56, "out", guard, {"hips_rot": [12, 0, 0], "spine": [12, 0, 0], "chest": [9, 0, 0], "upper": [4, 0, 0], "head": [-8, 0, 0],
			"r_upper": [-0.1, -0.55, 0.85], "r_fore": [0.0, -0.8, 0.6], "blade": [0.05, -0.85, 0.5],
			"l_upper": [0.15, -0.55, 0.85], "l_fore": [-0.1, -0.8, 0.6], "hips": [0, -0.2, 0.18], "foot_l": [0.02, 0, 0.42]}),
		_k(0.95, "smooth", guard),
	]})
	# Block: blade raised across the body.
	var block := _merge(guard, {"hips": [0, -0.09, -0.02], "hips_rot": [0, -6, 0], "spine": [8, 0, 0], "chest": [6, 0, 0], "head": [6, 0, 0],
		"r_upper": [-0.45, -0.35, 0.82], "r_fore": [0.1, 0.75, 0.65], "blade": [0.98, 0.15, 0.05],
		"l_upper": [0.45, -0.3, 0.84], "l_fore": [-0.1, 0.75, 0.65]})
	specs.append({"name": "Sword_Block", "loop": true, "keys": [_k(0.0, "smooth", block), _k(1.0, "smooth", block, {"hips": [0, -0.1, -0.02]}), _k(2.0, "smooth", block)]})
	# Hit reaction: knocked back at the chest, then recovers.
	var stand := _stand()
	specs.append({"name": "Hit_Chest", "keys": [
		_k(0.0, "smooth", stand),
		_k(0.1, "out", stand, {"hips": [0, -0.06, -0.08], "hips_rot": [-6, 0, 4], "spine": [-14, 0, 0], "chest": [-12, 0, 0], "neck": [-10, 0, 0], "head": [-14, 6, 0],
			"r_upper": [-0.6, -0.4, 0.6], "r_fore": [-0.3, 0.5, 0.8], "l_upper": [0.6, -0.4, 0.6], "l_fore": [0.3, 0.5, 0.8], "blade": [0.2, 0.8, 0.5]}),
		_k(0.42, "smooth", stand),
	]})
	# Death: knees give way and he falls on his back.
	specs.append({"name": "Death01", "keys": [
		_k(0.0, "smooth", stand),
		_k(0.35, "out", stand, {"hips": [0, -0.3, -0.05], "hips_rot": [-10, 8, 0], "spine": [-10, 0, 0], "head": [-15, 10, 0],
			"r_upper": [-0.5, -0.6, 0.6], "r_fore": [-0.2, 0.3, 0.9], "l_upper": [0.5, -0.6, 0.6], "l_fore": [0.2, 0.3, 0.9], "blade": [0, -1, 0.2]}),
		_k(0.85, "in", stand, {"hips": [0, -0.72, -0.35], "hips_rot": [-55, 10, 0], "spine": [-10, 0, 0], "chest": [-8, 0, 0], "head": [-10, 10, 0],
			"r_upper": [-0.8, -0.2, -0.5], "r_fore": [-0.9, 0.1, -0.4], "l_upper": [0.8, -0.2, -0.5], "l_fore": [0.9, 0.1, -0.4], "blade": [0, -0.3, -1],
			"foot_l": [0.05, 0, 0.1], "foot_r": [-0.05, 0, 0.25]}),
		_k(1.2, "out", stand, {"hips": [0, -0.82, -0.55], "hips_rot": [-84, 12, 0], "spine": [-4, 0, 0], "chest": [-2, 0, 0], "head": [-6, 25, 0],
			"r_upper": [-0.95, 0.1, -0.2], "r_fore": [-0.8, 0.1, 0.5], "l_upper": [0.95, 0.05, -0.3], "l_fore": [0.7, 0.0, 0.6], "blade": [-0.6, 0.0, 0.8],
			"foot_l": [0.12, 0, 0.35], "foot_r": [-0.1, 0, 0.55]}),
		_k(2.4, "smooth", stand, {"hips": [0, -0.82, -0.55], "hips_rot": [-86, 12, 0], "spine": [-4, 0, 0], "chest": [-2, 0, 0], "head": [-6, 28, 0],
			"r_upper": [-0.95, 0.1, -0.2], "r_fore": [-0.8, 0.1, 0.5], "l_upper": [0.95, 0.05, -0.3], "l_fore": [0.7, 0.0, 0.6], "blade": [-0.6, 0.0, 0.8],
			"foot_l": [0.12, 0, 0.35], "foot_r": [-0.1, 0, 0.55]}),
	]})
	# Talking: relaxed stance with open-hand gestures (loops).
	var talk := _merge(stand, {"r_upper": [-0.25, -0.95, 0.1], "r_fore": [-0.1, -0.6, 0.8], "l_upper": [0.22, -0.97, 0.0], "l_fore": [0.1, -0.95, 0.25]})
	specs.append({"name": "Idle_Talking", "loop": true, "keys": [
		_k(0.0, "smooth", talk),
		_k(0.7, "smooth", talk, {"r_upper": [-0.35, -0.85, 0.35], "r_fore": [-0.35, 0.25, 0.9], "head": [0, -8, 4], "chest": [0, -4, 0]}),
		_k(1.4, "smooth", talk, {"r_upper": [-0.3, -0.9, 0.25], "r_fore": [-0.55, 0.1, 0.85], "l_upper": [0.3, -0.88, 0.3], "l_fore": [0.4, 0.2, 0.9], "head": [4, 4, -2]}),
		_k(2.1, "smooth", talk, {"head": [-2, 6, 0], "chest": [0, 4, 0]}),
		_k(2.9, "smooth", talk),
	]})
	# Picking something up from the ground.
	specs.append({"name": "PickUp_Table", "keys": [
		_k(0.0, "smooth", stand),
		_k(0.4, "smooth", stand, {"hips": [0, -0.38, -0.12], "hips_rot": [28, 0, 0], "spine": [22, 0, 0], "chest": [16, 0, 0], "head": [-10, 0, 0],
			"r_upper": [-0.15, -0.6, 0.78], "r_fore": [0.0, -0.95, 0.3], "l_upper": [0.3, -0.7, 0.6], "l_fore": [0.2, -0.6, 0.8], "foot_r": [-0.02, 0, 0.25]}),
		_k(0.55, "smooth", stand, {"hips": [0, -0.38, -0.12], "hips_rot": [28, 0, 0], "spine": [22, 0, 0], "chest": [16, 0, 0], "head": [-10, 0, 0],
			"r_upper": [-0.15, -0.65, 0.74], "r_fore": [0.1, -0.7, 0.7], "l_upper": [0.3, -0.7, 0.6], "l_fore": [0.2, -0.6, 0.8], "foot_r": [-0.02, 0, 0.25]}),
		_k(0.95, "smooth", stand),
	]})
	# Riding a horse: seated in the saddle, knees bent around the horse's sides,
	# feet in the stirrups, both hands forward holding the reins (loops; a
	# gentle sway that the game adds the horse's own bounce to).
	var ride := _merge(stand, {"hips": [0, -0.30, -0.04], "hips_rot": [6, 0, 0], "spine": [4, 0, 0], "chest": [2, 0, 0], "head": [-6, 0, 0],
		"r_upper": [-0.12, -0.88, 0.45], "r_fore": [0.2, -0.55, 0.81], "l_upper": [0.12, -0.88, 0.45], "l_fore": [-0.2, -0.55, 0.81],
		"blade": [0.05, -0.2, 0.98], "foot_l": [0.3, -0.09, 0.06], "foot_r": [-0.3, -0.09, 0.06]})
	specs.append({"name": "Ride", "loop": true, "keys": [
		_k(0.0, "smooth", ride),
		_k(1.2, "smooth", ride, {"spine": [6, 0, 0], "head": [-4, 3, 0]}),
		_k(2.4, "smooth", ride),
	]})
	return specs


func _stand() -> Dictionary:
	return {"hips": [0, 0, 0], "hips_rot": [0, 0, 0], "spine": [0, 0, 0], "chest": [0, 0, 0], "upper": [0, 0, 0], "neck": [0, 0, 0], "head": [0, 0, 0],
		"r_upper": [-0.18, -0.98, 0.02], "r_fore": [-0.08, -0.96, 0.22], "l_upper": [0.18, -0.98, 0.02], "l_fore": [0.08, -0.96, 0.22],
		"blade": [0.05, -0.2, 0.98], "foot_l": [0, 0, 0], "foot_r": [0, 0, 0]}


func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var m := a.duplicate(true)
	m.merge(b, true)
	return m


func _k(t: float, ease: String, base: Dictionary, over := {}) -> Dictionary:
	return {"t": t, "ease": ease, "pose": _merge(base, over)}


# ---------- Solving a pose ----------

func _b(n: String) -> int:
	return sk.find_bone(n)


func _build_order() -> void:
	var done := {}
	while order.size() < nbones:
		for i in nbones:
			if done.has(i):
				continue
			if parent[i] == -1 or done.has(parent[i]):
				order.append(i)
				done[i] = true


## Local pose (rotations and positions) of Idle at time t, rest elsewhere.
func _idle_pose(t: float) -> Array:
	var pose := []
	for i in nbones:
		pose.append(Transform3D(rest[i]))
	for tr in idle.get_track_count():
		var bn := str(idle.track_get_path(tr)).get_slice(":", 1)
		var i := sk.find_bone(bn)
		if i == -1:
			continue
		var x: Transform3D = pose[i]
		match idle.track_get_type(tr):
			Animation.TYPE_ROTATION_3D:
				x.basis = Basis(idle.rotation_track_interpolate(tr, t)).scaled(x.basis.get_scale())
			Animation.TYPE_POSITION_3D:
				x.origin = idle.position_track_interpolate(tr, t)
		pose[i] = x
	return pose


func _globals(local: Array) -> Array:
	var g := []
	g.resize(nbones)
	for i in order:
		g[i] = local[i] if parent[i] == -1 else (g[parent[i]] as Transform3D) * (local[i] as Transform3D)
	return g


## Rotates bone i (and everything under it) by q in character space.
func _rotate_global(local: Array, i: int, q: Quaternion) -> void:
	var g := _globals(local)
	var gb: Basis = (g[i] as Transform3D).basis.orthonormalized()
	var nb := Basis(q) * gb
	var pb: Basis = Basis.IDENTITY if parent[i] == -1 else (g[parent[i]] as Transform3D).basis.orthonormalized()
	var x: Transform3D = local[i]
	x.basis = (pb.inverse() * nb).orthonormalized()
	local[i] = x


func _arc(from: Vector3, to: Vector3) -> Quaternion:
	from = from.normalized()
	to = to.normalized()
	if from.dot(to) > 0.99999:
		return Quaternion.IDENTITY
	if from.dot(to) < -0.9999:
		var axis := from.cross(Vector3.UP if absf(from.y) < 0.9 else Vector3.RIGHT).normalized()
		return Quaternion(axis, PI)
	return Quaternion(from, to)


func _aim(local: Array, i: int, dir: Vector3, axis := Vector3.UP) -> void:
	var g := _globals(local)
	var cur: Vector3 = (g[i] as Transform3D).basis.orthonormalized() * axis
	_rotate_global(local, i, _arc(cur, dir))


func _euler(a: Array) -> Quaternion:
	return Quaternion.from_euler(Vector3(deg_to_rad(a[0]), deg_to_rad(a[1]), deg_to_rad(a[2])))


func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## Two-bone leg IK: thigh and shin reach the foot target, knee bends forward.
func _leg(local: Array, side: String, target: Vector3) -> void:
	var thigh := _b(side + "UpperLeg")
	var shin := _b(side + "LowerLeg")
	var foot := _b(side + "Foot")
	var g := _globals(local)
	var hip: Vector3 = (g[thigh] as Transform3D).origin
	var knee0: Vector3 = (g[shin] as Transform3D).origin
	var ankle0: Vector3 = (g[foot] as Transform3D).origin
	var l1 := hip.distance_to(knee0)
	var l2 := knee0.distance_to(ankle0)
	var to := target - hip
	var d := clampf(to.length(), 0.05, (l1 + l2) * 0.999)
	var dir := to.normalized()
	# Knee position from the law of cosines, bending towards +Z (forward).
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var pole := (Vector3(0, 0, 1) - dir * dir.dot(Vector3(0, 0, 1))).normalized()
	var knee := hip + dir * a + pole * h
	_aim(local, thigh, knee - hip)
	_aim(local, shin, (hip + dir * d) - knee)
	# Keep the foot flat and pointing forward.
	g = _globals(local)
	var fb: Basis = (g[foot] as Transform3D).basis.orthonormalized()
	var want_y := Vector3(0, 0, 1)   # foot bone +Y runs to the toes
	var q := _arc(fb.y, want_y)
	_rotate_global(local, foot, q)
	g = _globals(local)
	fb = (g[foot] as Transform3D).basis.orthonormalized()
	_rotate_global(local, foot, _arc(fb.z, Vector3.UP))


func _solve(pose: Dictionary) -> Array:
	var local := _idle_pose(0.0)
	var hips := _b("Hips")
	var hx: Transform3D = local[hips]
	hx.origin += _v(pose.hips)
	local[hips] = hx
	_rotate_global(local, hips, _euler(pose.hips_rot))
	_rotate_global(local, _b("Spine"), _euler(pose.spine))
	_rotate_global(local, _b("Chest"), _euler(pose.chest))
	_rotate_global(local, _b("UpperChest"), _euler(pose.get("upper", [0, 0, 0])))
	_rotate_global(local, _b("Neck"), _euler(pose.get("neck", [0, 0, 0])))
	_rotate_global(local, _b("Head"), _euler(pose.head))
	_aim(local, _b("RightUpperArm"), _v(pose.r_upper))
	_aim(local, _b("RightLowerArm"), _v(pose.r_fore))
	# Hand follows the forearm, then turns so the blade points where asked.
	var g := _globals(local)
	_rotate_global(local, _b("RightHand"), _arc((g[_b("RightHand")] as Transform3D).basis.orthonormalized().y, _v(pose.r_fore)))
	_aim(local, _b("RightHand"), _v(pose.blade), BLADE_LOCAL)
	_aim(local, _b("LeftUpperArm"), _v(pose.l_upper))
	_aim(local, _b("LeftLowerArm"), _v(pose.l_fore))
	g = _globals(local)
	_rotate_global(local, _b("LeftHand"), _arc((g[_b("LeftHand")] as Transform3D).basis.orthonormalized().y, _v(pose.l_fore)))
	_leg(local, "Left", foot_rest["Left"] + _v(pose.foot_l))
	_leg(local, "Right", foot_rest["Right"] + _v(pose.foot_r))
	return local


# ---------- Baking ----------

func _ease(t: float, kind: String) -> float:
	match kind:
		"in":
			return t * t * t
		"out":
			return 1.0 - pow(1.0 - t, 3.0)
		"linear":
			return t
		_:
			return t * t * (3.0 - 2.0 * t)


func _bake(spec: Dictionary) -> Animation:
	var keys: Array = spec["keys"]
	var poses := []
	for k in keys:
		poses.append(_solve(k.pose))
	var a := Animation.new()
	a.length = float(keys[-1].t)
	a.loop_mode = Animation.LOOP_LINEAR if spec.get("loop", false) else Animation.LOOP_NONE
	var hips := _b("Hips")
	var pos_track := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(pos_track, PATH_PREFIX + "Hips")
	var rot_tracks := {}
	for i in order:
		var tr := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(tr, PATH_PREFIX + sk.get_bone_name(i))
		rot_tracks[i] = tr
	var frames := int(ceil(a.length * FPS))
	for f in frames + 1:
		var t := minf(f / FPS, a.length)
		var s := 0
		while s < keys.size() - 2 and t > float(keys[s + 1].t):
			s += 1
		var t0: float = keys[s].t
		var t1: float = keys[s + 1].t
		var u := _ease(clampf((t - t0) / maxf(t1 - t0, 0.0001), 0.0, 1.0), keys[s + 1].ease)
		var pa: Array = poses[s]
		var pb: Array = poses[s + 1]
		var pp: Array = poses[maxi(s - 1, 0)]
		var pn: Array = poses[mini(s + 2, poses.size() - 1)]
		if spec.get("loop", false):
			pp = poses[s - 1] if s > 0 else poses[poses.size() - 2]
			pn = poses[s + 2] if s + 2 < poses.size() else poses[1]
		for i in order:
			var qa := (pa[i] as Transform3D).basis.get_rotation_quaternion()
			var qb := (pb[i] as Transform3D).basis.get_rotation_quaternion()
			var qp := (pp[i] as Transform3D).basis.get_rotation_quaternion()
			var qn := (pn[i] as Transform3D).basis.get_rotation_quaternion()
			# Keep neighbours in the same hemisphere so the cubic doesn't spin the long way round.
			if qa.dot(qb) < 0.0:
				qb = -qb
			if qa.dot(qp) < 0.0:
				qp = -qp
			if qb.dot(qn) < 0.0:
				qn = -qn
			var q := qa.spherical_cubic_interpolate(qb, qp, qn, u).normalized()
			a.rotation_track_insert_key(rot_tracks[i], t, q)
		var o: Vector3 = (pa[hips] as Transform3D).origin.cubic_interpolate(
			(pb[hips] as Transform3D).origin, (pp[hips] as Transform3D).origin, (pn[hips] as Transform3D).origin, u)
		a.position_track_insert_key(pos_track, t, o)
	return a
