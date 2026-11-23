class_name Town
extends Node3D
## Brickton's streets beyond the houses: the market square with its stalls,
## well and contract board, the inn's tables, lamp posts along every street,
## gardens, the craft quarter's stacks and the east gate with its palisade.
## Street centre-lines come from data/town.json (baked with the houses) and
## double as the villagers' walking routes.

var data: WorldData
var village: Village
var streets: Array = []      # polylines of [x, z]
var plaza: Dictionary = {}
var lights: Array[Light3D] = []
var nodes: Array = []        # walking graph: Vector3 positions
var edges: Array = []        # adjacency lists
var board_pos := Vector3.ZERO


func setup(world_data: WorldData, v: Village) -> void:
	data = world_data
	village = v
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/town.json"))
	streets = d.streets
	plaza = d.plaza
	_build_graph()
	_square()
	_streets_furniture()
	_quarters()
	var lit := village.window_mat if village else Structures.glow_mat(Color(1.0, 0.7, 0.35), 1.0)
	Structures.gate(self, _ground(-196, 2.3), 0.0, data.height, lit)
	# A lantern-lit welcome at the gate.
	lights.append(Structures.flame_light(self, _ground(-196, 2.3) + Vector3(-2.0, 3.0, 0), Color(1.0, 0.7, 0.4), 1.3, 14.0))


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, data.height(x, z), z)


func set_night(amount: float) -> void:
	for l in lights:
		l.visible = amount > 0.3
		l.light_energy = 1.3 * amount


# ---------- Walking graph ----------

## Joins all street polylines into one graph (points closer than 2.5 m merge).
func _build_graph() -> void:
	var index_of := func(p: Vector3) -> int:
		for i in nodes.size():
			if (nodes[i] as Vector3).distance_to(p) < 2.5:
				return i
		nodes.append(p)
		edges.append([])
		return nodes.size() - 1
	for line: Array in streets:
		var prev := -1
		for k in line.size():
			var a := Vector3(line[k][0], 0, line[k][1])
			if k > 0:
				# Subdivide long segments so lanes cross streets at shared nodes.
				var b := Vector3(line[k - 1][0], 0, line[k - 1][1])
				var n := int(ceil(a.distance_to(b) / 6.0))
				for s in range(1, n):
					var q: int = index_of.call(b.lerp(a, float(s) / n))
					_link(prev, q)
					prev = q
			var i: int = index_of.call(a)
			if prev != -1:
				_link(prev, i)
			prev = i
	# Stitch dead ends (a lane stopping just short of a street or the square's
	# loop) to the nearest node close by, so every street is reachable.
	for i in nodes.size():
		if edges[i].size() != 1:
			continue
		var best := -1
		var bd := 6.5
		# Ignore its own short chain (a door path's other nodes).
		var near := {i: true}
		var ring: Array = [i]
		for hop in 4:
			var nxt: Array = []
			for a in ring:
				for b in edges[a]:
					if not near.has(b):
						near[b] = true
						nxt.append(b)
			ring = nxt
		for j in nodes.size():
			if near.has(j):
				continue
			var d := (nodes[i] as Vector3).distance_to(nodes[j])
			if d < bd:
				bd = d
				best = j
		if best != -1:
			_link(i, best)
	for i in nodes.size():
		var p: Vector3 = nodes[i]
		nodes[i] = Vector3(p.x, data.height(p.x, p.z), p.z)


func _link(a: int, b: int) -> void:
	if a == b or a < 0 or b < 0:
		return
	if not b in edges[a]:
		edges[a].append(b)
	if not a in edges[b]:
		edges[b].append(a)


func nearest_node(p: Vector3) -> int:
	var best := 0
	var bd := INF
	for i in nodes.size():
		var d := Vector2(p.x - nodes[i].x, p.z - nodes[i].z).length_squared()
		if d < bd:
			bd = d
			best = i
	return best


## Shortest path along the streets between two points (list of positions).
func route(from: Vector3, to: Vector3) -> Array:
	var a := nearest_node(from)
	var b := nearest_node(to)
	var prev := {a: -1}
	var queue := [a]
	while not queue.is_empty():
		var c: int = queue.pop_front()
		if c == b:
			break
		for n in edges[c]:
			if not prev.has(n):
				prev[n] = c
				queue.append(n)
	var path := []
	var c := b
	while c != -1 and prev.has(c):
		path.push_front(nodes[c])
		c = prev[c]
	return path


# ---------- Market square ----------

