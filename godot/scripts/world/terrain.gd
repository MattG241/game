class_name Terrain
extends Node3D
## Streams terrain chunks around a focus node. Mesh data, collision heights, rock
## placements and initial dust masks are computed on worker threads; the main thread
## only uploads finished results (time-sliced) and refreshes dirty mask textures.

signal chunk_count_changed(n: int)

const LOD0_DIST := 84.0
const COLLISION_DIST := 44.0
const MAX_TASKS := 4
const MAX_FINALIZE_PER_FRAME := 2
const MAX_TEX_UPDATES_PER_FRAME := 6

var dirt: DirtMap
var focus: Node3D
var view_distance := 190.0
var detail_level := 1

var chunks := {}      # Vector2i -> Dictionary {node, mesh, mat, tex, lod, body, rocks}
var _tasks := {}      # Vector2i -> {id, result, lod}
var _scan_timer := 0.0
var _desired := {}    # Vector2i -> lod
var _mat_template: ShaderMaterial
var _rock_mat: Material
var _tints := PackedColorArray()


func _ready() -> void:
	TerrainGen.setup()
	dirt = GameState.dirt
	for r in GameData.regions:
		_tints.append(Color.html(r["tint"]))
	_mat_template = ShaderMaterial.new()
	_mat_template.shader = load("res://shaders/terrain.gdshader")
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	var n := FastNoiseLite.new()
	n.frequency = 0.02
	n.fractal_octaves = 4
	nt.noise = n
	nt.generate_mipmaps = true
	var nn := NoiseTexture2D.new()
	nn.width = 256
	nn.height = 256
	nn.seamless = true
	nn.as_normal_map = true
	nn.bump_strength = 6.0
	var n2 := FastNoiseLite.new()
	n2.frequency = 0.045
	n2.fractal_octaves = 3
	nn.noise = n2
	_mat_template.set_shader_parameter("detail_noise", nt)
	_mat_template.set_shader_parameter("detail_normal", nn)
	_rock_mat = Meshes.rock_material()
	apply_settings()
	Settings.changed.connect(apply_settings)


func apply_settings() -> void:
	view_distance = float(Settings.get_value("view_distance", 190.0))
	detail_level = int(Settings.get_value("detail", 1))
	_mat_template.set_shader_parameter("far_fade", view_distance)
	for k in chunks:
		(chunks[k]["mat"] as ShaderMaterial).set_shader_parameter("far_fade", view_distance)
	_scan_timer = 0.0


func active_chunks() -> int:
	return chunks.size()


## Synchronously builds the chunks around a point (used on spawn so nothing falls through).
func prewarm(pos: Vector3) -> void:
	var c := TerrainGen.chunk_key(pos.x, pos.z)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := c + Vector2i(dx, dz)
			if chunks.has(key):
				continue
			var res := {}
			_build_task(key, 0, not dirt.has_chunk(key), res)
			_finalize(key, 0, res)
	_update_collision(pos)


func _process(delta: float) -> void:
	if focus == null:
		return
	var fp := focus.global_position
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 0.3
		_scan(fp)
		_update_collision(fp)
	_dispatch()
	_collect()
	_refresh_textures()


func _scan(fp: Vector3) -> void:
	_desired.clear()
	var r := int(ceil(view_distance / TerrainGen.CHUNK)) + 1
	var c := TerrainGen.chunk_key(fp.x, fp.z)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var key := c + Vector2i(dx, dz)
			var center := Vector2((key.x + 0.5) * TerrainGen.CHUNK, (key.y + 0.5) * TerrainGen.CHUNK)
			if center.length() > TerrainGen.WORLD_RADIUS + 120.0:
				continue
			var d := center.distance_to(Vector2(fp.x, fp.z))
			if d > view_distance + TerrainGen.CHUNK * 0.75:
				continue
			_desired[key] = 0 if d < LOD0_DIST else 1
	# Unload chunks no longer wanted
	for key in chunks.keys():
		if not _desired.has(key):
			_unload(key)
	chunk_count_changed.emit(chunks.size())


