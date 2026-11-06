class_name Landmarks
extends Node3D
## Authored points of interest layered on top of the procedural terrain:
## region permit barriers, the abandoned research facility (with salvage),
## industrial towers, the crashed probe and highland relics.

const RESEARCH_CENTER := Vector2(-330, 0)
const PROBE_POS := Vector2(420, -60)
const SALVAGE_COUNT := 30

var world: Node
var _barriers := {}        # region index -> Node3D
var _gate_labels := {}     # region index -> Label3D
var _salvage_nodes := {}   # id -> Node3D
var _probe: Node3D
var _t := 0.0


func build(w: Node) -> void:
	world = w
	_build_barriers()
	_build_facility()
	_build_industrial()
	_build_probe()
	_build_relics()
	# Everything was laid out flat (map coordinates): stand it on the round Moon.
	SphereLayout.wrap(self)
	GameState.inventory_changed.connect(_refresh)
	_refresh()


func _y(x: float, z: float) -> float:
	return TerrainGen.height(x, z)


## World position of a point of the flat layout (y = height above the mean radius).
func _w(flat: Vector3) -> Vector3:
	return TerrainGen.map_point(flat.x, flat.z, flat.y)


func _build_barriers() -> void:
	var post_mat := Meshes.hs(Color(0.2, 0.22, 0.26), 0.6, 0.4, Color(0, 0, 0), 0.0, 2.0, 0.3, 1.0)
	var centers := {1: 0.0, 2: -PI * 0.5, 3: PI, 4: PI * 0.5}
	for idx in centers:
		var c: float = centers[idx]
		var info := GameData.region(idx)
		var col := Color(1.0, 0.45, 0.15)
		var root := Node3D.new()
		add_child(root)
		var segs := 18
		var r := TerrainGen.ZONE_RADIUS + 1.0
		var wall_mat := Meshes.energy(col, 0.9, 0.6, 3.0)
		for i in segs + 1:
			var a := c - PI * 0.25 + i * (PI * 0.5) / segs
			var p := Vector3(cos(a) * r, 0, sin(a) * r)
			p.y = _y(p.x, p.z)
			Meshes.part(root, Meshes.box(Vector3(0.5, 5.0, 0.5)), post_mat, p + Vector3(0, 2.0, 0))
			Meshes.part(root, Meshes.sphere(0.3), Meshes.glow(col, 3.0), p + Vector3(0, 4.6, 0), Vector3.ZERO, Vector3.ONE, false)
			if i < segs:
				var a2 := a + (PI * 0.5) / segs
				var p2 := Vector3(cos(a2) * r, 0, sin(a2) * r)
				p2.y = _y(p2.x, p2.z)
				var quad := QuadMesh.new()
				var seg_len := p.distance_to(p2)
				quad.size = Vector2(seg_len, 4.2)
				var mi := Meshes.part(root, quad, wall_mat, (p + p2) * 0.5 + Vector3(0, 2.3, 0), Vector3.ZERO, Vector3.ONE, false)
				mi.look_at_from_position((p + p2) * 0.5 + Vector3(0, 2.3, 0), (p + p2) * 0.5 + Vector3(0, 2.3, 0) + (p2 - p).cross(Vector3.UP), Vector3.UP)
		_barriers[idx] = root
		# Gate arch and sign (always visible)
		var g := Vector3(cos(c) * (r - 4.0), 0, sin(c) * (r - 4.0))
		g.y = _y(g.x, g.z)
		var gate := Node3D.new()
		gate.position = g
		gate.rotation.y = -c + PI * 0.5
		add_child(gate)
		Meshes.part(gate, Meshes.box(Vector3(0.8, 7.0, 0.8)), post_mat, Vector3(-6, 3.5, 0))
		Meshes.part(gate, Meshes.box(Vector3(0.8, 7.0, 0.8)), post_mat, Vector3(6, 3.5, 0))
		Meshes.part(gate, Meshes.box(Vector3(13.0, 1.0, 0.9)), Meshes.hs(Color(1.0, 0.6, 0.15), 0.3, 0.4, Color(0, 0, 0), 0.0, 1.0, 0.2, 1.0), Vector3(0, 7.2, 0))
		var lbl := Meshes.label(gate, info["name"].to_upper(), Vector3(0, 9.2, 0), 140, Color(1.0, 0.85, 0.5))
		lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		_gate_labels[idx] = Meshes.label(gate, "", Vector3(0, 5.6, 0.6), 70, Color(1, 1, 1))
		_gate_labels[idx].billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		var region_index: int = idx
		world.add_interactable(_w(g), 7.0, func(): return _gate_text(region_index), func(): world.open_menu("permits"), "gate_%d" % idx)


