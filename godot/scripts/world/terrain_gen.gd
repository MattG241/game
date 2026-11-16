class_name TerrainGen
extends RefCounted
## Deterministic lunar terrain on a round Moon. Pure functions of a direction from the
## Moon's centre, so chunks can be built on worker threads and regenerated identically.
##
## Geometry
## - The Moon is a sphere of RADIUS metres centred on the world origin. The base sits on
##   the north pole (+Y).
## - The surface is split like a cube projected onto the sphere: 6 faces x N x N chunks.
##   A chunk key is Vector3i(face, i, j); inside a chunk, param (a, b) in [-1, 1] across
##   the face (equal-angle "tan" mapping keeps cells close to square).
## - "Map coordinates" (x, z) are the old flat layout: an azimuthal equidistant map
##   around the base (distance from the base is preserved). Authored content (base,
##   landmarks) is still laid out in map coordinates and placed with map_xform().

const RADIUS := 300.0
const N := 16                   # chunks per cube-face side (6 * N * N chunks)
const QUADS := 32               # LOD0 grid quads per chunk side (~0.9 m spacing)
const QUADS_FAR := 8            # LOD1 grid quads per chunk side
const MASK := 128               # dirt mask texels per chunk side (~0.23 m)
const CHUNK := RADIUS * PI * 0.5 / N    # approx. metres per chunk side
const TEXEL := CHUNK / MASK             # approx. metres per dirt texel
# Dust on ground steeper than this can't be reached, so none is generated there.
const MAX_DUST_SLOPE := 2.5     # rise/run (about 68 degrees): sheer cliffs only
const CLEAN_LEVEL := 10         # mask values at or below this count as clean
const BASE_RADIUS := 34.0
const ZONE_RADIUS := 150.0      # Landing Zone: within this distance of the base
const SEED := 4242

enum Region { LANDING, CRATERS, HIGHLANDS, RESEARCH, INDUSTRIAL }

# Authored landmark craters (map coordinates): [name, x, z, radius, depth]
const LANDMARK_CRATERS := [
	["tutorial_crater", 46.0, -40.0, 10.0, 2.4],
	["great_basin", 360.0, 40.0, 78.0, 15.0],
	["twin_west", 250.0, -110.0, 26.0, 6.0],
	["twin_east", 285.0, 120.0, 30.0, 7.0],
	["highland_bowl", -40.0, -330.0, 34.0, 7.0],
	["facility_pit", -300.0, 90.0, 22.0, 5.0],
	["south_scar", 60.0, 420.0, 40.0, 4.0],
	["far_side_basin", 640.0, -380.0, 60.0, 10.0],
	["south_pole_crater", 930.0, 30.0, 45.0, 9.0],
]

# Flattened pads for authored sites (map coordinates): [x, z, radius, height]
const FLAT_SITES := [
	[-330.0, 0.0, 46.0, 1.0],     # research facility compound
	[0.0, 330.0, 60.0, 0.0],      # industrial staging plain
	[420.0, -60.0, 8.0, -0.5],    # crashed probe
]

static var _inited := false
static var _n_base: FastNoiseLite
static var _n_detail: FastNoiseLite
static var _n_mtn: FastNoiseLite
static var _n_dirt: FastNoiseLite
static var _n_dirt2: FastNoiseLite
# Flattened tables (packed arrays are safe to read from worker threads):
# landmarks [dx, dy, dz, radius, depth]; flat sites [dx, dy, dz, radius, height]
static var _lm := PackedFloat32Array()
static var _flat := PackedFloat32Array()
static var _centers := PackedVector3Array()   # chunk centre directions by key_index


