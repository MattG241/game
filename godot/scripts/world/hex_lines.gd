class_name HexLines
extends MeshInstance3D
## Faint lines on the ground around the unfinished hexagons near the player.
## Borders are found by marching out from each hexagon's centre until the point
## belongs to another cell, then follow the ground (cached per hexagon).

const RANGE := 170.0           # draw hexagons whose centre is this close (m)
const STEPS := 144             # border points per hexagon
const LIFT := 0.22             # metres above the ground

static var _borders := {}      # cell -> PackedVector3Array (ground points, closed loop)

var world: Node                # the game world (follows the player or their vehicle)
var _shown := ""
var _t := 0.0


func _ready() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.55, 0.85, 1.0, 0.4)
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or world == null:
		return
	_t = 1.0
	var fd: Vector3 = (world.focus_node() as Node3D).global_position.normalized()
	var lim := cos(RANGE / TerrainGen.RADIUS)
	var cells := []
	for i in HexGrid.count():
		if HexGrid.centers[i].dot(fd) > lim and not GameState.hexes_done.has(i):
			cells.append(i)
	var key := str(cells)
	if key == _shown:
		return
	_shown = key
	var im := ImmediateMesh.new()
	if not cells.is_empty():
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		for c in cells:
			var pts := border(c)
			for k in pts.size():
				im.surface_add_vertex(pts[k])
				im.surface_add_vertex(pts[(k + 1) % pts.size()])
		im.surface_end()
	mesh = im


## Ground points along a hexagon's edge (computed once).
static func border(cell: int) -> PackedVector3Array:
	if _borders.has(cell):
		return _borders[cell]
	var c := HexGrid.centers[cell]
	var b := TerrainGen.frame(c)
	var out := PackedVector3Array()
	var far := HexGrid.cell_angle * 1.2
	for k in STEPS:
		var a := TAU * k / STEPS
		var dir := b.x * cos(a) + b.z * sin(a)
		# Binary search for the angle from the centre where the cell ends.
		var lo := 0.0
		var hi := far
		for it in 14:
			var mid := (lo + hi) * 0.5
			var d := c * cos(mid) + dir * sin(mid)
			if HexGrid.cell_of(d) == cell:
				lo = mid
			else:
				hi = mid
		var e := c * cos(lo) + dir * sin(lo)
		out.append(TerrainGen.surface(e, LIFT))
	_borders[cell] = out
	return out
