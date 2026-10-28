class_name DirtMap
extends RefCounted
## Persistent, chunked dust coverage on the round Moon. Each terrain chunk (cube-sphere
## key Vector3i(face, i, j)) has a 128x128 byte mask. Cleaning tools "stamp" brush shapes
## into the mask; the removed amount becomes dust. Only touched chunks are kept in memory
## permanently and saved (ZSTD compressed).
##
## Brushes are small next to a chunk, so inside one stamp the texel grid is treated as
## flat: a 2x2 matrix maps texel offsets to metres along the brush's right / forward axes.

const MAGIC := "LCDM"
const FORMAT_VERSION := 3
const MASK := TerrainGen.MASK
const TEXEL := TerrainGen.TEXEL
# The flat world before the Moon was round (format 2 saves).
const OLD_CHUNK := 32.0
const OLD_TEXEL := OLD_CHUNK / 128.0

enum Shape { ROUND, RECT }

var chunks := {}          # Vector3i -> DirtChunk
var visual_dirty := {}    # Vector3i -> true (needs GPU texture refresh)
var clean := {}           # Vector3i -> true: chunk has no dust left (persisted in the save)
# Ground under buildings, pads and machines (no dust there): PackedFloat32Array
# [cx, cy, cz, rx, ry, rz, half_x, half_z] for boxes (r = the box's right axis) or
# [cx, cy, cz, radius] for circles.
var covers: Array[PackedFloat32Array] = []
var _playable: Array[Vector3i] = []
# Flat-world chunks from an old save, projected onto the sphere the first time they're
# needed (see _migrate).
var _legacy: Array = []


class DirtChunk:
	extends RefCounted
	var data: PackedByteArray
	var total: int = 0
	var initial_total: int = 0
	var modified := false
	var compressed := PackedByteArray()
	var compressed_valid := false
	var dirty := 0                  # texels still above CLEAN_LEVEL
	var sanitized := true

	func _init(d: PackedByteArray, init_total := -1) -> void:
		data = d
		total = _sum(d)
		initial_total = init_total if init_total >= 0 else total
		recount()

	func recount() -> void:
		var n := 0
		for v in data:
			if v > TerrainGen.CLEAN_LEVEL:
				n += 1
		dirty = n

	## Removes all dust from one texel (covered or unreachable ground).
	func zero(idx: int) -> void:
		var v: int = data[idx]
		if v == 0:
			return
		if v > TerrainGen.CLEAN_LEVEL:
			dirty -= 1
		total -= v
		initial_total -= v
		data[idx] = 0
		modified = true
		compressed_valid = false

	## Lowers one texel to at most v (old saves projected onto the sphere).
	func lower(idx: int, v: int) -> void:
		var cur: int = data[idx]
		if v >= cur:
			return
		if cur > TerrainGen.CLEAN_LEVEL and v <= TerrainGen.CLEAN_LEVEL:
			dirty -= 1
		total -= cur - v
		data[idx] = v
		modified = true
		compressed_valid = false

	static func _sum(d: PackedByteArray) -> int:
		var s := 0
		for v in d:
			s += v
		return s

	func fraction_clean() -> float:
		if initial_total <= 0:
			return 1.0
		return clampf(1.0 - float(total) / float(initial_total), 0.0, 1.0)

	## Brush over texels lx0..lx1 x lz0..lz1. A texel's offset from the brush centre in
	## metres along the brush axes: u = m.x * dx + m.y * dz, v = m.z * dx + m.w * dz,
	## where dx, dz are texel offsets from (fx, fz). Round brushes use radius hw.
	func apply(round: bool, lx0: int, lx1: int, lz0: int, lz1: int, fx: float, fz: float,
			m: Vector4, hw: float, hl: float, amount: float, budget: int) -> int:
		var d := data
		var removed := 0
		var cl := TerrainGen.CLEAN_LEVEL
		var inv_r := 1.0 / hw
		var soft_w := 1.0 / maxf(hw * 0.25, 0.12)
		var soft_l := 1.0 / maxf(hl * 0.25, 0.12)
		var done := false
		for lz in range(lz0, lz1 + 1):
			var dz := lz + 0.5 - fz
			var row := lz * MASK
			var u0 := m.y * dz
			var v0 := m.w * dz
			for lx in range(lx0, lx1 + 1):
				var idx := row + lx
				var cur: int = d[idx]
				if cur == 0:
					continue
				var dx := lx + 0.5 - fx
				var u := u0 + m.x * dx
				var v := v0 + m.z * dx
				var w: float
				if round:
					var dist := sqrt(u * u + v * v) * inv_r
					if dist >= 1.0:
						continue
					w = minf(1.0, (1.0 - dist) * 3.0)
				else:
					u = absf(u)
					v = absf(v)
					if u >= hw or v >= hl:
						continue
					w = minf(minf(1.0, (hw - u) * soft_w), minf(1.0, (hl - v) * soft_l))
				var rem := mini(cur, int(ceil(amount * w)))
				d[idx] = cur - rem
				removed += rem
				if cur > cl and cur - rem <= cl:
					dirty -= 1
				if removed >= budget:
					done = true
					break
			if done:
				break
		if removed > 0:
			data = d
			total -= removed
			modified = true
			compressed_valid = false
		return removed

	func get_compressed() -> PackedByteArray:
		if not compressed_valid:
			compressed = data.compress(FileAccess.COMPRESSION_ZSTD)
			compressed_valid = true
		return compressed


