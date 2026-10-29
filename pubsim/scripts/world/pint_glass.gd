class_name PintGlass
extends Node3D
## A physical glass: transparent shell, parametric liquid, foam dome and slosh.

const PROFILE := [
	Vector2(0.029, 0.0), Vector2(0.0300, 0.02), Vector2(0.034, 0.07),
	Vector2(0.0415, 0.115), Vector2(0.042, 0.14), Vector2(0.0395, 0.16),
]
const TUMBLER_PROFILE := [Vector2(0.036, 0.0), Vector2(0.037, 0.03), Vector2(0.039, 0.085)]
const WALL := 0.0025
const BASE := 0.006

static var _shell_mesh: ArrayMesh
static var _liquid_mesh: ArrayMesh
static var _tumbler_shell: ArrayMesh
static var _tumbler_liquid: ArrayMesh

var contents := GlassContents.new()
var dirt := 0.0
var kind := "pint"
var height := 0.16
var inner_height := 0.154
var lace_top := 0.0
var tilt_axis := Vector3.FORWARD

var _shell: MeshInstance3D
var _liquid: MeshInstance3D
var _dome: MeshInstance3D
var _ice: Node3D
var _liq_mat: ShaderMaterial
var _shell_mat: ShaderMaterial
var _slosh := Vector2.ZERO
var _slosh_vel := Vector2.ZERO
var _last_pos := Vector3.ZERO
var _last_vel := Vector3.ZERO
var _color_drink := ""


func _init(glass_kind := "pint") -> void:
	kind = glass_kind


func _ready() -> void:
	_build()
	_last_pos = global_position


static func _profile_inner(src: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var top: float = src[src.size() - 1].y
	for p in src:
		var y := maxf(p.y, BASE)
		out.append(Vector2(p.x - WALL, y - BASE))
	out[0] = Vector2(src[0].x - WALL - 0.002, 0.0)
	return out


func _build() -> void:
	var prof: Array = PROFILE if kind == "pint" else TUMBLER_PROFILE
	height = prof[prof.size() - 1].y
	inner_height = height - BASE
	if kind == "pint":
		if _shell_mesh == null:
			_shell_mesh = MeshKit.lathe(PackedVector2Array(PROFILE), 28, true)
			_liquid_mesh = MeshKit.lathe(_profile_inner(PROFILE), 24, true)
	else:
		if _tumbler_shell == null:
			_tumbler_shell = MeshKit.lathe(PackedVector2Array(TUMBLER_PROFILE), 24, true)
			_tumbler_liquid = MeshKit.lathe(_profile_inner(TUMBLER_PROFILE), 20, true)
	_liquid = MeshInstance3D.new()
	_liquid.mesh = _liquid_mesh if kind == "pint" else _tumbler_liquid
	_liquid.position.y = BASE
	_liq_mat = MeshKit.shader_mat("res://assets/shaders/liquid.gdshader", {"height": inner_height})
	_liquid.material_override = _liq_mat
	_liquid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_liquid)
	_shell = MeshInstance3D.new()
	_shell.mesh = _shell_mesh if kind == "pint" else _tumbler_shell
	_shell_mat = MeshKit.shader_mat("res://assets/shaders/glass.gdshader", {"emblem": 1.0 if kind == "pint" else 0.0})
	_shell.material_override = _shell_mat
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shell)
	_dome = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = prof[prof.size() - 1].x - WALL
	sm.height = sm.radius
	sm.is_hemisphere = true
	sm.radial_segments = 20
	sm.rings = 6
	_dome.mesh = sm
	_dome.material_override = MeshKit.color_mat(Color(0.93, 0.86, 0.72), 0.6)
	_dome.position.y = height
	_dome.visible = false
	add_child(_dome)
	_ice = Node3D.new()
	add_child(_ice)
	var ice_mat := MeshKit.color_mat(Color(0.85, 0.92, 1.0, 0.55), 0.05)
	for i in 4:
		var cube := MeshKit.box(_ice, Vector3(0.022, 0.022, 0.022), Vector3((i % 2) * 0.02 - 0.01, 0.02 + i * 0.012, (i / 2) * 0.02 - 0.01), ice_mat, Vector3(i * 0.7, i * 0.4, 0))
		cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ice.visible = false
	refresh_colors()


