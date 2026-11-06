class_name HexFlash
extends MeshInstance3D
## The moment a hexagon is cleared: a wall of light rises from its border and fades,
## while a bright sweep closes from the edge to the centre, and a flash of light.

const LIFE := 2.6              # seconds
const WALL := 14.0             # wall height (m)

var _cell := 0
var _c := Vector3.UP           # centre direction
var _up := Vector3.UP
var _pts := PackedVector3Array()
var _t := 0.0
var _light: OmniLight3D


static func spawn(parent: Node, cell: int) -> HexFlash:
	var f := HexFlash.new()
	f._cell = cell
	parent.add_child(f)
	return f


func _ready() -> void:
	_c = HexGrid.centers[_cell]
	_up = _c
	_pts = HexLines.border(_cell)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = false
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light = OmniLight3D.new()
	_light.light_color = Color(0.6, 0.95, 1.0)
	_light.omni_range = HexGrid.cell_angle * TerrainGen.RADIUS * 1.4
	_light.shadow_enabled = false
	add_child(_light)
	_light.global_position = TerrainGen.surface(_c, 8.0)
	_draw()


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	_draw()


func _draw() -> void:
	var k := _t / LIFE
	var fade := pow(1.0 - k, 1.5)
	_light.light_energy = 2.5 * fade * fade
	var im := ImmediateMesh.new()
	var n := _pts.size()
	if n < 3:
		mesh = im
		return
	# Wall of light rising from the border.
	var h := WALL * (1.0 - pow(1.0 - minf(k * 1.6, 1.0), 3.0))
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n + 1:
		var p := _pts[i % n]
		var up := p.normalized()
		im.surface_set_color(Color(0.45, 0.95, 1.0, fade))
		im.surface_add_vertex(p)
		im.surface_set_color(Color(0.45, 0.95, 1.0, 0.0))
		im.surface_add_vertex(p + up * h)
	im.surface_end()
	# Golden sweep closing from the edge to the centre over the first second.
	var s := clampf(1.0 - k * 1.3, 0.0, 1.0)
	if s > 0.02:
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in n + 1:
			var d := _c.slerp(_pts[i % n].normalized(), s)
			var g := TerrainGen.surface(d, 0.25)
			im.surface_set_color(Color(1.0, 0.85, 0.35, 0.9))
			im.surface_add_vertex(g)
			im.surface_set_color(Color(1.0, 0.85, 0.35, 0.0))
			im.surface_add_vertex(g + d * 2.2)
		im.surface_end()
	mesh = im
