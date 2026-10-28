class_name Automation
extends Node3D
## Visual side of automation: machine models, conveyor belts between linked machines,
## drones/rovers (smooth per-frame motion only near the player), rocket launches and
## the placement ghost.

var world: Node
var sim: AutomationSim
var visuals := {}      # uid -> {root, spin, gauge, rocket, agent_node}
var _belts: Node3D
var _tick_t := 0.0
var _near := {}
var _belt_mat: ShaderMaterial
var _t := 0.0

# placement
var placing := ""
var ghost: Node3D
var ghost_yaw := 0.0
var ghost_ok := false
var ghost_reason := ""


func setup(w: Node) -> void:
	world = w
	sim = AutomationSim.new(GameState.dirt)
	_belts = Node3D.new()
	add_child(_belts)
	_belt_mat = Meshes.energy(Color(1.0, 0.7, 0.25), 0.6, 1.5, 12.0)
	rebuild_all()


func rebuild_all() -> void:
	for uid in visuals.keys():
		_remove_visual(uid)
	sim.rebuild()
	for m in GameState.machines:
		_add_visual(m)
	_rebuild_belts()


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
	root.position = AutomationSim.v3(m["pos"])
	root.rotation.y = float(m["yaw"])
	add_child(root)
	# Collision matches the model's real footprint (solar arrays are much wider
	# than the core), so vehicles and the player can't pass through any part.
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
	var c := root.position + Basis(Vector3.UP, root.rotation.y) * box.get_center()
	GameState.dirt.add_cover_box(c.x, c.z, sh.size.x * 0.5, sh.size.z * 0.5, root.rotation.y)
	var info := GameData.machine(m["id"])
	var lbl := Meshes.label(root, info["name"], Vector3(0, 5.6, 0), 40, Color(1, 0.9, 0.6), true)
	lbl.visible = false
	built["label"] = lbl
	var uid := int(m["uid"])
	if m.has("agent"):
		var agent: Node3D
		if m["id"] == "drone_bay":
			agent = ToolModels.mini_drone(Color.html(info["color"]), 1.3)
		else:
			agent = _rover_model(Color.html(info["color"]))
		agent.top_level = true
		add_child(agent)
		agent.global_position = AutomationSim.v3(m["agent"]["p"])
		built["agent_node"] = agent
	visuals[uid] = built
	world.add_interactable(root.position, 3.5, func(): return _machine_text(uid), func(): world.open_machine_panel(uid), "machine_%d" % uid)


func _rover_model(col: Color) -> Node3D:
	var r := Node3D.new()
	Meshes.part(r, Meshes.box(Vector3(1.6, 0.6, 2.4)), Meshes.hs(col, 0.4, 0.4), Vector3(0, 0.6, 0))
	Meshes.part(r, Meshes.box(Vector3(3.4, 0.3, 0.8)), Meshes.hs(Color(0.2, 0.2, 0.22), 0.4, 0.6, Color(0, 0, 0), 0.0, 1.0, 0.3, 1.2), Vector3(0, 0.25, 1.4))
	Meshes.part(r, Meshes.sphere(0.25), Meshes.glow(Color(0.3, 1.0, 0.5), 3.0), Vector3(0, 1.1, -0.6))
	for zi in [-1, 1]:
		for xi in [-1, 1]:
			Meshes.part(r, Meshes.cyl(0.35, 0.3, 12), Meshes.hs(Color(0.12, 0.12, 0.12), 0.1, 0.9), Vector3(xi * 0.95, 0.35, zi * 0.8), Vector3(0, 0, PI * 0.5))
	return r


func _machine_text(uid: int) -> String:
	var m := sim.get_machine(uid)
	if m.is_empty():
		return ""
	return "%s - %s" % [GameData.machine(m["id"])["name"], m.get("status", "")]


func _remove_visual(uid: int) -> void:
	var v: Dictionary = visuals.get(uid, {})
	if v.is_empty():
		return
	(v["root"] as Node).queue_free()
	if v.has("agent_node"):
		(v["agent_node"] as Node).queue_free()
	visuals.erase(uid)
	world.remove_interactable("machine_%d" % uid)


func _rebuild_belts() -> void:
	for c in _belts.get_children():
		c.queue_free()
	for e in sim.edges:
		var a := AutomationSim.BASE_POS if e[0] == AutomationSim.BASE_UID else AutomationSim.v3(sim.get_machine(e[0]).get("pos", [0, 0, 0]))
		var b := AutomationSim.BASE_POS if e[1] == AutomationSim.BASE_UID else AutomationSim.v3(sim.get_machine(e[1]).get("pos", [0, 0, 0]))
		_belt(a, b)