func _dispatch() -> void:
	if _tasks.size() >= MAX_TASKS:
		return
	var fp := focus.global_position
	var best_key := Vector2i.ZERO
	var best_d := INF
	var best_lod := 0
	var found := false
	# Pick the nearest chunk whose desired LOD differs from what is loaded.
	for key in _desired:
		var lod: int = _desired[key]
		if _tasks.has(key):
			continue
		if chunks.has(key) and chunks[key]["lod"] == lod:
			continue
		var center := Vector2((key.x + 0.5) * TerrainGen.CHUNK, (key.y + 0.5) * TerrainGen.CHUNK)
		var d := center.distance_squared_to(Vector2(fp.x, fp.z))
		if d < best_d:
			best_d = d
			best_key = key
			best_lod = lod
			found = true
	if not found:
		return
	var res := {}
	var need_dirt := not dirt.has_chunk(best_key)
	var id := WorkerThreadPool.add_task(_build_task.bind(best_key, best_lod, need_dirt, res), false, "terrain")
	_tasks[best_key] = {"id": id, "res": res, "lod": best_lod}
	if _tasks.size() < MAX_TASKS:
		_dispatch()


func _collect() -> void:
	var done := 0
	for key in _tasks.keys():
		var t: Dictionary = _tasks[key]
		if not WorkerThreadPool.is_task_completed(t["id"]):
			continue
		WorkerThreadPool.wait_for_task_completion(t["id"])
		_tasks.erase(key)
		if _desired.has(key):
			_finalize(key, t["lod"], t["res"])
		done += 1
		if done >= MAX_FINALIZE_PER_FRAME:
			break


func _refresh_textures() -> void:
	if dirt.visual_dirty.is_empty():
		return
	var n := 0
	for key in dirt.visual_dirty.keys():
		dirt.visual_dirty.erase(key)
		if chunks.has(key):
			var c: Dictionary = chunks[key]
			(c["tex"] as ImageTexture).update(dirt.get_image(key))
			n += 1
			if n >= MAX_TEX_UPDATES_PER_FRAME:
				break


func refresh_all_textures() -> void:
	for key in chunks:
		(chunks[key]["tex"] as ImageTexture).update(dirt.get_image(key))
	dirt.visual_dirty.clear()


func _unload(key: Vector2i) -> void:
	var c: Dictionary = chunks[key]
	var body: StaticBody3D = c["body"]
	if body.get_parent() == null:
		body.free()
	(c["node"] as Node).queue_free()
	chunks.erase(key)
	dirt.release(key)


func _update_collision(fp: Vector3) -> void:
	for key in chunks:
		var c: Dictionary = chunks[key]
		var center := Vector2((key.x + 0.5) * TerrainGen.CHUNK, (key.y + 0.5) * TerrainGen.CHUNK)
		var want: bool = center.distance_to(Vector2(fp.x, fp.z)) < COLLISION_DIST and c["lod"] == 0
		var body: StaticBody3D = c["body"]
		if want and body.get_parent() == null:
			c["node"].add_child(body)
		elif not want and body.get_parent() != null:
			c["node"].remove_child(body)


## Extra collision focus (e.g. a vehicle someone is driving).
func ensure_collision_near(pos: Vector3) -> void:
	_update_collision(pos)


# ------------------------------------------------------------- worker thread