func _square() -> void:
	var px: float = plaza.x
	var pz: float = plaza.z
	Structures.well(self, _ground(px, pz))
	var awnings := [Color(0.75, 0.22, 0.18), Color(0.2, 0.45, 0.7), Color(0.85, 0.65, 0.2), Color(0.3, 0.6, 0.3), Color(0.6, 0.3, 0.6), Color(0.85, 0.85, 0.8)]
	var goods := [
		[Color(0.85, 0.2, 0.15), Color(0.95, 0.75, 0.2), Color(0.4, 0.7, 0.2)],
		[Color(0.75, 0.55, 0.3), Color(0.8, 0.65, 0.4), Color(0.7, 0.45, 0.25)],
		[Color(0.3, 0.5, 0.8), Color(0.8, 0.3, 0.3), Color(0.9, 0.9, 0.85)],
		[Color(0.55, 0.35, 0.2), Color(0.95, 0.9, 0.8), Color(0.85, 0.55, 0.25)],
		[Color(0.5, 0.6, 0.65), Color(0.4, 0.42, 0.45), Color(0.65, 0.6, 0.5)],
		[Color(0.9, 0.5, 0.6), Color(0.6, 0.8, 0.5), Color(0.95, 0.85, 0.4)],
	]
	# Two rows of stalls facing each other across the square.
	# Three stalls along the north side, two along the south (the lane from the
	# main street comes in between them).
	for i in 3:
		var x := px - 9.0 + i * 9.0
		Structures.market_stall(self, _ground(x, pz - 6.0), 0.0, awnings[i], goods[i])
		if i != 1:
			Structures.market_stall(self, _ground(x, pz + 6.0), PI, awnings[i + 3], goods[i + 3])
	board_pos = _ground(px + 13.5, pz - 9.0)
	Structures.notice_board(self, board_pos, -PI * 0.35)
	for b in [[px - 4.0, pz - 2.5, 0.0], [px + 4.0, pz + 2.5, PI], [px - 13.0, pz + 3.0, PI * 0.5]]:
		Structures.bench(self, _ground(b[0], b[1]), b[2])
	for c in [[px + 15.0, pz + 10.5], [px - 15.5, pz - 10.5]]:
		Structures.barrel(self, _ground(c[0], c[1]))
		Structures.barrel(self, _ground(c[0] + 0.8, c[1] + 0.3))
		Structures.crate(self, _ground(c[0] - 0.9, c[1] - 0.2), 0.3)
	lights.append(Structures.flame_light(self, _ground(px, pz) + Vector3(0, 4.0, 0), Color(1.0, 0.72, 0.45), 1.3, 22.0))
	# Tables outside the inn.
	for t in [[px - 24.0, pz - 8.0], [px - 24.0, pz + 7.0]]:
		Structures.table_set(self, _ground(t[0], t[1]), PI * 0.5)


# ---------- Streets ----------

## Lamp posts every ~18 m along each street, set back from the centre line.
func _streets_furniture() -> void:
	var lit := village.window_mat if village else Structures.glow_mat(Color(1.0, 0.7, 0.35), 1.0)
	var placed: Array = []
	for line: Array in streets:
		if line.size() < 2:
			continue
		var length := 0.0
		for k in line.size() - 1:
			length += Vector2(line[k][0], line[k][1]).distance_to(Vector2(line[k + 1][0], line[k + 1][1]))
		if length < 20.0:
			continue   # door paths
		var walked := 9.0
		var side := 1.0
		for k in line.size() - 1:
			var a := Vector2(line[k][0], line[k][1])
			var b := Vector2(line[k + 1][0], line[k + 1][1])
			var seg := a.distance_to(b)
			while walked < seg:
				var p := a.lerp(b, walked / seg)
				var nrm := (b - a).normalized().orthogonal() * side * 3.4
				var q := p + nrm
				if _clear(q, placed, 6.0):
					Structures.lamp_post(self, _ground(q.x, q.y), lit)
					placed.append(q)
				side = -side
				walked += 18.0
			walked -= seg


## True when a spot is off the houses and away from things already placed.
func _clear(q: Vector2, placed: Array, gap: float) -> bool:
	for p in placed:
		if (p as Vector2).distance_to(q) < gap:
			return false
	for h in data.houses:
		var local := (q - Vector2(h.x, h.z)).rotated(float(h.rot))
		if absf(local.x) < h.w * 0.5 + 1.0 and absf(local.y) < h.d * 0.5 + 1.0:
			return false
	return true


## Gardens, hay and stacks in the residential streets and the craft quarter.
func _quarters() -> void:
	# Garden fences behind the north and south streets' houses.
	for g in [[-372, -124, -244, -124], [-372, 74, -246, 74]]:
		Structures.fence(self, _ground(g[0], g[1]), _ground(g[2], g[3]), data.height)
	# Craft quarter: timber stacks, hides on racks, barrels.
	for c in [[-205.0, -12.0], [-206.0, 13.0]]:
		Structures.crate(self, _ground(c[0], c[1]), 0.2, 0.9)
		Structures.crate(self, _ground(c[0] + 1.0, c[1] + 0.4), -0.3, 0.7)
		Structures.barrel(self, _ground(c[0] - 1.1, c[1] - 0.5))
	for i in 3:
		Structures.hay(self, _ground(-226.0 + i * 1.3, 30.0 + (i % 2) * 0.4), 0.2 * i)
	# Barrels and crates by doors along the main street.
	for c in [[-338.0, -3.0], [-262.0, 7.0], [-350.0, 6.0], [-283.0, -9.0]]:
		if _clear(Vector2(c[0], c[1]), [], 0.0):
			Structures.barrel(self, _ground(c[0], c[1]))