static func setup() -> void:
	if _inited:
		return
	_n_base = FastNoiseLite.new()
	_n_base.seed = SEED
	_n_base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_base.frequency = 0.006
	_n_base.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_base.fractal_octaves = 4
	_n_detail = FastNoiseLite.new()
	_n_detail.seed = SEED + 1
	_n_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_n_detail.frequency = 0.09
	_n_detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_detail.fractal_octaves = 2
	_n_mtn = FastNoiseLite.new()
	_n_mtn.seed = SEED + 2
	_n_mtn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_mtn.frequency = 0.0085
	_n_mtn.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_n_mtn.fractal_octaves = 4
	_n_dirt = FastNoiseLite.new()
	_n_dirt.seed = SEED + 3
	_n_dirt.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_n_dirt.frequency = 0.045
	_n_dirt.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_dirt.fractal_octaves = 3
	_n_dirt2 = FastNoiseLite.new()
	_n_dirt2.seed = SEED + 4
	_n_dirt2.noise_type = FastNoiseLite.TYPE_CELLULAR
	_n_dirt2.frequency = 0.012
	var lm := PackedFloat32Array()
	for c in LANDMARK_CRATERS:
		var d := map_to_dir(c[1], c[2])
		lm.append_array([d.x, d.y, d.z, c[3], c[4]])
	_lm = lm
	var fl := PackedFloat32Array()
	for f in FLAT_SITES:
		var d := map_to_dir(f[0], f[1])
		fl.append_array([d.x, d.y, d.z, f[2], f[3]])
	_flat = fl
	var cs := PackedVector3Array()
	cs.resize(6 * N * N)
	for f in 6:
		for j in N:
			for i in N:
				var span := 2.0 / N
				cs[(f * N + j) * N + i] = param_to_dir(f, -1.0 + (i + 0.5) * span, -1.0 + (j + 0.5) * span)
	_centers = cs
	_inited = true


static func _hash(ix: int, iz: int, s: int) -> int:
	var h: int = (ix * 73856093) ^ (iz * 19349663) ^ (s * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7fffffff


static func hashf(ix: int, iz: int, s: int) -> float:
	return float(_hash(ix, iz, s) & 0xffff) / 65535.0


# ------------------------------------------------------------- cube sphere

## Face normal / in-face axes. A match instead of constant arrays (thread safety).
static func face_n(f: int) -> Vector3:
	match f:
		0: return Vector3(1, 0, 0)
		1: return Vector3(-1, 0, 0)
		2: return Vector3(0, 1, 0)
		3: return Vector3(0, -1, 0)
		4: return Vector3(0, 0, 1)
	return Vector3(0, 0, -1)


static func face_u(f: int) -> Vector3:
	match f:
		0: return Vector3(0, 0, -1)
		1: return Vector3(0, 0, 1)
		2: return Vector3(1, 0, 0)
		3: return Vector3(1, 0, 0)
		4: return Vector3(1, 0, 0)
	return Vector3(-1, 0, 0)


static func face_v(f: int) -> Vector3:
	match f:
		2: return Vector3(0, 0, 1)
		3: return Vector3(0, 0, -1)
	return Vector3(0, 1, 0)


## Unit direction for a face param (a, b); params slightly outside [-1, 1] are fine.
static func param_to_dir(f: int, a: float, b: float) -> Vector3:
	return (face_n(f) + face_u(f) * tan(a * PI * 0.25) + face_v(f) * tan(b * PI * 0.25)).normalized()


static func face_of(d: Vector3) -> int:
	var ax := absf(d.x)
	var ay := absf(d.y)
	var az := absf(d.z)
	if ax >= ay and ax >= az:
		return 0 if d.x > 0.0 else 1
	if ay >= az:
		return 2 if d.y > 0.0 else 3
	return 4 if d.z > 0.0 else 5


## Face param of a direction projected onto face f (valid while dot(d, n_f) > 0).
static func param_on_face(f: int, d: Vector3) -> Vector2:
	var dn := d.dot(face_n(f))
	return Vector2(atan(d.dot(face_u(f)) / dn) * 4.0 / PI, atan(d.dot(face_v(f)) / dn) * 4.0 / PI)


static func key_of(d: Vector3) -> Vector3i:
	var f := face_of(d)
	var p := param_on_face(f, d)
	return Vector3i(f, clampi(floori((p.x + 1.0) * 0.5 * N), 0, N - 1), clampi(floori((p.y + 1.0) * 0.5 * N), 0, N - 1))


static func key_index(k: Vector3i) -> int:
	return (k.x * N + k.z) * N + k.y


static func chunk_center_dir(k: Vector3i) -> Vector3:
	if _centers.size() == 6 * N * N:
		return _centers[key_index(k)]
	var span := 2.0 / N
	return param_to_dir(k.x, -1.0 + (k.y + 0.5) * span, -1.0 + (k.z + 0.5) * span)


## Direction of a point given in chunk-local param (0..1 across the chunk).
static func chunk_dir(k: Vector3i, u: float, v: float) -> Vector3:
	var span := 2.0 / N
	return param_to_dir(k.x, -1.0 + (k.y + u) * span, -1.0 + (k.z + v) * span)


## Chunk-local param (0..1) of a direction, using that chunk's face.
static func chunk_uv(k: Vector3i, d: Vector3) -> Vector2:
	var p := param_on_face(k.x, d)
	return Vector2((p.x + 1.0) * 0.5 * N - k.y, (p.y + 1.0) * 0.5 * N - k.z)


## The 8 chunks around a chunk (across face edges too).
static func neighbours(k: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for dj in range(-1, 2):
		for di in range(-1, 2):
			if di == 0 and dj == 0:
				continue
			var nk := key_of(chunk_dir(k, 0.5 + di, 0.5 + dj))
			if nk != k and not out.has(nk):
				out.append(nk)
	return out


static func all_chunks() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for f in 6:
		for j in N:
			for i in N:
				out.append(Vector3i(f, i, j))
	return out


# ----------------------------------------------------------- map / frames

## Map coordinates (old flat layout, distance from the base preserved) -> direction.
static func map_to_dir(x: float, z: float) -> Vector3:
	var rho := sqrt(x * x + z * z)
	if rho < 0.0001:
		return Vector3.UP
	var phi := rho / RADIUS
	var th := atan2(z, x)
	return Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))


