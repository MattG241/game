class_name DirtMap
extends RefCounted
## Persistent, chunked dust coverage. Each chunk is a 128x128 byte mask (0.25 m texels).
## Cleaning tools "stamp" brush shapes into the mask; the removed amount becomes dust.
## Only touched chunks are kept in memory permanently and saved (ZSTD compressed).

const MAGIC := "LCDM"
const FORMAT_VERSION := 2
const MASK := TerrainGen.MASK
const TEXEL := TerrainGen.TEXEL
const CHUNK := TerrainGen.CHUNK

enum Shape { ROUND, RECT }

var chunks := {}          # Vector2i -> DirtChunk
var visual_dirty := {}    # Vector2i -> true (needs GPU texture refresh)
var clean := {}           # Vector2i -> true: chunk has no dust left (persisted in the save)
# Ground under buildings, pads and machines (no dust there): PackedFloat32Array
# [cx, cz, half_x, half_z, yaw] for boxes or [cx, cz, radius] for circles.
var covers: Array[PackedFloat32Array] = []
var _playable: Array[Vector2i] = []


class DirtChunk:
	extends RefCounted
	var data: PackedByteArray
	var total: int = 0
	var initial_total: int = 0
	var modified := false
	var compressed := PackedByteArray()
	var compressed_valid := false
	var dirty := 0                  # counted texels still above CLEAN_LEVEL
	var play := PackedByteArray()   # per-texel 1 = counts for 100%; empty = all count
	var sanitized := true           # false for chunks from saves before rocks/cliffs had no dust

	func _init(key: Vector2i, d: PackedByteArray, init_total := -1) -> void:
		data = d
		total = _sum(d)
		initial_total = init_total if init_total >= 0 else total
		# Texels past the wrap line never need cleaning.
		var ox := key.x * CHUNK
		var oz := key.y * CHUNK
		var far := Vector2(absf(ox + CHUNK * 0.5) + CHUNK * 0.5, absf(oz + CHUNK * 0.5) + CHUNK * 0.5)
		if far.length() > TerrainGen.WRAP_RADIUS:
			play.resize(MASK * MASK)
			for lz in MASK:
				var wz := oz + (lz + 0.5) * TEXEL
				for lx in MASK:
					play[lz * MASK + lx] = 1 if TerrainGen.in_play(ox + (lx + 0.5) * TEXEL, wz) else 0
		recount()

	func recount() -> void:
		var n := 0
		var all := play.is_empty()
		for i in data.size():
			if data[i] > TerrainGen.CLEAN_LEVEL and (all or play[i] == 1):
				n += 1
		dirty = n

	## Removes all dust from one texel (covered or unreachable ground).
	func zero(idx: int) -> void:
		var v: int = data[idx]
		if v == 0:
			return
		if v > TerrainGen.CLEAN_LEVEL and (play.is_empty() or play[idx] == 1):
			dirty -= 1
		total -= v
		initial_total -= v
		data[idx] = 0
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

	func apply_round(lx0: int, lx1: int, lz0: int, lz1: int, ox: float, oz: float,
			cx: float, cz: float, r: float, amount: float, budget: int) -> int:
		var d := data
		var removed := 0
		var cl := TerrainGen.CLEAN_LEVEL
		var pl := play
		var all := pl.is_empty()
		var inv_r := 1.0 / r
		var done := false
		for lz in range(lz0, lz1 + 1):
			var wz := oz + (lz + 0.5) * TEXEL - cz
			var row := lz * MASK
			for lx in range(lx0, lx1 + 1):
				var idx := row + lx
				var cur: int = d[idx]
				if cur == 0:
					continue
				var wx := ox + (lx + 0.5) * TEXEL - cx
				var dist := sqrt(wx * wx + wz * wz) * inv_r
				if dist >= 1.0:
					continue
				var w := minf(1.0, (1.0 - dist) * 3.0)
				var rem := mini(cur, int(ceil(amount * w)))
				d[idx] = cur - rem
				removed += rem
				if cur > cl and cur - rem <= cl and (all or pl[idx] == 1):
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

	func apply_rect(lx0: int, lx1: int, lz0: int, lz1: int, ox: float, oz: float,
			cx: float, cz: float, hw: float, hl: float, cs: float, sn: float, amount: float, budget: int) -> int:
		# Local frame: u across (right vector), v along (forward vector).
		var d := data
		var removed := 0
		var cl := TerrainGen.CLEAN_LEVEL
		var pl := play
		var all := pl.is_empty()
		var soft_w := 1.0 / maxf(hw * 0.25, 0.12)
		var soft_l := 1.0 / maxf(hl * 0.25, 0.12)
		var done := false
		for lz in range(lz0, lz1 + 1):
			var wz := oz + (lz + 0.5) * TEXEL - cz
			var row := lz * MASK
			for lx in range(lx0, lx1 + 1):
				var idx := row + lx
				var cur: int = d[idx]
				if cur == 0:
					continue
				var wx := ox + (lx + 0.5) * TEXEL - cx
				var u := absf(wx * cs - wz * sn)
				var v := absf(wx * sn + wz * cs)
				if u >= hw or v >= hl:
					continue
				var w := minf(minf(1.0, (hw - u) * soft_w), minf(1.0, (hl - v) * soft_l))
				var rem := mini(cur, int(ceil(amount * w)))
				d[idx] = cur - rem
				removed += rem
				if cur > cl and cur - rem <= cl and (all or pl[idx] == 1):
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


