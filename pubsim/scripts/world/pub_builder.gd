class_name PubBuilder
extends RefCounted
## Builds The Crooked Shamrock procedurally and returns anchors used by gameplay.


var root: Node3D
var info := {
	"taps": {},            # drink id -> {handle: Node3D, nozzle: Vector3, glass: Vector3, root: Node3D}
	"seats": [],           # {pos, yaw, table, kind}
	"upgrade_show": {},    # upgrade id -> Array[Node3D] visible once purchased
	"upgrade_hide": {},    # upgrade id -> Array[Node3D] hidden once purchased
	"lamps": [],           # OmniLight3D of pendant lamps
	"window_mats": [],
	"street_lights": [],
	"fire": null,
	"fire_light": null,
	"dust": [],
	"light_cones": [],
	"rack_glasses": null,  # Node3D holding visual clean glasses
	"rack_slots": [],
	"sink_slots": [],
	"keg_nodes": {},
	"door": null,
	"rain": [],
	"env": null,
	"photos": [],
	"festival": [],        # bunting and shamrock, shown on festival days
	"tv_mat": null,        # the big screen's picture (ShaderMaterial, "on" 0..1)
	"tv_label": null,      # the score in the corner of the screen
	"tv_light": null,
}
var _title_font: Font


const BRAND := "res://assets/brand/"


func build(parent: Node3D) -> Dictionary:
	root = Node3D.new()
	root.name = "Pub"
	parent.add_child(root)
	_title_font = MeshKit.font_title()
	_room()
	_bar()
	_taps()
	_back_bar()
	_fireplace()
	_seating()
	_front_wall()
	_decor()
	_lights()
	_cellar()
	_exterior()
	_upgrade_extras()
	_darts_corner()
	_stage()
	_jukebox()
	_big_screen()
	_bunting()
	_sky()
	return info


## A big dome of sky round the whole street (seen through the windows and outside).
func _sky() -> void:
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 60.0      # inside the far clip (80 m) from anywhere on the street
	sm.height = 120.0
	sm.radial_segments = 24
	sm.rings = 12
	dome.mesh = sm
	var mat := MeshKit.shader_mat("res://assets/shaders/night_sky.gdshader")
	dome.material_override = mat
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dome.extra_cull_margin = 200.0
	root.add_child(dome)
	info["sky_mat"] = mat


## A wall-mounted screen over the fireplace for match days.
func _big_screen() -> void:
	var g := _group("BigScreen")
	var p := PubLayout.FIREPLACE
	var at := Vector3(p.x + 0.43, 2.28, p.z)
	MeshKit.box(g, Vector3(0.05, 0.74, 1.28), at, MeshKit.color_mat(Color(0.02, 0.02, 0.02), 0.3, 0.3))
	var mat := MeshKit.shader_mat("res://assets/shaders/tv_match.gdshader", {"on": 0.0})
	var screen := MeshKit.quad(g, Vector2(1.2, 0.675), at + Vector3(0.027, 0, 0), mat, Vector3(0, PI / 2, 0))
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lbl := MeshKit.label(g, "", at + Vector3(0.035, 0.27, 0.0), 40, Color(1, 1, 1), Vector3(0, PI / 2, 0))
	lbl.outline_size = 10
	lbl.pixel_size = 0.0018
	lbl.font_size = 44
	var glow := OmniLight3D.new()
	glow.position = at + Vector3(0.6, -0.2, 0)
	glow.light_color = Color(0.6, 0.8, 1.0)
	glow.light_energy = 0.0
	glow.omni_range = 3.0
	g.add_child(glow)
	info["tv_mat"] = mat
	info["tv_label"] = lbl
	info["tv_light"] = glow
	_tag("big_screen", g)


## Festival bunting: strings of green, white and orange flags across the room, all in one mesh.
func _bunting() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := [Color(0.1, 0.55, 0.25), Color(0.95, 0.95, 0.92), Color(0.95, 0.5, 0.12)]
	var k := 0
	for z in [-0.6, 1.4, 3.4]:
		var x0 := PubLayout.ROOM_MIN.x + 0.3
		var x1 := PubLayout.PARTITION_X - 0.2
		var n := int((x1 - x0) / 0.24)
		for i in n:
			var u := float(i) / float(n - 1)
			var x := lerpf(x0, x1, u)
			var y := 3.05 - 0.35 * sin(u * PI)    # the string sags in the middle
			var c: Color = cols[k % 3]
			k += 1
			st.set_color(c)
			for v in [Vector3(x - 0.09, y, z), Vector3(x + 0.09, y, z), Vector3(x, y - 0.2, z)]:
				st.set_normal(Vector3(0, 0, 1))
				st.add_vertex(v)
			for v in [Vector3(x + 0.09, y, z), Vector3(x - 0.09, y, z), Vector3(x, y - 0.2, z)]:
				st.set_normal(Vector3(0, 0, -1))
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.8
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	root.add_child(mi)
	info["festival"].append(mi)


func _tag(id: String, node: Node3D, show := true) -> Node3D:
	var key := "upgrade_show" if show else "upgrade_hide"
	if not info[key].has(id):
		info[key][id] = []
	info[key][id].append(node)
	return node


func _group(name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	root.add_child(n)
	return n


# ------------------------------------------------------------------ shell
func _room() -> void:
	var g := _group("Room")
	var w := PubLayout.ROOM_MAX.x - PubLayout.ROOM_MIN.x
	var d := PubLayout.ROOM_MAX.y - PubLayout.ROOM_MIN.y
	var h := PubLayout.ROOM_H
	# floor & ceiling
	var fl := MeshKit.tiled_box(g, Vector3(w, 0.1, d), Vector3(0, -0.05, 0), MeshKit.mat("floor"))
	MeshKit.solid(g, Vector3(w + 2, 0.1, d + 2), Vector3(0, -0.05, 0))
	# an old pub ceiling: plaster yellowed by a century of turf smoke
	var ceil_mat := MeshKit.shader_mat("res://assets/shaders/plaster.gdshader", {"base_color": Color(0.46, 0.36, 0.23), "stain": 0.7,
		"room_ao": 1.0, "pattern": 1})
	MeshKit.tiled_box(g, Vector3(w, 0.1, d), Vector3(0, h + 0.05, 0), ceil_mat)
	# ceiling beams
	for i in 6:
		var x := PubLayout.ROOM_MIN.x + 1.2 + i * 2.3
		MeshKit.box(g, Vector3(0.22, 0.26, d), Vector3(x, h - 0.13, 0), MeshKit.mat("oak_z"))
	# walls: lower panelling/tiles + upper plaster. Two variants for the paint upgrade.
	# back wall has a doorway down to the cellar at x -6.7..-5.7
	var door_l := PubLayout.CELLAR_DOOR.x - 0.5
	var door_r := PubLayout.CELLAR_DOOR.x + 0.5
	var right_w := PubLayout.ROOM_MAX.x - door_r
	var walls := [
		# [centre, size, axis(0: faces z, 1: faces x)]
		[Vector3((PubLayout.ROOM_MIN.x + door_l) / 2.0, h / 2, PubLayout.ROOM_MIN.y), Vector3(door_l - PubLayout.ROOM_MIN.x, h, 0.2), 0],
		[Vector3(door_r + right_w / 2.0, h / 2, PubLayout.ROOM_MIN.y), Vector3(right_w, h, 0.2), 0],
		[Vector3(PubLayout.ROOM_MIN.x, h / 2, 0), Vector3(0.2, h, d), 1],
		[Vector3(PubLayout.ROOM_MAX.x, h / 2, 0), Vector3(0.2, h, d), 1],
	]
	for wd in walls:
		var c: Vector3 = wd[0]
		var s: Vector3 = wd[1]
		MeshKit.solid(g, s, c)
		_wall_skin(g, c, s, int(wd[2]))
	MeshKit.solid_box(g, Vector3(1.0, h - 2.2, 0.2), Vector3(PubLayout.CELLAR_DOOR.x, 2.2 + (h - 2.2) / 2.0, PubLayout.ROOM_MIN.y), MeshKit.mat("plaster_old"))
	for dx in [-0.52, 0.52]:
		MeshKit.box(g, Vector3(0.06, 2.2, 0.26), Vector3(PubLayout.CELLAR_DOOR.x + dx, 1.1, PubLayout.ROOM_MIN.y), MeshKit.mat("oak_y"))
	MeshKit.box(g, Vector3(1.1, 0.08, 0.26), Vector3(PubLayout.CELLAR_DOOR.x, 2.22, PubLayout.ROOM_MIN.y), MeshKit.mat("oak"))
	# partition behind the right end of the bar (back room wall)
	var px := PubLayout.PARTITION_X
	var pz := (PubLayout.ROOM_MIN.y + PubLayout.BAR_BACK_Z) / 2.0
	var pd := PubLayout.BAR_BACK_Z - PubLayout.ROOM_MIN.y
	MeshKit.solid(g, Vector3(0.15, h, pd), Vector3(px, h / 2, pz))
	MeshKit.box(g, Vector3(0.15, h, pd), Vector3(px, h / 2, pz), MeshKit.mat("oak_y"))
	# shadow gathered along the foot of each wall (cheap ambient occlusion)
	MeshKit.edge_shadow(g, Vector3(0, 0, PubLayout.ROOM_MIN.y + 0.1), w, Vector3(0, 0, 1))
	MeshKit.edge_shadow(g, Vector3(0, 0, PubLayout.ROOM_MAX.y - 0.13), w, Vector3(0, 0, -1))
	MeshKit.edge_shadow(g, Vector3(PubLayout.ROOM_MIN.x + 0.1, 0, 0), d, Vector3(1, 0, 0))
	MeshKit.edge_shadow(g, Vector3(PubLayout.ROOM_MAX.x - 0.1, 0, 0), d, Vector3(-1, 0, 0))
	# skirting
	MeshKit.box(g, Vector3(w, 0.14, 0.04), Vector3(0, 0.07, PubLayout.ROOM_MIN.y + 0.12), MeshKit.mat("oak"))
	MeshKit.box(g, Vector3(0.04, 0.14, d), Vector3(PubLayout.ROOM_MAX.x - 0.12, 0.07, 0), MeshKit.mat("oak_z"))
	MeshKit.box(g, Vector3(0.04, 0.14, d), Vector3(PubLayout.ROOM_MIN.x + 0.12, 0.07, 0), MeshKit.mat("oak_z"))


func _wall_skin(g: Node3D, c: Vector3, s: Vector3, axis: int) -> void:
	var inward := Vector3.ZERO
	if axis == 0:
		inward = Vector3(0, 0, 1) if c.z < 0 else Vector3(0, 0, -1)
	else:
		inward = Vector3(1, 0, 0) if c.x < 0 else Vector3(-1, 0, 0)
	var off := inward * 0.105
	var low_h := 1.15
	var up_h := s.y - low_h
	var thick := 0.01
	var low_size := Vector3(s.x, low_h, thick) if axis == 0 else Vector3(thick, low_h, s.z)
	var up_size := Vector3(s.x, up_h, thick) if axis == 0 else Vector3(thick, up_h, s.z)
	var low_pos := Vector3(c.x, low_h / 2, c.z) + off
	var up_pos := Vector3(c.x, low_h + up_h / 2, c.z) + off
	var old_low := MeshKit.tiled_box(g, low_size, low_pos, MeshKit.mat("tiles_old_z" if axis == 0 else "tiles_old_x"))
	var old_up := MeshKit.tiled_box(g, up_size, up_pos, MeshKit.mat("plaster_old"))
	var new_low := MeshKit.tiled_box(g, low_size, low_pos + inward * 0.002, MeshKit.mat("tiles_green_z" if axis == 0 else "tiles_green_x"))
	var new_up := MeshKit.tiled_box(g, up_size, up_pos + inward * 0.002, MeshKit.mat("plaster_new"))
	_tag("paint", old_low, false)
	_tag("paint", old_up, false)
	_tag("paint", new_low)
	_tag("paint", new_up)
	# dado rail
	var rail_size := Vector3(s.x, 0.06, 0.04) if axis == 0 else Vector3(0.04, 0.06, s.z)
	MeshKit.box(g, rail_size, Vector3(c.x, low_h, c.z) + inward * 0.12, MeshKit.mat("oak" if axis == 0 else "oak_z"))
	# picture rail
	MeshKit.box(g, rail_size * Vector3(1, 0.6, 1), Vector3(c.x, 2.6, c.z) + inward * 0.12, MeshKit.mat("oak" if axis == 0 else "oak_z"))


# ------------------------------------------------------------------ bar
func _bar() -> void:
	var g := _group("Bar")
	var x0 := PubLayout.BAR_X.x
	var x1 := PubLayout.BAR_X.y
	var len := x1 - x0
	var cx := (x0 + x1) / 2.0
	var zf := PubLayout.BAR_FRONT_Z
	var zb := PubLayout.BAR_BACK_Z
	var depth := zb - zf  # negative
	var cz := (zf + zb) / 2.0
	var top := PubLayout.BAR_TOP
	# body
	MeshKit.solid(g, Vector3(len, top, absf(depth)), Vector3(cx, top / 2, cz))
	MeshKit.box(g, Vector3(len, top - 0.06, absf(depth) - 0.1), Vector3(cx, (top - 0.06) / 2, cz - 0.03), MeshKit.mat("oak"))
	# raised panels on the customer side
	var panels := int(len / 0.9)
	for i in panels:
		var px := x0 + 0.45 + i * (len / panels)
		MeshKit.box(g, Vector3(len / panels - 0.16, 0.62, 0.03), Vector3(px, 0.52, zf + 0.01), MeshKit.mat("oak_y"))
		MeshKit.box(g, Vector3(0.05, top - 0.12, 0.05), Vector3(x0 + i * (len / panels), (top - 0.12) / 2, zf + 0.02), MeshKit.mat("oak_y"))
	# kick plinth & top
	MeshKit.box(g, Vector3(len, 0.12, 0.06), Vector3(cx, 0.06, zf + 0.04), MeshKit.mat("black_paint"))
	MeshKit.box(g, Vector3(len + 0.1, 0.06, absf(depth) + 0.16), Vector3(cx, top - 0.03, cz + 0.02), MeshKit.mat("bar_top"))
	MeshKit.cyl(g, 0.035, 0.035, len + 0.1, Vector3(cx, top - 0.035, zf + 0.1), MeshKit.mat("bar_top"), 10, Vector3(0, 0, PI / 2))
	# shade where the bar meets the floor, both sides
	MeshKit.edge_shadow(g, Vector3(cx, 0, zf), len, Vector3(0, 0, 1), 0.6, 0.5)
	MeshKit.edge_shadow(g, Vector3(cx, 0, zb), len, Vector3(0, 0, -1), 0.5, 0.45)
	# brass foot rail with brackets
	var rail := MeshKit.cyl(g, 0.025, 0.025, len, Vector3(cx, 0.2, zf + 0.25), MeshKit.mat("brass_dull"), 10, Vector3(0, 0, PI / 2))
	_tag("drip_tray", rail, false)
	var rail2 := MeshKit.cyl(g, 0.025, 0.025, len, Vector3(cx, 0.2, zf + 0.25), MeshKit.mat("brass"), 10, Vector3(0, 0, PI / 2))
	_tag("drip_tray", rail2)
	for i in 8:
		MeshKit.cyl(g, 0.012, 0.012, 0.3, Vector3(x0 + 0.5 + i * len / 8.0, 0.16, zf + 0.15), MeshKit.mat("brass_dull"), 6, Vector3(PI / 2.6, 0, 0))
	# bartender-side shelf under the counter
	MeshKit.box(g, Vector3(len - 0.2, 0.03, 0.4), Vector3(cx, 0.55, zb - 0.22), MeshKit.mat("oak"))
	# bar stools (customer side), set between the service spots so people stand at the bar beside them
	for x in PubLayout.BAR_SPOT_X:
		_stool(g, Vector3(x + 0.6, 0, zf + 0.42))
	# drip tray (old) vs brass drip tray (upgrade) under the taps
	var tray_old := MeshKit.box(g, Vector3(1.6, 0.025, 0.32), Vector3(-1.9, top + 0.012, PubLayout.TAP_Z - 0.08), MeshKit.mat("iron"))
	_tag("drip_tray", tray_old, false)
	var tray := MeshKit.box(g, Vector3(1.6, 0.025, 0.32), Vector3(-1.9, top + 0.012, PubLayout.TAP_Z - 0.08), MeshKit.mat("brass"))
	_tag("drip_tray", tray)
	# settling shelf slots (small brass rings)
	for s in PubLayout.SETTLE_SLOTS:
		MeshKit.cyl(g, 0.05, 0.05, 0.012, s + Vector3(0, 0.006, 0), MeshKit.mat("chrome"), 16)
	# till
	var till := Node3D.new()
	till.position = PubLayout.TILL_POS
	g.add_child(till)
	MeshKit.prop(till, "till")   # an old brass-and-enamel cash register, keys towards the bartender
	# tips jar
	MeshKit.cyl(g, 0.06, 0.055, 0.14, PubLayout.TILL_POS + Vector3(-0.38, 0.07, 0.05), MeshKit.color_mat(Color(0.8, 0.9, 0.9, 0.35), 0.05))
	MeshKit.label(g, "TIPS", PubLayout.TILL_POS + Vector3(-0.38, 0.08, 0.112), 28, Color(0.95, 0.85, 0.5), Vector3.ZERO, _title_font)
	# GALAGERS rubber drip mat under the taps and bar mats at the serving spots
	var flat := Vector3(-PI / 2, 0, 0)
	# ribbed black rubber drip mat over the tray, its GALAGERS print reading for the bartender
	var mat_pos := Vector3(-1.75, top + 0.028, PubLayout.TAP_Z - 0.08)
	MeshKit.box(g, Vector3(0.78, 0.008, 0.3), mat_pos, MeshKit.color_mat(Color(0.03, 0.03, 0.03), 0.75))
	for r in 9:
		MeshKit.box(g, Vector3(0.74, 0.004, 0.006), mat_pos + Vector3(0, 0.005, -0.12 + r * 0.03), MeshKit.color_mat(Color(0.06, 0.06, 0.06), 0.6))
	MeshKit.quad(g, Vector2(0.6, 0.225), mat_pos + Vector3(0, 0.0075, 0), MeshKit.print_mat(BRAND + "galagers_mirror.png", 0.0, 0.8), Vector3(-PI / 2, PI, 0))
	var mat_m := MeshKit.print_mat(BRAND + "galagers_keg.png", 0.0, 0.85)
	for x in PubLayout.BAR_SPOT_X:
		if absf(x - PubLayout.TILL_POS.x) < 0.5:
			continue
		MeshKit.quad(g, Vector2(0.44, 0.22), Vector3(x + 0.05, top + 0.002, zf - 0.17), mat_m, flat)
	var coaster := MeshKit.print_mat(BRAND + "galagers_coaster.png", 0.0, 0.9)
	for i in PubLayout.BAR_SPOT_X.size():
		var x: float = PubLayout.BAR_SPOT_X[i]
		MeshKit.quad(g, Vector2(0.095, 0.095), Vector3(x + 0.36, top + 0.003, zf - 0.12), coaster, Vector3(-PI / 2, i * 0.7, 0))


func _stool(g: Node3D, p: Vector3) -> void:
	var s := Node3D.new()
	s.position = p
	g.add_child(s)
	MeshKit.contact_shadow(s, Vector3.ZERO, Vector2(0.55, 0.55), 0.45)
	MeshKit.cyl(s, 0.19, 0.19, 0.06, Vector3(0, 0.76, 0), MeshKit.mat("leather_red"), 16)
	MeshKit.torus(s, 0.165, 0.2, Vector3(0, 0.76, 0), MeshKit.mat("leather_red"))  # rolled cushion edge
	MeshKit.cyl(s, 0.03, 0.03, 0.72, Vector3(0, 0.38, 0), MeshKit.mat("iron"), 8)
	MeshKit.torus(s, 0.13, 0.15, Vector3(0, 0.28, 0), MeshKit.mat("brass_dull"))
	MeshKit.cyl(s, 0.18, 0.2, 0.03, Vector3(0, 0.015, 0), MeshKit.mat("iron"), 16)
	MeshKit.solid(s, Vector3(0.36, 0.8, 0.36), Vector3(0, 0.4, 0))


# ------------------------------------------------------------------ taps
func _taps() -> void:
	var g := _group("Taps")
	_stout_tap(g)
	# lager tap font (visible once purchased)
	var lager := _lager_tap(g)
	_tag("lager_tap", lager)
	_tag("ale_pump", _ale_pump(g))
	_tag("drinks_fridge", _keg_font(g, "cider", "ORCHARD\nGATE", Color(0.75, 0.55, 0.15), Color(0.95, 0.85, 0.55)))
	_tag("drinks_fridge", _keg_font(g, "zero", "GALAGERS\n0.0", Color(0.05, 0.05, 0.05), Color(0.85, 0.7, 0.35)))
	_tag("whiskey_optics", _optic(g))
	_tag("soda_gun", _soda_gun(g))


func _station(g: Node3D, id: String, name: String) -> Node3D:
	var t := Node3D.new()
	t.name = name
	t.position = Vector3(PubLayout.TAP_X[id], PubLayout.BAR_TOP, PubLayout.TAP_Z)
	g.add_child(t)
	return t


func _register(id: String, t: Node3D, handle: Node3D, nozzle_h: float) -> void:
	info["taps"][id] = {"root": t, "handle": handle, "nozzle": t.position + Vector3(0, nozzle_h, -0.195), "glass": t.position + Vector3(0, 0.0, -0.195)}


## A hand-pulled beer engine: tall turned handle with a pump clip, brass swan neck over the glass.
func _ale_pump(g: Node3D) -> Node3D:
	var t := _station(g, "ale", "AlePump")
	MeshKit.box(t, Vector3(0.14, 0.05, 0.16), Vector3(0, 0.025, 0.02), MeshKit.mat("oak"))
	MeshKit.cyl(t, 0.035, 0.045, 0.12, Vector3(0, 0.11, 0.02), MeshKit.color_mat(Color(0.92, 0.9, 0.84), 0.25), 16)   # ceramic barrel
	MeshKit.torus(t, 0.03, 0.045, Vector3(0, 0.17, 0.02), MeshKit.mat("brass"))
	MeshKit.cyl(t, 0.012, 0.012, 0.2, Vector3(0, 0.2, -0.08), MeshKit.mat("brass"), 10, Vector3(PI / 2, 0, 0))
	MeshKit.cyl(t, 0.01, 0.012, 0.09, Vector3(0, 0.155, -0.195), MeshKit.mat("brass"), 10)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0.18, 0.02)
	t.add_child(pivot)
	MeshKit.cyl(pivot, 0.016, 0.024, 0.34, Vector3(0, 0.17, 0), MeshKit.mat("oak_y"), 12)
	MeshKit.sphere(pivot, 0.03, Vector3(0, 0.35, 0), MeshKit.mat("oak_y"))
	# pump clip: the ale's name, facing the customers
	MeshKit.box(pivot, Vector3(0.1, 0.12, 0.012), Vector3(0, 0.25, 0.03), MeshKit.color_mat(Color(0.5, 0.15, 0.06), 0.4))
	MeshKit.label(pivot, "RED\nFOX", Vector3(0, 0.25, 0.038), 20, Color(0.98, 0.85, 0.55), Vector3.ZERO, _title_font)
	_register("ale", t, pivot, 0.13)
	return t