func _gate_text(idx: int) -> String:
	if GameState.region_unlocked(idx):
		return ""
	return "Buy %s permit" % GameData.region(idx)["name"]


func _refresh() -> void:
	for idx in _barriers:
		var unlocked := GameState.region_unlocked(idx)
		(_barriers[idx] as Node3D).visible = not unlocked
		var info := GameData.region(idx)
		var lbl: Label3D = _gate_labels[idx]
		if unlocked:
			lbl.text = "OPEN  -  dust value x%s" % str(info["dust_mult"])
			lbl.modulate = Color(0.5, 1.0, 0.6)
		elif GameState.permit_requirement_met(idx):
			lbl.text = "PERMIT: %s CR" % GameState.fmt(info["permit"])
			lbl.modulate = Color(1.0, 0.8, 0.4)
		else:
			lbl.text = "LOCKED - keep completing missions"
			lbl.modulate = Color(1.0, 0.5, 0.4)
	for id in _salvage_nodes.keys():
		if GameState.salvage_taken.has(id):
			(_salvage_nodes[id] as Node3D).queue_free()
			_salvage_nodes.erase(id)
	if _probe and GameState.flags.get("probe_recovered", false):
		_probe.queue_free()
		_probe = null


func _build_facility() -> void:
	var rust := Meshes.hs(Color(0.55, 0.36, 0.25), 0.5, 0.75, Color(0, 0, 0), 0.0, 1.5, 0.7)
	var pale := Meshes.hs(Color(0.78, 0.76, 0.7), 0.3, 0.7, Color(0, 0, 0), 0.0, 1.2, 0.6)
	var dark := Meshes.hs(Color(0.2, 0.2, 0.22), 0.5, 0.6, Color(0, 0, 0), 0.0, 2.0, 0.5)
	var c := RESEARCH_CENTER
	var root := Node3D.new()
	root.position = Vector3(c.x, _y(c.x, c.y), c.y)
	add_child(root)
	# Broken domes
	for i in 4:
		var a := i * TAU / 4.0 + 0.4
		var p := Vector3(cos(a) * 22.0, 0, sin(a) * 22.0)
		var d := Meshes.part(root, Meshes.sphere(6.0 - i, 20, true), pale, p, Vector3(0.2 * (i % 2), a, 0.15 * (i - 1.5)))
		Meshes.part(root, Meshes.cyl(6.2 - i, 1.0, 20), rust, p + Vector3(0, 0.3, 0))
		_static(root, p + Vector3(0, 2.5, 0), Vector3(9.0 - i * 1.5, 5.0, 9.0 - i * 1.5))
	# Central tower (leaning) and collapsed walkway
	var tower := Meshes.part(root, Meshes.cyl(1.6, 22.0, 12, 1.0), rust, Vector3(0, 10.0, 0), Vector3(0.12, 0, 0.08))
	Meshes.part(root, Meshes.sphere(2.5, 16), dark, Vector3(1.3, 21.0, -0.8))
	Meshes.part(root, Meshes.sphere(0.4), Meshes.glow(Color(1.0, 0.2, 0.1), 3.0), Vector3(1.5, 23.6, -0.9))
	_static(root, Vector3(0, 10, 0), Vector3(3.2, 20, 3.2))
	for k in 6:
		var p := Vector3(-14.0 + k * 5.0, 1.5 + (k % 3) * 0.4, 8.0)
		Meshes.part(root, Meshes.box(Vector3(4.6, 0.3, 2.0)), dark, p, Vector3(0, 0.1 * k, 0.25 * ((k % 2) * 2 - 1)))
	Meshes.label(root, "ABANDONED\nSELENE RESEARCH STATION", Vector3(0, 12, 14), 120, Color(1.0, 0.6, 0.4), true)
	# Debris field + salvage crates
	for i in 26:
		var a := TerrainGen.hashf(i, 3, 71) * TAU
		var rr := 8.0 + TerrainGen.hashf(i, 9, 72) * 60.0
		var p := Vector3(cos(a) * rr, 0, sin(a) * rr)
		p.y = _y(c.x + p.x, c.y + p.z) - root.position.y
		Meshes.part(root, Meshes.box(Vector3(1.0 + TerrainGen.hashf(i, 1, 5) * 3.0, 0.2, 0.8 + TerrainGen.hashf(i, 2, 5) * 2.0)), rust if i % 2 == 0 else pale, p + Vector3(0, 0.1, 0), Vector3(TerrainGen.hashf(i, 4, 5) * 0.6, a, TerrainGen.hashf(i, 6, 5) * 0.5))
	for i in SALVAGE_COUNT:
		var id := "salvage_%d" % i
		if GameState.salvage_taken.has(id):
			continue
		var a := TerrainGen.hashf(i, 11, 91) * TAU
		var rr := 14.0 + TerrainGen.hashf(i, 13, 92) * 120.0
		var x := c.x + cos(a) * rr
		var z := c.y + sin(a) * rr
		if TerrainGen.region_at(x, z) != TerrainGen.Region.RESEARCH:
			x = c.x - absf(cos(a)) * rr * 0.5
		var pos := Vector3(x, _y(x, z), z)
		var crate := Node3D.new()
		crate.position = pos
		crate.rotation.y = a
		add_child(crate)
		Meshes.part(crate, Meshes.box(Vector3(1.1, 0.8, 0.8)), Meshes.hs(Color(0.95, 0.55, 0.12), 0.4, 0.5, Color(0, 0, 0), 0.0, 1.5, 0.5, 2.0), Vector3(0, 0.4, 0), Vector3(0.1, 0, 0.05))
		Meshes.part(crate, Meshes.sphere(0.12), Meshes.glow(Color(0.3, 1.0, 0.6), 4.0), Vector3(0, 0.9, 0), Vector3.ZERO, Vector3.ONE, false)
		_salvage_nodes[id] = crate
		var sid := id
		world.add_interactable(_w(pos), 2.6, func(): return "" if GameState.salvage_taken.has(sid) else "Recover salvage crate",
			func(): _take_salvage(sid), sid)