## New game: forget everything.
func reset() -> void:
	clear()
	clean.clear()


func _make(key: Vector2i, data: PackedByteArray, init_total := -1) -> DirtChunk:
	var c := DirtChunk.new(key, data, init_total)
	for cv in covers:
		_apply_cover(key, c, cv)
	_note(key, c)
	return c


func _note(key: Vector2i, c: DirtChunk) -> void:
	if c.dirty <= 0 and c.sanitized:
		clean[key] = true


# ------------------------------------------------------------------ covers

## Ground under a building or pad: rectangle (half sizes, rotated by yaw).
func add_cover_box(cx: float, cz: float, hx: float, hz: float, yaw: float) -> void:
	_add_cover(PackedFloat32Array([cx, cz, hx, hz, yaw]))


func add_cover_circle(cx: float, cz: float, r: float) -> void:
	_add_cover(PackedFloat32Array([cx, cz, r]))


func _add_cover(cv: PackedFloat32Array) -> void:
	covers.append(cv)
	var ext: float = cv[2] if cv.size() == 3 else Vector2(cv[2], cv[3]).length()
	var k0 := TerrainGen.chunk_key(cv[0] - ext, cv[1] - ext)
	var k1 := TerrainGen.chunk_key(cv[0] + ext, cv[1] + ext)
	for kz in range(k0.y, k1.y + 1):
		for kx in range(k0.x, k1.x + 1):
			var key := Vector2i(kx, kz)
			var c: DirtChunk = chunks.get(key)
			if c != null and _apply_cover(key, c, cv):
				visual_dirty[key] = true
				_note(key, c)


func _apply_cover(key: Vector2i, c: DirtChunk, cv: PackedFloat32Array) -> bool:
	var ox := key.x * CHUNK
	var oz := key.y * CHUNK
	var circle := cv.size() == 3
	var ext: float = cv[2] if circle else Vector2(cv[2], cv[3]).length()
	var lx0 := maxi(floori((cv[0] - ext - ox) / TEXEL), 0)
	var lx1 := mini(floori((cv[0] + ext - ox) / TEXEL), MASK - 1)
	var lz0 := maxi(floori((cv[1] - ext - oz) / TEXEL), 0)
	var lz1 := mini(floori((cv[1] + ext - oz) / TEXEL), MASK - 1)
	if lx0 > lx1 or lz0 > lz1:
		return false
	var cs := 1.0 if circle else cos(cv[4])
	var sn := 0.0 if circle else sin(cv[4])
	var changed := false
	for lz in range(lz0, lz1 + 1):
		var dz := oz + (lz + 0.5) * TEXEL - cv[1]
		for lx in range(lx0, lx1 + 1):
			var idx := lz * MASK + lx
			if c.data[idx] == 0:
				continue
			var dx := ox + (lx + 0.5) * TEXEL - cv[0]
			var inside: bool
			if circle:
				inside = dx * dx + dz * dz < cv[2] * cv[2]
			else:
				# Into the box's frame (Godot yaw about +Y).
				var u := dx * cs - dz * sn
				var v := dx * sn + dz * cs
				inside = absf(u) < cv[2] and absf(v) < cv[3]
			if inside:
				c.zero(idx)
				changed = true
	return changed