## A slim keg font for the draught cider and the alcohol-free stout.
func _keg_font(g: Node3D, id: String, text: String, body: Color, trim: Color) -> Node3D:
	var t := _station(g, id, id.capitalize() + "Tap")
	MeshKit.cyl(t, 0.05, 0.06, 0.04, Vector3(0, 0.02, 0.02), MeshKit.mat("chrome"), 16)
	MeshKit.cyl(t, 0.045, 0.045, 0.28, Vector3(0, 0.18, 0.02), MeshKit.color_mat(body, 0.35, 0.2), 16)
	MeshKit.torus(t, 0.04, 0.05, Vector3(0, 0.31, 0.02), MeshKit.color_mat(trim, 0.3, 0.8))
	MeshKit.label(t, text, Vector3(0, 0.19, -0.03), 18, trim, Vector3(0, PI, 0), _title_font)
	MeshKit.label(t, text, Vector3(0, 0.19, 0.07), 18, trim, Vector3.ZERO, _title_font)
	MeshKit.cyl(t, 0.014, 0.014, 0.2, Vector3(0, 0.3, -0.11), MeshKit.mat("chrome"), 10, Vector3(PI / 2, 0, 0))
	MeshKit.cyl(t, 0.011, 0.014, 0.05, Vector3(0, 0.28, -0.195), MeshKit.mat("chrome"), 10)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0.34, -0.06)
	t.add_child(pivot)
	MeshKit.cyl(pivot, 0.016, 0.02, 0.15, Vector3(0, 0.075, 0), MeshKit.color_mat(body.lightened(0.15), 0.3), 10)
	_register(id, t, pivot, 0.255)
	return t


## A bar-top optic stand: the whiskey bottle upside down over a measure you push the glass into.
func _optic(g: Node3D) -> Node3D:
	var t := _station(g, "whiskey", "WhiskeyOptic")
	MeshKit.box(t, Vector3(0.16, 0.02, 0.16), Vector3(0, 0.01, -0.12), MeshKit.mat("brass_dull"))
	MeshKit.box(t, Vector3(0.03, 0.62, 0.03), Vector3(0, 0.31, 0.0), MeshKit.mat("brass_dull"))
	MeshKit.box(t, Vector3(0.03, 0.03, 0.22), Vector3(0, 0.6, -0.1), MeshKit.mat("brass_dull"))
	var bottle := Node3D.new()
	bottle.position = Vector3(0, 0.48, -0.195)
	t.add_child(bottle)
	MeshKit.cyl(bottle, 0.04, 0.04, 0.2, Vector3(0, 0.1, 0), MeshKit.color_mat(Color(0.55, 0.3, 0.08, 0.85), 0.1), 16)
	MeshKit.cyl(bottle, 0.014, 0.04, 0.05, Vector3(0, -0.02, 0), MeshKit.color_mat(Color(0.55, 0.3, 0.08, 0.85), 0.1), 16)
	MeshKit.box(bottle, Vector3(0.06, 0.07, 0.005), Vector3(0, 0.1, 0.041), MeshKit.color_mat(Color(0.92, 0.86, 0.7), 0.6))
	# the measure and its plunger: pushing the glass up lifts it
	MeshKit.cyl(t, 0.02, 0.02, 0.07, Vector3(0, 0.4, -0.195), MeshKit.color_mat(Color(0.9, 0.92, 0.95, 0.5), 0.05), 12)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0.36, -0.195)
	t.add_child(pivot)
	MeshKit.cyl(pivot, 0.012, 0.012, 0.03, Vector3(0, -0.015, 0), MeshKit.mat("chrome"), 10)
	_register("whiskey", t, pivot, 0.34)
	return t


## The soda gun in its holster, its hose running down behind the bar.
func _soda_gun(g: Node3D) -> Node3D:
	var t := _station(g, "soft", "SodaGun")
	MeshKit.box(t, Vector3(0.1, 0.02, 0.1), Vector3(0, 0.01, -0.12), MeshKit.mat("chrome"))
	MeshKit.box(t, Vector3(0.02, 0.36, 0.02), Vector3(0, 0.18, -0.12), MeshKit.mat("chrome"))
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0.3, -0.16)
	t.add_child(pivot)
	MeshKit.box(pivot, Vector3(0.05, 0.05, 0.12), Vector3(0, 0.02, -0.03), MeshKit.color_mat(Color(0.12, 0.12, 0.13), 0.4))
	for i in 3:
		MeshKit.cyl(pivot, 0.007, 0.007, 0.01, Vector3(-0.015 + i * 0.015, 0.05, -0.04), MeshKit.color_mat([Color(0.8, 0.2, 0.2), Color(0.95, 0.85, 0.2), Color(0.2, 0.6, 0.9)][i], 0.4), 8)
	MeshKit.cyl(t, 0.012, 0.012, 0.3, Vector3(0, 0.15, -0.05), MeshKit.color_mat(Color(0.15, 0.15, 0.15), 0.6), 8)
	_register("soft", t, pivot, 0.29)
	return t


func _stout_tap(g: Node3D) -> void:
	var t := Node3D.new()
	t.name = "StoutTap"
	t.position = Vector3(PubLayout.TAP_X["stout"], PubLayout.BAR_TOP, PubLayout.TAP_Z)
	g.add_child(t)
	# tall brass font
	MeshKit.cyl(t, 0.045, 0.06, 0.04, Vector3(0, 0.02, 0.02), MeshKit.mat("brass"), 16)
	MeshKit.cyl(t, 0.032, 0.04, 0.36, Vector3(0, 0.2, 0.02), MeshKit.mat("brass"), 16)
	MeshKit.sphere(t, 0.045, Vector3(0, 0.39, 0.02), MeshKit.mat("brass"))
	# spout arm towards the bartender
	MeshKit.cyl(t, 0.016, 0.016, 0.22, Vector3(0, 0.36, -0.09), MeshKit.mat("brass"), 10, Vector3(PI / 2, 0, 0))
	MeshKit.cyl(t, 0.012, 0.016, 0.06, Vector3(0, 0.33, -0.195), MeshKit.mat("brass"), 10)
	# handle pivots on top; rotate around x to pull forward
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0.42, 0.02)
	t.add_child(pivot)
	MeshKit.cyl(pivot, 0.012, 0.016, 0.06, Vector3(0, 0.03, 0), MeshKit.mat("brass"), 8)
	MeshKit.cyl(pivot, 0.022, 0.03, 0.2, Vector3(0, 0.16, 0), MeshKit.mat("black_paint"), 12)
	# GALAGERS badge on both faces of the handle, each in a polished brass bezel proud of the handle
	var bm := MeshKit.print_mat(BRAND + "galagers_badge.png", 0.0, 0.35)
	for side in [-1, 1]:
		var badge := MeshKit.cyl(pivot, 0.047, 0.047, 0.008, Vector3(0, 0.2, side * 0.032), MeshKit.mat("brass"), 24, Vector3(PI / 2, 0, 0))
		if side == -1:
			badge.name = "Badge"
		MeshKit.quad(pivot, Vector2(0.088, 0.088), Vector3(0, 0.2, side * 0.0365), bm, Vector3(0, 0.0 if side == 1 else PI, 0))
	# black collar and chrome cap on the brass font
	MeshKit.cyl(t, 0.043, 0.043, 0.03, Vector3(0, 0.30, 0.02), MeshKit.mat("black_paint"), 16)
	MeshKit.cyl(t, 0.02, 0.02, 0.012, Vector3(0, 0.425, 0.02), MeshKit.mat("chrome"), 12)
	info["taps"]["stout"] = {"root": t, "handle": pivot, "nozzle": t.position + Vector3(0, 0.30, -0.195), "glass": t.position + Vector3(0, 0.0, -0.195)}


