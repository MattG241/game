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
	"rack_glasses": null,  # Node3D holding visual clean glasses
	"rack_slots": [],
	"sink_slots": [],
	"keg_nodes": {},
	"door": null,
	"rain": [],
	"env": null,
	"photos": [],
}
var _title_font: Font


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
	return info


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
	var fl := MeshKit.box(g, Vector3(w, 0.1, d), Vector3(0, -0.05, 0), MeshKit.mat("floor"))
	MeshKit.solid(g, Vector3(w + 2, 0.1, d + 2), Vector3(0, -0.05, 0))
	var ceil_mat := MeshKit.color_mat(Color(0.18, 0.12, 0.08), 0.9)
	MeshKit.box(g, Vector3(w, 0.1, d), Vector3(0, h + 0.05, 0), ceil_mat)
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
	var old_low := MeshKit.box(g, low_size, low_pos, MeshKit.mat("tiles_old_z" if axis == 0 else "tiles_old_x"))
	var old_up := MeshKit.box(g, up_size, up_pos, MeshKit.mat("plaster_old"))
	var new_low := MeshKit.box(g, low_size, low_pos + inward * 0.002, MeshKit.mat("tiles_green_z" if axis == 0 else "tiles_green_x"))
	var new_up := MeshKit.box(g, up_size, up_pos + inward * 0.002, MeshKit.mat("plaster_new"))
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
	# brass foot rail with brackets
	var rail := MeshKit.cyl(g, 0.025, 0.025, len, Vector3(cx, 0.2, zf + 0.25), MeshKit.mat("brass_dull"), 10, Vector3(0, 0, PI / 2))
	_tag("drip_tray", rail, false)
	var rail2 := MeshKit.cyl(g, 0.025, 0.025, len, Vector3(cx, 0.2, zf + 0.25), MeshKit.mat("brass"), 10, Vector3(0, 0, PI / 2))
	_tag("drip_tray", rail2)
	for i in 8:
		MeshKit.cyl(g, 0.012, 0.012, 0.3, Vector3(x0 + 0.5 + i * len / 8.0, 0.16, zf + 0.15), MeshKit.mat("brass_dull"), 6, Vector3(PI / 2.6, 0, 0))
	# bartender-side shelf under the counter
	MeshKit.box(g, Vector3(len - 0.2, 0.03, 0.4), Vector3(cx, 0.55, zb - 0.22), MeshKit.mat("oak"))
	# bar stools (customer side, one per service spot)
	for x in PubLayout.BAR_SPOT_X:
		_stool(g, Vector3(x, 0, zf + 0.42))
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
	MeshKit.box(till, Vector3(0.36, 0.12, 0.3), Vector3(0, 0.06, 0), MeshKit.mat("iron"))
	MeshKit.box(till, Vector3(0.3, 0.16, 0.06), Vector3(0, 0.2, -0.05), MeshKit.mat("iron"), Vector3(-0.4, 0, 0))
	MeshKit.box(till, Vector3(0.26, 0.08, 0.02), Vector3(0, 0.24, -0.02), MeshKit.color_mat(Color(0.2, 0.5, 0.3), 0.4, 0, 0.6), Vector3(-0.4, 0, 0))
	for i in 3:
		for j in 4:
			MeshKit.box(till, Vector3(0.04, 0.015, 0.035), Vector3(-0.09 + j * 0.06, 0.125, 0.04 + i * 0.045), MeshKit.color_mat(Color(0.85, 0.82, 0.75), 0.6))
	# tips jar
	MeshKit.cyl(g, 0.06, 0.055, 0.14, PubLayout.TILL_POS + Vector3(-0.38, 0.07, 0.05), MeshKit.color_mat(Color(0.8, 0.9, 0.9, 0.35), 0.05))
	MeshKit.label(g, "TIPS", PubLayout.TILL_POS + Vector3(-0.38, 0.08, 0.112), 28, Color(0.95, 0.85, 0.5), Vector3.ZERO, _title_font)


