class_name MeshKit
extends RefCounted
## Procedural mesh & material helpers used to build the pub without external models.

static var _mat_cache: Dictionary = {}
static var _shader_cache: Dictionary = {}


static func shader(path: String) -> Shader:
	if not _shader_cache.has(path):
		_shader_cache[path] = load(path)
	return _shader_cache[path]


static func shader_mat(path: String, params: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(path)
	for k in params.keys():
		m.set_shader_parameter(k, params[k])
	return m


## Cached materials keyed by name so identical surfaces share one material (better batching).
static func mat(key: String) -> Material:
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m: Material
	match key:
		"oak":
			m = shader_mat("res://assets/shaders/wood.gdshader", {"grain_dir": Vector3(1, 0, 0), "grain_scale": 5.0, "world_space": true})
		"oak_z":
			m = shader_mat("res://assets/shaders/wood.gdshader", {"grain_dir": Vector3(0, 0, 1), "grain_scale": 5.0, "world_space": true})
		"oak_y":
			m = shader_mat("res://assets/shaders/wood.gdshader", {"grain_dir": Vector3(0, 1, 0), "grain_scale": 5.0, "world_space": true})
		"bar_top":
			m = shader_mat("res://assets/shaders/wood.gdshader", {"grain_dir": Vector3(1, 0, 0), "grain_scale": 4.0, "world_space": true,
				"dark_color": Color(0.12, 0.05, 0.025), "light_color": Color(0.3, 0.14, 0.06), "roughness_base": 0.18})
		"floor":
			m = shader_mat("res://assets/shaders/wood.gdshader", {"grain_dir": Vector3(0, 0, 1), "grain_scale": 3.0, "world_space": true,
				"plank_width": 0.18, "dark_color": Color(0.11, 0.07, 0.045), "light_color": Color(0.27, 0.17, 0.1), "roughness_base": 0.55, "wear": 0.4})
		"pale_wood":
			m = shader_mat("res://assets/shaders/wood.gdshader", {"grain_dir": Vector3(1, 0, 0), "world_space": true,
				"dark_color": Color(0.36, 0.25, 0.14), "light_color": Color(0.58, 0.43, 0.26)})
		"plaster_old":
			m = shader_mat("res://assets/shaders/plaster.gdshader", {"base_color": Color(0.6, 0.5, 0.33), "stain": 0.55})
		"plaster_new":
			m = shader_mat("res://assets/shaders/plaster.gdshader", {"base_color": Color(0.82, 0.76, 0.6), "stain": 0.08})
		"tiles_old_z":
			m = shader_mat("res://assets/shaders/tiles.gdshader", {"tile_color": Color(0.24, 0.2, 0.14), "axis": 0})
		"tiles_old_x":
			m = shader_mat("res://assets/shaders/tiles.gdshader", {"tile_color": Color(0.24, 0.2, 0.14), "axis": 1})
		"tiles_green_z":
			m = shader_mat("res://assets/shaders/tiles.gdshader", {"tile_color": Color(0.04, 0.24, 0.14), "axis": 0, "glaze": 0.06})
		"tiles_green_x":
			m = shader_mat("res://assets/shaders/tiles.gdshader", {"tile_color": Color(0.04, 0.24, 0.14), "axis": 1, "glaze": 0.06})
		"floor_tiles":
			m = shader_mat("res://assets/shaders/tiles.gdshader", {"tile_color": Color(0.5, 0.15, 0.1), "axis": 2, "tile_size": Vector2(0.2, 0.2), "glaze": 0.5})
		"stone":
			m = shader_mat("res://assets/shaders/stone.gdshader", {"axis": 0, "scale": 4.0})
		"stone_x":
			m = shader_mat("res://assets/shaders/stone.gdshader", {"axis": 1, "scale": 4.0})
		"stone_floor":
			m = shader_mat("res://assets/shaders/stone.gdshader", {"axis": 2, "scale": 3.0})
		"cobbles":
			m = shader_mat("res://assets/shaders/stone.gdshader", {"axis": 2, "scale": 5.5, "wetness": 0.8,
				"stone_a": Color(0.3, 0.3, 0.31), "stone_b": Color(0.2, 0.2, 0.22)})
		"brick":
			m = shader_mat("res://assets/shaders/tiles.gdshader", {"tile_color": Color(0.42, 0.18, 0.12), "axis": 0, "tile_size": Vector2(0.23, 0.075), "glaze": 0.85, "grout_color": Color(0.5, 0.48, 0.44)})
		"render_wall":
			m = shader_mat("res://assets/shaders/plaster.gdshader", {"base_color": Color(0.16, 0.3, 0.24), "stain": 0.3})
		"render_cream":
			m = shader_mat("res://assets/shaders/plaster.gdshader", {"base_color": Color(0.78, 0.72, 0.58), "stain": 0.35})
		"render_red":
			m = shader_mat("res://assets/shaders/plaster.gdshader", {"base_color": Color(0.5, 0.14, 0.1), "stain": 0.3})
		"render_blue":
			m = shader_mat("res://assets/shaders/plaster.gdshader", {"base_color": Color(0.16, 0.24, 0.42), "stain": 0.3})
		"render_yellow":
			m = shader_mat("res://assets/shaders/plaster.gdshader", {"base_color": Color(0.78, 0.6, 0.22), "stain": 0.3})
		_:
			m = _std(key)
	_mat_cache[key] = m
	return m


static func _std(key: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	match key:
		"brass":
			m.albedo_color = Color(0.85, 0.62, 0.28)
			m.metallic = 1.0
			m.roughness = 0.22
		"brass_dull":
			m.albedo_color = Color(0.45, 0.33, 0.16)
			m.metallic = 0.85
			m.roughness = 0.55
		"chrome":
			m.albedo_color = Color(0.8, 0.8, 0.82)
			m.metallic = 1.0
			m.roughness = 0.15
		"iron":
			m.albedo_color = Color(0.08, 0.08, 0.08)
			m.metallic = 0.7
			m.roughness = 0.6
		"black_paint":
			m.albedo_color = Color(0.03, 0.03, 0.035)
			m.roughness = 0.35
		"green_paint":
			m.albedo_color = Color(0.03, 0.18, 0.1)
			m.roughness = 0.3
		"cream":
			m.albedo_color = Color(0.9, 0.84, 0.68)
			m.roughness = 0.7
		"leather_red":
			m.albedo_color = Color(0.32, 0.06, 0.05)
			m.roughness = 0.45
		"leather_green":
			m.albedo_color = Color(0.06, 0.18, 0.1)
			m.roughness = 0.45
		"fabric_tweed":
			m.albedo_color = Color(0.3, 0.26, 0.2)
			m.roughness = 0.95
		"mirror":
			m.albedo_color = Color(0.5, 0.48, 0.44)
			m.metallic = 1.0
			m.roughness = 0.05
		"window_night":
			m.albedo_color = Color(0.04, 0.06, 0.09)
			m.metallic = 0.3
			m.roughness = 0.05
			m.emission_enabled = true
			m.emission = Color(0.05, 0.08, 0.12)
		"window_warm":
			m.albedo_color = Color(0.9, 0.62, 0.3)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.62, 0.28)
			m.emission_energy_multiplier = 1.2
		"bulb":
			m.albedo_color = Color(1, 0.8, 0.5)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.72, 0.38)
			m.emission_energy_multiplier = 3.0
		"bulb_off":
			m.albedo_color = Color(0.3, 0.28, 0.24)
			m.roughness = 0.2
		"lamp_shade":
			m.albedo_color = Color(0.9, 0.7, 0.4)
			m.emission_enabled = true
			m.emission = Color(0.6, 0.35, 0.12)
			m.emission_energy_multiplier = 0.6
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"fire":
			m.albedo_color = Color(1.0, 0.5, 0.1)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.45, 0.08)
			m.emission_energy_multiplier = 4.0
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.vertex_color_use_as_albedo = true
			m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		"ember":
			m.albedo_color = Color(0.3, 0.06, 0.02)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.25, 0.05)
			m.emission_energy_multiplier = 1.5
		"turf":
			m.albedo_color = Color(0.13, 0.08, 0.05)
			m.roughness = 1.0
		"ash":
			m.albedo_color = Color(0.2, 0.19, 0.18)
			m.roughness = 1.0
		"rain":
			m.albedo_color = Color(0.7, 0.75, 0.85, 0.35)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		"foam":
			m.albedo_color = Color(0.93, 0.86, 0.72)
			m.roughness = 0.6
		"spill":
			m.albedo_color = Color(0.06, 0.03, 0.02, 0.85)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.02
			m.metallic = 0.2
		"chalk":
			m.albedo_color = Color(0.08, 0.1, 0.09)
			m.roughness = 0.95
		"paper":
			m.albedo_color = Color(0.86, 0.8, 0.66)
			m.roughness = 0.9
		"photo_frame":
			m.albedo_color = Color(0.1, 0.06, 0.03)
			m.roughness = 0.4
		"skin_a":
			m.albedo_color = Color(0.93, 0.76, 0.64)
			m.roughness = 0.6
		"cardboard":
			m.albedo_color = Color(0.55, 0.42, 0.26)
			m.roughness = 0.9
		"steel_keg":
			m.albedo_color = Color(0.7, 0.72, 0.74)
			m.metallic = 0.9
			m.roughness = 0.3
		"porcelain":
			m.albedo_color = Color(0.92, 0.92, 0.9)
			m.roughness = 0.15
		"shadow":
			m.albedo_color = Color(0, 0, 0, 0.35)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_:
			m.albedo_color = Color(1, 0, 1)
	return m


