class_name LunarBase
extends Node3D
## The Landing Zone base: habitat, Dust Exchange, Equipment terminal, Research lab,
## Vehicle Bay, lander and decorative industry. Registers its interactables with the world.

const EXCHANGE_POS := Vector3(11, 0, -3)
const SHOP_POS := Vector3(-11, 0, -3)
const LAB_POS := Vector3(-15, 0, -18)
const BAY_POS := Vector3(-19, 0, 14)
const NPC_POS := Vector3(-7.5, 0, 1.5)

var world: Node
var lander: Node3D
var _beacons: Array = []
var _hopper_spin: Node3D
var _npc: Node3D
var _t := 0.0


func build(w: Node) -> void:
	world = w
	var white := Meshes.hs(Color(0.88, 0.89, 0.9), 0.2, 0.55, Color(0, 0, 0), 0.0, 1.2, 0.3)
	var grey := Meshes.hs(Color(0.45, 0.47, 0.52), 0.6, 0.45, Color(0, 0, 0), 0.0, 1.5, 0.4)
	var dark := Meshes.hs(Color(0.16, 0.17, 0.2), 0.4, 0.5, Color(0, 0, 0), 0.0, 2.0, 0.3)
	var orange := Meshes.hs(Color(1.0, 0.55, 0.12), 0.3, 0.45)
	var yellow := Meshes.hs(Color(1.0, 0.82, 0.15), 0.3, 0.45, Color(0, 0, 0), 0.0, 1.5, 0.3)
	var hazard := Meshes.hs(Color(1.0, 0.8, 0.1), 0.2, 0.5, Color(0, 0, 0), 0.0, 1.0, 0.2, 1.2)
	var window := Meshes.glow(Color(1.0, 0.85, 0.55), 2.2)
	var cyan_glow := Meshes.glow(Color(0.2, 0.9, 1.0), 2.5)

	# Base floor pad

	# Habitat hub: dome + modules
	var hab := Node3D.new()
	hab.position = Vector3(0, 0, -16)
	add_child(hab)
	Meshes.part(hab, Meshes.cyl(7.0, 1.4, 32), grey, Vector3(0, 0.7, 0))
	Meshes.part(hab, Meshes.sphere(6.8, 32, true), white, Vector3(0, 1.4, 0))
	Meshes.part(hab, Meshes.torus(6.7, 7.1, 48), orange, Vector3(0, 1.45, 0))
	for i in 8:
		var a := i * TAU / 8.0
		Meshes.part(hab, Meshes.box(Vector3(1.4, 0.5, 0.1)), window, Vector3(cos(a) * 6.55, 2.6, sin(a) * 6.55), Vector3(0, -a + PI * 0.5, 0), Vector3.ONE, false)
	Meshes.part(hab, Meshes.sphere(1.2, 16), Meshes.glow(Color(0.6, 0.9, 1.0), 1.2), Vector3(0, 8.0, 0))
	# side modules
	for side in [-1, 1]:
		var m := Meshes.part(hab, Meshes.cyl(2.2, 9.0, 24), white, Vector3(side * 10.0, 2.2, 0), Vector3(0, 0, PI * 0.5))
		Meshes.part(hab, Meshes.box(Vector3(9.0, 0.35, 0.1)), window, Vector3(side * 10.0, 2.8, 2.18), Vector3.ZERO, Vector3.ONE, false)
		Meshes.part(hab, Meshes.cyl(2.35, 0.4, 24), orange, Vector3(side * 14.4, 2.2, 0), Vector3(0, 0, PI * 0.5))
		for k in 2:
			Meshes.part(hab, Meshes.box(Vector3(0.4, 2.0, 0.4)), dark, Vector3(side * (7.5 + k * 5.0), 0.6, 0))
	_static_box(Vector3(0, 3, -16), Vector3(14, 6, 14))
	_static_box(Vector3(-10, 2.2, -16), Vector3(9.5, 4.4, 4.4))
	_static_box(Vector3(10, 2.2, -16), Vector3(9.5, 4.4, 4.4))
	Meshes.label(self, "LUNAR CLEANUP CO.", Vector3(0, 6.1, -9.6), 160, Color(1.0, 0.65, 0.2))
	Meshes.label(self, "HQ - EST. TODAY", Vector3(0, 4.9, -9.4), 70, Color(0.8, 0.9, 1.0))

	# Dust Exchange: hopper funnel on a platform with a glowing screen
	var ex := Node3D.new()
	ex.position = EXCHANGE_POS
	add_child(ex)
	Meshes.part(ex, Meshes.box(Vector3(6.0, 0.5, 5.0)), hazard, Vector3(0, 0.25, 0))
	Meshes.part(ex, Meshes.cyl(2.2, 2.6, 24, 2.2), yellow, Vector3(0, 1.8, -0.6))
	Meshes.part(ex, Meshes.cyl(0.6, 2.4, 20, 2.4), yellow, Vector3(0, 4.3, -0.6))
	_hopper_spin = Node3D.new()
	_hopper_spin.position = Vector3(0, 5.6, -0.6)
	ex.add_child(_hopper_spin)
	for i in 4:
		Meshes.part(_hopper_spin, Meshes.box(Vector3(4.4, 0.12, 0.25)), dark, Vector3.ZERO, Vector3(0, i * PI * 0.25, 0))
	Meshes.part(ex, Meshes.torus(2.3, 2.5, 40), Meshes.glow(Color(1.0, 0.75, 0.2), 2.0), Vector3(0, 5.55, -0.6))
	for i in 4:
		var a := i * TAU / 4.0 + PI * 0.25
		Meshes.part(ex, Meshes.box(Vector3(0.3, 5.4, 0.3)), dark, Vector3(cos(a) * 2.2, 2.9, -0.6 + sin(a) * 2.2))
	Meshes.part(ex, Meshes.box(Vector3(2.4, 1.4, 0.2)), dark, Vector3(0, 1.6, 1.9), Vector3(-0.3, 0, 0))
	Meshes.part(ex, Meshes.box(Vector3(2.1, 1.1, 0.05)), Meshes.glow(Color(1.0, 0.7, 0.15), 1.6), Vector3(0, 1.62, 2.02), Vector3(-0.3, 0, 0), Vector3.ONE, false)
	Meshes.label(ex, "DUST\nEXCHANGE", Vector3(0, 7.2, -0.6), 120, Color(1.0, 0.8, 0.2), true)
	_static_box(EXCHANGE_POS + Vector3(0, 2.5, -0.6), Vector3(4.6, 5.0, 4.6))
	_light(EXCHANGE_POS + Vector3(0, 4, 3), Color(1.0, 0.75, 0.4), 14.0, 2.5)
	world.add_interactable(at(EXCHANGE_POS + Vector3(0, 0, 2.5)), 4.5, func(): return _sell_text(), func(): world.sell_all(), "exchange")

	# Equipment terminal kiosk
	var sh := Node3D.new()
	sh.position = SHOP_POS
	add_child(sh)
	Meshes.part(sh, Meshes.box(Vector3(5.0, 0.4, 4.0)), grey, Vector3(0, 0.2, 0))
	Meshes.part(sh, Meshes.box(Vector3(4.4, 3.2, 1.2)), white, Vector3(0, 2.0, -1.2))
	Meshes.part(sh, Meshes.box(Vector3(4.8, 0.3, 2.6)), orange, Vector3(0, 3.75, -0.6))
	Meshes.part(sh, Meshes.box(Vector3(3.4, 1.6, 0.06)), cyan_glow, Vector3(0, 2.2, -0.58), Vector3.ZERO, Vector3.ONE, false)
	Meshes.label(sh, "EQUIPMENT", Vector3(0, 4.5, -0.6), 110, Color(0.4, 0.9, 1.0), true)
	# display rack of giant toothbrushes
	for i in 3:
		var tb := Meshes.part(sh, Meshes.cyl(0.05, 2.2, 8), Meshes.hs([Color(0.3, 0.75, 1.0), Color(1.0, 0.45, 0.25), Color(1.0, 0.8, 0.2)][i], 0.1, 0.4), Vector3(-1.6 + i * 1.6, 1.4, 0.9), Vector3(0.25, 0, 0))
	_static_box(SHOP_POS + Vector3(0, 1.8, -1.2), Vector3(4.4, 3.6, 1.4))
	_light(SHOP_POS + Vector3(0, 3.0, 2.0), Color(0.4, 0.85, 1.0), 12.0, 2.0)
	world.add_interactable(at(SHOP_POS + Vector3(0, 0, 1.4)), 4.2, func(): return "Open Equipment Shop", func(): world.open_menu("shop"), "shop")

	# Research lab
	var lab := Node3D.new()
	lab.position = LAB_POS
	add_child(lab)
	Meshes.part(lab, Meshes.cyl(4.0, 1.0, 24), grey, Vector3(0, 0.5, 0))
	Meshes.part(lab, Meshes.sphere(3.8, 24, true), Meshes.hs(Color(0.75, 0.85, 0.95), 0.6, 0.2), Vector3(0, 1.0, 0))
	Meshes.part(lab, Meshes.box(Vector3(0.25, 4.0, 0.25)), dark, Vector3(2.6, 4.4, 0))
	var dish := Meshes.part(lab, Meshes.sphere(1.3, 16, true), white, Vector3(2.6, 6.6, 0), Vector3(PI * 0.75, 0.6, 0))
	Meshes.part(lab, Meshes.box(Vector3(2.0, 1.0, 0.06)), Meshes.glow(Color(0.6, 0.5, 1.0), 2.0), Vector3(0, 1.6, 3.72), Vector3.ZERO, Vector3.ONE, false)
	Meshes.label(lab, "RESEARCH", Vector3(0, 6.0, 0), 100, Color(0.75, 0.65, 1.0), true)
	_static_box(LAB_POS + Vector3(0, 2.0, 0), Vector3(7, 4, 7))
	world.add_interactable(at(LAB_POS + Vector3(0, 0, 4.8)), 4.0, func(): return "Research Lab", func(): world.open_menu("research"), "lab")

	# Vehicle bay
	var bay := Node3D.new()
	bay.position = BAY_POS
	add_child(bay)
	Meshes.part(bay, Meshes.box(Vector3(10, 0.2, 24)), Meshes.hs(Color(0.22, 0.23, 0.26), 0.3, 0.7, Color(0, 0, 0), 0.0, 0.4, 0.5), Vector3(0, 0.1, 3))
	for i in 4:
		Meshes.part(bay, Meshes.box(Vector3(9.4, 0.04, 0.2)), hazard, Vector3(0, 0.22, -8.5 + i * 7.0), Vector3.ZERO, Vector3.ONE, false)
	for z in [-9.0, 15.0]:
		for x in [-5.0, 5.0]:
			Meshes.part(bay, Meshes.cyl(0.15, 3.0, 8), dark, Vector3(x, 1.5, z))
			Meshes.part(bay, Meshes.sphere(0.25), Meshes.glow(Color(1.0, 0.6, 0.1), 3.0), Vector3(x, 3.1, z))
	Meshes.label(bay, "VEHICLE BAY", Vector3(0, 3.8, -9.0), 100, Color(1.0, 0.7, 0.3), true)
	world.add_interactable(at(BAY_POS + Vector3(5.5, 0, -9.0)), 3.5, func(): return "Vehicle Dealer", func(): world.open_menu("vehicles"), "bay")

	# Lander (how you arrived)
	lander = Node3D.new()
	lander.position = Vector3(4, 0, 30)
	lander.rotation.y = 0.4
	add_child(lander)
	# The pad stays on the ground when the lander flies home at the end.
	var pad := Node3D.new()
	pad.position = lander.position
	add_child(pad)
	Meshes.part(pad, Meshes.cyl(8.0, 0.25, 40), Meshes.hs(Color(0.3, 0.3, 0.33), 0.1, 0.8, Color(0, 0, 0), 0.0, 0.5, 0.4, 0.0), Vector3(0, 0.12, 0))
	Meshes.part(pad, Meshes.torus(7.4, 7.9, 48), hazard, Vector3(0, 0.26, 0))
	Meshes.part(lander, Meshes.cyl(2.2, 2.4, 8, 1.7), Meshes.hs(Color(0.85, 0.75, 0.4), 0.9, 0.3, Color(0, 0, 0), 0.0, 3.0, 0.3), Vector3(0, 2.6, 0))
	Meshes.part(lander, Meshes.cyl(1.6, 2.0, 12, 1.0), white, Vector3(0, 4.8, 0))
	Meshes.part(lander, Meshes.sphere(0.5), window, Vector3(0, 5.0, -1.2))
	for i in 4:
		var a := i * TAU / 4.0 + PI * 0.25
		var foot := Vector3(cos(a) * 4.0, 0.3, sin(a) * 4.0)
		var top := Vector3(cos(a) * 1.8, 2.0, sin(a) * 1.8)
		var leg := Meshes.part(lander, Meshes.cyl(0.5, 1.0, 8), grey)
		Meshes.span_local(leg, foot, top, 0.24)
		Meshes.part(lander, Meshes.cyl(0.55, 0.15, 12), dark, foot)
	_static_box(Vector3(4, 3, 30), Vector3(4.2, 6, 4.2))

	# Solar farm (decorative) and comms tower
	for i in 6:
		var px := 18.0 + (i % 3) * 4.2
		var pz := -22.0 + (i / 3) * 5.0
		Meshes.part(self, Meshes.box(Vector3(0.2, 1.4, 0.2)), dark, Vector3(px, 0.7, pz))
		Meshes.part(self, Meshes.box(Vector3(3.8, 0.08, 2.6)), Meshes.hs(Color(0.1, 0.2, 0.55), 0.8, 0.15, Color(0.02, 0.05, 0.15), 1.0, 5.0, 0.1), Vector3(px, 1.5, pz), Vector3(-0.45, 0, 0))
		_static_box(Vector3(px, 1.1, pz), Vector3(3.8, 2.2, 2.4))
	var tower := Node3D.new()
	tower.position = Vector3(6, 0, -27)
	add_child(tower)
	for k in 3:
		var a := k * TAU / 3.0
		Meshes.part(tower, Meshes.cyl(0.12, 16.0, 6), grey, Vector3(cos(a) * 0.9, 8.0, sin(a) * 0.9))
	for h in 5:
		Meshes.part(tower, Meshes.torus(0.85, 1.0, 12), grey, Vector3(0, 2.0 + h * 3.0, 0))
	var beacon := Meshes.part(tower, Meshes.sphere(0.35), Meshes.glow(Color(1.0, 0.15, 0.1), 4.0), Vector3(0, 16.4, 0))
	_beacons.append(beacon)

	# Perimeter lamps
	for i in 14:
		var a := i * TAU / 14.0
		var p := Vector3(cos(a) * 29.0, 0, -2 + sin(a) * 29.0)
		Meshes.part(self, Meshes.cyl(0.08, 2.4, 6), dark, p + Vector3(0, 1.2, 0))
		var b := Meshes.part(self, Meshes.sphere(0.16), Meshes.glow(Color(1.0, 0.65, 0.2), 3.0), p + Vector3(0, 2.5, 0))
		_beacons.append(b)
	_light(Vector3(0, 6, -6), Color(1.0, 0.9, 0.8), 26.0, 1.4)

	# Supervisor NPC
	_npc = Meshes.astronaut(Color(0.2, 0.7, 1.0))
	_npc.position = NPC_POS
	_npc.rotation.y = PI * 0.15
	add_child(_npc)
	Meshes.label(self, "Supervisor Gleam", NPC_POS + Vector3(0, 2.3, 0), 48, Color(0.6, 0.9, 1.0), true)
	world.add_interactable(at(NPC_POS), 3.0, func(): return "Talk to Supervisor", func(): world.supervisor_talk(), "npc")

	# Tutorial crater sign
	var tc := TerrainGen.landmark("tutorial_crater")
	var sign_pos := Vector3(tc[1] - 14.0, 0, tc[2] + 10.0)
	sign_pos.y = TerrainGen.height(sign_pos.x, sign_pos.z)
	Meshes.part(self, Meshes.cyl(0.08, 2.2, 6), dark, sign_pos + Vector3(0, 1.1, 0))
	Meshes.label(self, "TUTORIAL CRATER\nclean me!", sign_pos + Vector3(0, 2.6, 0), 56, Color(1.0, 0.8, 0.3), true)
	# Everything above was laid out flat (map coordinates): stand it on the round Moon.
	SphereLayout.wrap(self)