func _lager_tap(g: Node3D) -> Node3D:
	var t := Node3D.new()
	t.name = "LagerTap"
	t.position = Vector3(PubLayout.TAP_X["lager"], PubLayout.BAR_TOP, PubLayout.TAP_Z)
	g.add_child(t)
	MeshKit.cyl(t, 0.05, 0.06, 0.04, Vector3(0, 0.02, 0.02), MeshKit.mat("chrome"), 16)
	MeshKit.box(t, Vector3(0.12, 0.3, 0.12), Vector3(0, 0.19, 0.02), MeshKit.color_mat(Color(0.7, 0.85, 0.75, 0.9), 0.1, 0, 0.0))
	MeshKit.label(t, "LOUGH\nGLAS", Vector3(0, 0.2, -0.042), 26, Color(0.05, 0.3, 0.15), Vector3(0, PI, 0), _title_font)
	MeshKit.cyl(t, 0.014, 0.014, 0.2, Vector3(0, 0.3, -0.11), MeshKit.mat("chrome"), 10, Vector3(PI / 2, 0, 0))
	MeshKit.cyl(t, 0.011, 0.014, 0.05, Vector3(0, 0.28, -0.195), MeshKit.mat("chrome"), 10)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0.34, -0.06)
	t.add_child(pivot)
	MeshKit.cyl(pivot, 0.016, 0.02, 0.16, Vector3(0, 0.08, 0), MeshKit.color_mat(Color(0.1, 0.35, 0.18), 0.3), 10)
	info["taps"]["lager"] = {"root": t, "handle": pivot, "nozzle": t.position + Vector3(0, 0.255, -0.195), "glass": t.position + Vector3(0, 0.0, -0.195)}
	return t


# ------------------------------------------------------------------ back bar
func _back_bar() -> void:
	var g := _group("BackBar")
	var z := PubLayout.BACK_COUNTER_Z
	var x0 := PubLayout.CELLAR_DOOR.x + 0.7
	var x1 := PubLayout.PARTITION_X - 0.1
	var len := x1 - x0
	var cx := (x0 + x1) / 2.0
	var top := PubLayout.BACK_COUNTER_TOP
	MeshKit.solid(g, Vector3(len, top, 0.7), Vector3(cx, top / 2, z))
	MeshKit.box(g, Vector3(len, top - 0.04, 0.68), Vector3(cx, (top - 0.04) / 2, z), MeshKit.mat("oak"))
	MeshKit.box(g, Vector3(len + 0.04, 0.05, 0.74), Vector3(cx, top - 0.02, z + 0.01), MeshKit.mat("bar_top"))
	# cupboard doors
	for i in int(len / 0.6):
		MeshKit.box(g, Vector3(0.52, 0.7, 0.02), Vector3(x0 + 0.3 + i * 0.6, 0.45, z + 0.35), MeshKit.mat("oak_y"))
		MeshKit.sphere(g, 0.015, Vector3(x0 + 0.5 + i * 0.6, 0.6, z + 0.37), MeshKit.mat("brass"))
	# mirror and shelving above
	var mirror := MeshKit.box(g, Vector3(len - 1.0, 1.0, 0.02), Vector3(cx - 0.4, 1.75, PubLayout.ROOM_MIN.y + 0.13), MeshKit.mat("mirror"))
	mirror.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for sy in [1.25, 1.75, 2.25]:
		MeshKit.box(g, Vector3(len - 0.6, 0.04, 0.3), Vector3(cx - 0.4, sy, PubLayout.ROOM_MIN.y + 0.28), MeshKit.mat("oak"))
	for sx in [x0 + 0.25, cx - 0.4 - (len - 0.6) / 2.0, cx - 0.4 + (len - 0.6) / 2.0]:
		MeshKit.box(g, Vector3(0.06, 1.6, 0.32), Vector3(sx, 1.8, PubLayout.ROOM_MIN.y + 0.28), MeshKit.mat("oak_y"))
	MeshKit.box(g, Vector3(len - 0.4, 0.2, 0.36), Vector3(cx - 0.4, 2.7, PubLayout.ROOM_MIN.y + 0.28), MeshKit.mat("oak"))
	# illuminated GALAGERS sign over the back bar, with its own warm glow
	var sign_pos := Vector3(cx - 0.4, 2.72, PubLayout.ROOM_MIN.y + 0.47)
	MeshKit.box(g, Vector3(1.08, 0.56, 0.05), sign_pos + Vector3(0, 0, -0.03), MeshKit.mat("brass_dull"))
	var sign := MeshKit.quad(g, Vector2(1.0, 0.5), sign_pos, MeshKit.print_mat(BRAND + "galagers_sign.png", 1.1, 0.3))
	sign.name = "GalagersSign"
	sign.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glow := OmniLight3D.new()
	glow.position = sign_pos + Vector3(0, -0.1, 0.35)
	glow.light_color = Color(1.0, 0.78, 0.45)
	glow.light_energy = 0.35
	glow.omni_range = 1.8
	g.add_child(glow)
	info["brand_sign"] = sign
	_bottles(g, Vector3(cx - 0.4, 0, PubLayout.ROOM_MIN.y + 0.28), len - 0.9)
	# glass rack on the back counter (washed glasses stand here upside down)
	var rack := Node3D.new()
	rack.position = PubLayout.RACK_POS
	g.add_child(rack)
	MeshKit.box(rack, Vector3(0.62, 0.015, 0.4), Vector3(0, 0.008, 0), MeshKit.color_mat(Color(0.05, 0.05, 0.05), 0.9))
	info["rack_glasses"] = rack
	for i in 24:
		var col := i % 6
		var row := i / 6
		info["rack_slots"].append(Vector3(-0.25 + col * 0.1, 0.015, -0.15 + row * 0.1))
	# sink with taps
	var sink := Node3D.new()
	sink.position = PubLayout.SINK_POS
	g.add_child(sink)
	MeshKit.box(sink, Vector3(0.6, 0.03, 0.45), Vector3(0, 0.005, 0), MeshKit.mat("chrome"))
	MeshKit.box(sink, Vector3(0.5, 0.02, 0.36), Vector3(0, 0.002, 0), MeshKit.color_mat(Color(0.18, 0.2, 0.22), 0.2, 0.8))
	MeshKit.cyl(sink, 0.012, 0.012, 0.25, Vector3(0, 0.13, -0.18), MeshKit.mat("chrome"), 8)
	MeshKit.cyl(sink, 0.01, 0.01, 0.12, Vector3(0, 0.25, -0.13), MeshKit.mat("chrome"), 8, Vector3(PI / 2, 0, 0))
	MeshKit.box(sink, Vector3(0.12, 0.08, 0.04), Vector3(0.22, 0.04, 0.0), MeshKit.color_mat(Color(0.2, 0.45, 0.3), 0.8))  # sponge
	for i in 6:
		info["sink_slots"].append(PubLayout.SINK_POS + Vector3(-0.32 - (i % 3) * 0.09, 0.0, -0.08 + (i / 3) * 0.12))
	MeshKit.label(g, "Wash up", PubLayout.SINK_POS + Vector3(0, 0.35, -0.25), 36, Color(0.9, 0.85, 0.7), Vector3.ZERO)