static func dir_to_map(d: Vector3) -> Vector2:
	var phi := acos(clampf(d.y, -1.0, 1.0))
	var th := atan2(d.z, d.x)
	return Vector2(cos(th), sin(th)) * phi * RADIUS


## Local frame on the surface: Y = up (away from the centre), X/Z = the map's x/z
## directions there (at the base exactly the world axes). Singular only at the south pole.
static func frame(d: Vector3) -> Basis:
	var up := d.normalized()
	var phi := acos(clampf(up.y, -1.0, 1.0))
	var th := atan2(up.z, up.x)
	if phi < 0.0001:
		return Basis.IDENTITY
	var cp := cos(phi)
	var sp := sin(phi)
	var ct := cos(th)
	var st := sin(th)
	var e_phi := Vector3(cp * ct, -sp, cp * st)
	var e_th := Vector3(-st, 0, ct)
	var x := (e_phi * ct - e_th * st)
	x = (x - up * x.dot(up)).normalized()
	if x.length_squared() < 0.5:
		x = up.cross(Vector3.FORWARD).normalized()
	var z := x.cross(up).normalized()
	return Basis(x, up, z)


## Transform for something laid out in map coordinates: (x, z) on the surface, h metres
## above the Moon's mean radius (TerrainGen.height values), local axes = frame().
static func map_xform(x: float, z: float, h: float) -> Transform3D:
	var d := map_to_dir(x, z)
	return Transform3D(frame(d), d * (RADIUS + h))


## World position of a map point (x, z) at height h above the mean radius.
static func map_point(x: float, z: float, h: float) -> Vector3:
	return map_to_dir(x, z) * (RADIUS + h)


## World position of a map point standing on the ground (+ lift metres).
static func map_ground(x: float, z: float, lift := 0.0) -> Vector3:
	var d := map_to_dir(x, z)
	return d * (RADIUS + height_dir(d) + lift)


## Upright orientation at world point p (Y away from the centre) facing `forward`
## (projected onto the ground; the local frame's -Z when it is vertical or zero).
static func upright(p: Vector3, forward: Vector3) -> Basis:
	var up := p.normalized()
	var f := forward - up * forward.dot(up)
	if f.length_squared() < 1e-8:
		f = -frame(up).z
	var z := -f.normalized()
	return Basis(up.cross(z).normalized(), up, z)


