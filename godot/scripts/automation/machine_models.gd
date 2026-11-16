class_name MachineModels
extends RefCounted
## Procedural models for automation buildings. Returns {root, spin: [nodes], rocket, gauge}.

static func build(id: String) -> Dictionary:
	var info := GameData.machine(id)
	var col := Color.html(info.get("color", "#ffffff"))
	var root := Node3D.new()
	var out := {"root": root, "spin": [], "rocket": null, "gauge": null, "glow": null}
	var paint := Meshes.hs(col, 0.35, 0.45, Color(0, 0, 0), 0.0, 1.4, 0.3)
	var white := Meshes.hs(Color(0.86, 0.87, 0.88), 0.3, 0.5, Color(0, 0, 0), 0.0, 1.4, 0.3)
	var dark := Meshes.hs(Color(0.17, 0.18, 0.21), 0.5, 0.5, Color(0, 0, 0), 0.0, 2.0, 0.3)
	var metal := Meshes.hs(Color(0.65, 0.67, 0.7), 0.85, 0.3)
	var hazard := Meshes.hs(Color(1.0, 0.8, 0.1), 0.2, 0.5, Color(0, 0, 0), 0.0, 1.0, 0.2, 1.2)
	match id:
		"solar_array":
			Meshes.part(root, Meshes.box(Vector3(0.4, 1.6, 0.4)), dark, Vector3(0, 0.8, 0))
			var tilt := Node3D.new()
			tilt.position = Vector3(0, 1.7, 0)
			root.add_child(tilt)
			for i in 3:
				Meshes.part(tilt, Meshes.box(Vector3(1.9, 0.08, 3.4)), Meshes.hs(Color(0.08, 0.18, 0.5), 0.85, 0.12, Color(0.02, 0.06, 0.2), 1.0, 4.0, 0.05), Vector3((i - 1) * 2.0, 0, 0))
			Meshes.part(tilt, Meshes.box(Vector3(6.2, 0.12, 0.12)), metal, Vector3(0, -0.05, 0))
			tilt.rotation.x = -0.55
			out["spin"].append(tilt)
		"dust_collector":
			Meshes.part(root, Meshes.cyl(1.6, 0.4, 20), hazard, Vector3(0, 0.2, 0))
			Meshes.part(root, Meshes.cyl(1.1, 2.6, 20, 0.9), paint, Vector3(0, 1.7, 0))
			Meshes.part(root, Meshes.sphere(0.9, 16, true), white, Vector3(0, 3.0, 0))
			var arms := Node3D.new()
			arms.position = Vector3(0, 0.35, 0)
			root.add_child(arms)
			var r := minf(float(info.get("radius", 6.0)), 5.0)
			for i in 3:
				var arm := Node3D.new()
				arm.rotation.y = i * TAU / 3.0
				arms.add_child(arm)
				Meshes.part(arm, Meshes.box(Vector3(0.18, 0.18, r)), metal, Vector3(0, 0.1, -r * 0.5))
				Meshes.part(arm, Meshes.box(Vector3(1.0, 0.2, 0.5)), dark, Vector3(0, 0.0, -r + 0.3))
			out["spin"].append(arms)
			var gauge := Meshes.part(root, Meshes.box(Vector3(0.3, 1.8, 0.05)), Meshes.glow(Color(0.3, 1.0, 0.5), 2.5), Vector3(0, 1.6, -1.12), Vector3.ZERO, Vector3.ONE, false)
			out["gauge"] = gauge
		"storage_container":
			Meshes.part(root, Meshes.cyl(2.2, 0.3, 24), dark, Vector3(0, 0.15, 0))
			Meshes.part(root, Meshes.cyl(2.0, 4.4, 24), paint, Vector3(0, 2.5, 0))
			Meshes.part(root, Meshes.sphere(2.0, 24, true), white, Vector3(0, 4.7, 0))
			for k in 3:
				Meshes.part(root, Meshes.torus(1.98, 2.1, 32), dark, Vector3(0, 1.0 + k * 1.5, 0))
			var gauge := Meshes.part(root, Meshes.box(Vector3(0.35, 3.6, 0.05)), Meshes.glow(Color(0.2, 0.85, 1.0), 2.5), Vector3(0, 2.4, -2.02), Vector3.ZERO, Vector3.ONE, false)
			out["gauge"] = gauge
		"conveyor":
			Meshes.part(root, Meshes.box(Vector3(1.4, 0.6, 1.4)), dark, Vector3(0, 0.3, 0))
			Meshes.part(root, Meshes.box(Vector3(0.3, 1.8, 0.3)), paint, Vector3(0, 1.2, 0))
			var g := Meshes.part(root, Meshes.sphere(0.25), Meshes.glow(col, 3.0), Vector3(0, 2.2, 0), Vector3.ZERO, Vector3.ONE, false)
			out["glow"] = g
		"charging_station":
			Meshes.part(root, Meshes.cyl(2.4, 0.25, 24), dark, Vector3(0, 0.12, 0))
			Meshes.part(root, Meshes.torus(2.0, 2.3, 32), Meshes.glow(col, 2.0), Vector3(0, 0.27, 0))
			for i in 3:
				var a := i * TAU / 3.0
				Meshes.part(root, Meshes.cyl(0.15, 3.2, 8), metal, Vector3(cos(a) * 1.7, 1.6, sin(a) * 1.7))
			var coil := Node3D.new()
			coil.position = Vector3(0, 3.3, 0)
			root.add_child(coil)
			Meshes.part(coil, Meshes.torus(1.2, 1.5, 24), paint, Vector3.ZERO)
			Meshes.part(coil, Meshes.sphere(0.45), Meshes.glow(col, 4.0), Vector3.ZERO)
			out["spin"].append(coil)
		"hex_station":
			# Hexagonal pad, mast and a turning emitter that beams at its hexagon.
			Meshes.part(root, Meshes.cyl(3.0, 0.35, 6), hazard, Vector3(0, 0.17, 0))
			Meshes.part(root, Meshes.cyl(2.4, 1.2, 6), dark, Vector3(0, 0.9, 0))
			Meshes.part(root, Meshes.cyl(0.6, 5.0, 12, 0.4), paint, Vector3(0, 3.9, 0))
			var head := Node3D.new()
			head.position = Vector3(0, 7.0, 0)
			root.add_child(head)
			Meshes.part(head, Meshes.torus(0.9, 1.25, 24), Meshes.glow(col, 3.0), Vector3.ZERO)
			Meshes.part(head, Meshes.sphere(0.6, 16), white, Vector3(0, 0.5, 0))
			Meshes.part(head, Meshes.box(Vector3(3.0, 0.15, 0.3)), metal, Vector3(0, 0.0, 0))
			out["spin"].append(head)
		"drone_hangar":
			Meshes.part(root, Meshes.box(Vector3(7.0, 0.3, 6.0)), dark, Vector3(0, 0.15, 0))
			Meshes.part(root, Meshes.box(Vector3(6.6, 3.0, 0.4)), paint, Vector3(0, 1.8, 2.7))
			Meshes.part(root, Meshes.box(Vector3(6.6, 0.4, 5.6)), white, Vector3(0, 3.4, 0.0))
			for x in [-2.0, 0.0, 2.0]:
				Meshes.part(root, Meshes.torus(0.7, 0.85, 20), Meshes.glow(col, 2.5), Vector3(x, 0.32, -1.0))
			var radar := Node3D.new()
			radar.position = Vector3(2.5, 3.6, 1.5)
			root.add_child(radar)
			Meshes.part(radar, Meshes.box(Vector3(1.6, 0.6, 0.1)), metal, Vector3(0, 0.5, 0))
			out["spin"].append(radar)
		"drone_bay":
			Meshes.part(root, Meshes.box(Vector3(4.0, 0.3, 4.0)), dark, Vector3(0, 0.15, 0))
			Meshes.part(root, Meshes.box(Vector3(3.6, 2.2, 1.2)), paint, Vector3(0, 1.4, 1.4))
			Meshes.part(root, Meshes.torus(1.1, 1.3, 28), Meshes.glow(col, 2.5), Vector3(0, 0.32, -0.5))
			Meshes.part(root, Meshes.box(Vector3(3.0, 0.5, 0.06)), Meshes.glow(Color(1, 1, 1), 1.0), Vector3(0, 2.2, 0.78), Vector3.ZERO, Vector3.ONE, false)
		"rover_garage":
			Meshes.part(root, Meshes.box(Vector3(6.0, 0.3, 7.0)), dark, Vector3(0, 0.15, 0))
			Meshes.part(root, Meshes.box(Vector3(5.6, 3.4, 0.4)), paint, Vector3(0, 1.9, 3.2))
			Meshes.part(root, Meshes.box(Vector3(0.4, 3.4, 6.0)), paint, Vector3(-2.8, 1.9, 0.4))
			Meshes.part(root, Meshes.box(Vector3(0.4, 3.4, 6.0)), paint, Vector3(2.8, 1.9, 0.4))
			Meshes.part(root, Meshes.box(Vector3(6.2, 0.4, 7.0)), white, Vector3(0, 3.7, 0.4))
			Meshes.part(root, Meshes.box(Vector3(5.0, 0.15, 0.06)), Meshes.glow(Color(1.0, 0.8, 0.2), 3.0), Vector3(0, 3.4, -3.0), Vector3.ZERO, Vector3.ONE, false)
		"processor":
			Meshes.part(root, Meshes.box(Vector3(5.0, 3.0, 4.0)), paint, Vector3(0, 1.5, 0))
			Meshes.part(root, Meshes.cyl(0.6, 6.0, 12), metal, Vector3(1.6, 4.0, 1.0))
			Meshes.part(root, Meshes.cyl(0.9, 4.0, 16, 0.6), dark, Vector3(-1.4, 4.5, -0.6))
			var furnace := Meshes.part(root, Meshes.box(Vector3(2.0, 1.0, 0.06)), Meshes.glow(Color(1.0, 0.45, 0.1), 3.0), Vector3(0, 1.3, -2.02), Vector3.ZERO, Vector3.ONE, false)
			out["glow"] = furnace
			var fan := Node3D.new()
			fan.position = Vector3(1.6, 7.05, 1.0)
			root.add_child(fan)
			Meshes.part(fan, Meshes.box(Vector3(1.1, 0.05, 0.2)), dark)
			Meshes.part(fan, Meshes.box(Vector3(0.2, 0.05, 1.1)), dark)
			out["spin"].append(fan)
		"shipping_depot":
			Meshes.part(root, Meshes.cyl(3.4, 0.4, 28), dark, Vector3(0, 0.2, 0))
			Meshes.part(root, Meshes.torus(3.0, 3.3, 36), hazard, Vector3(0, 0.42, 0))
			for i in 4:
				var a := i * TAU / 4.0
				Meshes.part(root, Meshes.box(Vector3(0.3, 6.0, 0.3)), metal, Vector3(cos(a) * 2.6, 3.0, sin(a) * 2.6))
			var rocket := Node3D.new()
			rocket.position = Vector3(0, 0.4, 0)
			root.add_child(rocket)
			Meshes.part(rocket, Meshes.cyl(0.8, 4.2, 16), white, Vector3(0, 2.5, 0))
			Meshes.part(rocket, Meshes.cyl(0.8, 1.6, 16, 0.02), Meshes.hs(Color(1.0, 0.4, 0.15), 0.3, 0.4), Vector3(0, 5.4, 0))
			for i in 3:
				var a := i * TAU / 3.0
				Meshes.part(rocket, Meshes.box(Vector3(0.1, 1.2, 0.9)), Meshes.hs(Color(1.0, 0.4, 0.15), 0.3, 0.4), Vector3(cos(a) * 0.8, 0.9, sin(a) * 0.8), Vector3(0, -a, 0))
			var flame := Meshes.part(rocket, Meshes.cyl(0.6, 2.5, 12, 0.05), Meshes.energy(Color(1.0, 0.6, 0.2), 2.0, 4.0, 4.0), Vector3(0, -0.9, 0), Vector3(PI, 0, 0), Vector3.ONE, false)
			flame.name = "Flame"
			flame.visible = false
			out["rocket"] = rocket
	return out


static func ghostify(node: Node, ok: bool) -> void:
	var m := Meshes.energy(Color(0.2, 1.0, 0.5) if ok else Color(1.0, 0.25, 0.2), 0.8, 2.0, 8.0)
	_apply(node, m)


static func _apply(node: Node, m: Material) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).material_override = m
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		_apply(c, m)