func _bottles(g: Node3D, base: Vector3, width: float) -> void:
	# three bottle shapes (spirit, wine, squat liqueur), each one batched MultiMesh
	var shapes := [
		{"p": [Vector2(0.0, 0.0), Vector2(0.036, 0.0), Vector2(0.038, 0.012), Vector2(0.038, 0.19), Vector2(0.034, 0.215),
			Vector2(0.016, 0.245), Vector2(0.013, 0.272), Vector2(0.0145, 0.3), Vector2(0.0, 0.3)], "l": [0.06, 0.15], "cap": 0.272},
		{"p": [Vector2(0.0, 0.0), Vector2(0.034, 0.0), Vector2(0.036, 0.012), Vector2(0.036, 0.17), Vector2(0.03, 0.2),
			Vector2(0.015, 0.235), Vector2(0.013, 0.29), Vector2(0.0145, 0.31), Vector2(0.0, 0.31)], "l": [0.05, 0.13], "cap": 0.255},
		{"p": [Vector2(0.0, 0.0), Vector2(0.045, 0.0), Vector2(0.047, 0.02), Vector2(0.047, 0.12), Vector2(0.035, 0.15),
			Vector2(0.016, 0.17), Vector2(0.014, 0.198), Vector2(0.016, 0.21), Vector2(0.0, 0.21)], "l": [0.035, 0.105], "cap": 0.19},
	]
	var glass := [Color(0.35, 0.15, 0.04), Color(0.08, 0.22, 0.09), Color(0.55, 0.3, 0.06), Color(0.7, 0.72, 0.7),
		Color(0.32, 0.05, 0.08), Color(0.12, 0.14, 0.24), Color(0.45, 0.32, 0.12)]
	var labels := [Color(0.93, 0.88, 0.75, 1.0), Color(0.08, 0.07, 0.07, 0.0), Color(0.75, 0.12, 0.1, 0.0),
		Color(0.9, 0.82, 0.55, 1.0), Color(0.1, 0.3, 0.18, 0.0), Color(0.95, 0.95, 0.92, 1.0)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 87
	var per := int(width / 0.1)
	var picks: Array = [[], [], []]
	for shelf_y in [1.27, 1.77]:
		var x := base.x - width / 2.0
		while x < base.x + width / 2.0:
			var k := rng.randi() % 3
			var s := rng.randf_range(0.9, 1.1)
			var t := Transform3D(Basis(Vector3.UP, rng.randf_range(-0.25, 0.25)).scaled(Vector3(s, s, s)),
				Vector3(x, shelf_y + 0.02, base.z + rng.randf_range(-0.04, 0.04)))
			picks[k].append([t, glass[rng.randi() % glass.size()], labels[rng.randi() % labels.size()]])
			x += 0.085 + (0.02 if k == 2 else 0.0) + rng.randf_range(0.0, 0.025)
	for k in 3:
		var sh: Dictionary = shapes[k]
		var mesh := MeshKit.lathe(PackedVector2Array(sh["p"]), 14, false)
		var mat := MeshKit.shader_mat("res://assets/shaders/bottle.gdshader", {"label_y0": sh["l"][0], "label_y1": sh["l"][1], "cap_y": sh["cap"]})
		mesh.surface_set_material(0, mat)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = picks[k].size()
		for i in picks[k].size():
			var pk: Array = picks[k][i]
			mm.set_instance_transform(i, pk[0])
			mm.set_instance_color(i, pk[1])
			mm.set_instance_custom_data(i, pk[2])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		g.add_child(mmi)


# ------------------------------------------------------------------ fireplace
func _fireplace() -> void:
	var g := _group("Fireplace")
	var p := PubLayout.FIREPLACE
	var stone := MeshKit.mat("hearth_stone")
	MeshKit.solid_box(g, Vector3(0.5, 1.4, 0.35), Vector3(p.x + 0.25, 0.7, p.z - 0.8), stone)
	MeshKit.solid_box(g, Vector3(0.5, 1.4, 0.35), Vector3(p.x + 0.25, 0.7, p.z + 0.8), stone)
	MeshKit.box(g, Vector3(0.55, 0.35, 1.95), Vector3(p.x + 0.27, 1.22, p.z), stone)
	MeshKit.box(g, Vector3(0.7, 0.1, 2.2), Vector3(p.x + 0.35, 1.45, p.z), MeshKit.mat("oak_z"))
	MeshKit.box(g, Vector3(0.1, 1.05, 1.25), Vector3(p.x + 0.12, 0.52, p.z), MeshKit.color_mat(Color(0.03, 0.025, 0.02), 1.0))
	MeshKit.box(g, Vector3(0.9, 0.04, 2.0), Vector3(p.x + 0.45, 0.02, p.z), MeshKit.mat("stone_floor"))
	MeshKit.solid(g, Vector3(0.6, 1.4, 1.9), Vector3(p.x + 0.3, 0.7, p.z))
	# a mantel clock on the shelf, facing the room
	MeshKit.prop(g, "mantel_clock", Vector3(p.x + 0.42, 1.5, p.z + 0.55), -PI / 2)
	# chimney breast above
	MeshKit.box(g, Vector3(0.4, 1.85, 1.9), Vector3(p.x + 0.2, 2.4, p.z), MeshKit.mat("hearth_stone"))   # the stone carries on up
	# ash (unlit) vs turf fire (upgrade)
	var ash := MeshKit.box(g, Vector3(0.4, 0.05, 0.7), Vector3(p.x + 0.35, 0.05, p.z), MeshKit.mat("ash"))
	_tag("fireplace", ash, false)
	var fire := Node3D.new()
	fire.position = Vector3(p.x + 0.35, 0.05, p.z)
	g.add_child(fire)
	for i in 5:
		MeshKit.box(fire, Vector3(0.12, 0.08, 0.22), Vector3((i % 2) * 0.1 - 0.05, 0.04 + (i / 2) * 0.06, -0.25 + i * 0.12), MeshKit.mat("turf"), Vector3(0, i * 0.5, 0.2))
	MeshKit.box(fire, Vector3(0.3, 0.04, 0.6), Vector3(0, 0.02, 0), MeshKit.mat("ember"))
	# flames: crossed vertical quads with an animated flame shader, a few tongues along the turf
	var tongues := [[Vector3(0.0, 0.05, -0.15), 0.42, 0.0], [Vector3(0.02, 0.05, 0.1), 0.5, 1.7],
		[Vector3(-0.03, 0.05, 0.27), 0.34, 3.1], [Vector3(0.03, 0.05, -0.3), 0.3, 4.4]]
	for tg in tongues:
		var base: Vector3 = tg[0]
		var hgt: float = tg[1]
		for k in 2:
			var fm := MeshKit.shader_mat("res://assets/shaders/flame.gdshader", {"seed": float(tg[2]) + k * 0.37, "speed": 0.9 + k * 0.2})
			var q := MeshKit.quad(fire, Vector2(hgt * 0.75, hgt), base + Vector3(0, hgt / 2.0, 0), fm, Vector3(0, PI / 2.0 + (k - 0.5) * 1.1, 0))
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# sparks that drift up the chimney
	var sparks := CPUParticles3D.new()
	sparks.amount = 14
	sparks.lifetime = 1.6
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sparks.emission_box_extents = Vector3(0.08, 0.02, 0.25)
	sparks.direction = Vector3(0, 1, 0)
	sparks.spread = 25.0
	sparks.gravity = Vector3(0, 0.4, 0)
	sparks.initial_velocity_min = 0.3
	sparks.initial_velocity_max = 0.8
	sparks.scale_amount_min = 0.4
	sparks.scale_amount_max = 1.0
	var sgrad := Gradient.new()
	sgrad.set_color(0, Color(1.0, 0.8, 0.4, 1.0))
	sgrad.set_color(1, Color(1.0, 0.25, 0.05, 0.0))
	sparks.color_ramp = sgrad
	var sq := QuadMesh.new()
	sq.size = Vector2(0.012, 0.012)
	sq.material = MeshKit.mat("fire")
	sparks.mesh = sq
	sparks.position.y = 0.15
	fire.add_child(sparks)
	# a faint wisp of smoke drawn up the flue
	var smoke := CPUParticles3D.new()
	smoke.amount = 6
	smoke.lifetime = 2.5
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	smoke.emission_box_extents = Vector3(0.05, 0.02, 0.2)
	smoke.direction = Vector3(-0.3, 1, 0)
	smoke.spread = 10.0
	smoke.gravity = Vector3(-0.1, 0.2, 0)
	smoke.initial_velocity_min = 0.15
	smoke.initial_velocity_max = 0.3
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 2.0
	var smg := Gradient.new()
	smg.set_color(0, Color(0.25, 0.22, 0.2, 0.0))
	smg.add_point(0.3, Color(0.25, 0.22, 0.2, 0.18))
	smg.set_color(2, Color(0.2, 0.2, 0.2, 0.0))
	smoke.color_ramp = smg
	var smm := StandardMaterial3D.new()
	smm.albedo_texture = load("res://assets/env/soft_puff.png")
	smm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smm.vertex_color_use_as_albedo = true
	smm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var smq := QuadMesh.new()
	smq.size = Vector2(0.25, 0.25)
	smq.material = smm
	smoke.mesh = smq
	smoke.position.y = 0.45
	fire.add_child(smoke)
	var light := OmniLight3D.new()
	light.position = Vector3(0.4, 0.5, 0)
	light.light_color = Color(1.0, 0.55, 0.22)
	light.light_energy = 1.6
	light.omni_range = 5.0
	fire.add_child(light)
	info["fire"] = fire
	info["fire_light"] = light
	_tag("fireplace", fire)
	# fireside sign of life: a basket of turf
	MeshKit.cyl(g, 0.2, 0.17, 0.3, Vector3(p.x + 0.45, 0.15, p.z + 1.25), MeshKit.color_mat(Color(0.4, 0.28, 0.12), 0.9), 12)
	for i in 4:
		MeshKit.box(g, Vector3(0.1, 0.07, 0.18), Vector3(p.x + 0.42 + (i % 2) * 0.06, 0.32, p.z + 1.2 + (i / 2) * 0.08), MeshKit.mat("turf"), Vector3(0, i, 0.3))


# ------------------------------------------------------------------ seating
func _seating() -> void:
	var g := _group("Seating")
	_table_round(g, Vector3(-4.4, 0, 0.9), 3)
	_table_round(g, Vector3(-3.0, 0, 3.4), 4)
	_table_round(g, Vector3(2.5, 0, 1.0), 4)
	_table_round(g, Vector3(2.6, 0, 3.6), 3)
	# fireside armchairs, angled towards the hearth
	_armchair(g, Vector3(-6.0, 0, 0.9), Vector3(0.4, 0, 1.3), Vector3(-6.1, 0.55, 1.55))
	_armchair(g, Vector3(-6.0, 0, 3.5), Vector3(0.4, 0, -1.3), Vector3(-6.1, 0.55, 2.85))
	# upholstered booth beside the bar's end (upgrade)
	var booths := _group("Booths")
	_tag("booths", booths)
	_booth(booths, Vector3(5.6, 0, -1.25))


func _table_round(g: Node3D, p: Vector3, seats: int) -> void:
	var t := Node3D.new()
	t.position = p
	g.add_child(t)
	MeshKit.contact_shadow(t, Vector3.ZERO, Vector2(1.5, 1.5), 0.5)
	MeshKit.prop(t, "pub_table")   # a turned pedestal table
	# a GALAGERS menu tent and a candle in an amber jar in the middle of the table
	var menu_m := MeshKit.print_mat(BRAND + "galagers_menu.png", 0.0, 0.8)
	for side in [-1, 1]:
		MeshKit.quad(t, Vector2(0.09, 0.135), Vector3(0.0, 0.83, side * 0.022), menu_m, Vector3(side * -0.33, 0.0 if side == 1 else PI, 0))
	MeshKit.cyl(t, 0.032, 0.03, 0.07, Vector3(0.1, 0.8, 0.06), MeshKit.color_mat(Color(0.75, 0.42, 0.12, 0.6), 0.1), 12)
	MeshKit.sphere(t, 0.012, Vector3(0.1, 0.84, 0.06), MeshKit.mat("bulb"), Vector3(0.7, 1.4, 0.7))
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.45
	shape.height = 0.8
	cs.shape = shape
	sb.add_child(cs)
	sb.position = Vector3(0, 0.4, 0)
	t.add_child(sb)
	var coaster := MeshKit.print_mat(BRAND + "galagers_coaster.png", 0.0, 0.9)
	for i in 2:
		var ca := TAU * (i + 0.3) / 2.0 + p.x
		MeshKit.quad(t, Vector2(0.095, 0.095), Vector3(sin(ca) * 0.22, 0.7665, cos(ca) * 0.22), coaster, Vector3(-PI / 2, ca, 0))
	for i in seats:
		var a := TAU * i / seats + 0.4
		var dir := Vector3(sin(a), 0, cos(a))
		var sp := p + dir * 0.78
		var yaw := atan2(dir.x, dir.z)
		_chair(g, sp, yaw)
		var tp := p + dir * 0.24 + Vector3(0, 0.765, 0)
		info["seats"].append({"pos": sp, "yaw": yaw, "table": tp, "kind": "chair", "sit_y": 0.0})


func _chair(g: Node3D, p: Vector3, yaw: float) -> void:
	var c := Node3D.new()
	c.position = p
	c.rotation.y = yaw
	g.add_child(c)
	MeshKit.contact_shadow(c, Vector3.ZERO, Vector2(0.65, 0.65), 0.45)
	MeshKit.prop(c, "pub_chair")   # a worn, dark-stained wooden chair, back away from the table
	MeshKit.solid(c, Vector3(0.44, 0.9, 0.44), Vector3(0, 0.45, 0))


func _armchair(g: Node3D, p: Vector3, face: Vector3, table_pos: Vector3) -> void:
	var yaw := atan2(-face.x, -face.z)
	var c := Node3D.new()
	c.position = p
	c.rotation.y = yaw
	g.add_child(c)
	MeshKit.contact_shadow(c, Vector3.ZERO, Vector2(1.1, 1.0), 0.55)
	MeshKit.prop(c, "fireside_chair")   # a green upholstered armchair
	MeshKit.solid(c, Vector3(0.8, 0.9, 0.75), Vector3(0, 0.45, 0))
	info["seats"].append({"pos": p, "yaw": yaw, "table": table_pos, "kind": "armchair", "sit_y": 0.0})
	# small side table for the glass
	MeshKit.cyl(g, 0.16, 0.16, 0.03, table_pos - Vector3(0, 0.015, 0), MeshKit.mat("oak"), 16)
	MeshKit.cyl(g, 0.025, 0.025, 0.55, Vector3(table_pos.x, 0.27, table_pos.z), MeshKit.mat("oak_y"), 8)


func _booth(g: Node3D, p: Vector3) -> void:
	# benches either side of a table, running along x
	var b := Node3D.new()
	b.position = p
	b.rotation.y = PI / 2.0
	g.add_child(b)
	var leather := MeshKit.mat("leather_red")
	MeshKit.contact_shadow(b, Vector3.ZERO, Vector2(1.8, 2.3), 0.5)
	for side in [-1, 1]:
		var z: float = side * 0.75
		MeshKit.box(b, Vector3(1.3, 0.12, 0.5), Vector3(0, 0.44, z), leather)
		MeshKit.box(b, Vector3(1.3, 0.4, 0.5), Vector3(0, 0.2, z), MeshKit.mat("oak"))
		MeshKit.box(b, Vector3(1.3, 1.0, 0.12), Vector3(0, 0.9, z + side * 0.25), MeshKit.mat("oak_y"))
		MeshKit.box(b, Vector3(1.25, 0.5, 0.06), Vector3(0, 0.8, z + side * 0.18), leather)
		MeshKit.solid(b, Vector3(1.3, 1.3, 0.62), Vector3(0, 0.65, z + side * 0.06))
	MeshKit.box(b, Vector3(1.1, 0.05, 0.6), Vector3(0, 0.74, 0), MeshKit.mat("bar_top"))
	MeshKit.box(b, Vector3(0.1, 0.72, 0.1), Vector3(0, 0.36, 0), MeshKit.mat("iron"))
	MeshKit.solid(b, Vector3(1.1, 0.8, 0.6), Vector3(0, 0.4, 0))
	var lamp := MeshKit.sphere(b, 0.08, Vector3(0.0, 1.5, 0), MeshKit.mat("lamp_shade"))
	lamp.scale = Vector3(1, 0.7, 1)
	for side in [-1, 1]:
		for k in 2:
			var local_seat := Vector3(-0.3 + k * 0.6, 0, side * 0.62)
			var local_table := Vector3(-0.3 + k * 0.6, 0.765, side * 0.15)
			var face_local := Vector3(0, 0, -side)
			var face: Vector3 = b.transform.basis * face_local
			info["seats"].append({"pos": b.transform * local_seat, "yaw": atan2(-face.x, -face.z),
				"table": b.transform * local_table, "kind": "booth", "sit_y": 0.0, "upgrade": "booths"})


# ------------------------------------------------------------------ front wall, door, windows
func _front_wall() -> void:
	var g := _group("FrontWall")
	var z := PubLayout.ROOM_MAX.y
	var h := PubLayout.ROOM_H
	var door_w := 1.3
	var door_h := 2.3
	# wall segments around door and two windows (x: -4.2 and 3.6, 1.6 wide)
	var segs := [
		[PubLayout.ROOM_MIN.x, -5.0], [-3.4, -door_w / 2.0], [door_w / 2.0, 2.8], [4.4, PubLayout.ROOM_MAX.x],
	]
	for s in segs:
		var w: float = s[1] - s[0]
		var cx: float = (s[0] + s[1]) / 2.0
		MeshKit.solid(g, Vector3(w, h, 0.25), Vector3(cx, h / 2, z))
		var inner := Vector3(w, h, 0.01)
		var a := MeshKit.box(g, Vector3(w, 1.15, 0.01), Vector3(cx, 0.575, z - 0.13), MeshKit.mat("tiles_old_z"))
		var b := MeshKit.box(g, Vector3(w, h - 1.15, 0.01), Vector3(cx, 1.15 + (h - 1.15) / 2, z - 0.13), MeshKit.mat("plaster_old"))
		var a2 := MeshKit.box(g, Vector3(w, 1.15, 0.01), Vector3(cx, 0.575, z - 0.132), MeshKit.mat("tiles_green_z"))
		var b2 := MeshKit.box(g, Vector3(w, h - 1.15, 0.01), Vector3(cx, 1.15 + (h - 1.15) / 2, z - 0.132), MeshKit.mat("plaster_new"))
		_tag("paint", a, false)
		_tag("paint", b, false)
		_tag("paint", a2)
		_tag("paint", b2)
		# exterior skin: painted render
		MeshKit.box(g, Vector3(w, h, 0.01), Vector3(cx, h / 2, z + 0.13), MeshKit.mat("render_wall"))
	# over door / windows lintels and sills
	for span in [[-5.0, -3.4], [-door_w / 2.0, door_w / 2.0], [2.8, 4.4]]:
		var w: float = span[1] - span[0]
		var cx: float = (span[0] + span[1]) / 2.0
		var bottom := door_h if span[0] == -door_w / 2.0 else 2.4
		MeshKit.solid_box(g, Vector3(w, h - bottom, 0.25), Vector3(cx, bottom + (h - bottom) / 2, z), MeshKit.mat("render_wall"))
		if span[0] != -door_w / 2.0:
			MeshKit.solid_box(g, Vector3(w, 0.9, 0.25), Vector3(cx, 0.45, z), MeshKit.mat("oak"))
			_window(g, Vector3(cx, 1.65, z), Vector2(w, 1.5))
	# door (swings away from whoever walks through it; animated by the world)
	var door_pivot := Node3D.new()
	door_pivot.position = Vector3(-door_w / 2.0 + 0.02, 0, z - 0.05)
	g.add_child(door_pivot)
	# a glazed door: painted stiles and rails, a panelled kick plate, and one big pane of glass
	var dw := door_w - 0.04
	var dh := door_h - 0.02
	var paint := MeshKit.mat("green_paint")
	var stile := 0.11
	var glass_y0 := 0.78
	var glass_y1 := dh - 0.14
	MeshKit.box(door_pivot, Vector3(stile, dh, 0.06), Vector3(stile / 2.0, dh / 2.0, 0), paint)
	MeshKit.box(door_pivot, Vector3(stile, dh, 0.06), Vector3(dw - stile / 2.0, dh / 2.0, 0), paint)
	MeshKit.box(door_pivot, Vector3(dw, dh - glass_y1, 0.06), Vector3(dw / 2.0, (glass_y1 + dh) / 2.0, 0), paint)
	MeshKit.box(door_pivot, Vector3(dw, glass_y0, 0.06), Vector3(dw / 2.0, glass_y0 / 2.0, 0), paint)
	for side in [-1, 1]:
		# a raised panel on the kick plate and a slim moulding round the glass, both faces
		MeshKit.box(door_pivot, Vector3(dw - 0.36, glass_y0 - 0.3, 0.012), Vector3(dw / 2.0, glass_y0 / 2.0, side * 0.034), paint)
		MeshKit.box(door_pivot, Vector3(dw - 2.0 * stile + 0.03, 0.025, 0.012), Vector3(dw / 2.0, glass_y0, side * 0.034), MeshKit.mat("brass_dull"))
	var pane := MeshKit.box(door_pivot, Vector3(dw - 2.0 * stile, glass_y1 - glass_y0, 0.012), Vector3(dw / 2.0, (glass_y0 + glass_y1) / 2.0, 0),
		MeshKit.color_mat(Color(0.78, 0.86, 0.88, 0.14), 0.04, 0.3))
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the pub's name in gold leaf on the outside of the glass
	var gilt := MeshKit.label(door_pivot, GameState.pub_name.to_upper(), Vector3(dw / 2.0, glass_y1 - 0.12, 0.009), 30, Color(0.95, 0.78, 0.35), Vector3.ZERO, _title_font)
	gilt.pixel_size = 0.0014
	gilt.outline_size = 4
	gilt.outline_modulate = Color(0.25, 0.15, 0.05)
	info["door_gilt"] = gilt
	# brass push plate inside, pull handle outside
	MeshKit.box(door_pivot, Vector3(0.08, 0.28, 0.006), Vector3(dw - 0.18, 1.05, -0.034), MeshKit.mat("brass"))
	MeshKit.cyl(door_pivot, 0.013, 0.013, 0.3, Vector3(dw - 0.18, 1.05, 0.08), MeshKit.mat("brass"), 10)
	for dy in [-0.13, 0.13]:
		MeshKit.cyl(door_pivot, 0.008, 0.008, 0.05, Vector3(dw - 0.18, 1.05 + dy, 0.055), MeshKit.mat("brass"), 8, Vector3(PI / 2, 0, 0))
	info["door"] = door_pivot
	# door frame
	MeshKit.box(g, Vector3(0.08, door_h, 0.28), Vector3(-door_w / 2.0, door_h / 2.0, z), MeshKit.mat("oak_y"))
	MeshKit.box(g, Vector3(0.08, door_h, 0.28), Vector3(door_w / 2.0, door_h / 2.0, z), MeshKit.mat("oak_y"))
	# the OPEN / CLOSED sign hangs on two cords in the door's glass and flips over (it swings
	# with the door); the same word is on both faces, so it reads right from inside and out
	var hook := Node3D.new()
	hook.position = Vector3(door_w / 2.0, glass_y1 - 0.05, -0.045)      # just inside the glass
	door_pivot.add_child(hook)
	MeshKit.cyl(hook, 0.008, 0.008, 0.01, Vector3.ZERO, MeshKit.mat("brass"), 8, Vector3(PI / 2, 0, 0))
	var flip := Node3D.new()
	flip.position = Vector3(0, -0.36, -0.01)
	hook.add_child(flip)
	for sx in [-0.15, 0.15]:
		MeshKit.cyl(hook, 0.0025, 0.0025, 0.28, Vector3(sx * 0.6, -0.14, -0.01), MeshKit.color_mat(Color(0.75, 0.62, 0.35), 0.8), 4, Vector3(0, 0, sx * 1.0))
	MeshKit.box(flip, Vector3(0.42, 0.2, 0.012), Vector3.ZERO, MeshKit.color_mat(Color(0.08, 0.07, 0.06), 0.5))
	MeshKit.box(flip, Vector3(0.44, 0.22, 0.008), Vector3.ZERO, MeshKit.mat("brass_dull"))
	# OPEN on one face, CLOSED on the other; the board is turned so the street reads the pub's state
	var labels := []
	for side in [1, -1]:
		var open_face: bool = side == 1
		var lbl := MeshKit.label(flip, "OPEN" if open_face else "CLOSED", Vector3(0, 0, side * 0.0075), 52,
			Color(0.45, 0.95, 0.55) if open_face else Color(0.92, 0.3, 0.2), Vector3(0, 0.0 if side == 1 else PI, 0), _title_font)
		lbl.pixel_size = 0.0019
		labels.append(lbl)
	flip.rotation.y = PI      # starts the day CLOSED to the street
	info["door_sign"] = flip
	info["door_sign_labels"] = labels
	# coat hooks
	for i in 4:
		MeshKit.cyl(g, 0.01, 0.01, 0.08, Vector3(-2.4 + i * 0.22, 1.7, z - 0.17), MeshKit.mat("brass"), 6, Vector3(PI / 2.5, 0, 0))


func _window(g: Node3D, c: Vector3, size: Vector2) -> void:
	var glass_m := MeshKit.shader_mat("res://assets/shaders/window_rain.gdshader")
	info["window_mats"].append(glass_m)
	MeshKit.box(g, Vector3(size.x - 0.1, size.y - 0.1, 0.02), c, glass_m)
	MeshKit.solid(g, Vector3(size.x, size.y, 0.1), c)
	# glazing bars
	var frame := MeshKit.mat("cream")
	MeshKit.box(g, Vector3(size.x, 0.06, 0.1), c + Vector3(0, size.y / 2.0, 0), frame)
	MeshKit.box(g, Vector3(size.x, 0.08, 0.14), c - Vector3(0, size.y / 2.0, 0), frame)
	MeshKit.box(g, Vector3(0.05, size.y, 0.08), c, frame)
	MeshKit.box(g, Vector3(size.x, 0.04, 0.08), c + Vector3(0, size.y * 0.15, 0), frame)
	for sx in [-1, 1]:
		MeshKit.box(g, Vector3(0.06, size.y, 0.1), c + Vector3(sx * size.x / 2.0, 0, 0), frame)
	# half-height café curtain on a brass rod (inside)
	MeshKit.cyl(g, 0.012, 0.012, size.x - 0.02, c + Vector3(0, -0.1, -0.12), MeshKit.mat("brass"), 8, Vector3(0, 0, PI / 2))
	for sx in [-1, 1]:
		MeshKit.sphere(g, 0.022, c + Vector3(sx * (size.x / 2.0 - 0.01), -0.1, -0.12), MeshKit.mat("brass"))   # finials
	MeshKit.quad(g, Vector2(size.x - 0.08, 0.6), c + Vector3(0, -0.42, -0.12), MeshKit.shader_mat("res://assets/shaders/lace.gdshader"))


# ------------------------------------------------------------------ decor
func _decor() -> void:
	var g := _group("Decor")
	# framed photographs (procedural sepia landscapes) on the left wall
	for i in 5:
		var p := Vector3(PubLayout.ROOM_MIN.x + 0.13, 1.8 + (i % 2) * 0.35, -0.8 + i * 0.75)
		if absf(p.z - PubLayout.FIREPLACE.z) < 1.1:
			p.y = 2.15
		_photo(g, p, Vector3(0, PI / 2, 0), 1000 + i, Vector2(0.38, 0.28))
	for i in 3:
		_photo(g, Vector3(PubLayout.ROOM_MAX.x - 0.13, 2.0, 2.5 + i * 0.7), Vector3(0, -PI / 2, 0), 2000 + i, Vector2(0.32, 0.4))
	# shelf with old jugs over the right wall
	MeshKit.box(g, Vector3(0.25, 0.04, 2.2), Vector3(PubLayout.ROOM_MAX.x - 0.22, 2.55, -1.6), MeshKit.mat("oak_z"))
	for i in 6:
		var jug := MeshKit.cyl(g, 0.05, 0.07, 0.16, Vector3(PubLayout.ROOM_MAX.x - 0.22, 2.65, -2.5 + i * 0.36), MeshKit.color_mat(Color(0.75, 0.68, 0.55).darkened(0.1 * (i % 3)), 0.5), 12)
	# notice board with local notices
	var nb := Node3D.new()
	nb.position = Vector3(-2.95, 1.55, PubLayout.ROOM_MAX.y - 0.16)      # clear of the coat hooks
	nb.rotation.y = PI
	g.add_child(nb)
	MeshKit.box(nb, Vector3(0.8, 0.6, 0.03), Vector3.ZERO, MeshKit.color_mat(Color(0.55, 0.4, 0.25), 0.95))
	var notes := ["Lost: one grey cat,\nanswers to Biscuit", "Tidy Towns meeting\nThursday 7pm", "Trad session\nSundays (soon!)", "Turf for sale\nask Eamon"]
	for i in notes.size():
		var np := Vector3(-0.22 + (i % 2) * 0.42, 0.13 - (i / 2) * 0.27, 0.02)
		MeshKit.box(nb, Vector3(0.3, 0.2, 0.004), np, MeshKit.mat("paper"), Vector3(0, 0, (i - 1.5) * 0.04))
		var lb := MeshKit.label(nb, notes[i], np + Vector3(0, 0, 0.004), 20, Color(0.15, 0.12, 0.1))
		lb.pixel_size = 0.0008
	# GALAGERS posters in oak frames on the front wall, and an etched brand mirror on the right wall
	for ps in [[BRAND + "galagers_poster_pint.png", Vector3(-6.0, 1.95, PubLayout.ROOM_MAX.y - 0.14)],
			[BRAND + "galagers_poster_tune.png", Vector3(5.3, 1.95, PubLayout.ROOM_MAX.y - 0.14)]]:
		var pp: Vector3 = ps[1]
		MeshKit.box(g, Vector3(0.58, 0.83, 0.025), pp + Vector3(0, 0, 0.012), MeshKit.mat("oak_y"))
		MeshKit.quad(g, Vector2(0.5, 0.75), pp - Vector3(0, 0, 0.002), MeshKit.print_mat(str(ps[0]), 0.0, 0.7), Vector3(0, PI, 0))
	var mp := Vector3(PubLayout.ROOM_MAX.x - 0.14, 1.88, -1.55)
	MeshKit.box(g, Vector3(0.03, 0.54, 1.3), mp + Vector3(0.012, 0, 0), MeshKit.mat("oak_y"))
	MeshKit.box(g, Vector3(0.01, 0.46, 1.22), mp, MeshKit.mat("mirror"))
	MeshKit.quad(g, Vector2(1.16, 0.435), mp - Vector3(0.007, 0, 0), MeshKit.print_mat(BRAND + "galagers_mirror.png", 0.0, 0.2), Vector3(0, -PI / 2, 0))
	# brass wall sconces with tulip shades, each throwing a fan of warm light up and down the wall
	var wash_m := MeshKit.shader_mat("res://assets/shaders/wall_wash.gdshader")
	var shade_m := MeshKit.color_mat(Color(1.0, 0.9, 0.72), 0.3)
	(shade_m as StandardMaterial3D).emission_enabled = true
	(shade_m as StandardMaterial3D).emission = Color(1.0, 0.78, 0.5)
	(shade_m as StandardMaterial3D).emission_energy_multiplier = 1.6
	for sc in [[Vector3(PubLayout.ROOM_MIN.x + 0.11, 2.0, -2.6), 1], [Vector3(PubLayout.ROOM_MIN.x + 0.11, 2.05, 3.85), 1],
			[Vector3(PubLayout.ROOM_MAX.x - 0.11, 2.0, 1.55), -1], [Vector3(PubLayout.ROOM_MAX.x - 0.11, 2.0, -3.75), -1]]:
		var sp: Vector3 = sc[0]
		var out := Vector3(float(sc[1]), 0, 0)
		var sconce := Node3D.new()
		sconce.position = sp
		sconce.rotation.y = PI / 2.0 if int(sc[1]) == 1 else -PI / 2.0     # local +z points into the room
		g.add_child(sconce)
		MeshKit.cyl(sconce, 0.045, 0.045, 0.02, Vector3(0, 0, 0.0), MeshKit.mat("brass"), 14, Vector3(PI / 2, 0, 0))
		MeshKit.cyl(sconce, 0.008, 0.008, 0.14, Vector3(0, -0.02, 0.07), MeshKit.mat("brass"), 6, Vector3(PI / 2 - 0.35, 0, 0))
		MeshKit.cyl(sconce, 0.07, 0.035, 0.11, Vector3(0, 0.05, 0.14), shade_m, 14)
		MeshKit.torus(sconce, 0.066, 0.074, Vector3(0, 0.105, 0.14), MeshKit.mat("brass"))
		MeshKit.halo(sconce, Vector3(0, 0.06, 0.14), 0.42, Color(1.0, 0.75, 0.45, 0.5))
		var wash := MeshKit.quad(g, Vector2(1.3, 1.9), sp + out * 0.015 + Vector3(0, 0.05, 0), wash_m,
			Vector3(0, PI / 2.0 if int(sc[1]) == 1 else -PI / 2.0, 0))
		wash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# a patterned hearth rug in front of the fire
	var rug := Vector3(PubLayout.FIREPLACE.x + 1.45, 0.006, PubLayout.FIREPLACE.z)
	MeshKit.contact_shadow(g, rug, Vector2(1.4, 2.0), 0.25)
	MeshKit.quad(g, Vector2(1.1, 1.7), rug, MeshKit.shader_mat("res://assets/shaders/rug.gdshader"), Vector3(-PI / 2, 0, 0))
	# the brass bell for last orders, on a bracket behind the bar
	var bell_p := Vector3(2.6, 2.05, PubLayout.ROOM_MIN.y + 0.2)
	MeshKit.box(g, Vector3(0.04, 0.04, 0.22), bell_p + Vector3(0, 0.14, 0.0), MeshKit.mat("iron"))
	MeshKit.cyl(g, 0.02, 0.075, 0.11, bell_p, MeshKit.mat("brass"), 16)
	MeshKit.sphere(g, 0.012, bell_p + Vector3(0, -0.065, 0), MeshKit.mat("brass_dull"))
	MeshKit.cyl(g, 0.003, 0.003, 0.5, bell_p + Vector3(0, -0.3, 0.02), MeshKit.color_mat(Color(0.75, 0.68, 0.5), 0.9), 4)
	# two hurleys crossed on the wall above the booth, with a sliotar
	var hw := Vector3(PubLayout.ROOM_MAX.x - 0.15, 2.0, -0.6)
	var ash := MeshKit.color_mat(Color(0.78, 0.66, 0.46), 0.5)
	for k in [-1, 1]:
		var hurl := Node3D.new()
		hurl.position = hw
		hurl.rotation = Vector3(k * 0.7, -PI / 2.0, 0)
		g.add_child(hurl)
		MeshKit.box(hurl, Vector3(0.035, 0.75, 0.025), Vector3(0, 0.15, 0), ash)
		MeshKit.sphere(hurl, 0.06, Vector3(0, -0.27, 0.0), ash, Vector3(1.4, 1.8, 0.4))
		MeshKit.box(hurl, Vector3(0.04, 0.12, 0.03), Vector3(0, 0.45, 0), MeshKit.color_mat(Color(0.1, 0.1, 0.1), 0.7))
	MeshKit.sphere(g, 0.036, hw + Vector3(-0.02, -0.38, 0), MeshKit.color_mat(Color(0.92, 0.9, 0.84), 0.6))
	# a folded newspaper and a stack of GALAGERS beer mats at the end of the bar
	var bar_end := Vector3(PubLayout.BAR_X.y - 0.45, PubLayout.BAR_TOP + 0.004, PubLayout.BAR_FRONT_Z - 0.3)
	MeshKit.box(g, Vector3(0.3, 0.008, 0.21), bar_end, MeshKit.shader_mat("res://assets/shaders/newsprint.gdshader"), Vector3(0, 0.25, 0))
	for k in 6:
		MeshKit.cyl(g, 0.047, 0.047, 0.003, bar_end + Vector3(0.3, 0.002 + k * 0.0032, 0.08), MeshKit.color_mat(Color(0.93, 0.88, 0.76), 0.9), 14)
	MeshKit.quad(g, Vector2(0.094, 0.094), bar_end + Vector3(0.3, 0.0215, 0.08), MeshKit.print_mat(BRAND + "galagers_coaster.png", 0.0, 0.9), Vector3(-PI / 2, 0.4, 0))
	# framed menu board on the back wall, right of the shelving
	var mb := Vector3(3.05, 1.85, PubLayout.ROOM_MIN.y + 0.13)
	MeshKit.box(g, Vector3(0.5, 0.73, 0.03), mb, MeshKit.mat("oak_y"))
	MeshKit.quad(g, Vector2(0.44, 0.66), mb + Vector3(0, 0, 0.017), MeshKit.print_mat(BRAND + "galagers_menu.png", 0.0, 0.7))
	# coats and a flat cap on the hooks by the door, an umbrella stand
	# a tweed overcoat and a waxed jacket hang flat against the wall by their collars: a body
	# widening to the hem with soft folds, the sleeves hanging down the front
	var coat_mats := [MeshKit.shader_mat("res://assets/shaders/cloth.gdshader", {"base_color": Color(0.26, 0.2, 0.13)}),
		MeshKit.shader_mat("res://assets/shaders/cloth.gdshader", {"base_color": Color(0.1, 0.13, 0.1), "sheen": 0.7, "weave": 0.3})]
	for i in 2:
		var coat := Node3D.new()
		coat.position = Vector3(-2.4 + i * 0.44, 1.71, PubLayout.ROOM_MAX.y - 0.2)
		coat.rotation.z = [0.03, -0.05][i]
		g.add_child(coat)
		var cm: Material = coat_mats[i]
		var long_k := 1.0 if i == 0 else 0.75
		var len_c := 0.95 * long_k
		# a four-sided frustum turned square-on to the wall: narrow shoulders, wide hem, thin
		var body := MeshKit.cyl(coat, 0.15, 0.24, len_c, Vector3(0, -0.06 - len_c / 2.0, -0.04), cm, 4, Vector3(0, PI / 4.0, 0))
		body.scale = Vector3(1.0, 1.0, 0.28)
		body.rotation.y = PI / 4.0
		var collar := MeshKit.cyl(coat, 0.05, 0.11, 0.08, Vector3(0, -0.04, -0.03), cm, 4)
		collar.rotation.y = PI / 4.0
		collar.scale = Vector3(1.0, 1.0, 0.45)
		for sx in [-1, 1]:
			var sl := MeshKit.cyl(coat, 0.035, 0.05, 0.6 * long_k, Vector3(sx * 0.12, -0.12 - 0.3 * long_k, -0.075), cm, 8)
			sl.rotation.z = sx * 0.1
	MeshKit.cyl(g, 0.11, 0.12, 0.05, Vector3(-2.18, 1.73, PubLayout.ROOM_MAX.y - 0.2), MeshKit.color_mat(Color(0.3, 0.28, 0.22), 0.9), 14)
	var us := Vector3(-0.95, 0, PubLayout.ROOM_MAX.y - 0.3)
	MeshKit.contact_shadow(g, us, Vector2(0.4, 0.4), 0.5)
	MeshKit.cyl(g, 0.11, 0.1, 0.5, us + Vector3(0, 0.25, 0), MeshKit.mat("brass_dull"), 16)
	for i in 3:
		var a := i * 2.1
		MeshKit.cyl(g, 0.012, 0.03, 0.8, us + Vector3(sin(a) * 0.05, 0.45, cos(a) * 0.05), MeshKit.color_mat([Color(0.1, 0.1, 0.12), Color(0.45, 0.08, 0.08), Color(0.08, 0.2, 0.12)][i], 0.6), 8, Vector3(sin(a) * 0.12, 0, cos(a) * 0.12))
	# chalkboard (upgrade)
	var cb := Node3D.new()
	cb.position = Vector3(1.9, 1.7, PubLayout.ROOM_MAX.y - 0.16)
	cb.rotation.y = PI
	g.add_child(cb)
	MeshKit.box(cb, Vector3(0.9, 1.1, 0.03), Vector3.ZERO, MeshKit.mat("chalk"))
	MeshKit.box(cb, Vector3(0.96, 1.16, 0.02), Vector3(0, 0, -0.01), MeshKit.mat("oak_y"))
	var cl := MeshKit.label(cb, "Tonight\n~\nGalagers Irish Stout\nperfectly poured\n\nTrad & tunes\ncoming soon", Vector3(0, 0, 0.02), 34, Color(0.95, 0.95, 0.9), Vector3.ZERO, _title_font)
	cl.pixel_size = 0.0016
	info["chalkboard_label"] = cl
	_tag("chalkboard", cb)
	# a shamrock wreath above the back bar and a clock
	var clock := Node3D.new()
	clock.position = Vector3(-5.5, 2.45, PubLayout.ROOM_MIN.y + 0.14)
	g.add_child(clock)
	MeshKit.cyl(clock, 0.2, 0.2, 0.05, Vector3.ZERO, MeshKit.mat("oak"), 24, Vector3(PI / 2, 0, 0))
	MeshKit.cyl(clock, 0.17, 0.17, 0.052, Vector3.ZERO, MeshKit.mat("cream"), 24, Vector3(PI / 2, 0, 0))
	var hh := Node3D.new()
	hh.position = Vector3(0, 0, 0.03)
	clock.add_child(hh)
	MeshKit.box(hh, Vector3(0.012, 0.09, 0.005), Vector3(0, 0.045, 0), MeshKit.mat("black_paint"))
	var mh := Node3D.new()
	mh.position = Vector3(0, 0, 0.034)
	clock.add_child(mh)
	MeshKit.box(mh, Vector3(0.008, 0.14, 0.005), Vector3(0, 0.07, 0), MeshKit.mat("black_paint"))
	info["clock_hands"] = [hh, mh]
	# cobweb-y crates in the empty snug corner (cleared by the stage upgrade later)
	var crates := _group("Crates")
	for i in 3:
		MeshKit.box(crates, Vector3(0.5, 0.35, 0.4), Vector3(6.2 - (i % 2) * 0.55, 0.175 + (i / 2) * 0.35, 4.2), MeshKit.mat("pale_wood"), Vector3(0, i * 0.2, 0))
	MeshKit.solid(crates, Vector3(1.2, 0.8, 0.6), Vector3(5.95, 0.4, 4.2))
	_tag("snug_stage", crates, false)


func _photo(g: Node3D, p: Vector3, rot: Vector3, seed_v: int, size: Vector2) -> void:
	var f := Node3D.new()
	f.position = p
	f.rotation = rot
	g.add_child(f)
	MeshKit.box(f, Vector3(size.x + 0.06, size.y + 0.06, 0.025), Vector3.ZERO, MeshKit.mat("photo_frame"))
	var tex := ImageTexture.create_from_image(make_photo(seed_v, size.x > size.y))
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 0.4
	MeshKit.quad(f, size, Vector3(0, 0, 0.014), m)
	info["photos"].append(f)


## Procedural sepia "old photograph": sky, hills, a cottage or harbour wall.
static func make_photo(seed_v: int, landscape: bool) -> Image:
	var w := 96 if landscape else 72
	var h := 72 if landscape else 96
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.frequency = 0.04
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var horizon := h * rng.randf_range(0.45, 0.6)
	var hills := rng.randf_range(6, 16)
	var has_house := rng.randf() < 0.6
	var hx := rng.randf_range(0.2, 0.7) * w
	for y in h:
		for x in w:
			var v := 0.0
			var hill_y := horizon - hills * (0.5 + 0.5 * noise.get_noise_1d(x * 1.5))
			if y < hill_y:
				v = 0.75 - 0.25 * float(y) / h + 0.05 * noise.get_noise_2d(x * 3, y * 3)
			else:
				v = 0.35 + 0.15 * noise.get_noise_2d(x * 4, y * 4) - 0.1 * float(y - hill_y) / h
			if has_house and x > hx and x < hx + 14 and y > hill_y - 8 and y < hill_y + 4:
				v = 0.85 if y > hill_y - 4 else 0.2
				if y >= hill_y - 8 and y < hill_y - 4 and absf(x - hx - 7) > (hill_y - 4 - y) * 1.8:
					v = 0.7 - 0.25 * float(y) / h
			var dx := (x - w / 2.0) / (w / 2.0)
			var dy := (y - h / 2.0) / (h / 2.0)
			var vig := clampf(1.0 - 0.45 * (dx * dx + dy * dy), 0.0, 1.0)
			v *= vig
			img.set_pixel(x, y, Color(v * 1.05, v * 0.88, v * 0.66))
	img.generate_mipmaps()
	return img


# ------------------------------------------------------------------ lights
func _lights() -> void:
	var g := _group("Lights")
	var lamp_spots := [Vector3(-4.5, 0, 0.9), Vector3(-3.0, 0, 3.4), Vector3(2.5, 0, 1.0), Vector3(2.6, 0, 3.6), Vector3(-3.8, 0, -2.0), Vector3(-0.8, 0, -2.0), Vector3(1.8, 0, -2.0)]
	for p in lamp_spots:
		var hang_y := 2.15 if p.z > -1.5 else 2.35
		var lamp := Node3D.new()
		lamp.position = Vector3(p.x, hang_y, p.z)
		g.add_child(lamp)
		MeshKit.cyl(lamp, 0.006, 0.006, PubLayout.ROOM_H - hang_y, Vector3(0, (PubLayout.ROOM_H - hang_y) / 2.0, 0), MeshKit.mat("iron"), 4)
		# bare dim bulb before restoration
		var bare := MeshKit.sphere(lamp, 0.04, Vector3(0, -0.02, 0), MeshKit.mat("bulb"))
		_tag("lamps", bare, false)
		# restored brass & glass pendant
		var shade_root := Node3D.new()
		lamp.add_child(shade_root)
		MeshKit.cyl(shade_root, 0.03, 0.2, 0.16, Vector3(0, 0.0, 0), MeshKit.mat("brass"), 20)
		MeshKit.sphere(shade_root, 0.05, Vector3(0, -0.08, 0), MeshKit.mat("bulb"))
		MeshKit.cyl(shade_root, 0.2, 0.2, 0.01, Vector3(0, -0.08, 0), MeshKit.mat("lamp_shade"), 20)
		_tag("lamps", shade_root)
		# the shade throws the light down: a pool over the table and the floor round it, the ceiling
		# left to the soft ambient (as under real pendant shades)
		var light := SpotLight3D.new()
		light.position = Vector3(0, -0.1, 0)
		light.rotation_degrees = Vector3(-90, 0, 0)
		light.light_color = Color(1.0, 0.8, 0.58)
		light.spot_range = 4.6
		light.spot_angle = 78.0
		light.spot_angle_attenuation = 0.9
		light.spot_attenuation = 0.9
		lamp.add_child(light)
		info["lamps"].append(light)
		# a faint cone of light and drifting dust under each pendant (lit only once restored)
		var beam_root := Node3D.new()
		lamp.add_child(beam_root)
		var cone := MeshKit.cyl(beam_root, 0.19, 0.75, 1.6, Vector3(0, -0.9, 0), _beam_mat(), 16)
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(cone.mesh as CylinderMesh).cap_top = false
		(cone.mesh as CylinderMesh).cap_bottom = false
		info["light_cones"].append(cone)
		var dust := CPUParticles3D.new()
		dust.amount = 16
		dust.lifetime = 6.0
		dust.preprocess = 6.0
		dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		dust.emission_box_extents = Vector3(0.35, 0.6, 0.35)
		dust.position = Vector3(0, -0.8, 0)
		dust.direction = Vector3(0.2, 0.1, 0.1)
		dust.spread = 180.0
		dust.gravity = Vector3(0, -0.003, 0)
		dust.initial_velocity_min = 0.005
		dust.initial_velocity_max = 0.02
		var dq := QuadMesh.new()
		dq.size = Vector2(0.006, 0.006)
		dq.material = MeshKit.halo_material(Color(1.0, 0.85, 0.6, 0.6))
		dust.mesh = dq
		beam_root.add_child(dust)
		_tag("lamps", beam_root)
		info["dust"].append(dust)
	# warm strip over the back bar shelves
	var strip := OmniLight3D.new()
	strip.position = Vector3(-1.5, 2.9, PubLayout.ROOM_MIN.y + 0.6)
	strip.light_color = Color(1.0, 0.75, 0.45)
	strip.light_energy = 0.9
	strip.omni_range = 4.0
	g.add_child(strip)
	var strip2 := strip.duplicate()
	strip2.position.x = -5.0
	g.add_child(strip2)
	# a soft fill so corners are never pitch black
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 2.8, 2.5)
	fill.light_color = Color(0.8, 0.65, 0.5)
	fill.light_energy = 0.32
	fill.omni_range = 8.0
	g.add_child(fill)
	# a key light over the taps with shadows for the pour close-up
	var key := SpotLight3D.new()
	key.position = Vector3(-1.4, 2.7, -3.1)
	key.rotation_degrees = Vector3(-55, 180, 0)
	key.light_color = Color(1.0, 0.8, 0.55)
	key.light_energy = 1.4
	key.spot_range = 3.5
	key.spot_angle = 38.0
	g.add_child(key)
	info["key_light"] = key