## Clears loaded dust (not the clean-chunk record or covers: see reset()).
func clear() -> void:
	chunks.clear()
	visual_dirty.clear()
	_legacy.clear()


## New game: forget everything.
func reset() -> void:
	clear()
	clean.clear()


func _make(key: Vector3i, data: PackedByteArray, init_total := -1) -> DirtChunk:
	var c := DirtChunk.new(data, init_total)
	for cv in covers:
		_apply_cover(key, c, cv)
	_note(key, c)
	return c


func _note(key: Vector3i, c: DirtChunk) -> void:
	if c.dirty <= 0 and c.sanitized:
		clean[key] = true


# ------------------------------------------------------------ brush geometry

## Chunks a brush of extent ext metres around world point p can touch.
static func keys_near(p: Vector3, ext: float) -> Array[Vector3i]:
	var d := p.normalized()
	var out: Array[Vector3i] = [TerrainGen.key_of(d)]
	var b := TerrainGen.frame(d)
	var steps := maxi(1, ceili(ext / 8.0))
	for j in range(-steps, steps + 1):
		for i in range(-steps, steps + 1):
			if i == 0 and j == 0:
				continue
			var q := d * TerrainGen.RADIUS + (b.x * i + b.z * j) * (ext / steps)
			var k := TerrainGen.key_of(q.normalized())
			if not out.has(k):
				out.append(k)
	return out


## Where a brush lies on one chunk's texel grid: [fx, fz, m, span] or [] when the
## brush's centre is not on that chunk's side of the Moon. right / fwd: unit tangents.
static func _footprint(key: Vector3i, p: Vector3, right: Vector3, fwd: Vector3, ext: float) -> Array:
	var d := p.normalized()
	if d.dot(TerrainGen.face_n(key.x)) < 0.2:
		return []
	var uv := TerrainGen.chunk_uv(key, d)
	var r := TerrainGen.RADIUS
	var c0 := TerrainGen.chunk_dir(key, uv.x, uv.y) * r
	var ex := TerrainGen.chunk_dir(key, uv.x + 1.0 / MASK, uv.y) * r - c0
	var ez := TerrainGen.chunk_dir(key, uv.x, uv.y + 1.0 / MASK) * r - c0
	var m := Vector4(ex.dot(right), ez.dot(right), ex.dot(fwd), ez.dot(fwd))
	var span := ext / minf(ex.length(), ez.length()) + 1.0
	return [uv.x * MASK, uv.y * MASK, m, span]


## Unit tangent axes at p: right, forward (forward projected from the given vector, or
## the local frame's when it is zero / vertical).
static func axes(p: Vector3, forward: Vector3) -> Array:
	var up := p.normalized()
	var f := forward - up * forward.dot(up)
	if f.length_squared() < 1e-6:
		f = -TerrainGen.frame(up).z
	f = f.normalized()
	return [f.cross(up).normalized(), f]


# ------------------------------------------------------------------ covers

## Ground under a building or pad: a box centred at xf.origin, half sizes along the
## transform's own X and Z axes.
func add_cover_box(xf: Transform3D, hx: float, hz: float) -> void:
	var p := xf.origin
	var r := xf.basis.x.normalized()
	_add_cover(PackedFloat32Array([p.x, p.y, p.z, r.x, r.y, r.z, hx, hz]))