func _belt(a: Vector3, b: Vector3) -> void:
	var dir := Vector3(b.x - a.x, 0, b.z - a.z)
	var length := dir.length()
	if length < 0.5:
		return
	var segs := maxi(int(length / 6.0), 1)
	var frame := Meshes.hs(Color(0.25, 0.26, 0.3), 0.6, 0.45, Color(0, 0, 0), 0.0, 2.0, 0.3)
	for i in segs:
		var p0 := a.lerp(b, float(i) / segs)
		var p1 := a.lerp(b, float(i + 1) / segs)
		p0.y = TerrainGen.height(p0.x, p0.z) + 0.9
		p1.y = TerrainGen.height(p1.x, p1.z) + 0.9
		var seg := Node3D.new()
		_belts.add_child(seg)
		var mid := (p0 + p1) * 0.5
		var l := p0.distance_to(p1)
		var bar := Meshes.part(seg, Meshes.box(Vector3(0.9, 0.18, 1.0)), frame)
		bar.look_at_from_position(mid, p1, Vector3.UP)
		bar.scale = Vector3(1, 1, l)
		var strip := Meshes.part(seg, Meshes.box(Vector3(0.6, 0.02, 1.0)), _belt_mat, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
		strip.look_at_from_position(mid + Vector3(0, 0.11, 0), p1 + Vector3(0, 0.11, 0), Vector3.UP)
		strip.scale = Vector3(1, 1, l)
		var leg := Meshes.part(seg, Meshes.box(Vector3(0.15, 1.0, 0.15)), frame, Vector3(mid.x, TerrainGen.height(mid.x, mid.z) + 0.4, mid.z))


func add_machine(id: String, pos: Vector3, yaw: float) -> void:
	var m := sim.add_machine(id, pos, yaw)
	_add_visual(m)
	_rebuild_belts()
	GameState.machines_changed.emit()


func remove_machine(uid: int) -> void:
	_remove_visual(uid)
	var refund := sim.remove_machine(uid)
	GameState.add_credits(refund, false)
	GameState.notify.emit("Machine removed (+%s CR refund)" % GameState.fmt(refund), "info")
	_rebuild_belts()
	GameState.machines_changed.emit()


func _process(delta: float) -> void:
	_t += delta
	var focus: Node3D = world.focus_node()
	var fp := focus.global_position if focus else Vector3.ZERO
	# Determine which agents are simulated per-frame (near the player).
	_near.clear()
	for m in GameState.machines:
		if m.has("agent") and AutomationSim.v3(m["agent"]["p"]).distance_to(fp) < AutomationSim.NEAR_DISTANCE:
			_near[int(m["uid"])] = true
	if not get_tree().paused:
		for m in GameState.machines:
			if _near.has(int(m["uid"])):
				sim.update_agent(m, delta)
		_tick_t += delta
		if _tick_t >= 1.0:
			_tick_t -= 1.0
			sim.tick(1.0, _near)
			for uid in sim.ship_events:
				_launch(uid)
				if visuals.has(uid) and (visuals[uid]["root"] as Node3D).global_position.distance_to(fp) < 120.0:
					Audio.play("rocket", -6.0)
	# Visual animation only for nearby machines.
	for uid in visuals:
		var v: Dictionary = visuals[uid]
		var root: Node3D = v["root"]
		var dist := root.global_position.distance_to(fp)
		var m := sim.get_machine(uid)
		if m.is_empty():
			continue
		(v["label"] as Label3D).visible = dist < 18.0
		if v.has("agent_node"):
			var an: Node3D = v["agent_node"]
			var target := AutomationSim.v3(m["agent"]["p"])
			an.visible = dist < 260.0
			if an.visible:
				var prev := an.global_position
				an.global_position = prev.lerp(target, minf(delta * 8.0, 1.0)) if prev.distance_to(target) < 10.0 else target
				var mv := an.global_position - prev
				if mv.length() > 0.01:
					an.rotation.y = atan2(-mv.x, -mv.z)
				if an.has_node("Props"):
					(an.get_node("Props") as Node3D).rotation.y += delta * 40.0
		if dist > 140.0:
			continue
		var working: bool = m.get("status", "") in ["Cleaning surface", "Deep extraction", "Refining", "Cleaning"] or m["id"] in ["solar_array", "charging_station", "conveyor"]
		for s in v["spin"]:
			if m["id"] == "solar_array":
				(s as Node3D).rotation.x = -0.55 + sin(_t * 0.05) * 0.05
			else:
				(s as Node3D).rotation.y += delta * (1.2 if working else 0.1)
		if v["gauge"]:
			var g: Node3D = v["gauge"]
			var fill := 0.0
			if m["id"] == "storage_container":
				fill = sim.stored(m) / maxf(sim.storage_capacity(m), 1.0)
			else:
				fill = float(m.get("d", 0.0)) / maxf(sim.buffer_capacity(m), 1.0)
			g.scale.y = clampf(fill, 0.03, 1.0)
		if v["rocket"]:
			var r: Node3D = v["rocket"]
			var lt := float(m.get("launch_t", -1.0))
			if lt >= 0.0:
				lt += delta
				m["launch_t"] = lt
				r.position.y = 0.4 + lt * lt * 6.0
				r.get_node("Flame").visible = true
				if lt > 3.0:
					m["launch_t"] = -1.0
					r.position.y = 0.4
					r.get_node("Flame").visible = false
	# Machine hum near the player
	var nearest := INF
	for uid in visuals:
		nearest = minf(nearest, (visuals[uid]["root"] as Node3D).global_position.distance_to(fp))
	Audio.loop("machines", "machine_loop", nearest < 25.0, lerpf(-8.0, -30.0, clampf(nearest / 25.0, 0.0, 1.0)))
	_update_ghost()


func _launch(uid: int) -> void:
	var m := sim.get_machine(uid)
	if not m.is_empty():
		m["launch_t"] = 0.0


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
	var pos: Vector3 = p.global_position + fwd * 8.0
	pos.y = TerrainGen.height(pos.x, pos.z)
	ghost.global_position = pos
	ghost.rotation.y = ghost_yaw
	var reason := sim.can_place(placing, pos)
	var price := float(GameData.machine(placing)["price"])
	if reason == "" and not GameState.can_afford(price):
		reason = "Not enough credits"
	var ok := reason == ""
	if ok != ghost_ok or reason != ghost_reason:
		ghost_ok = ok
		ghost_reason = reason
		MachineModels.ghostify(ghost, ok)


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