## Chunks loaded from saves made before rocks and cliffs were dust-free.
func needs_sanitize(key: Vector2i) -> bool:
	var c: DirtChunk = chunks.get(key)
	return c != null and not c.sanitized


## Applies an unreachable-texel mask from TerrainGen.unreachable_mask (once).
func sanitize(key: Vector2i, blocked: PackedByteArray) -> void:
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

func playable() -> Array[Vector2i]:
	if _playable.is_empty():
		_playable = TerrainGen.playable_chunks()
	return _playable


## True when every chunk of the Moon (inside the wrap line) has no dust left.
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


## The nearest spot that still has dust (for the dust finder). Vector3.INF if none.
func nearest_dust(from: Vector3) -> Vector3:
	var best_key := Vector2i.ZERO
	var best_d := INF
	for key in playable():
		if clean.has(key):
			continue
		var cc := Vector2((key.x + 0.5) * CHUNK, (key.y + 0.5) * CHUNK)
		var d := cc.distance_squared_to(Vector2(from.x, from.z))
		if d < best_d:
			best_d = d
			best_key = key
	if best_d == INF:
		return Vector3.INF
	var ox := best_key.x * CHUNK
	var oz := best_key.y * CHUNK
	var centre := Vector3(ox + CHUNK * 0.5, 0, oz + CHUNK * 0.5)
	var ch: DirtChunk = chunks.get(best_key)
	if ch == null or not ch.sanitized:
		return centre
	# Nearest remaining dusty texel in that chunk.
	var best := centre
	var bd := INF
	var all := ch.play.is_empty()
	var data := ch.data
	for lz in MASK:
		var wz := oz + (lz + 0.5) * TEXEL
		var row := lz * MASK
		for lx in MASK:
			var idx := row + lx
			if data[idx] > TerrainGen.CLEAN_LEVEL and (all or ch.play[idx] == 1):
				var wx := ox + (lx + 0.5) * TEXEL
				var d := (wx - from.x) * (wx - from.x) + (wz - from.z) * (wz - from.z)
				if d < bd:
					bd = d
					best = Vector3(wx, 0, wz)
	if bd == INF:
		# Nothing left after all (counts were stale): record it as clean.
		ch.recount()
		_note(best_key, ch)
	return best


func has_chunk(key: Vector2i) -> bool:
	return chunks.has(key)


func get_chunk(key: Vector2i) -> DirtChunk:
	var c: DirtChunk = chunks.get(key)
	if c == null:
		TerrainGen.setup()
		var init := TerrainGen.initial_dirt(key)
		c = _make(key, init)
		chunks[key] = c
	return c


## Register initial data generated on a worker thread (ignored if already present).
func put_initial(key: Vector2i, data: PackedByteArray) -> void:
	if not chunks.has(key):
		chunks[key] = _make(key, data)


## Free memory for chunks the player never touched.
func release(key: Vector2i) -> void:
	var c: DirtChunk = chunks.get(key)
	if c != null and not c.modified:
		chunks.erase(key)


func get_image(key: Vector2i) -> Image:
	return Image.create_from_data(MASK, MASK, false, Image.FORMAT_L8, get_chunk(key).data)


## Dust coverage 0..1 at a world position.
func sample(x: float, z: float) -> float:
	var key := TerrainGen.chunk_key(x, z)
	var c := get_chunk(key)
	var lx := clampi(int((x - key.x * CHUNK) / TEXEL), 0, MASK - 1)
	var lz := clampi(int((z - key.y * CHUNK) / TEXEL), 0, MASK - 1)
	return c.data[lz * MASK + lx] / 255.0