static var _beam_m: ShaderMaterial


static func _beam_mat() -> ShaderMaterial:
	if _beam_m == null:
		_beam_m = MeshKit.shader_mat("res://assets/shaders/light_cone.gdshader")
	return _beam_m


# ------------------------------------------------------------------ cellar
func _cellar() -> void:
	var g := _group("Cellar")
	var mn := PubLayout.CELLAR_MIN
	var mx := PubLayout.CELLAR_MAX
	var w := mx.x - mn.x
	var d := mx.y - mn.y
	var c := Vector3((mn.x + mx.x) / 2.0, 0, (mn.y + mx.y) / 2.0)
	MeshKit.box(g, Vector3(w, 0.1, d), c + Vector3(0, -0.05, 0), MeshKit.mat("stone_floor"))
	MeshKit.solid(g, Vector3(w, 0.1, d), c + Vector3(0, -0.05, 0))
	MeshKit.box(g, Vector3(w, 0.1, d), c + Vector3(0, 2.6, 0), MeshKit.color_mat(Color(0.2, 0.18, 0.16), 0.9))
	MeshKit.solid_box(g, Vector3(w, 2.6, 0.2), Vector3(c.x, 1.3, mn.y), MeshKit.mat("stone"))
	MeshKit.solid_box(g, Vector3(0.2, 2.6, d), Vector3(mn.x, 1.3, c.z), MeshKit.mat("stone_x"))
	MeshKit.solid_box(g, Vector3(0.2, 2.6, d), Vector3(mx.x, 1.3, c.z), MeshKit.mat("stone_x"))
	# doorway hole in the back wall of the bar: wall pieces either side of the cellar door
	# (the main back wall is solid; we cut it by overlaying a dark doorway and removing collision there)
	var lamp := OmniLight3D.new()
	lamp.position = c + Vector3(0, 2.2, 0)
	lamp.light_color = Color(0.9, 0.85, 0.7)
	lamp.light_energy = 0.9
	lamp.omni_range = 4.5
	g.add_child(lamp)
	MeshKit.sphere(g, 0.05, c + Vector3(0, 2.4, 0), MeshKit.mat("bulb"))
	# keg couplers on the wall
	for id in PubLayout.KEG_POS.keys():
		var kp: Vector3 = PubLayout.KEG_POS[id]
		var keg := Node3D.new()
		keg.position = kp
		g.add_child(keg)
		MeshKit.cyl(keg, 0.2, 0.2, 0.6, Vector3(0, 0.3, 0), MeshKit.mat("steel_keg"), 20)
		MeshKit.torus(keg, 0.18, 0.21, Vector3(0, 0.6, 0), MeshKit.mat("steel_keg"))
		MeshKit.torus(keg, 0.18, 0.21, Vector3(0, 0.02, 0), MeshKit.mat("steel_keg"))
		MeshKit.cyl(keg, 0.04, 0.04, 0.06, Vector3(0, 0.63, 0), MeshKit.mat("black_paint"), 10)
		MeshKit.cyl(keg, 0.01, 0.01, 1.6, Vector3(-0.15, 1.4, 0), MeshKit.color_mat(Color(0.8, 0.8, 0.8, 0.6), 0.2), 6)
		if id == "stout":
			MeshKit.quad(keg, Vector2(0.3, 0.15), Vector3(0.203, 0.35, 0), MeshKit.print_mat(BRAND + "galagers_keg.png", 0.0, 0.5), Vector3(0, PI / 2, 0))
		else:
			MeshKit.label(keg, GameData.drink(id).get("short", id), Vector3(0.21, 0.35, 0), 30, Color(0.95, 0.9, 0.8), Vector3(0, PI / 2, 0))
		info["keg_nodes"][id] = keg
		if id != "stout":
			_tag(GameData.drink(id).get("unlock", ""), keg)
	# stacked GALAGERS bottle crates
	var crate_print := MeshKit.print_mat(BRAND + "galagers_sign.png", 0.0, 0.8)
	for i in 3:
		var cp := Vector3(-4.3, 0.15 + i * 0.3, -5.6) if i < 2 else Vector3(-4.3, 0.15, -6.05)
		MeshKit.box(g, Vector3(0.6, 0.3, 0.4), cp, MeshKit.mat("pale_wood"), Vector3(0, i * 0.05, 0))
		MeshKit.quad(g, Vector2(0.4, 0.2), cp + Vector3(0.302, 0, 0), crate_print, Vector3(0, PI / 2 + i * 0.05, 0))
	MeshKit.solid(g, Vector3(0.65, 0.6, 0.9), Vector3(-4.3, 0.3, -5.8))
	# spare stock pile
	var pile := Node3D.new()
	pile.position = PubLayout.STOCK_PILE
	g.add_child(pile)
	info["stock_pile"] = pile
	MeshKit.label(g, "Deliveries", PubLayout.STOCK_PILE + Vector3(0.0, 1.5, -0.6), 36, Color(0.9, 0.85, 0.7))
	MeshKit.label(g, "Cellar", Vector3(-5.4, 2.1, -5.12), 40, Color(0.9, 0.85, 0.7), Vector3(0, PI, 0), _title_font)