## Upright orientation at p turned `yaw` radians from the local frame (yaw 0 = facing
## the map's -Z there, like Basis(Vector3.UP, yaw) on the old flat map).
static func heading_basis(p: Vector3, yaw: float) -> Basis:
	return frame(p.normalized()) * Basis(Vector3.UP, yaw)


## The yaw of an orientation at p relative to the local frame (inverse of heading_basis).
static func yaw_of(p: Vector3, b: Basis) -> float:
	var local := frame(p.normalized()).inverse() * b.z
	return atan2(local.x, local.z)


## Standing point lift metres above the ground under world position p.
static func surface(p: Vector3, lift := 0.0) -> Vector3:
	var d := p.normalized()
	return d * (RADIUS + height_dir(d) + lift)


# --------------------------------------------------------------- regions

static func region_dir(d: Vector3) -> int:
	if acos(clampf(d.y, -1.0, 1.0)) * RADIUS < ZONE_RADIUS:
		return Region.LANDING
	var a := atan2(d.z, d.x)
	if absf(a) < PI * 0.25:
		return Region.CRATERS
	if a <= -PI * 0.25 and a > -PI * 0.75:
		return Region.HIGHLANDS
	if a >= PI * 0.25 and a < PI * 0.75:
		return Region.INDUSTRIAL
	return Region.RESEARCH


## Region at a world position.
static func region_of(p: Vector3) -> int:
	return region_dir(p.normalized())


## Region at map coordinates.
static func region_at(x: float, z: float) -> int:
	return region_dir(map_to_dir(x, z))


## Smooth weights (craters, highlands, research, industrial) for blending terrain style.
static func region_weights_dir(d: Vector3) -> Vector4:
	var s := acos(clampf(d.y, -1.0, 1.0)) * RADIUS
	var radial := smoothstep(ZONE_RADIUS - 20.0, ZONE_RADIUS + 30.0, s)
	if radial <= 0.0:
		return Vector4.ZERO
	var a := atan2(d.z, d.x)
	var w := Vector4(
		_sector_w(a, 0.0),
		_sector_w(a, -PI * 0.5),
		_sector_w(a, PI),
		_sector_w(a, PI * 0.5))
	return w * radial


static func _sector_w(a: float, center: float) -> float:
	var dd := absf(wrapf(a - center, -PI, PI))
	return clampf((PI * 0.25 - dd) / 0.22 + 0.5, 0.0, 1.0)


# ---------------------------------------------------------------- shape

static func _crater_profile(d: float) -> float:
	var bowl := 0.0
	if d < 1.0:
		bowl = d * d - 1.0
	var rim := exp(-pow((d - 1.0) / 0.3, 2.0)) * 0.32
	return bowl + rim


## One crater field on the cube sphere: G x G cells per face, each holding a crater with
## probability prob. Returns Vector2(height contribution, interior 0..1).
static func _crater_layer(d: Vector3, g: int, prob: float, rmin: float, rmax: float, depth_k: float, s: int) -> Vector2:
	var h := 0.0
	var inside := 0.0
	var f0 := face_of(d)
	for f in 6:
		var dn := d.dot(face_n(f))
		if f != f0 and dn < 0.55:
			continue
		var p := param_on_face(f, d)
		var ci := floori((p.x + 1.0) * 0.5 * g)
		var cj := floori((p.y + 1.0) * 0.5 * g)
		# Other faces only matter near their edge.
		if f != f0 and (ci < -1 or ci > g or cj < -1 or cj > g):
			continue
		for ix in range(ci - 1, ci + 2):
			if ix < 0 or ix >= g:
				continue
			for iz in range(cj - 1, cj + 2):
				if iz < 0 or iz >= g:
					continue
				var hs := _hash(f * 4096 + ix, iz, s)
				if float(hs & 1023) / 1023.0 > prob:
					continue
				var pa := -1.0 + (float(ix) + 0.15 + 0.7 * float((hs >> 10) & 1023) / 1023.0) * 2.0 / g
				var pb := -1.0 + (float(iz) + 0.15 + 0.7 * float((hs >> 20) & 1023) / 1023.0) * 2.0 / g
				var c := param_to_dir(f, pa, pb)
				var rad := lerpf(rmin, rmax, hashf(f * 4096 + ix, iz, s + 7))
				var dist := (d - c).length() * RADIUS
				var d2 := dist * dist / (rad * rad)
				if d2 > 3.0:
					continue
				var dd := sqrt(d2)
				h += _crater_profile(dd) * rad * depth_k
				if dd < 1.0:
					inside = maxf(inside, 1.0 - dd * dd)
	return Vector2(h, inside)