func _stool(g: Node3D, p: Vector3) -> void:
	var s := Node3D.new()
	s.position = p
	g.add_child(s)
	MeshKit.cyl(s, 0.19, 0.19, 0.06, Vector3(0, 0.76, 0), MeshKit.mat("leather_red"), 16)
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
	var badge := MeshKit.cyl(pivot, 0.04, 0.04, 0.012, Vector3(0, 0.2, -0.032), MeshKit.color_mat(Color(0.92, 0.86, 0.68), 0.4), 20, Vector3(PI / 2, 0, 0))
	badge.name = "Badge"
	var lb := MeshKit.label(pivot, "K", Vector3(0, 0.2, -0.04), 40, Color(0.08, 0.05, 0.03), Vector3(0, PI, 0), _title_font)
	lb.pixel_size = 0.0012
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
	var sign := MeshKit.label(g, "Kilbrack · Est. 1887", Vector3(cx - 0.4, 2.7, PubLayout.ROOM_MIN.y + 0.47), 64, Color(0.95, 0.8, 0.45), Vector3.ZERO, _title_font)
	sign.pixel_size = 0.002
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
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bottle := CylinderMesh.new()
	bottle.top_radius = 0.018
	bottle.bottom_radius = 0.04
	bottle.height = 0.3
	bottle.radial_segments = 10
	bottle.rings = 2
	var bm := StandardMaterial3D.new()
	bm.vertex_color_use_as_albedo = true
	bm.roughness = 0.12
	bm.metallic = 0.1
	bottle.material = bm
	mm.mesh = bottle
	var rng := RandomNumberGenerator.new()
	rng.seed = 87
	var per := int(width / 0.1)
	mm.instance_count = per * 2
	var palette := [Color(0.25, 0.1, 0.03), Color(0.08, 0.2, 0.08), Color(0.45, 0.25, 0.05), Color(0.6, 0.6, 0.55), Color(0.3, 0.05, 0.08), Color(0.1, 0.12, 0.2)]
	var idx := 0
	for shelf_y in [1.27, 1.77]:
		for i in per:
			var x := base.x - width / 2.0 + i * 0.1 + rng.randf_range(-0.02, 0.02)
			var s := rng.randf_range(0.8, 1.15)
			var t := Transform3D(Basis().scaled(Vector3(s, s, s)), Vector3(x, shelf_y + 0.15 * s, base.z + rng.randf_range(-0.05, 0.05)))
			mm.set_instance_transform(idx, t)
			mm.set_instance_color(idx, palette[rng.randi() % palette.size()])
			idx += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	g.add_child(mmi)


# ------------------------------------------------------------------ fireplace
func _fireplace() -> void:
	var g := _group("Fireplace")
	var p := PubLayout.FIREPLACE
	var stone := MeshKit.mat("stone_x")
	MeshKit.solid_box(g, Vector3(0.5, 1.4, 0.35), Vector3(p.x + 0.25, 0.7, p.z - 0.8), stone)
	MeshKit.solid_box(g, Vector3(0.5, 1.4, 0.35), Vector3(p.x + 0.25, 0.7, p.z + 0.8), stone)
	MeshKit.box(g, Vector3(0.55, 0.35, 1.95), Vector3(p.x + 0.27, 1.22, p.z), stone)
	MeshKit.box(g, Vector3(0.7, 0.1, 2.2), Vector3(p.x + 0.35, 1.45, p.z), MeshKit.mat("oak_z"))
	MeshKit.box(g, Vector3(0.1, 1.05, 1.25), Vector3(p.x + 0.12, 0.52, p.z), MeshKit.color_mat(Color(0.03, 0.025, 0.02), 1.0))
	MeshKit.box(g, Vector3(0.9, 0.04, 2.0), Vector3(p.x + 0.45, 0.02, p.z), MeshKit.mat("stone_floor"))
	MeshKit.solid(g, Vector3(0.6, 1.4, 1.9), Vector3(p.x + 0.3, 0.7, p.z))
	# chimney breast above
	MeshKit.box(g, Vector3(0.4, 1.85, 1.9), Vector3(p.x + 0.2, 2.4, p.z), MeshKit.mat("plaster_old"))
	# ash (unlit) vs turf fire (upgrade)
	var ash := MeshKit.box(g, Vector3(0.4, 0.05, 0.7), Vector3(p.x + 0.35, 0.05, p.z), MeshKit.mat("ash"))
	_tag("fireplace", ash, false)
	var fire := Node3D.new()
	fire.position = Vector3(p.x + 0.35, 0.05, p.z)
	g.add_child(fire)
	for i in 5:
		MeshKit.box(fire, Vector3(0.12, 0.08, 0.22), Vector3((i % 2) * 0.1 - 0.05, 0.04 + (i / 2) * 0.06, -0.25 + i * 0.12), MeshKit.mat("turf"), Vector3(0, i * 0.5, 0.2))
	MeshKit.box(fire, Vector3(0.3, 0.04, 0.6), Vector3(0, 0.02, 0), MeshKit.mat("ember"))
	var parts := CPUParticles3D.new()
	parts.amount = 28
	parts.lifetime = 0.9
	parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	parts.emission_box_extents = Vector3(0.1, 0.02, 0.28)
	parts.direction = Vector3(0, 1, 0)
	parts.spread = 12.0
	parts.gravity = Vector3(0, 0.6, 0)
	parts.initial_velocity_min = 0.25
	parts.initial_velocity_max = 0.5
	parts.scale_amount_min = 0.6
	parts.scale_amount_max = 1.2
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.75, 0.3, 0.9))
	grad.set_color(1, Color(0.8, 0.15, 0.02, 0.0))
	parts.color_ramp = grad
	var qm := QuadMesh.new()
	qm.size = Vector2(0.14, 0.2)
	qm.material = MeshKit.mat("fire")
	parts.mesh = qm
	parts.position.y = 0.08
	fire.add_child(parts)
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
	MeshKit.cyl(t, 0.42, 0.42, 0.05, Vector3(0, 0.74, 0), MeshKit.mat("bar_top"), 24)
	MeshKit.cyl(t, 0.05, 0.06, 0.7, Vector3(0, 0.37, 0), MeshKit.mat("iron"), 10)
	MeshKit.cyl(t, 0.25, 0.28, 0.04, Vector3(0, 0.02, 0), MeshKit.mat("iron"), 16)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.45
	shape.height = 0.8
	cs.shape = shape
	sb.add_child(cs)
	sb.position = Vector3(0, 0.4, 0)
	t.add_child(sb)
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
	var wood := MeshKit.mat("oak_y")
	MeshKit.box(c, Vector3(0.42, 0.05, 0.4), Vector3(0, 0.46, 0), MeshKit.mat("oak"))
	for lx in [-0.18, 0.18]:
		for lz in [-0.17, 0.17]:
			MeshKit.box(c, Vector3(0.04, 0.46, 0.04), Vector3(lx, 0.23, lz), wood)
	MeshKit.box(c, Vector3(0.42, 0.5, 0.04), Vector3(0, 0.74, 0.19), wood)
	for i in 3:
		MeshKit.box(c, Vector3(0.03, 0.42, 0.02), Vector3(-0.12 + i * 0.12, 0.7, 0.18), MeshKit.mat("oak"))
	MeshKit.solid(c, Vector3(0.44, 0.9, 0.44), Vector3(0, 0.45, 0))