static func color_mat(c: Color, rough := 0.6, metal := 0.0, emission := 0.0) -> StandardMaterial3D:
	var key := "c_%s_%.2f_%.2f_%.2f" % [c.to_html(), rough, metal, emission]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if c.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	_mat_cache[key] = m
	return m


# ------------------------------------------------------------------ primitives
static func box(parent: Node, size: Vector3, pos: Vector3, material: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func cyl(parent: Node, r_top: float, r_bot: float, h: float, pos: Vector3, material: Material, segs := 16, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func sphere(parent: Node, r: float, pos: Vector3, material: Material, scale := Vector3.ONE, segs := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = segs
	sm.rings = maxi(4, segs / 2)
	mi.mesh = sm
	mi.material_override = material
	mi.position = pos
	mi.scale = scale
	parent.add_child(mi)
	return mi


static func capsule(parent: Node, r: float, h: float, pos: Vector3, material: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	cm.radial_segments = 12
	cm.rings = 4
	mi.mesh = cm
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func torus(parent: Node, r_in: float, r_out: float, pos: Vector3, material: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r_in
	tm.outer_radius = r_out
	tm.rings = 24
	tm.ring_segments = 8
	mi.mesh = tm
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func quad(parent: Node, size: Vector2, pos: Vector3, material: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func label(parent: Node, text: String, pos: Vector3, size := 48, color := Color(0.95, 0.9, 0.75), rot := Vector3.ZERO, font: Font = null) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0015
	l.modulate = color
	l.outline_size = 0
	l.position = pos
	l.rotation = rot
	l.double_sided = false
	if font:
		l.font = font
	parent.add_child(l)
	return l


## Static collision box; colliders are on layer 1 and used to bake the navigation mesh.
static func solid(parent: Node, size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> StaticBody3D:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.position = pos
	sb.rotation = rot
	parent.add_child(sb)
	return sb


static func solid_box(parent: Node, size: Vector3, pos: Vector3, material: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := box(parent, size, pos, material, rot)
	solid(parent, size, pos, rot)
	return mi


## Surface of revolution from a profile of (radius, height) points.
static func lathe(profile: PackedVector2Array, segs := 24, cap_bottom := true, inward := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h_max := profile[profile.size() - 1].y
	for i in profile.size() - 1:
		var a := profile[i]
		var b := profile[i + 1]
		var slope := Vector2(b.y - a.y, -(b.x - a.x)).normalized()  # outward normal in (r, y)
		for s in segs:
			var t0 := TAU * s / segs
			var t1 := TAU * (s + 1) / segs
			var d0 := Vector3(sin(t0), 0, cos(t0))
			var d1 := Vector3(sin(t1), 0, cos(t1))
			var p00 := d0 * a.x + Vector3(0, a.y, 0)
			var p01 := d1 * a.x + Vector3(0, a.y, 0)
			var p10 := d0 * b.x + Vector3(0, b.y, 0)
			var p11 := d1 * b.x + Vector3(0, b.y, 0)
			var n0 := (d0 * slope.x + Vector3(0, slope.y, 0)).normalized()
			var n1 := (d1 * slope.x + Vector3(0, slope.y, 0)).normalized()
			if inward:
				n0 = -n0
				n1 = -n1
			var uv00 := Vector2(float(s) / segs, a.y / h_max)
			var uv01 := Vector2(float(s + 1) / segs, a.y / h_max)
			var uv10 := Vector2(float(s) / segs, b.y / h_max)
			var uv11 := Vector2(float(s + 1) / segs, b.y / h_max)
			var tri := [[p00, n0, uv00], [p10, n0, uv10], [p11, n1, uv11], [p00, n0, uv00], [p11, n1, uv11], [p01, n1, uv01]]
			if inward:
				tri = [tri[0], tri[2], tri[1], tri[3], tri[5], tri[4]]
			for v in tri:
				st.set_normal(v[1])
				st.set_uv(v[2])
				st.add_vertex(v[0])
	if cap_bottom:
		var r0 := profile[0].x
		var y0 := profile[0].y
		var n := Vector3.DOWN if not inward else Vector3.UP
		for s in segs:
			var t0 := TAU * s / segs
			var t1 := TAU * (s + 1) / segs
			var p0 := Vector3(sin(t0) * r0, y0, cos(t0) * r0)
			var p1 := Vector3(sin(t1) * r0, y0, cos(t1) * r0)
			var c := Vector3(0, y0, 0)
			var tri2 := [c, p1, p0] if not inward else [c, p0, p1]
			for v in tri2:
				st.set_normal(n)
				st.set_uv(Vector2(0.5, 0))
				st.add_vertex(v)
	return st.commit()


static func font_title() -> Font:
	return load("res://assets/fonts/UncialAntiqua-Regular.ttf")


static func font_ui(weight := 700) -> Font:
	var key := "font_ui_%d" % weight
	if _mat_cache.has(key):
		return _mat_cache[key]
	var fv := FontVariation.new()
	fv.base_font = load("res://assets/fonts/Nunito.ttf")
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	_mat_cache[key] = fv
	return fv