## Main terrain sample at a direction: Vector3(height above RADIUS, crater interior 0..1,
## rockiness 0..1).
static func sample_dir(d: Vector3) -> Vector3:
	var p := d * RADIUS
	var s := acos(clampf(d.y, -1.0, 1.0)) * RADIUS   # surface distance from the base
	var w := region_weights_dir(d)
	var flat := 1.0 - 0.6 * w.w
	var h := _n_base.get_noise_3d(p.x, p.y, p.z) * 3.2 * flat
	h += _n_detail.get_noise_3d(p.x, p.y, p.z) * 0.35 * flat
	var interior := 0.0
	var rock := 0.0
	# Highland mountains
	if w.y > 0.0:
		var m := _n_mtn.get_noise_3d(p.x, p.y, p.z) * 0.5 + 0.5
		h += w.y * (m * m * 46.0 - 6.0)
		rock = maxf(rock, w.y * m)
	# Research facility rolling dunes
	if w.z > 0.0:
		h += w.z * _n_base.get_noise_3d(p.z * 1.7, p.x * 1.7, p.y * 1.7) * 5.0
	# Crater fields: dense large craters
	var c1 := _crater_layer(d, 10, 0.8, 7.0, 19.0, 0.26, SEED + 11)
	var crater_amt := 0.25 + 0.75 * w.x
	h += c1.x * crater_amt
	interior = maxf(interior, c1.y * crater_amt)
	# Scattered small craters everywhere
	var c2 := _crater_layer(d, 25, 0.45, 1.6, 5.0, 0.22, SEED + 12)
	h += c2.x * (1.0 - 0.5 * w.w)
	interior = maxf(interior, c2.y * 0.6)
	# Authored landmark craters
	var lm := _lm
	for li in range(0, lm.size(), 5):
		var dist := Vector3(d.x - lm[li], d.y - lm[li + 1], d.z - lm[li + 2]).length() * RADIUS
		var rad: float = lm[li + 3]
		var d2 := dist * dist / (rad * rad)
		if d2 < 3.0:
			var dd := sqrt(d2)
			h += _crater_profile(dd) * lm[li + 4]
			if dd < 1.0:
				interior = maxf(interior, 1.0 - dd * dd)
	# Dividing ridges between the outer regions (along the diagonal meridians). They
	# die away before the far pole, so a wide plain there joins every region: you can
	# walk or drive all the way round the Moon.
	if s > 150.0 and s < 870.0:
		var a := atan2(d.z, d.x)
		var nearest := absf(wrapf(a - PI * 0.25, -PI * 0.25, PI * 0.25))
		var lateral := RADIUS * sin(s / RADIUS) * sin(nearest)
		if lateral < 34.0:
			var k := 1.0 - lateral / 34.0
			h += smoothstep(150.0, 215.0, s) * (1.0 - smoothstep(760.0, 860.0, s)) * 44.0 * k * k * (0.75 + 0.5 * (_n_mtn.get_noise_3d(p.x * 2.0, p.y * 2.0, p.z * 2.0) * 0.5 + 0.5))
			rock = maxf(rock, k * smoothstep(150.0, 215.0, s))
	# Flattened authored sites
	var fl := _flat
	for fi in range(0, fl.size(), 5):
		var dist := Vector3(d.x - fl[fi], d.y - fl[fi + 1], d.z - fl[fi + 2]).length() * RADIUS
		var sr: float = fl[fi + 3]
		if dist < sr * 1.6:
			var k := 1.0 - smoothstep(sr, sr * 1.6, dist)
			h = lerpf(h, fl[fi + 4], k)
			interior *= 1.0 - k
	# Base pad is perfectly flat (on the sphere)
	if s < BASE_RADIUS * 1.8:
		var k := 1.0 - smoothstep(BASE_RADIUS, BASE_RADIUS * 1.8, s)
		h = lerpf(h, 0.0, k)
		interior *= 1.0 - k
	return Vector3(h, interior, rock)


