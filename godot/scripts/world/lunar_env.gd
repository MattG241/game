class_name LunarEnv
extends Node3D
## Sky, sun, ambient lighting and the Earth hanging over the horizon.
## The Moon is round, but it's always a sunny day with Earth in the sky wherever you
## are: the sun and Earth are placed relative to the camera's local "up", carried along
## smoothly as you travel (no sudden swing near the poles).

const EARTH_DIR := Vector3(-0.42, 0.36, -0.83)   # in the local frame (y = up)
const EARTH_DIST := 1900.0
const SUN_ROT := Vector3(-24.0, 52.0, 0.0)        # degrees, in the local frame

var sun: DirectionalLight3D
var env: Environment
var earth: MeshInstance3D
var _earth_mat: ShaderMaterial
var camera_ref: Camera3D
var sky_mat: ShaderMaterial
var planets: Array[Node3D] = []   # far planets, fixed among the stars
# Meteor showers (visual): more frequent as more of the Moon is cleaned.
var _shower_in := 0.0            # seconds until the next shower
var _shower_t := -1.0            # seconds into the current shower (-1 = none)
const SHOWER_LEN := 50.0
const PLANET_DIST := 2200.0
const PLANETS := [
	# direction (world), radius, kind, colours a b c, bands, rings, tilt (deg)
	{"dir": Vector3(0.75, 0.45, -0.5), "r": 70.0, "kind": 0, "a": Color(0.92, 0.78, 0.55), "b": Color(0.62, 0.42, 0.26), "c": Color(0.98, 0.94, 0.85), "bands": 9.0, "rings": true, "tilt": 24.0},
	{"dir": Vector3(-0.7, 0.3, 0.65), "r": 18.0, "kind": 1, "a": Color(0.85, 0.42, 0.22), "b": Color(0.5, 0.2, 0.12), "c": Color(0.95, 0.92, 0.9), "bands": 0.0, "rings": false, "tilt": 10.0},
	{"dir": Vector3(0.1, -0.35, 0.93), "r": 34.0, "kind": 0, "a": Color(0.55, 0.85, 0.95), "b": Color(0.3, 0.55, 0.8), "c": Color(0.85, 0.97, 1.0), "bands": 5.0, "rings": false, "tilt": 70.0},
]
var _frame := Basis.IDENTITY     # local sky frame (Y = up at the camera)
var _frame_set := false


func _ready() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky.gdshader")
	sm.set_shader_parameter("milky", load("res://assets/textures/sky_milkyway.png"))
	sky_mat = sm
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.36, 0.48)
	env.ambient_light_energy = 0.38
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.08
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.light_energy = 1.55
	sun.rotation = SUN_ROT * (PI / 180.0)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_split_1 = 0.25
	sun.directional_shadow_blend_splits = false
	sun.light_angular_distance = 0.5
	add_child(sun)
	# Earth
	earth = MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 105.0
	sp.height = 210.0
	sp.radial_segments = 48
	sp.rings = 24
	earth.mesh = sp
	_earth_mat = ShaderMaterial.new()
	_earth_mat.shader = load("res://shaders/earth.gdshader")
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 256
	nt.seamless = true
	var n := FastNoiseLite.new()
	n.seed = 3
	n.frequency = 0.012
	n.fractal_octaves = 5
	nt.noise = n
	_earth_mat.set_shader_parameter("noise_tex", nt)
	_earth_mat.set_shader_parameter("sun_dir", -sun.global_transform.basis.z if is_inside_tree() else Vector3(0.5, 0.4, 0.7))
	earth.material_override = _earth_mat
	earth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	earth.top_level = true
	add_child(earth)
	_make_planets()
	_shower_in = randf_range(150.0, 300.0)
	apply_settings()
	Settings.changed.connect(apply_settings)