func _take_salvage(id: String) -> void:
	if GameState.salvage_taken.has(id):
		return
	GameState.add_salvage(id, float(GameData.economy["salvage_credits"]), float(GameData.economy["salvage_rp"]))
	world.remove_interactable(id)
	_refresh()


func _build_industrial() -> void:
	var steel := Meshes.hs(Color(0.5, 0.52, 0.56), 0.8, 0.35, Color(0, 0, 0), 0.0, 0.8, 0.4)
	var paint := Meshes.hs(Color(0.95, 0.4, 0.15), 0.4, 0.45, Color(0, 0, 0), 0.0, 0.8, 0.4)
	var root := Node3D.new()
	add_child(root)
	var sites := [Vector2(-60, 470), Vector2(70, 500), Vector2(170, 430), Vector2(-170, 420), Vector2(10, 540)]
	for i in sites.size():
		var s: Vector2 = sites[i]
		var base := Vector3(s.x, _y(s.x, s.y), s.y)
		var h := 30.0 + i * 8.0
		Meshes.part(root, Meshes.cyl(7.0, h, 20, 5.0), steel, base + Vector3(0, h * 0.5, 0))
		Meshes.part(root, Meshes.torus(5.0, 5.8, 24), paint, base + Vector3(0, h * 0.8, 0))
		Meshes.part(root, Meshes.cyl(1.5, h + 14.0, 10), paint, base + Vector3(10, (h + 14.0) * 0.5, 4))
		Meshes.part(root, Meshes.sphere(0.8), Meshes.glow(Color(1.0, 0.2, 0.1), 4.0), base + Vector3(10, h + 14.5, 4))
		Meshes.part(root, Meshes.cyl(0.8, 24.0, 8), steel, base + Vector3(-6, 3, 8), Vector3(0, 0, PI * 0.5))
		_static(root, base + Vector3(0, h * 0.5, 0), Vector3(12, h, 12))
	var staging := Vector3(0, _y(0, 330), 330)
	Meshes.label(root, "INDUSTRIAL EXPANSE\nAUTOMATION ZONE", staging + Vector3(0, 8, -40), 160, Color(1.0, 0.6, 0.3), true)