static func height_dir(d: Vector3) -> float:
	return sample_dir(d).x


## Map-coordinate sample / height (for authored layouts).
static func sample(x: float, z: float) -> Vector3:
	return sample_dir(map_to_dir(x, z))


static func height(x: float, z: float) -> float:
	return sample_dir(map_to_dir(x, z)).x


## Ground point directly below/above a world position.
static func ground(p: Vector3) -> Vector3:
	var d := p.normalized()
	return d * (RADIUS + height_dir(d))


## Distance from the Moon's centre to the ground under a world position.
static func ground_radius(p: Vector3) -> float:
	return RADIUS + height_dir(p.normalized())


## How far a world position is above the ground (negative = below).
static func altitude(p: Vector3) -> float:
	return p.length() - ground_radius(p)


## World-space ground normal at a direction.
static func normal_dir(d: Vector3) -> Vector3:
	var b := frame(d)
	var e := 0.5
	var c := ground(d)
	var px := ground(c + b.x * e)
	var pz := ground(c + b.z * e)
	var n := (pz - c).cross(px - c).normalized()
	return n if n.dot(d) > 0.0 else -n


## Ground normal at map coordinates, in the local frame (y = how flat: 1 = level).
static func normal(x: float, z: float) -> Vector3:
	var d := map_to_dir(x, z)
	return frame(d).inverse() * normal_dir(d)


## Flatness at a world position: 1 = level ground, 0 = vertical.
static func flatness(p: Vector3) -> float:
	var d := p.normalized()
	return normal_dir(d).dot(d)


static func landmark(name: String) -> Array:
	for c in LANDMARK_CRATERS:
		if c[0] == name:
			return c
	return []


## World position of a landmark crater's centre on the ground.
static func landmark_point(name: String) -> Vector3:
	var c := landmark(name)
	return map_ground(c[1], c[2]) if not c.is_empty() else Vector3.UP * RADIUS


# ---------------------------------------------------------------- rocks

## Large boulders per chunk by region. A match instead of a constant array: constant
## arrays are shared between threads and their reference counting raced on 8-core phones.
static func rocks_for_region(region: int) -> int:
	match region:
		Region.CRATERS:
			return 7
		Region.HIGHLANDS:
			return 14
		Region.RESEARCH:
			return 6
		Region.INDUSTRIAL:
			return 3
	return 4


const SMALL_ROCKS := 26


## Rock i of a chunk: Vector4(chunk u, chunk v, size, hash) or w < 0 when absent.
## Rocks i < big_count are boulders; the rest are pebbles.
static func rock(key: Vector3i, i: int, big_count: int) -> Vector4:
	var kx := key.x * 97 + key.y
	var kz := key.z
	var hu := hashf(kx * 31 + i, kz * 17 - i, 991)
	var hv := hashf(kx * 13 - i, kz * 29 + i, 553)
	var hsz := hashf(kx + i * 7, kz - i * 3, 211)
	var d := chunk_dir(key, hu, hv)
	if acos(clampf(d.y, -1.0, 1.0)) * RADIUS < 60.0:
		return Vector4(0, 0, 0, -1)
	var big := i < big_count
	var s := (0.5 + hsz * hsz * 2.6) if big else (0.08 + hsz * 0.22)
	if big and sample_dir(d).z > 0.4:
		s *= 1.6
	return Vector4(hu, hv, s, hsz)


static func big_rocks_in(key: Vector3i) -> int:
	return rocks_for_region(region_dir(chunk_center_dir(key)))


## Chunks close enough to the base have no rocks at all.
static func chunk_has_rocks(key: Vector3i) -> bool:
	return acos(clampf(chunk_center_dir(key).y, -1.0, 1.0)) * RADIUS >= 30.0


