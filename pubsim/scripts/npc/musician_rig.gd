class_name MusicianRig
extends RefCounted
## A session instrument held by a seated musician, and where their hands go on it.
##
## Builds the instrument (sculpted meshes from tools/gen_instruments.py) in the musician's body
## space and, every frame, returns the hand targets for both arms plus the orientation of
## anything held in the right hand (bow, tipper). Customer solves the arms to these targets.
## Body space: +Y up, the musician faces -Z, shoulders at y 1.41, mouth near (0, 1.61, -0.11).

const SHADER := "res://assets/shaders/instrument.gdshader"
static var _meshes := {}
static var _mats := {}

var kind := ""
var prop: Node3D
var held: Node3D          # bow or tipper, child of the right hand
var _parts := {}
var _base := Transform3D()
var size_k := 1.0               # the musician's size relative to the layout below (shoulders at 1.395)
var lips := Vector3(0, 1.605, -0.112)


static func mesh(name: String) -> Mesh:
	if not _meshes.has(name):
		_meshes[name] = load("res://assets/instruments/%s.obj" % name)
	return _meshes[name]


static func mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"fiddle":
			m = MeshKit.shader_mat(SHADER, {"mode": 1, "base_color": Color(0.58, 0.22, 0.06)})
		"ebony":
			m = MeshKit.shader_mat(SHADER, {"mode": 4, "base_color": Color(0.035, 0.028, 0.022)})
		"guitar":
			m = MeshKit.shader_mat(SHADER, {"mode": 2, "base_color": Color(0.3, 0.12, 0.05), "accent_color": Color(0.86, 0.66, 0.38)})
		"guitar_frets":
			m = MeshKit.shader_mat(SHADER, {"mode": 4, "base_color": Color(0.06, 0.035, 0.025), "frets": 0.65, "nut_x": 0.665})
		"banjo":
			m = MeshKit.shader_mat(SHADER, {"mode": 7, "base_color": Color(0.36, 0.17, 0.06)})
		"banjo_head":
			m = MeshKit.shader_mat(SHADER, {"mode": 3, "accent_color": Color(0.93, 0.9, 0.82), "mottle": 0.06})
		"banjo_frets":
			m = MeshKit.shader_mat(SHADER, {"mode": 4, "base_color": Color(0.06, 0.035, 0.025), "frets": 0.66, "nut_x": 0.6})
		"accordion":
			m = MeshKit.shader_mat(SHADER, {"mode": 5, "base_color": Color(0.5, 0.03, 0.04), "accent_color": Color(0.85, 0.66, 0.3)})
		"bellows":
			m = MeshKit.shader_mat(SHADER, {"mode": 6})
		"bodhran":
			m = MeshKit.shader_mat(SHADER, {"mode": 0, "base_color": Color(0.42, 0.24, 0.1)})
		"skin":
			m = MeshKit.shader_mat(SHADER, {"mode": 3, "accent_color": Color(0.86, 0.77, 0.58), "mottle": 0.7, "celtic": 1.0, "base_color": Color(0.05, 0.22, 0.09)})
		"chrome":
			m = MeshKit.color_mat(Color(0.78, 0.78, 0.76), 0.18, 0.9)
		"string":
			m = MeshKit.color_mat(Color(0.82, 0.8, 0.74), 0.25, 0.8)
		"hair":
			m = MeshKit.color_mat(Color(0.9, 0.88, 0.8), 0.6)
		"whistle":
			m = MeshKit.color_mat(Color(0.72, 0.72, 0.7), 0.22, 0.85)
		"whistle_top":
			m = MeshKit.color_mat(Color(0.05, 0.16, 0.08), 0.35)
		_:
			m = MeshKit.color_mat(Color(0.5, 0.5, 0.5))
	_mats[key] = m
	return m


## Orthonormal basis from an exact local X axis and a hint for local Z.
static func frame_x(x_axis: Vector3, z_hint: Vector3) -> Basis:
	var x := x_axis.normalized()
	var z := (z_hint - x * x.dot(z_hint)).normalized()
	return Basis(x, z.cross(x), z)


## Orthonormal basis from an exact local Z axis and a hint for local Y.
static func frame_z(z_axis: Vector3, y_hint: Vector3) -> Basis:
	var z := z_axis.normalized()
	var x := y_hint.cross(z).normalized()
	return Basis(x, z.cross(x), z)