func _build_probe() -> void:
	if GameState.flags.get("probe_recovered", false):
		return
	var p := Vector3(PROBE_POS.x, _y(PROBE_POS.x, PROBE_POS.y), PROBE_POS.y)
	_probe = Node3D.new()
	_probe.position = p
	add_child(_probe)
	var gold := Meshes.hs(Color(0.85, 0.65, 0.25), 0.9, 0.3, Color(0, 0, 0), 0.0, 3.0, 0.4)
	var panel := Meshes.hs(Color(0.12, 0.2, 0.5), 0.8, 0.2, Color(0.02, 0.05, 0.15), 1.0, 4.0, 0.2)
	Meshes.part(_probe, Meshes.sphere(1.0, 16), gold, Vector3(0, 0.7, 0), Vector3(0.4, 0.3, 0.2))
	Meshes.part(_probe, Meshes.box(Vector3(3.2, 0.06, 1.0)), panel, Vector3(-2.0, 0.6, 0), Vector3(0.2, 0.3, 0.5))
	Meshes.part(_probe, Meshes.box(Vector3(3.2, 0.06, 1.0)), panel, Vector3(2.2, 0.3, 0.2), Vector3(-0.1, -0.2, -0.3))
	Meshes.part(_probe, Meshes.cyl(0.03, 2.0, 6), Meshes.hs(Color(0.8, 0.8, 0.8), 0.9, 0.3), Vector3(0, 1.8, 0), Vector3(0.6, 0, 0.3))
	# Tall locator beam visible from far away
	var beam := Meshes.part(_probe, Meshes.cyl(0.8, 220.0, 12), Meshes.energy(Color(0.2, 1.0, 0.5), 0.6, 0.4, 2.0), Vector3(0, 110, 0), Vector3.ZERO, Vector3.ONE, false)
	world.add_interactable(_w(p), 3.5, func(): return "" if GameState.flags.get("probe_recovered", false) else "Recover the crashed probe",
		func(): _recover_probe(), "probe")


func _recover_probe() -> void:
	GameState.flags["probe_recovered"] = true
	GameState.rp += 20
	Audio.play("pickup")
	GameState.notify.emit("Probe recovered! Its data has been sent to Research.", "mission")
	world.remove_interactable("probe")
	_refresh()


func _build_relics() -> void:
	# Old flag and descent stage in the highland bowl
	var c := TerrainGen.landmark("highland_bowl")
	var p := Vector3(c[1] + 20.0, 0, c[2] + 30.0)
	p.y = _y(p.x, p.z)
	var relic := Node3D.new()
	relic.position = p
	add_child(relic)
	Meshes.part(relic, Meshes.cyl(0.04, 3.0, 6), Meshes.hs(Color(0.8, 0.8, 0.8), 0.9, 0.3), Vector3(0, 1.5, 0))
	Meshes.part(relic, Meshes.box(Vector3(1.4, 0.9, 0.03)), Meshes.hs(Color(0.95, 0.6, 0.15), 0.0, 0.7, Color(0, 0, 0), 0.0, 3.0, 0.2, 2.5), Vector3(0.72, 2.5, 0))
	Meshes.part(relic, Meshes.cyl(1.8, 1.2, 8, 1.4), Meshes.hs(Color(0.85, 0.7, 0.3), 0.9, 0.3, Color(0, 0, 0), 0.0, 3.0, 0.4), Vector3(4, 0.6, 2))
	Meshes.label(relic, "FIRST CLEANING EXPEDITION\n(they gave up)", Vector3(0, 4.0, 0), 50, Color(0.9, 0.9, 0.9), true)
	# Great basin rim marker
	var gb := TerrainGen.landmark("great_basin")
	var m := Vector3(gb[1] - gb[3] - 6.0, 0, gb[2])
	m.y = _y(m.x, m.z)
	Meshes.part(self, Meshes.cyl(0.15, 6.0, 8), Meshes.hs(Color(0.3, 0.3, 0.32), 0.6, 0.4), m + Vector3(0, 3, 0))
	Meshes.label(self, "THE GREAT BASIN", m + Vector3(0, 7.5, 0), 140, Color(0.7, 0.85, 1.0), true)


func _static(parent: Node3D, center: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	b.position = center
	b.add_child(cs)
	parent.add_child(b)


func _process(delta: float) -> void:
	_t += delta
	for id in _salvage_nodes:
		var n: Node3D = _salvage_nodes[id]
		n.rotation.y += delta * 0.3