func add_cover_circle(center: Vector3, r: float) -> void:
	_add_cover(PackedFloat32Array([center.x, center.y, center.z, r]))


func _add_cover(cv: PackedFloat32Array) -> void:
	covers.append(cv)
	var ext: float = cv[3] if cv.size() == 4 else Vector2(cv[6], cv[7]).length()
	for key in keys_near(Vector3(cv[0], cv[1], cv[2]), ext):
		var c: DirtChunk = chunks.get(key)
		if c != null and _apply_cover(key, c, cv):
			visual_dirty[key] = true
			_note(key, c)


func _apply_cover(key: Vector3i, c: DirtChunk, cv: PackedFloat32Array) -> bool:
	var p := Vector3(cv[0], cv[1], cv[2])
	var circle := cv.size() == 4
	var right: Vector3
	var fwd: Vector3
	var hw: float
	var hl: float
	if circle:
		var ax := axes(p, Vector3.ZERO)
		right = ax[0]
		fwd = ax[1]
		hw = cv[3]
		hl = cv[3]
	else:
		var up := p.normalized()
		right = Vector3(cv[3], cv[4], cv[5])
		right = (right - up * right.dot(up)).normalized()
		fwd = up.cross(right)
		hw = cv[6]
		hl = cv[7]
	var ext := Vector2(hw, hl).length()
	var fp := _footprint(key, p, right, fwd, ext)
	if fp.is_empty():
		return false
	var fx: float = fp[0]
	var fz: float = fp[1]
	var m: Vector4 = fp[2]
	var span: float = fp[3]
	var lx0 := maxi(floori(fx - span), 0)
	var lx1 := mini(floori(fx + span), MASK - 1)
	var lz0 := maxi(floori(fz - span), 0)
	var lz1 := mini(floori(fz + span), MASK - 1)
	if lx0 > lx1 or lz0 > lz1:
		return false
	var changed := false
	for lz in range(lz0, lz1 + 1):
		var dz := lz + 0.5 - fz
		for lx in range(lx0, lx1 + 1):
			var idx := lz * MASK + lx
			if c.data[idx] == 0:
				continue
			var dx := lx + 0.5 - fx
			var u := m.x * dx + m.y * dz
			var v := m.z * dx + m.w * dz
			var inside: bool
			if circle:
				inside = u * u + v * v < hw * hw
			else:
				inside = absf(u) < hw and absf(v) < hl
			if inside:
				c.zero(idx)
				changed = true
	return changed


## Removes all dust of one terrain chunk that lies in hexagon `cell` (the finishing
## sweep when a hexagon is cleared). Works on 8x8 texel blocks: blocks whose corners
## all fall in one cell are handled whole, only blocks on a border are checked texel
## by texel. Returns the removed area in square metres.
func sweep_cell(key: Vector3i, cell: int) -> float:
	var c := get_chunk(key)
	var cand := HexGrid.candidates(key)
	var b := 8
	var nb := MASK / b
	var owner := PackedInt32Array()
	owner.resize((nb + 1) * (nb + 1))
	for j in nb + 1:
		for i in nb + 1:
			owner[j * (nb + 1) + i] = HexGrid.nearest(TerrainGen.chunk_dir(key, float(i * b) / MASK, float(j * b) / MASK), cand)
	var before := c.total
	for j in nb:
		for i in nb:
			var o0 := owner[j * (nb + 1) + i]
			var same := o0 == owner[j * (nb + 1) + i + 1] and o0 == owner[(j + 1) * (nb + 1) + i] and o0 == owner[(j + 1) * (nb + 1) + i + 1]
			if same and o0 != cell:
				continue
			for tz in b:
				var lz := j * b + tz
				for tx in b:
					var lx := i * b + tx
					var idx := lz * MASK + lx
					if c.data[idx] == 0:
						continue
					if same or HexGrid.nearest(TerrainGen.chunk_dir(key, (lx + 0.5) / MASK, (lz + 0.5) / MASK), cand) == cell:
						c.zero(idx)
	var removed := before - c.total
	if removed > 0:
		visual_dirty[key] = true
		_note(key, c)
	return float(removed) / 255.0 * TEXEL * TEXEL


## Chunks whose unreachable texels (under rocks, on cliffs) still need clearing.
func needs_sanitize(key: Vector3i) -> bool:
	var c: DirtChunk = chunks.get(key)
	return c != null and not c.sanitized


