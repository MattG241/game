class_name Meshes
extends RefCounted
## Procedural model kit: materials, primitive helpers, rocks, astronaut.

static var _mats := {}
static var _shader_hs: Shader
static var _shader_energy: Shader
static var _rock_meshes: Array = []


static func hs(color: Color, metallic := 0.25, rough := 0.5, emit := Color(0, 0, 0), emit_strength := 0.0, panel := 1.6, grime := 0.3, stripes := 0.0) -> ShaderMaterial:
	var key := "%s|%.2f|%.2f|%s|%.2f|%.2f|%.2f|%.2f" % [color.to_html(), metallic, rough, emit.to_html(), emit_strength, panel, grime, stripes]
	if _mats.has(key):
		return _mats[key]
	if _shader_hs == null:
		_shader_hs = load("res://shaders/hardsurface.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _shader_hs
	m.set_shader_parameter("paint", color)
	m.set_shader_parameter("metallic", metallic)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("emit_color", emit)
	m.set_shader_parameter("emit_strength", emit_strength)
	m.set_shader_parameter("panel_scale", panel)
	m.set_shader_parameter("grime", grime)
	m.set_shader_parameter("stripes", stripes)
	_mats[key] = m
	return m


static func glow(color: Color, strength := 2.0) -> ShaderMaterial:
	var key := "glow|%s|%.2f" % [color.to_html(), strength]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/glow.gdshader")
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("strength", strength)
	_mats[key] = m
	return m


static func plain(color: Color, metallic := 0.0, rough := 0.6) -> ShaderMaterial:
	var key := "plain|%s|%.2f|%.2f" % [color.to_html(), metallic, rough]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/plain.gdshader")
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("metallic", metallic)
	m.set_shader_parameter("roughness", rough)
	_mats[key] = m
	return m


static func visor() -> ShaderMaterial:
	if _mats.has("visor"):
		return _mats["visor"]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/plain.gdshader")
	m.set_shader_parameter("albedo", Color(0.85, 0.55, 0.15))
	m.set_shader_parameter("metallic", 1.0)
	m.set_shader_parameter("roughness", 0.08)
	m.set_shader_parameter("emission", Color(0.25, 0.12, 0.02))
	_mats["visor"] = m
	return m


static func energy(color: Color, intensity := 1.0, speed := 1.0, bands := 6.0) -> ShaderMaterial:
	if _shader_energy == null:
		_shader_energy = load("res://shaders/energy.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _shader_energy
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("speed", speed)
	m.set_shader_parameter("bands", bands)
	return m


static func part(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func cyl(radius: float, height: float, segments := 16, top := -1.0) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius if top < 0.0 else top
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


static func sphere(radius: float, segments := 16, hemi := false) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * (1.0 if hemi else 2.0)
	m.radial_segments = segments
	m.rings = maxi(segments / 2, 4)
	m.is_hemisphere = hemi
	return m


static func capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 12
	m.rings = 4
	return m


static func torus(inner: float, outer: float, segs := 24) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = segs
	m.ring_segments = 8
	return m


static func label(parent: Node3D, text: String, pos: Vector3, size := 64, color := Color.WHITE, billboard := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UIKit.font_title()
	l.font_size = size
	l.pixel_size = 0.01
	l.modulate = color
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.position = pos
	l.shaded = false
	l.double_sided = true
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	parent.add_child(l)
	return l


## Orients a node so its local +Y axis runs from a to b (length baked into scale.y).
static func span(node: Node3D, a: Vector3, b: Vector3, thickness := 1.0) -> void:
	node.global_transform = span_transform(a, b, thickness)


static func span_local(node: Node3D, a: Vector3, b: Vector3, thickness := 1.0) -> void:
	node.transform = span_transform(a, b, thickness)


static func span_transform(a: Vector3, b: Vector3, thickness := 1.0) -> Transform3D:
	var d := b - a
	var l := d.length()
	if l < 0.0001:
		return Transform3D(Basis.IDENTITY.scaled(Vector3(thickness, 0.0001, thickness)), a)
	var y := d / l
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.FORWARD)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x * thickness, y * l, z * thickness), (a + b) * 0.5)


# ------------------------------------------------------------------- rocks

static func rock_mesh(variant: int) -> ArrayMesh:
	if _rock_meshes.is_empty():
		for v in 3:
			_rock_meshes.append(_build_rock(v))
	return _rock_meshes[variant % _rock_meshes.size()]


static func _build_rock(v: int) -> ArrayMesh:
	var base := SphereMesh.new()
	base.radius = 1.0
	base.height = 1.6
	base.radial_segments = 10
	base.rings = 6
	var arrays := base.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = 77 + v * 13
	noise.frequency = 1.3
	for i in verts.size():
		var p := verts[i]
		var k := 1.0 + noise.get_noise_3dv(p) * 0.35
		p *= k
		p.y = maxf(p.y, -0.3)
		verts[i] = p
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in idx:
		st.add_vertex(verts[i])
	st.generate_normals()
	var mesh := st.commit()
	return mesh


static func rock_material() -> ShaderMaterial:
	return hs(Color(0.42, 0.41, 0.40), 0.0, 0.92, Color(0, 0, 0), 0.0, 3.0, 0.55)


# --------------------------------------------------------------- astronaut

## Stylised astronaut (approx 1.8 m). Origin at the feet.
static func astronaut(accent := Color(1.0, 0.45, 0.1)) -> Node3D:
	var root := Node3D.new()
	root.name = "Astronaut"
	var suit := hs(Color(0.92, 0.92, 0.9), 0.05, 0.75, Color(0, 0, 0), 0.0, 4.0, 0.25)
	var dark := hs(Color(0.25, 0.26, 0.3), 0.3, 0.6)
	var acc := hs(accent, 0.1, 0.5)
	part(root, capsule(0.27, 0.8), suit, Vector3(0, 1.15, 0))
	part(root, box(Vector3(0.48, 0.12, 0.3)), acc, Vector3(0, 1.32, 0))
	part(root, box(Vector3(0.45, 0.6, 0.25)), suit, Vector3(0, 1.2, 0.27))
	part(root, box(Vector3(0.12, 0.3, 0.05)), acc, Vector3(0.1, 1.25, 0.41))
	part(root, sphere(0.24), suit, Vector3(0, 1.72, 0))
	part(root, sphere(0.19), visor(), Vector3(0, 1.73, -0.08), Vector3.ZERO, Vector3(1.0, 0.85, 0.75))
	# legs
	var leg_l := Node3D.new()
	leg_l.name = "LegL"
	leg_l.position = Vector3(-0.13, 0.8, 0)
	root.add_child(leg_l)
	part(leg_l, capsule(0.12, 0.75), suit, Vector3(0, -0.35, 0))
	part(leg_l, box(Vector3(0.2, 0.14, 0.32)), dark, Vector3(0, -0.74, -0.04))
	var leg_r := leg_l.duplicate()
	leg_r.name = "LegR"
	leg_r.position = Vector3(0.13, 0.8, 0)
	root.add_child(leg_r)
	# arms
	var arm_l := Node3D.new()
	arm_l.name = "ArmL"
	arm_l.position = Vector3(-0.36, 1.45, 0)
	root.add_child(arm_l)
	part(arm_l, capsule(0.09, 0.65), suit, Vector3(0, -0.28, 0))
	part(arm_l, sphere(0.09), dark, Vector3(0, -0.62, 0))
	var arm_r := arm_l.duplicate()
	arm_r.name = "ArmR"
	arm_r.position = Vector3(0.36, 1.45, 0)
	root.add_child(arm_r)
	return root
