class_name HorseNav
extends RefCounted
## Where a horse can walk, and the way there. A 4 m grid over the island
## (AStarGrid2D) with lava, cliffs and the inside of every building, wall,
## fence and rock blocked, so a summoned horse goes round obstacles instead of
## through them, and never sets a hoof in the crater. Built the first time it
## is needed (after the world is up) and rebuilt if the world changes.

const CELL := 4.0
## Steepest ground a horse will climb (y of the surface normal).
const MAX_SLOPE_NORMAL := 0.74
## How far the grid looks for open ground around a blocked spot (cells).
const SEARCH_RADIUS := 40

var data: WorldData
var grid := AStarGrid2D.new()
var n := 0
var built := false


func _init(world_data: WorldData) -> void:
	data = world_data
	n = int(WorldData.SIZE / CELL)


## Marks every cell. `scene_root` is searched for solid bodies (buildings, walls, rocks).
func build(scene_root: Node) -> void:
	grid.region = Rect2i(0, 0, n, n)
	grid.cell_size = Vector2(CELL, CELL)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	for j in n:
		for i in n:
			var w := cell_center(Vector2i(i, j))
			if _ground_blocked(w.x, w.y):
				grid.set_point_solid(Vector2i(i, j), true)
	if scene_root:
		_block_bodies(scene_root)
	built = true


## Lava, cliffs and the island's rim.
func _ground_blocked(x: float, z: float) -> bool:
	if absf(x) > WorldData.SIZE * 0.5 - 12.0 or absf(z) > WorldData.SIZE * 0.5 - 12.0:
		return true
	if data.is_lava(x, z):
		return true
	return data.normal(x, z).y < MAX_SLOPE_NORMAL


## True where a horse may stand.
func is_open(x: float, z: float) -> bool:
	var c := cell_of(Vector2(x, z))
	return grid.is_in_boundsv(c) and not grid.is_point_solid(c)


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int((p.x + WorldData.SIZE * 0.5) / CELL), 0, n - 1), clampi(int((p.y + WorldData.SIZE * 0.5) / CELL), 0, n - 1))


func cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL - WorldData.SIZE * 0.5, (c.y + 0.5) * CELL - WorldData.SIZE * 0.5)


## The nearest open cell centre to `p` (spiral search), or Vector2.INF.
func nearest_open(p: Vector2) -> Vector2:
	var c := cell_of(p)
	if not grid.is_point_solid(c):
		return cell_center(c)
	for r in range(1, SEARCH_RADIUS):
		var best := Vector2.INF
		var best_d := INF
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				if maxi(absi(di), absi(dj)) != r:
					continue
				var q := c + Vector2i(di, dj)
				if grid.is_in_boundsv(q) and not grid.is_point_solid(q):
					var w := cell_center(q)
					var d := w.distance_squared_to(p)
					if d < best_d:
						best_d = d
						best = w
		if best != Vector2.INF:
			return best
	return Vector2.INF


## Waypoints (x, z) from `from` to `to`, both snapped to open ground, or [] when
## there is no way through. The first point is the horse's own cell.
func path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := nearest_open(from)
	var b := nearest_open(to)
	if a == Vector2.INF or b == Vector2.INF:
		return PackedVector2Array()
	var cells := grid.get_id_path(cell_of(a), cell_of(b))
	var out := PackedVector2Array()
	for c in cells:
		out.append(cell_center(c))
	return _smooth(out)


## Drops waypoints that a straight walk can skip (no blocked cell on the line).
func _smooth(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	var anchor := 0
	var i := 2
	while i < pts.size():
		if not _clear_line(pts[anchor], pts[i]):
			out.append(pts[i - 1])
			anchor = i - 1
		i += 1
	out.append(pts[pts.size() - 1])
	return out


func _clear_line(a: Vector2, b: Vector2) -> bool:
	var steps := int(a.distance_to(b) / (CELL * 0.5)) + 1
	for k in steps + 1:
		var p := a.lerp(b, float(k) / steps)
		# Check a horse's width either side of the line too.
		var side := (b - a).orthogonal().normalized() * 1.0
		for o in [Vector2.ZERO, side, -side]:
			if not is_open(p.x + o.x, p.y + o.y):
				return false
	return true


func _block_bodies(node: Node) -> void:
	for c in node.get_children():
		if c is StaticBody3D and not c.has_meta("walkable"):
			for s in c.get_children():
				if s is CollisionShape3D and not s.disabled and s.shape and not s.shape is HeightMapShape3D:
					_block_shape(s)
		if c.get_child_count() > 0:
			_block_bodies(c)


func _block_shape(cs: CollisionShape3D) -> void:
	var x := cs.global_transform
	var local := _shape_aabb(cs.shape)
	var world_box := x * local
	# Only things standing on the ground at their spot block (not interiors far
	# below the island or high bridges you ride under).
	var gc := world_box.get_center()
	var ground := data.height(gc.x, gc.z)
	if world_box.end.y < ground + 0.5 or world_box.position.y > ground + 2.6:
		return
	var inv := x.affine_inverse()
	var margin := 0.9   # half a horse
	var lo := cell_of(Vector2(world_box.position.x - margin, world_box.position.z - margin))
	var hi := cell_of(Vector2(world_box.end.x + margin, world_box.end.z + margin))
	for j in range(lo.y, hi.y + 1):
		for i in range(lo.x, hi.x + 1):
			var w := cell_center(Vector2i(i, j))
			var lp := inv * Vector3(w.x, gc.y, w.y)
			# Inside the shape's footprint (with the margin), in its own space.
			if absf(lp.x - local.get_center().x) <= local.size.x * 0.5 + margin and absf(lp.z - local.get_center().z) <= local.size.z * 0.5 + margin:
				grid.set_point_solid(Vector2i(i, j), true)


static func _shape_aabb(sh: Shape3D) -> AABB:
	if sh is BoxShape3D:
		return AABB(-sh.size * 0.5, sh.size)
	if sh is CylinderShape3D:
		return AABB(Vector3(-sh.radius, -sh.height * 0.5, -sh.radius), Vector3(sh.radius * 2, sh.height, sh.radius * 2))
	if sh is CapsuleShape3D:
		return AABB(Vector3(-sh.radius, -sh.height * 0.5, -sh.radius), Vector3(sh.radius * 2, sh.height, sh.radius * 2))
	if sh is SphereShape3D:
		return AABB(Vector3.ONE * -sh.radius, Vector3.ONE * sh.radius * 2)
	return sh.get_debug_mesh().get_aabb()
