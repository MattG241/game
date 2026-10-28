class_name TerrainGen
extends RefCounted
## Deterministic lunar terrain. Pure functions of (x, z) so chunks can be built on
## worker threads and regenerated identically after loading a save.

const CHUNK := 32.0            # metres per chunk side
const QUADS := 32              # LOD0 grid quads per side (1 m spacing)
const QUADS_FAR := 8           # LOD1 grid quads per side (4 m spacing)
const MASK := 128              # dirt mask texels per chunk side (0.25 m)
const TEXEL := CHUNK / MASK
const WORLD_RADIUS := 600.0
const BASE_RADIUS := 34.0
const ZONE_RADIUS := 150.0
const SEED := 4242

enum Region { LANDING, CRATERS, HIGHLANDS, RESEARCH, INDUSTRIAL }

# Authored landmark craters: [name, x, z, radius, depth]
const LANDMARK_CRATERS := [
	["tutorial_crater", 46.0, -40.0, 10.0, 2.4],
	["great_basin", 360.0, 40.0, 78.0, 15.0],
	["twin_west", 250.0, -110.0, 26.0, 6.0],
	["twin_east", 285.0, 120.0, 30.0, 7.0],
	["highland_bowl", -40.0, -330.0, 34.0, 7.0],
	["facility_pit", -300.0, 90.0, 22.0, 5.0],
	["south_scar", 60.0, 420.0, 40.0, 4.0],
]

# Flattened pads for authored sites: [x, z, radius, height]
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
# Flattened copies of the authored tables (packed arrays are safe to read from worker threads).
static var _lm := PackedFloat32Array()
static var _flat := PackedFloat32Array()


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
		lm.append_array([c[1], c[2], c[3], c[4]])
	_lm = lm
	var fl := PackedFloat32Array()
	for f in FLAT_SITES:
		fl.append_array([f[0], f[1], f[2], f[3]])
	_flat = fl
	_inited = true