## Stamp a brush. Returns removed "full-coverage" area in m2 (multiply by dust density for dust).
## budget_m2 caps how much may be removed (tank space).
func stamp(shape: int, cx: float, cz: float, a: float, b: float, yaw: float, strength_dt: float, budget_m2: float) -> float:
	if budget_m2 <= 0.0 or strength_dt <= 0.0:
		return 0.0
	var ext: float
	if shape == Shape.ROUND:
		ext = a
	else:
		ext = sqrt(a * a + b * b)
	var amount := strength_dt * 255.0
	var budget := int(ceil(budget_m2 / (TEXEL * TEXEL) * 255.0))
	var cs := cos(yaw)
	var sn := sin(yaw)
	var gx0 := floori((cx - ext) / TEXEL)
	var gx1 := floori((cx + ext) / TEXEL)
	var gz0 := floori((cz - ext) / TEXEL)
	var gz1 := floori((cz + ext) / TEXEL)
	var kx0 := floori(float(gx0) / MASK)
	var kx1 := floori(float(gx1) / MASK)
	var kz0 := floori(float(gz0) / MASK)
	var kz1 := floori(float(gz1) / MASK)
	var removed := 0
	for kz in range(kz0, kz1 + 1):
		for kx in range(kx0, kx1 + 1):
			if removed >= budget:
				break
			var key := Vector2i(kx, kz)
			var c := get_chunk(key)
			var lx0 := maxi(gx0 - kx * MASK, 0)
			var lx1 := mini(gx1 - kx * MASK, MASK - 1)
			var lz0 := maxi(gz0 - kz * MASK, 0)
			var lz1 := mini(gz1 - kz * MASK, MASK - 1)
			var ox := kx * CHUNK
			var oz := kz * CHUNK
			var r: int
			if shape == Shape.ROUND:
				r = c.apply_round(lx0, lx1, lz0, lz1, ox, oz, cx, cz, a, amount, budget - removed)
			else:
				r = c.apply_rect(lx0, lx1, lz0, lz1, ox, oz, cx, cz, a, b, cs, sn, amount, budget - removed)
			if r > 0:
				removed += r
				visual_dirty[key] = true
				if c.dirty <= 0:
					_note(key, c)
	return float(removed) / 255.0 * TEXEL * TEXEL


## Fraction (0..1) of a circular area that is clean (coverage below 20%).
func area_clean_fraction(cx: float, cz: float, radius: float, step := 1.0) -> float:
	var total := 0
	var clean := 0
	var x := cx - radius
	while x <= cx + radius:
		var z := cz - radius
		while z <= cz + radius:
			var dx := x - cx
			var dz := z - cz
			if dx * dx + dz * dz <= radius * radius:
				total += 1
				if sample(x, z) < 0.2:
					clean += 1
			z += step
		x += step
	return float(clean) / float(maxi(total, 1))


func chunk_fraction(key: Vector2i) -> float:
	var c: DirtChunk = chunks.get(key)
	return c.fraction_clean() if c != null else 0.0


# ---------------------------------------------------------------- persistence

## Cheap main-thread snapshot (packed arrays are copy-on-write, so later edits don't race).
func snapshot() -> Array:
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
		var key: Vector2i = e[0]
		var comp: PackedByteArray = e[1]
		buf.put_32(key.x)
		buf.put_32(key.y)
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
	# Version 1 saves predate dust-free rocks/cliffs: those chunks get cleaned up
	# the first time they stream in near the player.
	var sanitized_saves := version >= 2
	var count := buf.get_u32()
	for i in count:
		if buf.get_position() + 16 > bytes.size():
			return false
		var kx := buf.get_32()
		var kz := buf.get_32()
		var init_total := buf.get_u32()
		var size := buf.get_u32()
		var res := buf.get_data(size)
		if res[0] != OK:
			return false
		var raw: PackedByteArray = (res[1] as PackedByteArray).decompress(MASK * MASK, FileAccess.COMPRESSION_ZSTD)
		if raw.size() != MASK * MASK:
			return false
		var key := Vector2i(kx, kz)
		var c := DirtChunk.new(key, raw, init_total)
		c.modified = true
		c.sanitized = sanitized_saves
		chunks[key] = c
	return true
