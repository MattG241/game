class_name Automation
extends Node3D
## Visual side of automation: machine models, collector sweep arms, the beams of
## Hexagon Cleaning Stations, Drone Hangar squads over their hexagon, and the placement
## ghost. The rules live in AutomationSim.

var world: Node
var sim: AutomationSim
var visuals := {}      # uid -> {root, spin, gauge, label, beam, drones}
var _tick_t := 0.0
var _t := 0.0

# placement
var placing := ""
var ghost: Node3D
var ghost_yaw := 0.0
var ghost_ok := false
var ghost_reason := ""
var ghost_link_text := ""       # what the machine will do, shown while placing
var _preview: MeshInstance3D    # collector circle while placing
var _preview_key := ""


func setup(w: Node) -> void:
	world = w
	sim = AutomationSim.new(GameState.dirt)
	if w.has_method("complete_hex"):
		sim.on_hex_cleared = Callable(w, "complete_hex")
	rebuild_all()


func rebuild_all() -> void:
	for uid in visuals.keys():
		_remove_visual(uid)
	sim.rebuild()
	for m in GameState.machines:
		_add_visual(m)


## Combined bounding box of every mesh in a model, in the model's own space.
static func model_bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var mi := n as MeshInstance3D
			var xf := _relative_xform(root, mi)
			var b: AABB = xf * mi.mesh.get_aabb()
			out = b if first else out.merge(b)
			first = false
	return out if not first else AABB(Vector3(-1, 0, -1), Vector3(2, 3, 2))