static func _hash(ix: int, iz: int, s: int) -> int:
	var h: int = (ix * 73856093) ^ (iz * 19349663) ^ (s * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7fffffff


static func hashf(ix: int, iz: int, s: int) -> float:
	return float(_hash(ix, iz, s) & 0xffff) / 65535.0


static func region_at(x: float, z: float) -> int:
	if x * x + z * z < ZONE_RADIUS * ZONE_RADIUS:
		return Region.LANDING
	var a := atan2(z, x)
	if absf(a) < PI * 0.25:
		return Region.CRATERS
	if a <= -PI * 0.25 and a > -PI * 0.75:
		return Region.HIGHLANDS
	if a >= PI * 0.25 and a < PI * 0.75:
		return Region.INDUSTRIAL
	return Region.RESEARCH


## Smooth weights (craters, highlands, research, industrial) for blending terrain style.
static func region_weights(x: float, z: float) -> Vector4:
	var r := sqrt(x * x + z * z)
	var radial := smoothstep(ZONE_RADIUS - 20.0, ZONE_RADIUS + 30.0, r)
	if radial <= 0.0:
		return Vector4.ZERO
	var a := atan2(z, x)
	var w := Vector4(
		_sector_w(a, 0.0),
		_sector_w(a, -PI * 0.5),
		_sector_w(a, PI),
		_sector_w(a, PI * 0.5))
	return w * radial


static func _sector_w(a: float, center: float) -> float:
	var d := absf(wrapf(a - center, -PI, PI))
	return clampf((PI * 0.25 - d) / 0.22 + 0.5, 0.0, 1.0)


static func _crater_profile(d: float) -> float:
	var bowl := 0.0
	if d < 1.0:
		bowl = d * d - 1.0
	var rim := exp(-pow((d - 1.0) / 0.3, 2.0)) * 0.32
	return bowl + rim


## Returns Vector2(height contribution, interior factor 0..1)
static func _crater_layer(x: float, z: float, cell: float, prob: float, rmin: float, rmax: float, depth_k: float, s: int) -> Vector2:
	var cx := floori(x / cell)
	var cz := floori(z / cell)
	var h := 0.0
	var inside := 0.0
	for ix in range(cx - 1, cx + 2):
		for iz in range(cz - 1, cz + 2):
			var hs := _hash(ix, iz, s)
			if float(hs & 1023) / 1023.0 > prob:
				continue
			var px := (float(ix) + 0.15 + 0.7 * float((hs >> 10) & 1023) / 1023.0) * cell
			var pz := (float(iz) + 0.15 + 0.7 * float((hs >> 20) & 1023) / 1023.0) * cell
			var rad := lerpf(rmin, rmax, hashf(ix, iz, s + 7))
			var dx := x - px
			var dz := z - pz
			var d2 := (dx * dx + dz * dz) / (rad * rad)
			if d2 > 3.0:
				continue
			var d := sqrt(d2)
			h += _crater_profile(d) * rad * depth_k
			if d < 1.0:
				inside = maxf(inside, 1.0 - d * d)
	return Vector2(h, inside)


## Main terrain sample: Vector3(height, crater_interior 0..1, rockiness 0..1)
static func sample(x: float, z: float) -> Vector3:
	var r := sqrt(x * x + z * z)
	var w := region_weights(x, z)
	var flat := 1.0 - 0.6 * w.w
	var h := _n_base.get_noise_2d(x, z) * 3.2 * flat
	h += _n_detail.get_noise_2d(x, z) * 0.35 * flat
	var interior := 0.0
	var rock := 0.0
	# Highland mountains
	if w.y > 0.0:
		var m := _n_mtn.get_noise_2d(x, z) * 0.5 + 0.5
		h += w.y * (m * m * 46.0 - 6.0)
		rock = maxf(rock, w.y * m)
	# Research facility rolling dunes
	if w.z > 0.0:
		h += w.z * _n_base.get_noise_2d(z * 1.7, x * 1.7) * 5.0
	# Crater fields: dense large craters
	var c1 := _crater_layer(x, z, 46.0, 0.8, 7.0, 19.0, 0.26, SEED + 11)
	var crater_amt := 0.25 + 0.75 * w.x
	h += c1.x * crater_amt
	interior = maxf(interior, c1.y * crater_amt)
	# Scattered small craters everywhere
	var c2 := _crater_layer(x, z, 19.0, 0.45, 1.6, 5.0, 0.22, SEED + 12)
	h += c2.x * (1.0 - 0.5 * w.w)
	interior = maxf(interior, c2.y * 0.6)
	# Authored landmark craters
	var lm := _lm
	for li in range(0, lm.size(), 4):
		var dx: float = x - lm[li]
		var dz: float = z - lm[li + 1]
		var rad: float = lm[li + 2]
		var d2 := (dx * dx + dz * dz) / (rad * rad)
		if d2 < 3.0:
			var d := sqrt(d2)
			var depth: float = lm[li + 3]
			h += _crater_profile(d) * depth
			if d < 1.0:
				interior = maxf(interior, 1.0 - d * d)
	# Dividing ridges between the outer regions (along the diagonals)
	if r > 150.0:
		var a := atan2(z, x)
		var nearest := absf(wrapf(a - PI * 0.25, -PI * 0.25, PI * 0.25))
		var lateral := r * sin(nearest)
		if lateral < 34.0:
			var k := 1.0 - lateral / 34.0
			h += smoothstep(150.0, 215.0, r) * 44.0 * k * k * (0.75 + 0.5 * (_n_mtn.get_noise_2d(x * 2.0, z * 2.0) * 0.5 + 0.5))
			rock = maxf(rock, k * smoothstep(150.0, 215.0, r))
	# Outer ring mountains bound the playable world
	if r > 540.0:
		var e := smoothstep(540.0, 640.0, r)
		h += e * e * 95.0 * (0.7 + 0.6 * (_n_mtn.get_noise_2d(x * 0.7, z * 0.7) * 0.5 + 0.5))
		rock = maxf(rock, e)
	# Flattened authored sites
	var fl := _flat
	for fi in range(0, fl.size(), 4):
		var dx: float = x - fl[fi]
		var dz: float = z - fl[fi + 1]
		var sr: float = fl[fi + 2]
		var d := sqrt(dx * dx + dz * dz)
		if d < sr * 1.6:
			var k := 1.0 - smoothstep(sr, sr * 1.6, d)
			h = lerpf(h, fl[fi + 3], k)
			interior *= 1.0 - k
	# Base pad is perfectly flat
	if r < BASE_RADIUS * 1.8:
		var k := 1.0 - smoothstep(BASE_RADIUS, BASE_RADIUS * 1.8, r)
		h = lerpf(h, 0.0, k)
		interior *= 1.0 - k
	return Vector3(h, interior, rock)


static func height(x: float, z: float) -> float:
	return sample(x, z).x


static func normal(x: float, z: float) -> Vector3:
	var e := 0.5
	var hl := height(x - e, z)
	var hr := height(x + e, z)
	var hd := height(x, z - e)
	var hu := height(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


static func chunk_key(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CHUNK), floori(z / CHUNK))


static func chunk_origin(key: Vector2i) -> Vector2:
	return Vector2(key.x * CHUNK, key.y * CHUNK)


static func landmark(name: String) -> Array:
	for c in LANDMARK_CRATERS:
		if c[0] == name:
			return c
	return []


## Initial dust layer for a chunk (thread-safe). Bytes 0..255 per texel.
# Ground covered by base structures has no dust: you could never see or reach it.
# Footprints must match base.gd. (Plain code, not a const Array: this runs on worker
# threads, where sharing a constant Array is not thread-safe.)
const LANDER_PAD := Vector3(4.0, 30.0, 8.3)   # x, z, radius


static func _in_rect(x: float, z: float, cx: float, cz: float, hx: float, hz: float) -> bool:
	return absf(x - cx) < hx and absf(z - cz) < hz


## True where a base building or landing pad sits on the ground.
static func covered(x: float, z: float) -> bool:
	if Vector2(x - LANDER_PAD.x, z - LANDER_PAD.y).length() < LANDER_PAD.z:
		return true
	return _in_rect(x, z, 0.0, -16.0, 7.2, 7.2) \
		or _in_rect(x, z, -10.0, -16.0, 4.9, 2.4) \
		or _in_rect(x, z, 10.0, -16.0, 4.9, 2.4) \
		or _in_rect(x, z, 11.0, -3.6, 2.5, 2.5) \
		or _in_rect(x, z, -11.0, -4.2, 2.4, 0.9) \
		or _in_rect(x, z, -15.0, -18.0, 3.7, 3.7) \
		or _in_rect(x, z, -19.0, 17.0, 5.2, 12.2)


static func initial_dirt(key: Vector2i) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(MASK * MASK)
	var ox := key.x * CHUNK
	var oz := key.y * CHUNK
	var r_c := Vector2(ox + CHUNK * 0.5, oz + CHUNK * 0.5).length()
	# Near the base the ground has been "swept a little" - lighter coverage.
	var base_k := clampf((r_c - 20.0) / 40.0, 0.0, 1.0)
	var near_base := r_c < BASE_RADIUS + CHUNK
	for lz in MASK:
		var wz := oz + (lz + 0.5) * TEXEL
		var row := lz * MASK
		for lx in MASK:
			var wx := ox + (lx + 0.5) * TEXEL
			var n := _n_dirt.get_noise_2d(wx, wz)
			var c := _n_dirt2.get_noise_2d(wx, wz)
			var v := 0.78 + 0.18 * n - 0.1 * c
			v = lerpf(0.62 + 0.1 * n, v, base_k)
			data[row + lx] = 0 if near_base and covered(wx, wz) else clampi(int(v * 255.0), 120, 255)
	return data


## Dust quantity multiplier at a position (region thickness x crater interiors).
static func thickness(x: float, z: float, region_thickness: float) -> float:
	var s := sample(x, z)
	return region_thickness * (1.0 + 0.8 * s.y)