func _build_task(key: Vector2i, lod: int, need_dirt: bool, res: Dictionary) -> void:
	var quads := TerrainGen.QUADS if lod == 0 else TerrainGen.QUADS_FAR
	var step := TerrainGen.CHUNK / quads
	var ox := key.x * TerrainGen.CHUNK
	var oz := key.y * TerrainGen.CHUNK
	var n := quads + 1
	var g := n + 2   # with 1-sample border for normals
	var hs := PackedFloat32Array()
	hs.resize(g * g)
	var interior := PackedFloat32Array()
	interior.resize(g * g)
	for j in g:
		for i in g:
			var s := TerrainGen.sample(ox + (i - 1) * step, oz + (j - 1) * step)
			hs[j * g + i] = s.x
			interior[j * g + i] = s.y
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(n * n)
	norms.resize(n * n)
	uvs.resize(n * n)
	cols.resize(n * n)
	for j in n:
		for i in n:
			var gi := (j + 1) * g + (i + 1)
			var h := hs[gi]
			var nx := hs[gi - 1] - hs[gi + 1]
			var nz := hs[gi - g] - hs[gi + g]
			var vi := j * n + i
			verts[vi] = Vector3(i * step, h, j * step)
			norms[vi] = Vector3(nx, 2.0 * step, nz).normalized()
			uvs[vi] = Vector2(float(i) / quads, float(j) / quads)
			var wx := ox + i * step
			var wz := oz + j * step
			cols[vi] = _tint(wx, wz, interior[gi])
	for j in quads:
		for i in quads:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	# Skirts hide cracks between neighbouring LODs.
	var skirt := 2.5 if lod == 0 else 5.0
	var edges := Array()
	for e in 4:
		edges.append(Array())
	for i in n:
		edges[0].append(i)                  # north row (j = 0)
		edges[1].append((n - 1) * n + i)    # south row
		edges[2].append(i * n)              # west column
		edges[3].append(i * n + n - 1)      # east column
	for e in 4:
		var line: Array = edges[e]
		var base := verts.size()
		for vi in line:
			verts.append(verts[vi] - Vector3(0, skirt, 0))
			norms.append(norms[vi])
			uvs.append(uvs[vi])
			cols.append(cols[vi])
		for k in line.size() - 1:
			var a: int = line[k]
			var b: int = line[k + 1]
			var a2 := base + k
			var b2 := base + k + 1
			# Double-sided so winding does not matter.
			idx.append_array([a, a2, b, b, a2, b2, a, b, a2, b, b2, a2])
	var arrays := Array()
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	res["arrays"] = arrays
	if lod == 0:
		var coll := PackedFloat32Array()
		coll.resize(n * n)
		for j in n:
			for i in n:
				coll[j * n + i] = hs[(j + 1) * g + (i + 1)]
		res["collision"] = coll
	if need_dirt:
		res["dirt"] = TerrainGen.initial_dirt(key)
	res["rocks"] = _rock_placements(key, lod)


func _tint(x: float, z: float, interior: float) -> Color:
	var w := TerrainGen.region_weights(x, z)
	var tints := _tints
	var base: Color = tints[0]
	var total := w.x + w.y + w.z + w.w
	var c := base * maxf(1.0 - total, 0.0)
	c += tints[1] * w.x + tints[2] * w.y + tints[3] * w.z + tints[4] * w.w
	if total > 1.0:
		c = (c - base * maxf(1.0 - total, 0.0)) / total
	c.a = interior
	return c


## Large boulders per chunk by region. A match instead of a constant array: constant
## arrays are shared between threads and their reference counting raced on 8-core phones.
static func _rocks_for_region(region: int) -> int:
	match region:
		TerrainGen.Region.CRATERS:
			return 7
		TerrainGen.Region.HIGHLANDS:
			return 14
		TerrainGen.Region.RESEARCH:
			return 6
		TerrainGen.Region.INDUSTRIAL:
			return 3
	return 4