## Texels of a chunk where dust could never be reached or seen: under rocks and on
## slopes too steep to stand on. Returns a byte per texel (1 = unreachable).
static func unreachable_mask(key: Vector3i) -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(MASK * MASK)
	# Steep ground: grid of QUADS x QUADS cells, each covering per x per texels.
	var n := QUADS + 1
	var pts := PackedVector3Array()
	pts.resize(n * n)
	for j in n:
		for i in n:
			var d := chunk_dir(key, float(i) / QUADS, float(j) / QUADS)
			pts[j * n + i] = d * (RADIUS + height_dir(d))
	var per := MASK / QUADS
	var min_up := 1.0 / sqrt(1.0 + MAX_DUST_SLOPE * MAX_DUST_SLOPE)
	for cj in QUADS:
		for ci in QUADS:
			var p00 := pts[cj * n + ci]
			var nrm := (pts[cj * n + ci + 1] - p00).cross(pts[(cj + 1) * n + ci] - p00).normalized()
			if absf(nrm.dot(p00.normalized())) < min_up:
				for tz in per:
					var row := (cj * per + tz) * MASK + ci * per
					for tx in per:
						m[row + tx] = 1
	# Rocks from this chunk and its neighbours (they overlap chunk edges).
	var keys: Array[Vector3i] = [key]
	keys.append_array(neighbours(key))
	for k in keys:
		if not chunk_has_rocks(k):
			continue
		var big := big_rocks_in(k)
		for i in big + SMALL_ROCKS:
			var rk := rock(k, i, big)
			if rk.w < 0.0:
				continue
			var rd := chunk_dir(k, rk.x, rk.y)
			var rad := rk.z * 1.15 + 0.05
			if rd.dot(face_n(key.x)) <= 0.1:
				continue
			var uv := chunk_uv(key, rd)
			var span := rad / TEXEL * 1.5 + 1.0
			var lx0 := maxi(int(uv.x * MASK - span), 0)
			var lx1 := mini(int(uv.x * MASK + span), MASK - 1)
			var lz0 := maxi(int(uv.y * MASK - span), 0)
			var lz1 := mini(int(uv.y * MASK + span), MASK - 1)
			if lx0 > lx1 or lz0 > lz1:
				continue
			var r2 := rad * rad / (RADIUS * RADIUS)
			for lz in range(lz0, lz1 + 1):
				for lx in range(lx0, lx1 + 1):
					var td := chunk_dir(key, (lx + 0.5) / MASK, (lz + 0.5) / MASK)
					if (td - rd).length_squared() < r2:
						m[lz * MASK + lx] = 1
	return m


## Initial dust layer for a chunk (thread-safe). Bytes 0..255 per texel.
static func initial_dirt(key: Vector3i) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(MASK * MASK)
	var s_c := acos(clampf(chunk_center_dir(key).y, -1.0, 1.0)) * RADIUS
	# Near the base the ground has been "swept a little" - lighter coverage.
	var base_k := clampf((s_c - 20.0) / 40.0, 0.0, 1.0)
	var blocked := unreachable_mask(key)
	for lz in MASK:
		var row := lz * MASK
		var v := (lz + 0.5) / MASK
		for lx in MASK:
			if blocked[row + lx] != 0:
				continue
			var p := chunk_dir(key, (lx + 0.5) / MASK, v) * RADIUS
			var nn := _n_dirt.get_noise_3d(p.x, p.y, p.z)
			var c := _n_dirt2.get_noise_3d(p.x, p.y, p.z)
			var val := 0.78 + 0.18 * nn - 0.1 * c
			val = lerpf(0.62 + 0.1 * nn, val, base_k)
			data[row + lx] = clampi(int(val * 255.0), 120, 255)
	return data


## Every chunk of the Moon must be cleaned to finish.
static func playable_chunks() -> Array[Vector3i]:
	return all_chunks()


## Dust quantity multiplier at a world position (region thickness x crater interiors).
static func thickness(p: Vector3, region_thickness: float) -> float:
	var s := sample_dir(p.normalized())
	return region_thickness * (1.0 + 0.8 * s.y)