func _armchair(g: Node3D, p: Vector3, face: Vector3, table_pos: Vector3) -> void:
	var yaw := atan2(-face.x, -face.z)
	var c := Node3D.new()
	c.position = p
	c.rotation.y = yaw
	g.add_child(c)
	var fab := MeshKit.mat("leather_green")
	MeshKit.box(c, Vector3(0.75, 0.25, 0.7), Vector3(0, 0.3, 0), fab)
	MeshKit.box(c, Vector3(0.75, 0.6, 0.15), Vector3(0, 0.7, 0.3), fab)
	MeshKit.box(c, Vector3(0.12, 0.25, 0.7), Vector3(-0.38, 0.55, 0), fab)
	MeshKit.box(c, Vector3(0.12, 0.25, 0.7), Vector3(0.38, 0.55, 0), fab)
	MeshKit.box(c, Vector3(0.7, 0.18, 0.66), Vector3(0, 0.1, 0), MeshKit.mat("oak"))
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
	# door (opens inward; animated by the world)
	var door_pivot := Node3D.new()
	door_pivot.position = Vector3(-door_w / 2.0 + 0.02, 0, z - 0.05)
	g.add_child(door_pivot)
	var door := MeshKit.box(door_pivot, Vector3(door_w - 0.04, door_h - 0.02, 0.06), Vector3((door_w - 0.04) / 2.0, door_h / 2.0, 0), MeshKit.mat("green_paint"))
	MeshKit.box(door_pivot, Vector3(0.5, 0.6, 0.065), Vector3(door_w / 2.0, 1.6, 0), MeshKit.color_mat(Color(0.9, 0.62, 0.3, 0.7), 0.1, 0, 0.4))
	MeshKit.sphere(door_pivot, 0.035, Vector3(door_w - 0.15, 1.05, -0.05), MeshKit.mat("brass"))
	MeshKit.sphere(door_pivot, 0.035, Vector3(door_w - 0.15, 1.05, 0.05), MeshKit.mat("brass"))
	info["door"] = door_pivot
	# door frame
	MeshKit.box(g, Vector3(0.08, door_h, 0.28), Vector3(-door_w / 2.0, door_h / 2.0, z), MeshKit.mat("oak_y"))
	MeshKit.box(g, Vector3(0.08, door_h, 0.28), Vector3(door_w / 2.0, door_h / 2.0, z), MeshKit.mat("oak_y"))
	# OPEN / CLOSED sign by the door
	var sign_root := Node3D.new()
	sign_root.position = PubLayout.DOOR_SIGN_POS
	g.add_child(sign_root)
	MeshKit.box(sign_root, Vector3(0.42, 0.22, 0.02), Vector3.ZERO, MeshKit.mat("black_paint"))
	var sl := MeshKit.label(sign_root, "CLOSED", Vector3(0, 0, -0.012), 52, Color(0.9, 0.3, 0.2), Vector3(0, PI, 0), _title_font)
	sl.pixel_size = 0.0018
	info["door_sign_label"] = sl
	# coat hooks
	for i in 4:
		MeshKit.cyl(g, 0.01, 0.01, 0.08, Vector3(-2.4 + i * 0.22, 1.7, z - 0.17), MeshKit.mat("brass"), 6, Vector3(PI / 2.5, 0, 0))