# ------------------------------------------------------------------ exterior
func _exterior() -> void:
	var g := _group("Street")
	# cobbled street and pavements
	MeshKit.box(g, Vector3(40, 0.1, 9), Vector3(0, -0.07, 9.6), MeshKit.mat("cobbles"))
	MeshKit.solid(g, Vector3(40, 0.1, 10), Vector3(0, -0.05, 10))
	var paving := MeshKit.shader_mat("res://assets/shaders/tiles.gdshader", {"tile_color": Color(0.35, 0.35, 0.36), "axis": 2, "tile_size": Vector2(0.6, 0.6), "glaze": 0.3, "grout_color": Color(0.2, 0.2, 0.2)})
	MeshKit.box(g, Vector3(40, 0.14, 1.6), Vector3(0, 0.0, 5.95), paving)
	MeshKit.box(g, Vector3(40, 0.14, 1.4), Vector3(0, 0.0, 13.2), paving)
	# ---- the pub front: a traditional Irish shopfront under a rendered upper storey
	var z0 := PubLayout.ROOM_MAX.y + 0.13
	var gold := MeshKit.color_mat(Color(0.78, 0.6, 0.28), 0.35, 0.8)
	var green := MeshKit.mat("green_paint")
	var dark := MeshKit.mat("black_paint")
	# upper storey with three sash windows, a cornice and a parapet over the slate roof
	MeshKit.box(g, Vector3(14.2, 3.4, 0.3), Vector3(0, 3.3 + 1.7, PubLayout.ROOM_MAX.y), MeshKit.mat("render_cream"))
	for wx in [-4.4, 0.0, 4.4]:
		var lit: bool = wx != 0.0
		MeshKit.box(g, Vector3(1.0, 1.45, 0.05), Vector3(wx, 4.75, z0 + 0.02), MeshKit.mat("window_warm") if lit else MeshKit.mat("window_night"))
		for bx in [-0.25, 0.25]:
			MeshKit.box(g, Vector3(0.035, 1.45, 0.06), Vector3(wx + bx, 4.75, z0 + 0.05), MeshKit.mat("cream"))
		MeshKit.box(g, Vector3(1.0, 0.05, 0.07), Vector3(wx, 4.75, z0 + 0.05), MeshKit.mat("cream"))
		MeshKit.box(g, Vector3(1.16, 0.08, 0.1), Vector3(wx, 5.5, z0 + 0.05), MeshKit.mat("cream"))
		MeshKit.box(g, Vector3(1.2, 0.08, 0.2), Vector3(wx, 3.98, z0 + 0.09), MeshKit.mat("cream"))  # sill
		for side in [-1, 1]:
			MeshKit.box(g, Vector3(0.06, 1.55, 0.08), Vector3(wx + side * 0.55, 4.75, z0 + 0.05), MeshKit.mat("cream"))
		if lit:
			MeshKit.box(g, Vector3(0.42, 1.3, 0.02), Vector3(wx - 0.27, 4.75, z0 + 0.0), MeshKit.color_mat(Color(0.55, 0.15, 0.12), 0.9))  # curtain
	MeshKit.box(g, Vector3(14.6, 0.16, 0.42), Vector3(0, 6.62, z0 + 0.06), MeshKit.mat("cream"))
	MeshKit.box(g, Vector3(14.4, 0.5, 0.22), Vector3(0, 6.95, z0 - 0.05), MeshKit.mat("render_cream"))
	var roof := MeshKit.box(g, Vector3(14.2, 0.2, 6.5), Vector3(0, 7.9, 2.4), MeshKit.color_mat(Color(0.12, 0.13, 0.15), 0.6), Vector3(-0.42, 0, 0))
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for cx in [-5.6, 5.0]:
		MeshKit.box(g, Vector3(0.7, 1.4, 0.6), Vector3(cx, 8.0, 1.2), MeshKit.mat("brick"))
		for k in 2:
			MeshKit.cyl(g, 0.09, 0.1, 0.35, Vector3(cx - 0.15 + k * 0.3, 8.85, 1.2), MeshKit.color_mat(Color(0.5, 0.25, 0.15), 0.8), 10)
	# fascia: black board with gilt trim, a deep cornice and carved console brackets at each end
	MeshKit.box(g, Vector3(14.2, 0.66, 0.14), Vector3(0, 2.76, z0 + 0.07), dark)
	for ty in [2.45, 3.07]:
		MeshKit.box(g, Vector3(14.2, 0.035, 0.16), Vector3(0, ty, z0 + 0.08), gold)
	MeshKit.box(g, Vector3(14.6, 0.14, 0.4), Vector3(0, 3.16, z0 + 0.14), green)
	MeshKit.box(g, Vector3(14.8, 0.06, 0.46), Vector3(0, 3.26, z0 + 0.16), green)
	for side in [-1, 1]:
		MeshKit.box(g, Vector3(0.3, 0.75, 0.3), Vector3(side * 7.0, 2.76, z0 + 0.14), green)
		MeshKit.sphere(g, 0.11, Vector3(side * 7.0, 2.42, z0 + 0.22), gold, Vector3(1.0, 0.7, 0.6))
	var name_l := MeshKit.label(g, GameState.pub_name, Vector3(0, 2.76, z0 + 0.15), 96, Color(0.95, 0.78, 0.38), Vector3.ZERO, _title_font)
	name_l.pixel_size = 0.0035
	name_l.outline_size = 6
	name_l.outline_modulate = Color(0.25, 0.15, 0.05)
	info["facade_label"] = name_l
	for sx in [-5.6, 5.6]:
		MeshKit.box(g, Vector3(1.08, 0.54, 0.03), Vector3(sx, 2.76, z0 + 0.15), gold)
		MeshKit.quad(g, Vector2(1.0, 0.5), Vector3(sx, 2.76, z0 + 0.168), MeshKit.print_mat(BRAND + "galagers_sign.png", 0.9, 0.3))
	# fluted pilasters with gilt capitals between the windows and the door
	for px in [-6.86, -5.12, -3.28, -0.78, 0.78, 2.68, 4.52, 6.86]:
		MeshKit.box(g, Vector3(0.22, 2.42, 0.12), Vector3(px, 1.21, z0 + 0.06), green)
		for fx in [-0.05, 0.0, 0.05]:
			MeshKit.box(g, Vector3(0.015, 1.9, 0.02), Vector3(px + fx, 1.3, z0 + 0.125), MeshKit.color_mat(Color(0.02, 0.1, 0.06), 0.4))
		MeshKit.box(g, Vector3(0.3, 0.1, 0.16), Vector3(px, 2.37, z0 + 0.08), gold)
		MeshKit.box(g, Vector3(0.28, 0.26, 0.16), Vector3(px, 0.13, z0 + 0.08), dark)
	# panelled stall risers under the windows, lettered in gold
	for wd in [[-4.2, "FINE ALES"], [3.6, "TRAD MUSIC"]]:
		var wxr: float = wd[0]
		MeshKit.box(g, Vector3(1.64, 0.88, 0.06), Vector3(wxr, 0.45, z0 + 0.03), green)
		MeshKit.box(g, Vector3(1.4, 0.6, 0.02), Vector3(wxr, 0.45, z0 + 0.07), MeshKit.color_mat(Color(0.02, 0.12, 0.07), 0.3))
		var rl := MeshKit.label(g, str(wd[1]), Vector3(wxr, 0.45, z0 + 0.085), 52, Color(0.92, 0.74, 0.36), Vector3.ZERO, _title_font)
		rl.pixel_size = 0.0022
	# brass carriage lanterns either side of the door, with a soft glow
	for side in [-1, 1]:
		var lp := Vector3(side * 1.05, 2.05, z0 + 0.28)
		MeshKit.box(g, Vector3(0.04, 0.04, 0.3), lp + Vector3(0, 0.12, -0.14), dark)
		MeshKit.cyl(g, 0.02, 0.13, 0.12, lp + Vector3(0, 0.22, 0), dark, 4)
		MeshKit.box(g, Vector3(0.18, 0.26, 0.18), lp, MeshKit.mat("window_warm"))
		for cx2 in [-1, 1]:
			for cz in [-1, 1]:
				MeshKit.box(g, Vector3(0.02, 0.28, 0.02), lp + Vector3(cx2 * 0.09, 0, cz * 0.09), MeshKit.mat("brass"))
		MeshKit.cyl(g, 0.06, 0.04, 0.06, lp + Vector3(0, -0.16, 0), MeshKit.mat("brass"), 8)
		MeshKit.halo(g, lp, 0.9, Color(1.0, 0.7, 0.4, 0.55))
		var ll := OmniLight3D.new()
		ll.position = lp + Vector3(0, 0, 0.25)
		ll.light_color = Color(1.0, 0.72, 0.42)
		ll.light_energy = 0.9
		ll.omni_range = 3.5
		g.add_child(ll)
	# hanging flower baskets at the ends of the front
	for bx2 in [-6.2, 6.2]:
		var bp := Vector3(bx2, 2.05, z0 + 0.45)
		MeshKit.cyl(g, 0.005, 0.005, 0.35, bp + Vector3(0, 0.3, 0), MeshKit.mat("iron"), 4)
		MeshKit.sphere(g, 0.22, bp, MeshKit.color_mat(Color(0.12, 0.3, 0.1), 0.9), Vector3(1.0, 0.75, 1.0))
		var cols := [Color(0.85, 0.15, 0.2), Color(0.95, 0.5, 0.7), Color(0.95, 0.92, 0.85), Color(0.6, 0.2, 0.6)]
		for k in 22:
			var a := k * 2.39996
			var r := 0.2 + 0.03 * sin(k * 1.7)
			var yy := 0.1 - (k % 5) * 0.06
			MeshKit.sphere(g, 0.035, bp + Vector3(cos(a) * r, yy, sin(a) * r), MeshKit.color_mat(cols[k % 4], 0.6), Vector3.ONE, 6)
		for k in 6:
			var a2 := k * 1.05
			MeshKit.capsule(g, 0.025, 0.3, bp + Vector3(cos(a2) * 0.2, -0.22, sin(a2) * 0.2), MeshKit.color_mat(Color(0.15, 0.38, 0.12), 0.9))
	# hanging shamrock sign on a wrought-iron bracket at the corner
	var hs := Node3D.new()
	hs.position = Vector3(7.3, 2.25, PubLayout.ROOM_MAX.y + 0.75)
	g.add_child(hs)
	MeshKit.cyl(hs, 0.015, 0.015, 0.75, Vector3(0, 0.38, -0.37), MeshKit.mat("iron"), 6, Vector3(PI / 2, 0, 0))
	MeshKit.box(hs, Vector3(0.04, 0.6, 0.6), Vector3(0, 0, 0), MeshKit.mat("green_paint"), Vector3(0, PI / 2, 0))
	for side in [-1, 1]:
		MeshKit.quad(hs, Vector2(0.52, 0.52), Vector3(0, 0, side * 0.022), MeshKit.print_mat(BRAND + "galagers_badge.png", 0.0, 0.4), Vector3(0, 0.0 if side == 1 else PI, 0))
	# terrace across the road: rendered houses with sash windows, panelled doors and chimneys
	var colours := ["render_red", "render_cream", "render_blue", "render_yellow", "render_wall", "render_cream", "render_red"]
	var door_cols := [Color(0.45, 0.06, 0.06), Color(0.05, 0.2, 0.12), Color(0.1, 0.12, 0.3), Color(0.06, 0.06, 0.06), Color(0.55, 0.35, 0.05)]
	var zf := 13.88   # front face of the terrace
	for i in colours.size():
		var x := -15.0 + i * 5.0
		var hgt := 6.0 + (i % 3) * 0.6
		MeshKit.solid_box(g, Vector3(4.95, hgt, 1.0), Vector3(x, hgt / 2.0, 14.4), MeshKit.mat(colours[i]))
		MeshKit.box(g, Vector3(5.1, 0.12, 0.2), Vector3(x, hgt - 0.05, zf - 0.08), MeshKit.color_mat(Color(0.12, 0.12, 0.13), 0.4))  # gutter
		MeshKit.box(g, Vector3(5.0, 1.6, 0.2), Vector3(x, hgt + 0.55, 14.6), MeshKit.color_mat(Color(0.14, 0.15, 0.17), 0.7), Vector3(0.6, 0, 0))  # slate
		var cx := x + (1.6 if i % 2 == 0 else -1.6)
		MeshKit.box(g, Vector3(0.6, 1.0, 0.5), Vector3(cx, hgt + 0.9, 14.7), MeshKit.mat("brick"))
		for k in 3:
			MeshKit.cyl(g, 0.07, 0.08, 0.3, Vector3(cx - 0.18 + k * 0.18, hgt + 1.55, 14.7), MeshKit.color_mat(Color(0.55, 0.28, 0.16), 0.8), 8)
		MeshKit.box(g, Vector3(4.95, 0.35, 0.08), Vector3(x, 0.17, zf - 0.02), MeshKit.color_mat(Color(0.25, 0.25, 0.26), 0.9))  # plinth
		for wy in [1.6, 4.2]:
			for wx in [-1.4, 1.4]:
				var lit := (i * 3 + int(wy) + int(wx)) % 3 != 0
				var wc := Vector3(x + wx, wy, zf)
				MeshKit.box(g, Vector3(0.9, 1.2, 0.05), wc, MeshKit.mat("window_warm") if lit else MeshKit.mat("window_night"))
				for bx in [-0.22, 0.22]:
					MeshKit.box(g, Vector3(0.03, 1.2, 0.04), wc + Vector3(bx, 0, -0.035), MeshKit.mat("cream"))
				MeshKit.box(g, Vector3(0.9, 0.04, 0.04), wc + Vector3(0, 0.0, -0.035), MeshKit.mat("cream"))
				for sx2 in [-1, 1]:
					MeshKit.box(g, Vector3(0.06, 1.3, 0.06), wc + Vector3(sx2 * 0.48, 0, -0.04), MeshKit.mat("cream"))
				MeshKit.box(g, Vector3(1.1, 0.14, 0.08), wc + Vector3(0, 0.68, -0.04), MeshKit.mat("cream"))  # lintel
				MeshKit.box(g, Vector3(1.08, 0.07, 0.16), wc + Vector3(0, -0.65, -0.07), MeshKit.mat("cream"))  # sill
				if lit and (i + int(wx)) % 2 == 0:
					MeshKit.box(g, Vector3(0.3, 1.1, 0.02), wc + Vector3(-0.28, 0, -0.03), MeshKit.color_mat(Color(0.5, 0.14, 0.1), 0.9))
		# panelled front door with a fanlight, brass knocker and step
		var dc: Color = door_cols[i % door_cols.size()]
		var dpos := Vector3(x, 1.05, zf - 0.01)
		MeshKit.box(g, Vector3(0.95, 2.1, 0.05), dpos, MeshKit.color_mat(dc, 0.35))
		for py in [0.45, -0.4]:
			for px in [-0.2, 0.2]:
				MeshKit.box(g, Vector3(0.28, 0.6, 0.02), dpos + Vector3(px, py, -0.035), MeshKit.color_mat(dc.darkened(0.25), 0.4))
		MeshKit.sphere(g, 0.035, dpos + Vector3(0, 0.25, -0.06), MeshKit.mat("brass"))
		# a glazed transom over the door, glowing from the hall
		MeshKit.box(g, Vector3(0.9, 0.32, 0.04), dpos + Vector3(0, 1.25, 0.0), MeshKit.mat("window_warm"))
		for k in 4:
			MeshKit.box(g, Vector3(0.025, 0.32, 0.03), dpos + Vector3(-0.33 + k * 0.22, 1.25, -0.03), MeshKit.mat("cream"))
		MeshKit.box(g, Vector3(1.1, 0.1, 0.07), dpos + Vector3(0, 1.08, -0.04), MeshKit.mat("cream"))
		MeshKit.box(g, Vector3(1.1, 0.1, 0.07), dpos + Vector3(0, 1.45, -0.04), MeshKit.mat("cream"))
		MeshKit.box(g, Vector3(1.2, 0.15, 0.35), Vector3(x, 0.07, zf - 0.17), MeshKit.color_mat(Color(0.4, 0.4, 0.41), 0.8))
	# side buildings flanking the pub
	MeshKit.solid_box(g, Vector3(8, 7, 10), Vector3(-11.2, 3.5, 0.2), MeshKit.mat("render_cream"))
	MeshKit.solid_box(g, Vector3(8, 6.5, 10), Vector3(11.2, 3.25, 0.2), MeshKit.mat("brick"))
	# street lamps
	for x in [-9.0, 5.5, 14.0]:
		var sl := Node3D.new()
		sl.position = Vector3(x, 0, 6.6)
		g.add_child(sl)
		MeshKit.cyl(sl, 0.05, 0.07, 3.6, Vector3(0, 1.8, 0), MeshKit.mat("black_paint"), 8)
		MeshKit.cyl(sl, 0.03, 0.24, 0.18, Vector3(0, 4.03, 0), MeshKit.mat("black_paint"), 6)
		MeshKit.cyl(sl, 0.17, 0.12, 0.36, Vector3(0, 3.76, 0), MeshKit.mat("window_warm"), 6)
		MeshKit.cyl(sl, 0.09, 0.09, 0.08, Vector3(0, 3.55, 0), MeshKit.mat("black_paint"), 8)
		MeshKit.sphere(sl, 0.05, Vector3(0, 4.15, 0), MeshKit.mat("black_paint"))
		MeshKit.halo(sl, Vector3(0, 3.76, 0), 1.4, Color(1.0, 0.68, 0.38, 0.5))
		var lt := OmniLight3D.new()
		lt.position = Vector3(0, 3.5, 0)
		lt.light_color = Color(1.0, 0.75, 0.45)
		lt.light_energy = 1.6
		lt.omni_range = 7.0
		sl.add_child(lt)
		info["street_lights"].append(lt)
	# rain: one emitter over the street, visible through the windows
	var rain := CPUParticles3D.new()
	rain.amount = 500
	rain.lifetime = 0.9
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(12, 0.2, 4)
	rain.position = Vector3(0, 6, 9.5)
	rain.direction = Vector3(0.1, -1, 0)
	rain.spread = 2.0
	rain.gravity = Vector3(0, -9.8, 0)
	rain.initial_velocity_min = 6.0
	rain.initial_velocity_max = 7.0
	var rq := QuadMesh.new()
	rq.size = Vector2(0.012, 0.35)
	rq.material = MeshKit.mat("rain")
	rain.mesh = rq
	g.add_child(rain)
	info["rain"].append(rain)
	# environment-ish backdrop: hills silhouette far away
	MeshKit.box(g, Vector3(80, 12, 1), Vector3(0, 6, 40), MeshKit.color_mat(Color(0.05, 0.06, 0.08), 1.0))