## World position of a point of the flat base layout (x, z = map coordinates, y = height
## above the Moon's mean radius; the base pad is at height 0).
static func at(flat: Vector3) -> Vector3:
	return TerrainGen.map_point(flat.x, flat.z, flat.y)


## Transform for a flat-layout point turned yaw radians (yaw as on the old flat map).
static func at_xform(flat: Vector3, yaw: float) -> Transform3D:
	var t := TerrainGen.map_xform(flat.x, flat.z, flat.y)
	t.basis = t.basis * Basis(Vector3.UP, yaw)
	return t


## Where a new astronaut stands: just in front of the habitat.
static func spawn_point() -> Vector3:
	return at(Vector3(0, 1.0, 14))


func _sell_text() -> String:
	var amount: float = GameState.tank_dust + world.vehicle_hopper_amount()
	if amount < 0.5:
		return "Dust Exchange (tank empty)"
	var value: float = (GameState.tank_value + world.vehicle_hopper_value()) * GameState.dust_price()
	return "SELL %s dust for %s CR" % [GameState.fmt(amount), GameState.fmt(value)]


func _static_box(center: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	b.position = center
	b.add_child(cs)
	add_child(b)


func _light(pos: Vector3, col: Color, rng: float, energy: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.omni_range = rng
	l.light_energy = energy
	l.shadow_enabled = false
	add_child(l)


func _process(delta: float) -> void:
	_t += delta
	if _hopper_spin:
		_hopper_spin.rotation.y += delta * 0.8
	var blink := fmod(_t, 1.6) < 0.25
	for b in _beacons:
		(b as Node3D).visible = blink or b != _beacons[0]
	if _npc:
		_npc.get_node("ArmR").rotation.z = 0.3 + sin(_t * 2.2) * 0.25
		_npc.position.y = sin(_t * 1.3) * 0.02
