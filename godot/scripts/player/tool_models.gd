class_name ToolModels
extends RefCounted
## Distinct procedural 3D models for all twelve cleaning tools.
## The "head" is the part touching the ground (local +Y = ground normal, -Z = forward).
## A shaft is drawn separately from the head's attach point to the astronaut's glove.

static func build(id: String, stats: Dictionary) -> Dictionary:
	var col := Color.html(stats.get("color", "#ffffff"))
	var head := Node3D.new()
	head.name = "Head"
	var out := {"head": head, "attach": Vector3(0, 0.12, 0.1), "shaft_r": 0.03,
		"shaft_mat": Meshes.hs(col, 0.1, 0.4), "spinners": [], "grip_mat": Meshes.hs(Color(0.95, 0.95, 0.95), 0.0, 0.6),
		"emitter": false, "hand_item": null}
	var white := Meshes.hs(Color(0.96, 0.96, 0.93), 0.0, 0.8, Color(0, 0, 0), 0.0, 8.0, 0.1)
	var dark := Meshes.hs(Color(0.18, 0.19, 0.22), 0.5, 0.45)
	var metal := Meshes.hs(Color(0.7, 0.72, 0.76), 0.85, 0.3)
	var r: float = stats.get("radius", 0.3)
	var hw: float = stats.get("half_width", 0.5)
	var hl: float = stats.get("half_length", 0.3)
	match id:
		"toothbrush", "big_toothbrush":
			var s := r / 0.2
			Meshes.part(head, Meshes.box(Vector3(0.13, 0.05, 0.36) * s), Meshes.hs(col, 0.1, 0.35), Vector3(0, 0.1 * s, 0))
			# Bristle tufts in two colours
			for i in 6:
				for k in 2:
					var tuft_col := white if (i + k) % 3 != 0 else Meshes.hs(Color(0.3, 0.8, 1.0), 0.0, 0.7)
					Meshes.part(head, Meshes.box(Vector3(0.045, 0.08, 0.045) * s), tuft_col,
						Vector3((k - 0.5) * 0.06 * s, 0.04 * s, (i - 2.5) * 0.055 * s))
			out["attach"] = Vector3(0, 0.1 * s, 0.18 * s)
			out["shaft_r"] = 0.022 * s
			out["grip_mat"] = Meshes.hs(Color(0.95, 0.95, 0.95), 0.0, 0.7)
		"hand_brush":
			Meshes.part(head, Meshes.box(Vector3(0.55, 0.12, 0.85) * (r / 0.48)), Meshes.hs(Color(0.55, 0.34, 0.18), 0.0, 0.7, Color(0, 0, 0), 0.0, 5.0, 0.4), Vector3(0, 0.14, 0))
			Meshes.part(head, Meshes.box(Vector3(0.5, 0.1, 0.8) * (r / 0.48)), Meshes.hs(col, 0.0, 0.9, Color(0, 0, 0), 0.0, 12.0, 0.2), Vector3(0, 0.05, 0))
			out["attach"] = Vector3(0, 0.2, 0.3)
			out["shaft_mat"] = Meshes.hs(Color(0.55, 0.34, 0.18), 0.0, 0.7)
			out["shaft_r"] = 0.03
		"broom":
			Meshes.part(head, Meshes.box(Vector3(hw * 2.0, 0.14, 0.22)), Meshes.hs(Color(0.45, 0.28, 0.16), 0.0, 0.7), Vector3(0, 0.22, 0))
			Meshes.part(head, Meshes.box(Vector3(hw * 2.0, 0.2, hl * 1.6)), Meshes.hs(Color(0.85, 0.7, 0.35), 0.0, 0.95, Color(0, 0, 0), 0.0, 14.0, 0.2), Vector3(0, 0.08, 0))
			out["attach"] = Vector3(0, 0.28, 0.0)
			out["shaft_mat"] = Meshes.hs(Color(0.5, 0.32, 0.18), 0.0, 0.7)
			out["shaft_r"] = 0.035
		"electric_scrubber":
			var pad := Node3D.new()
			head.add_child(pad)
			Meshes.part(pad, Meshes.cyl(r, 0.1, 24), Meshes.hs(Color(0.15, 0.15, 0.17), 0.2, 0.9, Color(0, 0, 0), 0.0, 6.0), Vector3(0, 0.05, 0))
			for i in 6:
				Meshes.part(pad, Meshes.box(Vector3(r * 1.7, 0.03, 0.05)), Meshes.hs(col, 0.2, 0.5), Vector3(0, 0.11, 0), Vector3(0, i * PI / 6.0, 0))
			out["spinners"].append(pad)
			Meshes.part(head, Meshes.cyl(r * 0.45, 0.28, 16, r * 0.35), Meshes.hs(col, 0.4, 0.35), Vector3(0, 0.25, 0))
			Meshes.part(head, Meshes.sphere(0.06), Meshes.glow(Color(0.3, 1.0, 0.8), 3.0), Vector3(0, 0.4, -r * 0.3))
			out["attach"] = Vector3(0, 0.38, 0)
			out["shaft_mat"] = metal
			out["shaft_r"] = 0.035
		"portable_vacuum", "industrial_vacuum", "suction_cleaner":
			var w := r * 1.6
			Meshes.part(head, Meshes.box(Vector3(w, 0.12, 0.35)), Meshes.hs(col, 0.3, 0.4), Vector3(0, 0.08, 0))
			Meshes.part(head, Meshes.box(Vector3(w * 1.02, 0.04, 0.38)), dark, Vector3(0, 0.015, 0))
			Meshes.part(head, Meshes.cyl(0.12, 0.25, 12), Meshes.hs(col.darkened(0.2), 0.4, 0.4), Vector3(0, 0.22, 0.05))
			if id == "industrial_vacuum":
				Meshes.part(head, Meshes.box(Vector3(w, 0.12, 0.35)), Meshes.hs(col, 0.3, 0.4), Vector3(0, 0.08, -0.4))
				Meshes.part(head, Meshes.cyl(0.1, 0.4, 12), metal, Vector3(0, 0.2, -0.2), Vector3(PI * 0.5, 0, 0))
			if id == "suction_cleaner":
				Meshes.part(head, Meshes.torus(w * 0.42, w * 0.5, 28), Meshes.glow(Color(0.4, 1.0, 0.5), 3.0), Vector3(0, 0.16, 0), Vector3.ZERO, Vector3(1, 1, 0.35))
				Meshes.part(head, Meshes.sphere(0.16, 16, true), Meshes.hs(Color(0.9, 0.95, 0.9), 0.6, 0.2), Vector3(0, 0.15, 0.05))
			out["attach"] = Vector3(0, 0.32, 0.08)
			out["shaft_mat"] = Meshes.hs(Color(0.2, 0.2, 0.24), 0.2, 0.6, Color(0, 0, 0), 0.0, 18.0, 0.1)
			out["shaft_r"] = 0.06 if id == "portable_vacuum" else 0.085
			out["suction"] = true
		"rotary_scrubber":
			var disc := Node3D.new()
			head.add_child(disc)
			Meshes.part(disc, Meshes.cyl(r, 0.16, 32), Meshes.hs(Color(0.1, 0.12, 0.15), 0.3, 0.8, Color(0, 0, 0), 0.0, 3.0), Vector3(0, 0.08, 0))
			for i in 8:
				Meshes.part(disc, Meshes.box(Vector3(r * 1.9, 0.05, 0.12)), Meshes.hs(col, 0.3, 0.4), Vector3(0, 0.18, 0), Vector3(0, i * PI / 8.0, 0))
			out["spinners"].append(disc)
			# Low motor housing: big enough to read as a machine, small enough not to block the view.
			Meshes.part(head, Meshes.sphere(r * 0.24, 20, true), Meshes.hs(col.lightened(0.2), 0.5, 0.3), Vector3(0, 0.18, 0), Vector3.ZERO, Vector3(1, 0.6, 1))
			Meshes.part(head, Meshes.torus(r * 0.95, r * 1.02, 40), Meshes.glow(col, 2.0), Vector3(0, 0.18, 0))
			out["attach"] = Vector3(0, r * 0.18, 0)
			out["shaft_mat"] = metal
			out["shaft_r"] = 0.05
		"heavy_cleaner":
			Meshes.part(head, Meshes.box(Vector3(hw * 2.0, 0.6, hl * 2.0)), Meshes.hs(col, 0.35, 0.45, Color(0, 0, 0), 0.0, 1.2, 0.35, 0.0), Vector3(0, 0.45, 0))
			Meshes.part(head, Meshes.box(Vector3(hw * 2.05, 0.18, hl * 2.05)), Meshes.hs(Color(0.12, 0.12, 0.12), 0.0, 0.8, Color(0, 0, 0), 0.0, 2.0, 0.3, 1.5), Vector3(0, 0.09, 0))
			var roller := Node3D.new()
			roller.position = Vector3(0, 0.2, -hl)
			head.add_child(roller)
			Meshes.part(roller, Meshes.cyl(0.2, hw * 2.0, 12), Meshes.hs(Color(0.2, 0.8, 1.0), 0.2, 0.6), Vector3.ZERO, Vector3(0, 0, PI * 0.5))
			out["roller"] = roller
			for i in 3:
				Meshes.part(head, Meshes.box(Vector3(0.6, 0.08, 0.05)), Meshes.glow(Color(1.0, 0.8, 0.3), 2.5), Vector3((i - 1) * hw * 0.6, 0.6, -hl - 0.01))
			Meshes.part(head, Meshes.cyl(0.25, 0.5, 12), dark, Vector3(hw * 0.6, 0.9, hl * 0.5))
			out["attach"] = Vector3(0, 0.75, hl)
			out["shaft_mat"] = dark
			out["shaft_r"] = 0.05
		"cleaning_beam", "swarm_controller":
			# No ground head - an emitter is held in the hand instead.
			var gun := Node3D.new()
			Meshes.part(gun, Meshes.box(Vector3(0.1, 0.12, 0.34)), Meshes.hs(Color(0.85, 0.88, 0.92), 0.6, 0.25), Vector3(0, 0, -0.1))
			Meshes.part(gun, Meshes.cyl(0.05, 0.2, 12), Meshes.hs(col, 0.5, 0.3), Vector3(0, 0.0, -0.32), Vector3(PI * 0.5, 0, 0))
			Meshes.part(gun, Meshes.torus(0.045, 0.07, 16), Meshes.glow(col, 3.0), Vector3(0, 0, -0.42), Vector3(PI * 0.5, 0, 0))
			Meshes.part(gun, Meshes.box(Vector3(0.06, 0.16, 0.08)), dark, Vector3(0, -0.1, 0.0), Vector3(0.3, 0, 0))
			if id == "swarm_controller":
				Meshes.part(gun, Meshes.box(Vector3(0.16, 0.02, 0.12)), Meshes.glow(col, 2.0), Vector3(0, 0.08, -0.05))
			out["hand_item"] = gun
			out["emitter"] = true
	return out


