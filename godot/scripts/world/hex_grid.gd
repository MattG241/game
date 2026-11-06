class_name HexGrid
extends RefCounted
## Hexagon sectors covering the whole Moon: the cells of a subdivided icosahedron
## (a Goldberg polyhedron: hexagons plus 12 pentagons). A point belongs to the cell
## whose centre is nearest. Clearing a cell to CLEAR_AT sweeps the rest of it and pays
## a bonus (see HexProgress).

const FREQ := 6                       # icosahedron edge subdivisions: 10 * FREQ^2 + 2 cells
const CLEAR_AT := 0.9                 # fraction clean that completes a hexagon

static var _inited := false
static var centers := PackedVector3Array()    # cell centre directions
static var _cand := []                         # chunk key_index -> PackedInt32Array of cells
static var _chunks := []                       # cell -> Array[Vector3i] chunks it touches
static var _samples := {}                      # cell -> PackedVector3Array (lazy)
static var cell_angle := 0.0                   # typical centre spacing (radians)


static func count() -> int:
	return centers.size()


static func setup() -> void:
	if _inited:
		return
	TerrainGen.setup()
	var t := (1.0 + sqrt(5.0)) * 0.5
	var v := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	# Turn it so a cell centre sits exactly on the base (north pole).
	var tilt := Basis(Quaternion((v[0] as Vector3).normalized(), Vector3.UP))
	var seen := {}
	var pts := PackedVector3Array()
	for f in faces:
		var a: Vector3 = v[f[0]]
		var b: Vector3 = v[f[1]]
		var c: Vector3 = v[f[2]]
		for i in FREQ + 1:
			for j in FREQ + 1 - i:
				var p: Vector3 = (tilt * (a + (b - a) * (float(i) / FREQ) + (c - a) * (float(j) / FREQ))).normalized()
				var key := Vector3i(roundi(p.x * 10000.0), roundi(p.y * 10000.0), roundi(p.z * 10000.0))
				if not seen.has(key):
					seen[key] = true
					pts.append(p)
	centers = pts
	cell_angle = sqrt(4.0 * PI / pts.size())
	# Candidate cells per terrain chunk (cells that can own a point of the chunk).
	var n := 6 * TerrainGen.N * TerrainGen.N
	_cand.resize(n)
	_chunks.resize(pts.size())
	for i in pts.size():
		_chunks[i] = []
	var lim := cos(cell_angle * 0.85 + TerrainGen.CHUNK / TerrainGen.RADIUS * 0.8)
	for k in TerrainGen.all_chunks():
		var cd := TerrainGen.chunk_center_dir(k)
		var list := PackedInt32Array()
		for i in pts.size():
			if pts[i].dot(cd) > lim:
				list.append(i)
				(_chunks[i] as Array).append(k)
		_cand[TerrainGen.key_index(k)] = list
	_inited = true


## The cell a direction belongs to.
static func cell_of(d: Vector3) -> int:
	return nearest(d.normalized(), _cand[TerrainGen.key_index(TerrainGen.key_of(d))])


static func nearest(d: Vector3, list: PackedInt32Array) -> int:
	var best := 0
	var bd := -2.0
	for i in list:
		var dd := centers[i].dot(d)
		if dd > bd:
			bd = dd
			best = i
	return best


static func candidates(k: Vector3i) -> PackedInt32Array:
	return _cand[TerrainGen.key_index(k)]


static func chunks_of(cell: int) -> Array:
	return _chunks[cell]


## Points spread over a cell (about one every 3 m) for measuring how clean it is.
static func samples(cell: int) -> PackedVector3Array:
	if _samples.has(cell):
		return _samples[cell]
	var c := centers[cell]
	var b := TerrainGen.frame(c)
	var out := PackedVector3Array()
	var reach := cell_angle * TerrainGen.RADIUS * 0.75
	var step := 3.0
	var x := -reach
	while x <= reach:
		var z := -reach
		while z <= reach:
			var d := (c * TerrainGen.RADIUS + b.x * x + b.z * z).normalized()
			if cell_of(d) == cell:
				out.append(d)
			z += step
		x += step
	_samples[cell] = out
	return out


## World position of a cell's centre on the ground.
static func center_point(cell: int) -> Vector3:
	return TerrainGen.ground(centers[cell])