## Applies an unreachable-texel mask from TerrainGen.unreachable_mask (once).
func sanitize(key: Vector3i, blocked: PackedByteArray) -> void:
	var c: DirtChunk = chunks.get(key)
	if c == null or c.sanitized:
		return
	for i in blocked.size():
		if blocked[i] != 0:
			c.zero(i)
	c.sanitized = true
	visual_dirty[key] = true
	_note(key, c)


# ---------------------------------------------------------------- progress

func playable() -> Array[Vector3i]:
	if _playable.is_empty():
		_playable = TerrainGen.playable_chunks()
	return _playable


## True when every chunk of the Moon has no dust left.
func world_clean() -> bool:
	for key in playable():
		if not clean.has(key):
			return false
	return true


## Approximate cleaned fraction of the whole Moon (exactly 1.0 only when world_clean()).
func world_fraction() -> float:
	var keys := playable()
	var sum := 0.0
	var all := true
	for key in keys:
		if clean.has(key):
			sum += 1.0
			continue
		all = false
		var c: DirtChunk = chunks.get(key)
		if c != null and c.modified:
			sum += clampf(1.0 - float(c.dirty) / float(MASK * MASK), 0.0, 0.999)
	if all:
		return 1.0
	# Stays below 100% (mission checks add a small epsilon) until every chunk is clean.
	return minf(sum / float(keys.size()), 0.998)


## How clean one chunk is for the map: 1 = no dust left, 0 = untouched.
func chunk_state(key: Vector3i) -> float:
	if clean.has(key):
		return 1.0
	var c: DirtChunk = chunks.get(key)
	if c == null or not c.modified:
		return 0.0
	return clampf(1.0 - float(c.dirty) / float(MASK * MASK), 0.0, 0.999)


## The nearest spot that still has dust (for the dust finder), on the ground.
## Vector3.INF if none.
func nearest_dust(from: Vector3) -> Vector3:
	var best_key := Vector3i.ZERO
	var best_d := INF
	for key in playable():
		if clean.has(key):
			continue
		var d := (TerrainGen.chunk_center_dir(key) * TerrainGen.RADIUS).distance_squared_to(from)
		if d < best_d:
			best_d = d
			best_key = key
	if best_d == INF:
		return Vector3.INF
	var centre := TerrainGen.ground(TerrainGen.chunk_center_dir(best_key))
	var ch: DirtChunk = chunks.get(best_key)
	if ch == null or not ch.sanitized:
		return centre
	# Nearest remaining dusty texel in that chunk (texel grid distance is close enough).
	var fd := from.normalized()
	var fuv := Vector2(0.5, 0.5)
	if fd.dot(TerrainGen.face_n(best_key.x)) > 0.2:
		fuv = TerrainGen.chunk_uv(best_key, fd)
	var fx := fuv.x * MASK
	var fz := fuv.y * MASK
	var bi := -1
	var bd := INF
	var data := ch.data
	for lz in MASK:
		var row := lz * MASK
		var dz := lz + 0.5 - fz
		for lx in MASK:
			if data[row + lx] > TerrainGen.CLEAN_LEVEL:
				var dx := lx + 0.5 - fx
				var dd := dx * dx + dz * dz
				if dd < bd:
					bd = dd
					bi = row + lx
	if bi < 0:
		# Nothing left after all (counts were stale): record it as clean.
		ch.recount()
		_note(best_key, ch)
		return centre
	var td := TerrainGen.chunk_dir(best_key, ((bi % MASK) + 0.5) / MASK, ((bi / MASK) + 0.5) / MASK)
	return TerrainGen.ground(td)


func has_chunk(key: Vector3i) -> bool:
	return chunks.has(key)


func get_chunk(key: Vector3i) -> DirtChunk:
	var c: DirtChunk = chunks.get(key)
	if c == null:
		TerrainGen.setup()
		c = _make(key, TerrainGen.initial_dirt(key))
		chunks[key] = c
		_migrate_into(key, c)
	return c


## Register initial data generated on a worker thread (ignored if already present).
func put_initial(key: Vector3i, data: PackedByteArray) -> void:
	if not chunks.has(key):
		var c := _make(key, data)
		chunks[key] = c
		_migrate_into(key, c)