# ------------------------------------------------------------------ darts
func _darts_corner() -> void:
	var g := _group("Darts")
	_tag("dartboard", g)
	var b := PubLayout.DARTBOARD
	# cabinet doors either side of the board
	MeshKit.box(g, Vector3(0.04, 0.62, 0.62), b + Vector3(0.02, 0, 0), MeshKit.mat("oak_z"))
	for side in [-1, 1]:
		MeshKit.box(g, Vector3(0.03, 0.62, 0.3), b + Vector3(-0.0, 0, side * 0.47), MeshKit.mat("oak_z"))
	var board := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.451, 0.451)
	board.mesh = qm
	board.material_override = MeshKit.shader_mat("res://assets/shaders/dartboard.gdshader")
	board.position = b + Vector3(-0.002, 0, 0)
	board.rotation.y = -PI / 2.0
	g.add_child(board)
	var order := [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]
	for i in 20:
		var a := TAU * i / 20.0
		var lp := b + Vector3(-0.006, cos(a) * 0.198, sin(a) * 0.198)
		var l := MeshKit.label(g, str(order[i]), lp, 30, Color(0.95, 0.92, 0.8), Vector3(0, -PI / 2.0, 0))
		l.pixel_size = 0.0011
	# chalk scoreboard and the oche line
	MeshKit.box(g, Vector3(0.03, 0.5, 0.4), b + Vector3(0, -0.05, -0.85), MeshKit.mat("chalk"))
	MeshKit.label(g, "301", b + Vector3(-0.02, 0.1, -0.85), 40, Color(0.95, 0.95, 0.9), Vector3(0, -PI / 2.0, 0), _title_font)
	MeshKit.box(g, Vector3(0.05, 0.012, 0.6), Vector3(PubLayout.OCHE_X, 0.006, b.z), MeshKit.mat("brass"))
	var lamp := SpotLight3D.new()
	lamp.position = b + Vector3(-0.7, 0.9, 0)
	lamp.rotation_degrees = Vector3(-50, -90, 0)
	lamp.light_color = Color(1.0, 0.85, 0.6)
	lamp.light_energy = 1.2
	lamp.spot_range = 2.0
	lamp.spot_angle = 30.0
	g.add_child(lamp)


