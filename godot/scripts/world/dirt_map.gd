class_name DirtMap
extends RefCounted
## Persistent, chunked dust coverage. Each chunk is a 128x128 byte mask (0.25 m texels).
## Cleaning tools "stamp" brush shapes into the mask; the removed amount becomes dust.
## Only touched chunks are kept in memory permanently and saved (ZSTD compressed).

const MAGIC := "LCDM"
const FORMAT_VERSION := 1
const MASK := TerrainGen.MASK
const TEXEL := TerrainGen.TEXEL
const CHUNK := TerrainGen.CHUNK

enum Shape { ROUND, RECT }

var chunks := {}          # Vector2i -> DirtChunk
var visual_dirty := {}    # Vector2i -> true (needs GPU texture refresh)


class DirtChunk:
	extends RefCounted
	var data: PackedByteArray
	var total: int = 0
	var initial_total: int = 0
	var modified := false
	var compressed := PackedByteArray()
	var compressed_valid := false

	func _init(d: PackedByteArray, init_total := -1) -> void:
		data = d
		total = _sum(d)
		initial_total = init_total if init_total >= 0 else total

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


func clear() -> void:
	chunks.clear()
	visual_dirty.clear()


func has_chunk(key: Vector2i) -> bool:
	return chunks.has(key)


func get_chunk(key: Vector2i) -> DirtChunk:
	var c: DirtChunk = chunks.get(key)
	if c == null:
		TerrainGen.setup()
		var init := TerrainGen.initial_dirt(key)
		c = DirtChunk.new(init)
		chunks[key] = c
	return c


## Register initial data generated on a worker thread (ignored if already present).
func put_initial(key: Vector2i, data: PackedByteArray) -> void:
	if not chunks.has(key):
		chunks[key] = DirtChunk.new(data)


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
		var c := DirtChunk.new(raw, init_total)
		c.modified = true
		chunks[Vector2i(kx, kz)] = c
	return true
