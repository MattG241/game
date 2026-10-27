class_name LunarEnv
extends Node3D
## Sky, sun, ambient lighting and the Earth hanging over the horizon.

const EARTH_DIR := Vector3(-0.42, 0.36, -0.83)
const EARTH_DIST := 1900.0

var sun: DirectionalLight3D
var env: Environment
var earth: MeshInstance3D
var _earth_mat: ShaderMaterial
var camera_ref: Camera3D


func _ready() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky.gdshader")
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
	sun.rotation = Vector3(deg_to_rad(-24.0), deg_to_rad(52.0), 0.0)
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
	apply_settings()
	Settings.changed.connect(apply_settings)


func apply_settings() -> void:
	sun.shadow_enabled = bool(Settings.get_value("shadows", true))


func _process(delta: float) -> void:
	_earth_mat.set_shader_parameter("sun_dir", sun.global_transform.basis.z)
	_earth_mat.set_shader_parameter("spin", Time.get_ticks_msec() * 0.0000015)
	var cam := get_viewport().get_camera_3d()
	if cam:
		earth.global_position = cam.global_position + EARTH_DIR.normalized() * EARTH_DIST
		earth.rotation.y += delta * 0.002