func _make_planets() -> void:
	var ps: Shader = load("res://shaders/planet.gdshader")
	var rs: Shader = load("res://shaders/planet_ring.gdshader")
	for p in PLANETS:
		var root := Node3D.new()
		root.top_level = true
		add_child(root)
		root.set_meta("dir", (p["dir"] as Vector3).normalized())
		var tilt := Basis(Vector3(1, 0, 0.3).normalized(), deg_to_rad(float(p["tilt"])))
		var body := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = p["r"]
		sp.height = float(p["r"]) * 2.0
		sp.radial_segments = 40
		sp.rings = 20
		body.mesh = sp
		var m := ShaderMaterial.new()
		m.shader = ps
		m.set_shader_parameter("kind", p["kind"])
		m.set_shader_parameter("col_a", p["a"])
		m.set_shader_parameter("col_b", p["b"])
		m.set_shader_parameter("col_c", p["c"])
		m.set_shader_parameter("bands", p["bands"])
		body.material_override = m
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.basis = tilt
		root.add_child(body)
		if p["rings"]:
			var ring := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2.ONE * float(p["r"]) * 4.6
			ring.mesh = pm
			var rm := ShaderMaterial.new()
			rm.shader = rs
			rm.set_shader_parameter("ring_col", p["a"])
			ring.material_override = rm
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ring.basis = tilt
			root.add_child(ring)
		planets.append(root)


## Keeps the far planets and the Earth around a camera position.
func place_sky_objects(cam_pos: Vector3) -> void:
	var sd := sun.global_transform.basis.z
	for root in planets:
		root.global_position = cam_pos + (root.get_meta("dir") as Vector3) * PLANET_DIST
		for c in root.get_children():
			((c as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("sun_dir", sd)


## Meteor showers and shooting stars (only to look at).
func _update_meteors(delta: float) -> void:
	var progress := 0.0
	if HexGrid.count() > 0:
		progress = float(GameState.hexes_done.size()) / HexGrid.count()
	sky_mat.set_shader_parameter("sky_up", _frame.y)
	sky_mat.set_shader_parameter("meteor_period", lerpf(14.0, 5.0, progress))
	if _shower_t < 0.0:
		_shower_in -= delta
		if _shower_in <= 0.0:
			start_shower()
	else:
		_shower_t += delta
		var k := _shower_t / SHOWER_LEN
		sky_mat.set_shader_parameter("shower", smoothstep(0.0, 0.15, k) * smoothstep(1.0, 0.75, k) * lerpf(0.55, 1.0, progress))
		if _shower_t >= SHOWER_LEN:
			_shower_t = -1.0
			sky_mat.set_shader_parameter("shower", 0.0)
			_shower_in = lerpf(720.0, 240.0, progress) * randf_range(0.8, 1.2)


func start_shower() -> void:
	_shower_t = 0.0
	var side := _frame.x * randf_range(-1.0, 1.0) + _frame.z * randf_range(-1.0, 1.0)
	sky_mat.set_shader_parameter("shower_dir", (_frame.y * 1.2 + side * 0.6).normalized())
	if GameState.active:
		GameState.notify.emit("METEOR SHOWER - look up!", "info")


func shower_active() -> bool:
	return _shower_t >= 0.0


func apply_settings() -> void:
	sun.shadow_enabled = bool(Settings.get_value("shadows", true))


## Direction of Earth in the sky (world space) for the current view.
func earth_dir() -> Vector3:
	return _frame * EARTH_DIR.normalized()


## Re-centres the sky on a point of the Moon (e.g. after a teleport or loading).
func reset_frame(p: Vector3) -> void:
	_frame = TerrainGen.frame(p.normalized())
	_frame_set = true
	_apply_frame()


func _apply_frame() -> void:
	sun.global_basis = _frame * Basis.from_euler(SUN_ROT * (PI / 180.0))


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.length() > 1.0:
		var up := cam.global_position.normalized()
		if not _frame_set:
			reset_frame(up)
		elif _frame.y.dot(up) < 0.99996:   # moved about 0.5 degrees round the Moon
			_frame = (Basis(Quaternion(_frame.y.normalized(), up)) * _frame).orthonormalized()
			_apply_frame()
		earth.global_position = cam.global_position + earth_dir() * EARTH_DIST
		earth.rotation.y += delta * 0.002
		place_sky_objects(cam.global_position)
	_update_meteors(delta)
	_earth_mat.set_shader_parameter("sun_dir", sun.global_transform.basis.z)
	_earth_mat.set_shader_parameter("spin", Time.get_ticks_msec() * 0.0000015)