## Free memory for chunks the player never touched.
func release(key: Vector3i) -> void:
	var c: DirtChunk = chunks.get(key)
	if c != null and not c.modified:
		chunks.erase(key)


func get_image(key: Vector3i) -> Image:
	return Image.create_from_data(MASK, MASK, false, Image.FORMAT_L8, get_chunk(key).data)


## Dust coverage 0..1 at a world position (any height above the ground).
func sample(p: Vector3) -> float:
	var d := p.normalized()
	var key := TerrainGen.key_of(d)
	var c := get_chunk(key)
	var uv := TerrainGen.chunk_uv(key, d)
	var lx := clampi(int(uv.x * MASK), 0, MASK - 1)
	var lz := clampi(int(uv.y * MASK), 0, MASK - 1)
	return c.data[lz * MASK + lx] / 255.0


## Stamp a brush centred on world point p. ROUND: radius a. RECT: half width a across,
## half length b along `forward` (a world vector, projected onto the ground).
## Returns removed "full-coverage" area in m2 (multiply by dust density for dust).
## budget_m2 caps how much may be removed (tank space).
func stamp(shape: int, p: Vector3, a: float, b: float, forward: Vector3, strength_dt: float, budget_m2: float) -> float:
	if budget_m2 <= 0.0 or strength_dt <= 0.0:
		return 0.0
	var round := shape == Shape.ROUND
	var ext := a if round else sqrt(a * a + b * b)
	var amount := strength_dt * 255.0
	var ax := axes(p, forward)
	var removed := 0.0
	for key in keys_near(p, ext):
		if removed >= budget_m2:
			break
		var fp := _footprint(key, p, ax[0], ax[1], ext)
		if fp.is_empty():
			continue
		var fx: float = fp[0]
		var fz: float = fp[1]
		var m: Vector4 = fp[2]
		var span: float = fp[3]
		var lx0 := maxi(floori(fx - span), 0)
		var lx1 := mini(floori(fx + span), MASK - 1)
		var lz0 := maxi(floori(fz - span), 0)
		var lz1 := mini(floori(fz + span), MASK - 1)
		if lx0 > lx1 or lz0 > lz1:
			continue
		# Texels differ a little in size across the Moon: count real square metres.
		var texel_m2 := absf(m.x * m.w - m.y * m.z)
		var budget := int(ceil((budget_m2 - removed) / texel_m2 * 255.0))
		var c := get_chunk(key)
		var r := c.apply(round, lx0, lx1, lz0, lz1, fx, fz, m, a, a if round else b, amount, budget)
		if r > 0:
			removed += float(r) / 255.0 * texel_m2
			visual_dirty[key] = true
			if c.dirty <= 0:
				_note(key, c)
	return removed


## Fraction (0..1) of a circular area around world point p that is clean (coverage
## below 20%).
func area_clean_fraction(p: Vector3, radius: float, step := 1.0) -> float:
	var up := p.normalized()
	var b := TerrainGen.frame(up)
	var c := up * TerrainGen.RADIUS
	var total := 0
	var n_clean := 0
	var x := -radius
	while x <= radius:
		var z := -radius
		while z <= radius:
			if x * x + z * z <= radius * radius:
				total += 1
				if sample(c + b.x * x + b.z * z) < 0.2:
					n_clean += 1
			z += step
		x += step
	return float(n_clean) / float(maxi(total, 1))


func chunk_fraction(key: Vector3i) -> float:
	var c: DirtChunk = chunks.get(key)
	return c.fraction_clean() if c != null else 0.0


# ---------------------------------------------------------------- persistence

## Cheap main-thread snapshot (packed arrays are copy-on-write, so later edits don't race).
func snapshot() -> Array:
	_migrate_all()
	var out := []
	for key in chunks:
		var c: DirtChunk = chunks[key]
		if c.modified:
			out.append([key, c.get_compressed(), c.initial_total])
	return out


static func encode_snapshot(snap: Array) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_data(MAGIC.to_ascii_buffer())
	buf.put_u32(FORMAT_VERSION)
	buf.put_u32(snap.size())
	for e in snap:
		var key: Vector3i = e[0]
		var comp: PackedByteArray = e[1]
		buf.put_8(key.x)
		buf.put_8(key.y)
		buf.put_8(key.z)
		buf.put_8(0)
		buf.put_u32(int(e[2]))
		buf.put_u32(comp.size())
		buf.put_data(comp)
	return buf.data_array