func _rock_placements(key: Vector2i, lod: int) -> Array:
	var ox := key.x * TerrainGen.CHUNK
	var oz := key.y * TerrainGen.CHUNK
	var cx := ox + TerrainGen.CHUNK * 0.5
	var cz := oz + TerrainGen.CHUNK * 0.5
	var r := sqrt(cx * cx + cz * cz)
	if r < 30.0:
		return Array()
	var region := TerrainGen.region_at(cx, cz)
	var big_count := _rocks_for_region(region)
	var count: int = big_count
	if lod == 0:
		count += 26 if detail_level >= 1 else 10
	var out := Array()
	for i in count:
		var hx := TerrainGen.hashf(key.x * 31 + i, key.y * 17 - i, 991)
		var hz := TerrainGen.hashf(key.x * 13 - i, key.y * 29 + i, 553)
		var hsz := TerrainGen.hashf(key.x + i * 7, key.y - i * 3, 211)
		var x := ox + hx * TerrainGen.CHUNK
		var z := oz + hz * TerrainGen.CHUNK
		if x * x + z * z < 60.0 * 60.0:
			continue
		var big: bool = i < big_count
		var s := (0.5 + hsz * hsz * 2.6) if big else (0.08 + hsz * 0.22)
		var s3 := TerrainGen.sample(x, z)
		if s3.z > 0.4 and big:
			s *= 1.6
		var y := s3.x - s * 0.25
		var rot := Basis(Vector3.UP, hx * TAU) * Basis(Vector3.RIGHT, (hz - 0.5) * 0.6)
		var sc := Vector3(s * (0.8 + hz * 0.5), s * (0.6 + hx * 0.5), s * (0.8 + hsz * 0.4))
		out.append([Transform3D(rot.scaled(sc), Vector3(x - ox, y, z - oz)), s])
	return out


# ----------------------------------------------------------------- finalize

func _finalize(key: Vector2i, lod: int, res: Dictionary) -> void:
	if not res.has("arrays"):
		return
	if res.has("dirt"):
		dirt.put_initial(key, res["dirt"])
	var old: Dictionary = chunks.get(key, {})
	var node := Node3D.new()
	node.name = "Chunk_%d_%d" % [key.x, key.y]
	node.position = Vector3(key.x * TerrainGen.CHUNK, 0, key.y * TerrainGen.CHUNK)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res["arrays"])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat: ShaderMaterial = _mat_template.duplicate()
	var tex: ImageTexture
	if old.has("tex"):
		tex = old["tex"]
	else:
		tex = ImageTexture.create_from_image(dirt.get_image(key))
	mat.set_shader_parameter("dirt_mask", tex)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if lod > 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.add_child(mi)
	# Collision (added to the tree only when the player is near)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	if res.has("collision"):
		var shape := HeightMapShape3D.new()
		var n := TerrainGen.QUADS + 1
		shape.map_width = n
		shape.map_depth = n
		shape.map_data = res["collision"]
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(TerrainGen.CHUNK * 0.5, 0, TerrainGen.CHUNK * 0.5)
		body.add_child(cs)
	# Rocks
	var rocks: Array = res["rocks"]
	if not rocks.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = Meshes.rock_mesh(absi(key.x * 7 + key.y * 3))
		mm.instance_count = rocks.size()
		for i in rocks.size():
			mm.set_instance_transform(i, rocks[i][0])
			if lod == 0 and rocks[i][1] > 1.1:
				var rcs := CollisionShape3D.new()
				var sph := SphereShape3D.new()
				sph.radius = rocks[i][1] * 0.75
				rcs.shape = sph
				rcs.position = (rocks[i][0] as Transform3D).origin
				body.add_child(rcs)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _rock_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mmi)
	add_child(node)
	if not old.is_empty():
		(old["node"] as Node).queue_free()
		var ob: StaticBody3D = old["body"]
		if ob.get_parent() == null:
			ob.free()
	chunks[key] = {"node": node, "mat": mat, "tex": tex, "lod": lod, "body": body}
	if focus:
		var center := Vector2((key.x + 0.5) * TerrainGen.CHUNK, (key.y + 0.5) * TerrainGen.CHUNK)
		if center.distance_to(Vector2(focus.global_position.x, focus.global_position.z)) < COLLISION_DIST and lod == 0:
			node.add_child(body)


func _exit_tree() -> void:
	for key in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[key]["id"])
	_tasks.clear()
	for key in chunks:
		var b: StaticBody3D = chunks[key]["body"]
		if b.get_parent() == null:
			b.free()