# ------------------------------------------------------------------ music
func _stage() -> void:
	var g := _group("Stage")
	_tag("snug_stage", g)
	var c := PubLayout.STAGE_POS
	MeshKit.solid_box(g, Vector3(2.5, 0.22, 2.1), Vector3(c.x + 0.05, 0.11, c.z + 0.05), MeshKit.mat("floor"))
	MeshKit.box(g, Vector3(2.52, 0.04, 2.12), Vector3(c.x + 0.05, 0.22, c.z + 0.05), MeshKit.mat("oak_z"))
	MeshKit.box(g, Vector3(0.04, 0.2, 2.1), Vector3(c.x - 1.2, 0.1, c.z + 0.05), MeshKit.mat("brass"))
	# stools for the players (put aside while a band brings its own)
	var stools := Node3D.new()
	g.add_child(stools)
	for i in 5:
		var spread := (i / 4.0 - 0.5) * 1.8
		var sp := c + Vector3(spread * 0.5 + 0.15, 0.22, spread)
		MeshKit.cyl(stools, 0.17, 0.17, 0.05, sp + Vector3(0, 0.46, 0), MeshKit.mat("oak"), 14)
		MeshKit.cyl(stools, 0.03, 0.03, 0.44, sp + Vector3(0, 0.22, 0), MeshKit.mat("oak_y"), 8)
	info["stage_stools"] = stools
	# hanging sign
	var l := MeshKit.label(g, "The Snug", c + Vector3(1.14, 2.45, 0.05), 64, Color(0.95, 0.8, 0.45), Vector3(0, -PI / 2.0, 0), _title_font)
	l.pixel_size = 0.0022
	MeshKit.box(g, Vector3(0.03, 0.4, 1.2), c + Vector3(1.16, 2.45, 0.05), MeshKit.mat("green_paint"))
	var spot := SpotLight3D.new()
	spot.position = c + Vector3(-1.4, 2.9, 0)
	spot.rotation_degrees = Vector3(-55, -90, 0)
	spot.light_color = Color(1.0, 0.82, 0.55)
	spot.light_energy = 1.6
	spot.spot_range = 4.0
	spot.spot_angle = 40.0
	g.add_child(spot)
	# speakers (sound system upgrade)
	var sp_g := _group("Speakers")
	_tag("sound_system", sp_g)
	for side in [-1, 1]:
		# on stands just off either end of the stage, clear of the players
		var p := c + Vector3(0.6, 0.0, side * 1.3)
		MeshKit.cyl(sp_g, 0.02, 0.02, 1.2, p + Vector3(0, 0.6, 0), MeshKit.mat("iron"), 6)
		MeshKit.box(sp_g, Vector3(0.3, 0.45, 0.3), p + Vector3(0, 1.2, 0), MeshKit.mat("black_paint"), Vector3(0, -PI / 4.0 * side, 0))
		MeshKit.cyl(sp_g, 0.09, 0.09, 0.02, p + Vector3(-0.15, 1.15, 0), MeshKit.color_mat(Color(0.15, 0.15, 0.15), 0.8), 16, Vector3(0, 0, PI / 2.0))


func _jukebox() -> void:
	# the old jukebox is always there (it plays the pub's music); restoring it lights it up
	var g := _group("Jukebox")
	var p := PubLayout.JUKEBOX_POS
	g.position = p
	g.rotation.y = PI / 2.0  # faces +x into the room
	MeshKit.solid(g, Vector3(0.75, 1.5, 0.5), Vector3(0, 0.75, 0))
	MeshKit.box(g, Vector3(0.75, 1.1, 0.5), Vector3(0, 0.55, 0), MeshKit.mat("oak"))
	MeshKit.cyl(g, 0.375, 0.375, 0.5, Vector3(0, 1.1, 0), MeshKit.mat("oak"), 20, Vector3(PI / 2.0, 0, 0))
	var dull := Node3D.new()
	g.add_child(dull)
	MeshKit.box(dull, Vector3(0.6, 0.35, 0.02), Vector3(0, 0.95, 0.255), MeshKit.color_mat(Color(0.35, 0.28, 0.2), 0.6))
	MeshKit.torus(dull, 0.33, 0.37, Vector3(0, 1.1, 0.24), MeshKit.mat("brass_dull"), Vector3(PI / 2.0, 0, 0))
	_tag("jukebox", dull, false)
	var lit := Node3D.new()
	g.add_child(lit)
	MeshKit.box(lit, Vector3(0.6, 0.35, 0.02), Vector3(0, 0.95, 0.255), MeshKit.color_mat(Color(1.0, 0.6, 0.2), 0.3, 0.0, 1.6))
	for i in 5:
		MeshKit.box(lit, Vector3(0.05, 0.5, 0.02), Vector3(-0.24 + i * 0.12, 0.45, 0.255), MeshKit.color_mat(Color.from_hsv(i * 0.18, 0.8, 1.0), 0.3, 0.0, 1.2))
	MeshKit.torus(lit, 0.33, 0.37, Vector3(0, 1.1, 0.24), MeshKit.color_mat(Color(1.0, 0.75, 0.3), 0.3, 0.0, 1.5), Vector3(PI / 2.0, 0, 0))
	var lt := OmniLight3D.new()
	lt.position = Vector3(0, 1.0, 0.6)
	lt.light_color = Color(1.0, 0.6, 0.3)
	lt.light_energy = 0.6
	lt.omni_range = 2.0
	lit.add_child(lt)
	_tag("jukebox", lit)
	var l := MeshKit.label(g, "JUKEBOX", Vector3(0, 1.32, 0.26), 30, Color(0.95, 0.85, 0.6), Vector3.ZERO, _title_font)
	l.pixel_size = 0.0016


# ------------------------------------------------------------------ upgrade-only extras
func _upgrade_extras() -> void:
	# extra glasses sitting on the shelf after buying glassware is shown by the rack itself.
	pass