func decode(bytes: PackedByteArray) -> bool:
	clear()
	if bytes.size() < 12:
		return bytes.is_empty()
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	var magic := buf.get_data(4)
	if magic[0] != OK or (magic[1] as PackedByteArray).get_string_from_ascii() != MAGIC:
		return false
	var version := buf.get_u32()
	if version > FORMAT_VERSION:
		return false
	var legacy := version < 3
	var count := buf.get_u32()
	var old := []
	for i in count:
		var key3 := Vector3i.ZERO
		var key2 := Vector2i.ZERO
		if legacy:
			if buf.get_position() + 16 > bytes.size():
				return false
			key2 = Vector2i(buf.get_32(), buf.get_32())
		else:
			if buf.get_position() + 12 > bytes.size():
				return false
			key3 = Vector3i(buf.get_8(), buf.get_8(), buf.get_8())
			buf.get_8()
			if key3.x < 0 or key3.x > 5 or key3.y < 0 or key3.y >= TerrainGen.N or key3.z < 0 or key3.z >= TerrainGen.N:
				return false
		var init_total := buf.get_u32()
		var size := buf.get_u32()
		var res := buf.get_data(size)
		if res[0] != OK:
			return false
		var raw: PackedByteArray = (res[1] as PackedByteArray).decompress(MASK * MASK, FileAccess.COMPRESSION_ZSTD)
		if raw.size() != MASK * MASK:
			return false
		if legacy:
			old.append([key2, raw])
			continue
		var c := DirtChunk.new(raw, init_total)
		c.modified = true
		chunks[key3] = c
	if legacy:
		_legacy = _index_legacy(old)
	return true


# ------------------------------------------------------- old (flat) saves

## Old flat chunks, split up by the sphere chunk each cleaned texel lands on:
## Array of [Vector3i key, PackedInt32Array texel indices, PackedByteArray values].
## Only texels that had clearly been cleaned (below any fresh dust) are kept.
static func _index_legacy(old: Array) -> Array:
	TerrainGen.setup()
	var per_key := {}
	for e in old:
		var k2: Vector2i = e[0]
		var raw: PackedByteArray = e[1]
		var ox := k2.x * OLD_CHUNK
		var oz := k2.y * OLD_CHUNK
		for lz in 128:
			var row := lz * 128
			for lx in 128:
				var v: int = raw[row + lx]
				if v >= 118:
					continue
				var d := TerrainGen.map_to_dir(ox + (lx + 0.5) * OLD_TEXEL, oz + (lz + 0.5) * OLD_TEXEL)
				var key := TerrainGen.key_of(d)
				var uv := TerrainGen.chunk_uv(key, d)
				var idx := clampi(int(uv.y * MASK), 0, MASK - 1) * MASK + clampi(int(uv.x * MASK), 0, MASK - 1)
				var bucket: Array = per_key.get(key, [])
				if bucket.is_empty():
					per_key[key] = bucket
				# (plain Arrays here: appending to a packed array held in a container
				# would only change a copy)
				bucket.append(idx)
				bucket.append(v)
	var out := []
	for key in per_key:
		var b: Array = per_key[key]
		var idxs := PackedInt32Array()
		var vals := PackedByteArray()
		idxs.resize(b.size() / 2)
		vals.resize(b.size() / 2)
		for i in idxs.size():
			idxs[i] = b[i * 2]
			vals[i] = b[i * 2 + 1]
		out.append([key, idxs, vals])
	return out


## Whether an old save's cleaning still waits to be applied to the sphere.
func has_legacy() -> bool:
	return not _legacy.is_empty()


func _migrate_into(key: Vector3i, c: DirtChunk) -> void:
	if _legacy.is_empty():
		return
	for i in _legacy.size():
		var e: Array = _legacy[i]
		if e[0] != key:
			continue
		var idx: PackedInt32Array = e[1]
		var val: PackedByteArray = e[2]
		for t in idx.size():
			c.lower(idx[t], val[t])
		c.modified = true
		visual_dirty[key] = true
		_note(key, c)
		_legacy.remove_at(i)
		return


## Applies all of an old save's cleaning (before saving in the new format).
func _migrate_all() -> void:
	while not _legacy.is_empty():
		var key: Vector3i = _legacy[0][0]
		if chunks.has(key):
			_migrate_into(key, chunks[key])
		else:
			get_chunk(key)