func _window(g: Node3D, c: Vector3, size: Vector2) -> void:
	var glass_m := StandardMaterial3D.new()
	glass_m.albedo_color = Color(0.25, 0.35, 0.45, 0.25)
	glass_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_m.roughness = 0.05
	glass_m.metallic = 0.4
	glass_m.emission_enabled = true
	glass_m.emission = Color(0.2, 0.25, 0.3)
	glass_m.emission_energy_multiplier = 0.3
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
	MeshKit.cyl(g, 0.01, 0.01, size.x, c + Vector3(0, -0.1, -0.12), MeshKit.mat("brass"), 6, Vector3(0, 0, PI / 2))
	MeshKit.box(g, Vector3(size.x - 0.08, 0.6, 0.01), c + Vector3(0, -0.42, -0.12), MeshKit.color_mat(Color(0.75, 0.68, 0.5, 0.85), 0.9))


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
	nb.position = Vector3(-1.8, 1.55, PubLayout.ROOM_MAX.y - 0.16)
	nb.rotation.y = PI
	g.add_child(nb)
	MeshKit.box(nb, Vector3(0.8, 0.6, 0.03), Vector3.ZERO, MeshKit.color_mat(Color(0.55, 0.4, 0.25), 0.95))
	var notes := ["Lost: one grey cat,\nanswers to Biscuit", "Tidy Towns meeting\nThursday 7pm", "Trad session\nSundays (soon!)", "Turf for sale\nask Eamon"]
	for i in notes.size():
		var np := Vector3(-0.22 + (i % 2) * 0.42, 0.13 - (i / 2) * 0.27, 0.02)
		MeshKit.box(nb, Vector3(0.3, 0.2, 0.004), np, MeshKit.mat("paper"), Vector3(0, 0, (i - 1.5) * 0.04))
		var lb := MeshKit.label(nb, notes[i], np + Vector3(0, 0, 0.004), 20, Color(0.15, 0.12, 0.1))
		lb.pixel_size = 0.0008
	# chalkboard (upgrade)
	var cb := Node3D.new()
	cb.position = Vector3(1.9, 1.7, PubLayout.ROOM_MAX.y - 0.16)
	cb.rotation.y = PI
	g.add_child(cb)
	MeshKit.box(cb, Vector3(0.9, 1.1, 0.03), Vector3.ZERO, MeshKit.mat("chalk"))
	MeshKit.box(cb, Vector3(0.96, 1.16, 0.02), Vector3(0, 0, -0.01), MeshKit.mat("oak_y"))
	var cl := MeshKit.label(cb, "Tonight\n~\nKilbrack Stout\nperfectly poured\n\nTrad & tunes\ncoming soon", Vector3(0, 0, 0.02), 34, Color(0.95, 0.95, 0.9), Vector3.ZERO, _title_font)
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
		var light := OmniLight3D.new()
		light.position = Vector3(0, -0.15, 0)
		light.light_color = Color(1.0, 0.8, 0.58)
		light.omni_range = 4.5
		light.omni_attenuation = 1.2
		lamp.add_child(light)
		info["lamps"].append(light)
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
	fill.light_energy = 0.35
	fill.omni_range = 9.0
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
		var lb := MeshKit.label(keg, GameData.drink(id).get("short", id), Vector3(0.21, 0.35, 0), 30, Color(0.95, 0.9, 0.8), Vector3(0, PI / 2, 0))
		info["keg_nodes"][id] = keg
		if id != "stout":
			_tag(GameData.drink(id).get("unlock", ""), keg)
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
	# pub facade dressing
	var fascia := MeshKit.box(g, Vector3(9.4, 0.6, 0.12), Vector3(0, 2.75, PubLayout.ROOM_MAX.y + 0.2), MeshKit.mat("green_paint"))
	var name_l := MeshKit.label(g, GameState.pub_name, Vector3(0, 2.75, PubLayout.ROOM_MAX.y + 0.27), 96, Color(0.95, 0.78, 0.38), Vector3.ZERO, _title_font)
	name_l.pixel_size = 0.0035
	info["facade_label"] = name_l
	for sx in [-4.75, 4.75]:
		MeshKit.box(g, Vector3(0.3, 3.1, 0.2), Vector3(sx, 1.55, PubLayout.ROOM_MAX.y + 0.18), MeshKit.mat("green_paint"))
	MeshKit.label(g, "Kilbrack Stout · Fine Ales · Trad Music", Vector3(0, 2.3, PubLayout.ROOM_MAX.y + 0.27), 40, Color(0.9, 0.85, 0.7), Vector3.ZERO)
	# hanging sign with a shamrock
	var hs := Node3D.new()
	hs.position = Vector3(1.4, 2.6, PubLayout.ROOM_MAX.y + 0.7)
	g.add_child(hs)
	MeshKit.cyl(hs, 0.015, 0.015, 0.7, Vector3(0, 0.35, -0.35), MeshKit.mat("iron"), 6, Vector3(PI / 2, 0, 0))
	MeshKit.box(hs, Vector3(0.04, 0.55, 0.55), Vector3(0, 0, 0), MeshKit.mat("green_paint"), Vector3(0, PI / 2, 0))
	for i in 3:
		var a := TAU * i / 3.0 + PI / 2.0
		MeshKit.sphere(hs, 0.09, Vector3(0.03, sin(a) * 0.09 + 0.02, cos(a) * 0.09), MeshKit.color_mat(Color(0.2, 0.6, 0.25), 0.5), Vector3(0.3, 1, 1))
		MeshKit.sphere(hs, 0.09, Vector3(-0.03, sin(a) * 0.09 + 0.02, cos(a) * 0.09), MeshKit.color_mat(Color(0.2, 0.6, 0.25), 0.5), Vector3(0.3, 1, 1))
	# terrace across the road
	var colours := ["render_red", "render_cream", "render_blue", "render_yellow", "render_wall", "render_cream", "render_red"]
	for i in colours.size():
		var x := -15.0 + i * 5.0
		var hgt := 6.0 + (i % 3) * 0.6
		MeshKit.solid_box(g, Vector3(4.95, hgt, 1.0), Vector3(x, hgt / 2.0, 14.4), MeshKit.mat(colours[i]))
		MeshKit.box(g, Vector3(5.1, 0.3, 1.3), Vector3(x, hgt + 0.15, 14.3), MeshKit.color_mat(Color(0.15, 0.15, 0.17), 0.8))
		for wy in [1.6, 4.2]:
			for wx in [-1.4, 1.4]:
				var lit := (i * 3 + int(wy) + int(wx)) % 3 != 0
				var wm := MeshKit.mat("window_warm") if lit else MeshKit.mat("window_night")
				MeshKit.box(g, Vector3(0.9, 1.2, 0.05), Vector3(x + wx, wy, 13.88), wm)
				MeshKit.box(g, Vector3(1.0, 0.08, 0.12), Vector3(x + wx, wy - 0.64, 13.86), MeshKit.mat("cream"))
		MeshKit.box(g, Vector3(0.9, 2.1, 0.05), Vector3(x, 1.05, 13.88), MeshKit.color_mat(Color(0.1, 0.1, 0.12).lerp(Color(0.5, 0.1, 0.1), (i % 2) * 0.6), 0.4))
	# side buildings flanking the pub
	MeshKit.solid_box(g, Vector3(8, 7, 10), Vector3(-11.2, 3.5, 0.2), MeshKit.mat("render_cream"))
	MeshKit.solid_box(g, Vector3(8, 6.5, 10), Vector3(11.2, 3.25, 0.2), MeshKit.mat("brick"))
	# street lamps
	for x in [-9.0, 5.5, 14.0]:
		var sl := Node3D.new()
		sl.position = Vector3(x, 0, 6.6)
		g.add_child(sl)
		MeshKit.cyl(sl, 0.05, 0.07, 3.6, Vector3(0, 1.8, 0), MeshKit.mat("black_paint"), 8)
		MeshKit.box(sl, Vector3(0.3, 0.4, 0.3), Vector3(0, 3.75, 0), MeshKit.color_mat(Color(1, 0.8, 0.5), 0.3, 0, 2.0))
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


# ------------------------------------------------------------------ upgrade-only extras
func _upgrade_extras() -> void:
	# extra glasses sitting on the shelf after buying glassware is shown by the rack itself.
	pass