func refresh_colors() -> void:
	var d := GameData.drink(contents.drink_id) if contents.drink_id != "" else GameData.drink("stout")
	var c: Array = d.get("color", [0.05, 0.02, 0.015])
	var f: Array = d.get("foam", [0.93, 0.86, 0.72])
	var body_c := Color(c[0], c[1], c[2])
	_liq_mat.set_shader_parameter("body_color", body_c)
	_liq_mat.set_shader_parameter("foam_color", Color(f[0], f[1], f[2]))
	var stout_like: bool = contents.drink_id in ["stout", "zero", ""]
	_liq_mat.set_shader_parameter("cascade_color", Color(0.45, 0.28, 0.15) if stout_like else body_c.lightened(0.3))
	_liq_mat.set_shader_parameter("clarity", 0.0 if stout_like else 0.6)
	_dome.material_override = MeshKit.color_mat(Color(f[0], f[1], f[2]), 0.6)
	_color_drink = contents.drink_id


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if contents.drink_id != _color_drink:
		refresh_colors()
	_update_slosh(delta)
	update_visual()


func _update_slosh(delta: float) -> void:
	if delta <= 0.0:
		return
	var pos := global_position
	var vel := (pos - _last_pos) / delta
	var acc := (vel - _last_vel) / delta
	_last_pos = pos
	_last_vel = vel
	if acc.length() > 60.0:
		acc = acc.normalized() * 60.0
	var local_acc := global_transform.basis.orthonormalized().inverse() * acc
	var reduced := bool(GameState.settings.get("reduced_motion", false))
	var k := 0.004 if not reduced else 0.0015
	_slosh_vel += Vector2(-local_acc.x, -local_acc.z) * k
	_slosh_vel += -_slosh * 120.0 * delta
	_slosh_vel *= exp(-4.0 * delta)
	_slosh += _slosh_vel * delta * 60.0 * 0.016
	_slosh = _slosh.limit_length(0.25)


func update_visual() -> void:
	var c := contents
	var up := (global_transform.basis.orthonormalized().inverse() * Vector3.UP).normalized()
	up = (up + Vector3(_slosh.x, 0, _slosh.y)).normalized()
	var lvl_body := clampf(c.liquid_level(), 0.0, 1.0)
	var lvl_total := clampf(c.total(), 0.0, 1.0)
	_liq_mat.set_shader_parameter("up_local", up)
	_liq_mat.set_shader_parameter("level_body", lvl_body)
	_liq_mat.set_shader_parameter("level_total", lvl_total if c.total() > 0.003 else -0.01)
	_liq_mat.set_shader_parameter("dark_frac", clampf(c.body, 0.0, 1.0))
	_liq_mat.set_shader_parameter("lace_top", lace_top)
	_liq_mat.set_shader_parameter("cascade_strength", 1.0)
	_shell_mat.set_shader_parameter("dirt", dirt)
	var over := c.total() - 1.0
	_dome.visible = over > 0.002 and c.foam > 0.01 and up.y > 0.97
	if _dome.visible:
		var r: float = (_dome.mesh as SphereMesh).radius
		_dome.scale = Vector3(1.0, clampf(over * inner_height / (r * 0.5), 0.02, 1.0), 1.0)
	_ice.visible = c.ice > 0.05


func set_dirty(amount: float) -> void:
	dirt = clampf(amount, 0.0, 1.0)


func is_clean() -> bool:
	return dirt < 0.1 and contents.is_empty()


func empty_out() -> void:
	contents.reset()
	lace_top = 0.0