static func _relative_xform(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != root and cur is Node3D:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _add_visual(m: Dictionary) -> void:
	var built := MachineModels.build(m["id"])
	var root: Node3D = built["root"]
	var mp := AutomationSim.v3(m["pos"])
	root.transform = Transform3D(TerrainGen.heading_basis(mp, float(m["yaw"])), mp)
	add_child(root)
	# Collision matches the model's real footprint, so nothing passes through it.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := model_bounds(root)
	var sh := BoxShape3D.new()
	sh.size = Vector3(maxf(box.size.x, 1.0), maxf(box.size.y, 1.0), maxf(box.size.z, 1.0))
	cs.shape = sh
	cs.position = box.get_center()
	body.add_child(cs)
	root.add_child(body)
	# The ground under a machine can't be reached any more: no dust there.
	GameState.dirt.add_cover_box(Transform3D(root.basis, root.transform * box.get_center()), sh.size.x * 0.5, sh.size.z * 0.5)
	var info := GameData.machine(m["id"])
	var lbl := Meshes.label(root, info["name"], Vector3(0, box.end.y + 1.6, 0), 40, Color(1, 0.9, 0.6), true)
	lbl.visible = false
	built["label"] = lbl
	var col := Color.html(info.get("color", "#ffffff"))
	if m["id"] == "hex_station":
		var beam := Meshes.part(self, Meshes.cyl(0.5, 1.0, 12), Meshes.energy(col, 1.0, 2.0, 6.0), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
		beam.top_level = true
		beam.visible = false
		built["beam"] = beam
	elif m["id"] == "drone_hangar":
		var squad := Node3D.new()
		squad.top_level = true
		add_child(squad)
		for i in 6:
			squad.add_child(ToolModels.mini_drone(col, 1.4))
		built["drones"] = squad
	var uid := int(m["uid"])
	visuals[uid] = built
	world.add_interactable(root.position, 3.5, func(): return _machine_text(uid), func(): world.open_machine_panel(uid), "machine_%d" % uid)


func _machine_text(uid: int) -> String:
	var m := sim.get_machine(uid)
	if m.is_empty():
		return ""
	return "%s %s - %s" % [GameData.machine(m["id"])["name"], AutomationSim.tier_name(AutomationSim.tier(m)), m.get("status", "")]


func _remove_visual(uid: int) -> void:
	var v: Dictionary = visuals.get(uid, {})
	if v.is_empty():
		return
	(v["root"] as Node).queue_free()
	for k in ["beam", "drones"]:
		if v.has(k):
			(v[k] as Node).queue_free()
	visuals.erase(uid)
	world.remove_interactable("machine_%d" % uid)


func add_machine(id: String, pos: Vector3, yaw: float) -> void:
	var m := sim.add_machine(id, pos, yaw)
	_add_visual(m)
	GameState.machines_changed.emit()


func remove_machine(uid: int) -> void:
	_remove_visual(uid)
	var refund := sim.remove_machine(uid)
	GameState.add_credits(refund, false)
	GameState.notify.emit("Machine removed (+%s CR refund)" % GameState.fmt(refund), "info")
	GameState.machines_changed.emit()


func _process(delta: float) -> void:
	_t += delta
	var focus: Node3D = world.focus_node()
	var fp := focus.global_position if focus else Vector3.ZERO
	if not get_tree().paused:
		_tick_t += delta
		if _tick_t >= 1.0:
			_tick_t -= 1.0
			sim.tick(1.0)
	var nearest := INF
	for uid in visuals:
		var v: Dictionary = visuals[uid]
		var root: Node3D = v["root"]
		var dist := root.global_position.distance_to(fp)
		nearest = minf(nearest, dist)
		var m := sim.get_machine(uid)
		if m.is_empty():
			continue
		(v["label"] as Label3D).visible = dist < 18.0
		for s in v["spin"]:
			(s as Node3D).rotation.y += delta * (0.6 + 0.3 * AutomationSim.tier(m))
		var t := int(m.get("target", -1))
		var tp := HexGrid.center_point(t) if t >= 0 and t < HexGrid.count() else Vector3.INF
		if v.has("beam"):
			# A station's beam reaches out to the hexagon it is clearing.
			var beam: MeshInstance3D = v["beam"]
			var top := root.global_transform * Vector3(0, 7.5, 0)
			beam.visible = tp.is_finite() and top.distance_to(tp) < 400.0 and dist < 500.0
			if beam.visible:
				var w := 0.25 + 0.08 * sin(_t * 9.0)
				Meshes.span(beam, top, tp + tp.normalized() * 0.5, w)
		if v.has("drones"):
			# The squad circles over its hexagon, low enough to see them working.
			var squad: Node3D = v["drones"]
			var show := tp.is_finite() and tp.distance_to(fp) < 300.0
			squad.visible = show
			if show:
				var b := TerrainGen.frame(tp.normalized())
				var n := squad.get_child_count()
				for i in n:
					var d: Node3D = squad.get_child(i)
					var a := _t * 0.5 + i * TAU / n
					var r := 12.0 + 8.0 * sin(_t * 0.3 + i)
					var p := TerrainGen.surface(tp + (b.x * cos(a) + b.z * sin(a)) * r, 2.5)
					d.global_transform = Transform3D(TerrainGen.upright(p, b.z * cos(a) - b.x * sin(a)), p)
					(d.get_node("Props") as Node3D).rotation.y += delta * 40.0
	Audio.loop("machines", "machine_loop", nearest < 25.0, lerpf(-8.0, -30.0, clampf(nearest / 25.0, 0.0, 1.0)))
	_update_ghost()


# ------------------------------------------------------------------ placement

func start_placement(id: String) -> void:
	cancel_placement()
	placing = id
	var built := MachineModels.build(id)
	ghost = built["root"]
	add_child(ghost)
	ghost_yaw = world.player.yaw
	MachineModels.ghostify(ghost, true)


func rotate_ghost() -> void:
	ghost_yaw += PI * 0.25


func _update_ghost() -> void:
	if ghost == null:
		return
	var p: Node3D = world.player
	var fwd := -p.global_basis.z
	var pos := TerrainGen.surface(p.global_position + fwd * 8.0)
	ghost.global_transform = Transform3D(TerrainGen.heading_basis(pos, ghost_yaw), pos)
	_update_preview(pos)
	var reason := sim.can_place(placing, pos)
	var price := float(GameData.machine(placing)["price"])
	if reason == "" and not GameState.can_afford(price):
		reason = "Not enough credits"
	var ok := reason == ""
	if ok != ghost_ok or reason != ghost_reason:
		ghost_ok = ok
		ghost_reason = reason
		MachineModels.ghostify(ghost, ok)


## Explains what the machine will do here; draws a collector's circle.
func _update_preview(pos: Vector3) -> void:
	var r := 0.0
	match placing:
		"dust_collector":
			r = sim.collector_radius({"id": placing, "tier": 1})
			ghost_link_text = "Keeps this %d m circle clean and sells the dust" % int(r)
		"hex_station":
			var cell := HexGrid.cell_of(pos)
			ghost_link_text = "Clears hexagon %d%s, then the next one" % [cell + 1, " (already clean)" if GameState.hexes_done.has(cell) else ""]
		"drone_hangar":
			ghost_link_text = "Drones clear any hexagon - choose it on the map after building"
		_:
			ghost_link_text = ""
	var key := "%d|%d|%d|%d" % [roundi(pos.x * 2.0), roundi(pos.y * 2.0), roundi(pos.z * 2.0), int(r)]
	if key == _preview_key and _preview:
		return
	_preview_key = key
	if _preview == null:
		_preview = MeshInstance3D.new()
		_preview.material_override = Meshes.glow(Color(0.3, 0.9, 1.0), 2.5)
		_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_preview)
	var im := ImmediateMesh.new()
	if r > 0.0:
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		var n := 48
		var fb := TerrainGen.frame(pos.normalized())
		for i in n:
			for k in 2:
				var a := TAU * float(i + k) / n
				im.surface_add_vertex(TerrainGen.surface(pos + (fb.x * cos(a) + fb.z * sin(a)) * r, 0.3))
		im.surface_end()
	_preview.mesh = im


func confirm_placement() -> bool:
	if ghost == null:
		return false
	_update_ghost()
	if not ghost_ok:
		Audio.play("error")
		GameState.notify.emit("Can't build here: " + ghost_reason, "error")
		return false
	var info := GameData.machine(placing)
	if not GameState.spend(float(info["price"])):
		return false
	add_machine(placing, ghost.global_position, ghost_yaw)
	Audio.play("place")
	Settings.vibrate(30, 0.5)
	GameState.notify.emit(info["name"] + " built", "purchase")
	cancel_placement()
	return true


func cancel_placement() -> void:
	if ghost:
		ghost.queue_free()
		ghost = null
	placing = ""
	ghost_ok = false
	ghost_reason = ""
	ghost_link_text = ""
	_preview_key = ""
	if _preview:
		_preview.queue_free()
		_preview = null