## A small cleaning drone used by the swarm controller and drone bays.
static func mini_drone(col: Color, scale := 1.0) -> Node3D:
	var d := Node3D.new()
	var body := Meshes.hs(Color(0.92, 0.93, 0.95), 0.4, 0.3)
	Meshes.part(d, Meshes.sphere(0.22 * scale, 16), body)
	Meshes.part(d, Meshes.cyl(0.25 * scale, 0.06 * scale, 16), Meshes.hs(col, 0.3, 0.4), Vector3(0, -0.08 * scale, 0))
	Meshes.part(d, Meshes.sphere(0.07 * scale), Meshes.glow(col, 3.0), Vector3(0, 0.02 * scale, -0.2 * scale))
	var props := Node3D.new()
	props.name = "Props"
	d.add_child(props)
	for i in 4:
		var a := i * PI * 0.5 + PI * 0.25
		var p := Vector3(cos(a), 0, sin(a)) * 0.38 * scale
		Meshes.part(d, Meshes.box(Vector3(0.3 * scale, 0.03, 0.04)), Meshes.hs(Color(0.3, 0.3, 0.35), 0.5, 0.4), p * 0.5, Vector3(0, -a, 0))
		Meshes.part(props, Meshes.cyl(0.14 * scale, 0.01, 12), Meshes.plain(Color(0.8, 0.85, 0.9, 1.0), 0.2, 0.3), p + Vector3(0, 0.04, 0))
	return d