func _add(parent: Node3D, mesh_name: String, mat_key: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(mesh_name)
	mi.material_override = mat(mat_key)
	parent.add_child(mi)
	return mi


func _strings(parent: Node3D, pts: Array, width: float) -> void:
	# each string is a thin box between two points; merged into one mesh
	var holder := Node3D.new()
	parent.add_child(holder)
	for pair in pts:
		var a: Vector3 = pair[0]
		var b: Vector3 = pair[1]
		var mid := (a + b) * 0.5
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(width, width, a.distance_to(b))
		mi.mesh = bm
		mi.material_override = mat("string")
		holder.add_child(mi)
		mi.transform = Transform3D(frame_z(b - a, Vector3.UP if absf((b - a).normalized().y) < 0.9 else Vector3.RIGHT), mid)
	MeshKit.merge_children(holder, "Strings")


func build(body: Node3D, right_hand: Node3D, k: String) -> void:
	kind = k
	prop = Node3D.new()
	prop.name = "Instrument"
	body.add_child(prop)
	match kind:
		"fiddle":
			# under the chin on the left collarbone, scroll forward-left, top rolled towards the bow
			var b := frame_z(-Vector3(-0.55, 0.1, -1.0), Vector3(0.45, 1.0, 0.0))
			var chin := Vector3(-0.07, 1.47, -0.075) * size_k
			_base = Transform3D(b, chin - b * Vector3(-0.038, 0.026, 0.17))
			_add(prop, "fiddle_body", "fiddle")
			_add(prop, "fiddle_fittings", "ebony")
			var st := []
			for i in 4:
				var x := -0.0075 + i * 0.005
				st.append([Vector3(x * 0.8, 0.0315, -0.305), Vector3(x * 1.3, 0.0425, 0.035)])
				st.append([Vector3(x * 1.3, 0.0425, 0.035), Vector3(x, 0.031, 0.115)])
			_strings(prop, st, 0.0009)
			held = _bow()
		"whistle":
			_base = Transform3D(Basis(Vector3.RIGHT, 0.74), lips + Vector3(0, 0.0, -0.006))
			MeshKit.cyl(prop, 0.0065, 0.0065, 0.29, Vector3(0, -0.175, 0), mat("whistle"), 10)
			MeshKit.cyl(prop, 0.0078, 0.0068, 0.065, Vector3(0, -0.032, 0), mat("whistle_top"), 10)
			for i in 6:
				MeshKit.sphere(prop, 0.0026, Vector3(0, -0.105 - i * 0.022, -0.0055), MeshKit.color_mat(Color(0.02, 0.02, 0.02), 0.5), Vector3(1, 1, 0.4), 6)
		"accordion":
			_base = Transform3D(Basis(Vector3.UP, 0.12), Vector3(0.0, 1.1, -0.22) * size_k)
			_parts["l"] = _add(prop, "accordion_end_l", "accordion")
			var r := Node3D.new()
			prop.add_child(r)
			_parts["r"] = r
			_add(r, "accordion_end_r", "accordion")
			_add(r, "accordion_buttons", "chrome")
			_parts["bellows"] = _add(prop, "accordion_bellows", "bellows")
		"bodhran":
			var b := frame_z(Vector3(-0.55, 0.05, 0.84), Vector3.UP)
			_base = Transform3D(b, Vector3(-0.14, 1.17, -0.3) * size_k)
			_add(prop, "bodhran_frame", "bodhran")
			_add(prop, "bodhran_skin", "skin")
			held = _tipper()
		"guitar", "banjo":
			var b := frame_x(Vector3(-1.0, 0.45, -0.22), Vector3(0.05, 0.05, 1.0))
			_base = Transform3D(b, Vector3(0.11, 1.07, -0.24) * size_k)
			if kind == "guitar":
				_add(prop, "guitar_body", "guitar")
				_add(prop, "guitar_fittings", "guitar_frets")
				var st := []
				for i in 6:
					var t := (i - 2.5) / 2.5
					st.append([Vector3(0.665, t * 0.02, -0.052), Vector3(-0.17, t * 0.028, -0.059)])
				_strings(prop, st, 0.0011)
			else:
				_add(prop, "banjo_body", "banjo")
				_add(prop, "banjo_head", "banjo_head")
				_add(prop, "banjo_fittings", "banjo_frets")
				var st := []
				for i in 5:
					var t := (i - 2.0) / 2.0
					st.append([Vector3(0.6, t * 0.014, -0.053), Vector3(-0.12, t * 0.012, -0.044)])
				_strings(prop, st, 0.0009)
	prop.transform = _base
	if held:
		right_hand.add_child(held)


func _bow() -> Node3D:
	# along +X from the frog (origin, on the hair line) to the tip; the stick sits above the hair
	var bw := Node3D.new()
	var holder := Node3D.new()
	bw.add_child(holder)
	MeshKit.cyl(holder, 0.0032, 0.0042, 0.72, Vector3(0.37, 0.016, 0), mat("ebony"), 8, Vector3(0, 0, -PI / 2.0))
	MeshKit.box(holder, Vector3(0.69, 0.0018, 0.008), Vector3(0.375, 0.0, 0), mat("hair"))
	MeshKit.box(holder, Vector3(0.045, 0.02, 0.012), Vector3(0.025, 0.007, 0), mat("ebony"))
	MeshKit.box(holder, Vector3(0.014, 0.02, 0.008), Vector3(0.725, 0.009, 0), mat("hair"))
	MeshKit.merge_children(holder, "Bow")
	return bw


func _tipper() -> Node3D:
	# held in the middle; along +X
	var tp := Node3D.new()
	var holder := Node3D.new()
	tp.add_child(holder)
	MeshKit.cyl(holder, 0.0065, 0.0065, 0.2, Vector3.ZERO, mat("bodhran"), 8, Vector3(0, 0, -PI / 2.0))
	for s in [-1, 1]:
		MeshKit.sphere(holder, 0.011, Vector3(s * 0.1, 0, 0), mat("bodhran"), Vector3.ONE, 8)
	MeshKit.merge_children(holder, "Tipper")
	return tp


## Hand targets (body space) and pole directions for this moment of the tune.
## Returns {"l", "r", "pl", "pr"} and "held" (body-space basis for the right-hand item, if any).
func pose(t: float, beat: float) -> Dictionary:
	var ph := t / beat * TAU
	var b := _base.basis
	var o := _base.origin
	var out := {}
	match kind:
		"fiddle":
			# left hand on the neck by the nut, fingers working; bow travelling across the strings
			out["l"] = o + b * Vector3(0.0, -0.028, -0.275 + 0.006 * sin(ph * 2.0))
			out["pl"] = Vector3(-0.3, -1.0, 0.2)
			var cross := 0.12 * sin(ph * 0.25)
			var roll := Basis(b.z, cross)
			var bow_x := roll * -b.x
			var bow_y := roll * b.y
			var bb := Basis(bow_x, bow_y, bow_x.cross(bow_y))
			var stroke := 0.36 + 0.24 * sin(ph * 0.5)
			var contact := o + b * Vector3(0.0, 0.046, 0.004)
			var frog := contact - bow_x * stroke
			out["r"] = frog + bb * Vector3(0.025, 0.035, 0.0)
			out["pr"] = Vector3(1.0, -0.35, 0.45)
			out["held"] = bb
			if held:
				held.position = -Vector3(0.025, 0.035, 0.0)
		"whistle":
			var down := b * Vector3.DOWN
			out["l"] = o + down * 0.115 + Vector3(-0.014, -0.012, 0.03)
			out["r"] = o + down * 0.2 + Vector3(0.014, -0.012, 0.03)
			out["pl"] = Vector3(-0.8, -0.6, 0.1)
			out["pr"] = Vector3(0.8, -0.6, 0.1)
		"accordion":
			var open := 1.0 + 0.45 * sin(ph * 0.125)
			var hw := 0.08 * open
			(_parts["bellows"] as Node3D).scale = Vector3(open, 1, 1)
			(_parts["l"] as Node3D).position = Vector3(-(hw + 0.045), 0, 0)
			(_parts["r"] as Node3D).position = Vector3(hw + 0.045, 0, 0)
			out["l"] = o + b * Vector3(-(hw + 0.105), 0.02, 0.0)
			out["r"] = o + b * Vector3(hw + 0.04, -0.02 + 0.01 * sin(ph * 2.0), -0.115)
			out["pl"] = Vector3(-0.8, -0.6, 0.3)
			out["pr"] = Vector3(0.8, -0.6, 0.3)
		"bodhran":
			var n := -b.z
			out["l"] = o + b * Vector3(0.03, -0.02, 0.06)
			out["pl"] = Vector3(-0.7, -0.7, 0.2)
			var wrist := sin(ph) * 0.65
			out["r"] = o + n * 0.13 + b.y * (0.03 * sin(ph)) + b.x * 0.02
			out["pr"] = Vector3(0.9, -0.5, 0.3)
			var axis := (b.y * cos(wrist) - n * sin(wrist)).normalized()
			out["held"] = frame_x(axis, n.cross(axis))
		"guitar", "banjo":
			var slide := 0.03 * sin(ph * 0.125)
			out["l"] = o + b * Vector3(0.47 + slide, -0.04, 0.012)
			out["pl"] = Vector3(-0.4, -1.0, 0.2)
			var strum := sin(ph) * 0.055
			out["r"] = o + b * Vector3(0.03 if kind == "guitar" else -0.05, strum, -0.1)
			out["pr"] = Vector3(0.9, -0.4, 0.55)
	return out
